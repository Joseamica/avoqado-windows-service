import { ConsumeMessage } from 'amqplib'
import { log } from '../core/logger'
import {
  getRabbitMQChannel,
  getChannelModel,
  onReconnect,
  POS_COMMANDS_EXCHANGE,
  DEAD_LETTER_EXCHANGE,
  COMMANDS_DLQ_ROUTING_KEY,
} from '../core/rabbitmq'
import {
  IPOSAdapter,
  OrderCreateData,
  OrderAddItemData,
  IntelligentPaymentData,
  ShiftOpenData,
  ShiftCloseData,
  FastPaymentData,
} from '../adapters/IPosAdapter'
import { SoftRestaurant11Adapter } from '../adapters/SoftRestaurant11Adapter'
import { loadConfig } from '../config'
import { getDbPool } from '../core/db'
import sql from 'mssql'

let adapter: IPOSAdapter
let reconnectHandlerRegistered = false

export const handleCommand = async (msg: ConsumeMessage | null) => {
  if (!msg) return

  const channel = getRabbitMQChannel()
  const routingKey = msg.fields.routingKey

  // Parseamos UNA sola vez, en su propio try: un mensaje con JSON inválido
  // se va directo a la DLQ. (Antes, el catch principal re-parseaba el mismo
  // contenido para loguearlo, explotaba, y el mensaje quedaba sin ack ni
  // nack — con prefetch(1) eso congelaba la cola entera hasta reiniciar.)
  let commandMessage: any
  try {
    commandMessage = JSON.parse(msg.content.toString())
  } catch (parseError: any) {
    log.error({
      message: '[Comandante] Mensaje con JSON inválido. Enviando a la Dead-Letter Queue.',
      routingKey,
      errorMessage: parseError.message,
      rawContent: msg.content.toString().slice(0, 500),
    })
    channel.nack(msg, false, false)
    return
  }

  try {
    log.info(`[Comandante] Comando recibido: ${routingKey}`)
    const { entity, action, payload } = commandMessage
    log.info(`[Comandante] Despachando acción: ${entity}.${action}`)

    // 🔧 5a-2: idempotencia de comandos. Key estable = messageId (AMQP) / commandId / idempotencyKey
    // que envíe el backend. Sin id NO se puede de-duplicar con seguridad (dos comandos legítimos
    // idénticos colisionarían), así que en ese caso seguimos SIN dedup (fail-open + aviso).
    const commandKey: string | null =
      msg.properties?.messageId || commandMessage?.commandId || payload?.commandId || payload?.idempotencyKey || null
    if (commandKey) {
      try {
        const dup = await getDbPool()
          .request()
          .input('k', sql.VarChar(200), String(commandKey))
          .query('SELECT 1 AS x FROM AvoqadoProcessedCommands WHERE CommandKey = @k')
        if (dup.recordset.length > 0) {
          log.warn(`[Comandante] Comando ${commandKey} (${entity}.${action}) ya aplicado — idempotente: ack y skip.`)
          channel.ack(msg)
          return
        }
      } catch (dedupErr: any) {
        log.warn(
          `[Comandante] Dedup no disponible (¿falta AvoqadoProcessedCommands?); procediendo sin idempotencia: ${dedupErr?.message ?? dedupErr}`,
        )
      }
    } else {
      log.warn(
        `[Comandante] Comando ${entity}.${action} SIN id (messageId/commandId/idempotencyKey): sin protección de idempotencia. El backend debería enviar un id único por comando.`,
      )
    }

    const keyParts = routingKey.split('.')
    if (keyParts[0] !== 'command' || keyParts.length !== 3) {
      throw new Error(`Routing key de comando no tiene el formato esperado (command.pos_type.venueId): ${routingKey}`)
    }

    switch (`${entity}.${action}`) {
      case 'Order.CREATE':
        await adapter.createEmptyOrder(payload as OrderCreateData)
        log.info(`[Comandante] Acción 'createEmptyOrder' completada.`)
        break

      case 'OrderItem.CREATE':
        // El payload ya contiene todo lo que necesitamos
        const { orderFolio, ...itemData } = payload
        if (!orderFolio) {
          throw new Error("El payload para 'OrderItem.CREATE' debe incluir 'orderFolio'.")
        }
        await adapter.addItemToOrder(orderFolio, itemData as OrderAddItemData)
        log.info(`[Comandante] Acción 'addItemToOrder' completada para el folio ${orderFolio}.`)
        break

      case 'OrderItem.CANCEL': {
        // 🔧 5c: cablear cancelOrderItem (existía pero era inalcanzable desde Avoqado).
        const { orderFolio: cancelFolio, movementId, reason, user } = payload
        if (!cancelFolio || movementId == null) {
          throw new Error("El payload para 'OrderItem.CANCEL' debe incluir 'orderFolio' y 'movementId'.")
        }
        await adapter.cancelOrderItem(cancelFolio, movementId, reason ?? 'Cancelado vía Avoqado', user ?? 'AVOQADO')
        log.info(`[Comandante] Acción 'cancelOrderItem' completada (folio ${cancelFolio}, movimiento ${movementId}).`)
        break
      }

      case 'Order.SPLIT': {
        // 🔧 5c: cablear splitOrder (orquesta los helpers de split que ya existían).
        const { orderFolio: splitFolio, splitRatio } = payload
        if (!splitFolio || splitRatio == null) {
          throw new Error("El payload para 'Order.SPLIT' debe incluir 'orderFolio' y 'splitRatio' (0<r<1).")
        }
        const splitResult = await adapter.splitOrder(splitFolio, splitRatio)
        log.info(`[Comandante] Acción 'splitOrder' completada. Padre: ${splitResult.parentFolio}, Hija: ${splitResult.childFolio}.`)
        break
      }

      case 'Payment.APPLY':
        // ✅ NUEVO: Manejo de pagos inteligentes
        const { orderExternalId, paymentData } = payload
        if (!orderExternalId || !paymentData) {
          throw new Error("El payload para 'Payment.APPLY' debe incluir 'orderExternalId' y 'paymentData'.")
        }

        log.info(`[Comandante] Aplicando pago inteligente para orden ${orderExternalId}`)
        const paymentResult = await adapter.applyIntelligentPayment(orderExternalId, paymentData as IntelligentPaymentData)

        if (paymentResult.closed) {
          log.info(
            `[Comandante] ✅ Orden ${orderExternalId} pagada completamente. Total: ${paymentResult.totalPaid}${paymentResult.change ? `, Cambio: ${paymentResult.change}` : ''}`,
          )
        } else {
          log.info(
            `[Comandante] 💰 Pago parcial aplicado a orden ${orderExternalId}. Pagado: ${paymentResult.totalPaid}, Restante: ${paymentResult.remaining}`,
          )
        }
        break

      case 'Shift.OPEN':
        // Handle shift opening
        const shiftOpenData = payload as ShiftOpenData
        if (!shiftOpenData.posStaffId) {
          throw new Error("El payload para 'Shift.OPEN' debe incluir 'posStaffId'.")
        }

        log.info(`[Comandante] Abriendo turno para cajero ${shiftOpenData.posStaffId}`)
        const openResult = await adapter.openShift(shiftOpenData)

        log.info(`[Comandante] ✅ Turno abierto exitosamente. ID: ${openResult.shiftId}, Cajero: ${openResult.staffName}`)
        break

      case 'Shift.CLOSE':
        // Handle shift closing
        const shiftCloseData = payload as ShiftCloseData
        if (!shiftCloseData.shiftId) {
          throw new Error("El payload para 'Shift.CLOSE' debe incluir 'shiftId'.")
        }

        log.info(`[Comandante] Cerrando turno ${shiftCloseData.shiftId}`)
        await adapter.closeShift(shiftCloseData.shiftId, shiftCloseData)

        log.info(`[Comandante] ✅ Turno ${shiftCloseData.shiftId} cerrado exitosamente`)
        break

      case 'FastPayment.CREATE':
        // ✅ NUEVO: Manejo de pagos rápidos (fast payments)
        const fastPaymentData = payload as FastPaymentData
        if (!fastPaymentData.amount || !fastPaymentData.posPaymentMethodId || !fastPaymentData.cashierPosId) {
          throw new Error("El payload para 'FastPayment.CREATE' debe incluir 'amount', 'posPaymentMethodId' y 'cashierPosId'.")
        }

        log.info(`[Comandante] Creando pago rápido por $${fastPaymentData.amount} con método ${fastPaymentData.posPaymentMethodId}`)
        const fastPaymentResult = await adapter.createFastPayment(fastPaymentData)

        if (fastPaymentResult.success) {
          log.info(
            `[Comandante] ✅ Pago rápido creado exitosamente. Folio: ${fastPaymentResult.folio}, Cheque: ${fastPaymentResult.checkNumber}, Total: $${fastPaymentResult.totalAmount}`,
          )
        } else {
          log.error(`[Comandante] ❌ Error al crear pago rápido`)
        }
        break

      default:
        // 🔧 5a: comando desconocido NO se ack-ea en silencio (antes se perdía). Lanzamos para que
        // el catch lo mande a la DLQ de comandos, donde queda visible para diagnóstico/replay.
        throw new Error(`No hay un manejador para el comando: ${entity}.${action}`)
    }

    // 🔧 5a-2: registrar el comando aplicado para que un redelivery (at-least-once) no lo repita.
    if (commandKey) {
      try {
        await getDbPool()
          .request()
          .input('k', sql.VarChar(200), String(commandKey))
          .input('e', sql.VarChar(50), String(entity ?? '').slice(0, 50))
          .input('a', sql.VarChar(50), String(action ?? '').slice(0, 50))
          .query(
            'IF NOT EXISTS (SELECT 1 FROM AvoqadoProcessedCommands WHERE CommandKey=@k) INSERT INTO AvoqadoProcessedCommands (CommandKey, Entity, Action) VALUES (@k, @e, @a)',
          )
      } catch (recErr: any) {
        log.warn(`[Comandante] No se pudo registrar el command key ${commandKey} (idempotencia): ${recErr?.message ?? recErr}`)
      }
    }

    channel.ack(msg)
    log.info(`[Comandante] Comando ${routingKey} procesado con éxito.`)
  } catch (error: any) {
    log.error({
      message: `[Comandante] Error al procesar comando`,
      routingKey: routingKey,
      // Aquí imprimimos explícitamente el mensaje y el stack del error
      errorMessage: error.message,
      errorStack: error.stack,
      // Logueamos el payload YA parseado (nunca re-parsear aquí: si el JSON
      // fuera inválido, el throw dentro del catch dejaría el mensaje colgado)
      payload: commandMessage,
    })
    channel.nack(msg, false, false) // Enviar a la Dead-Letter Queue
  }
}

const setupConsumer = async (): Promise<void> => {
  const config = loadConfig()
  const channel = getRabbitMQChannel()

  const queueName = `commands_queue.venue_${config.venueId}`

  // ✅ CORRECCIÓN: Eliminamos la palabra '.venue' para que coincida con la routing key
  const bindingKey = `command.${config.posType}.${config.venueId}`

  // 🔧 5a: la cola de comandos DEBE tener dead-letter-exchange. Antes se asertaba sin DLX, así que
  // un nack(requeue=false) — comando fallido, JSON inválido o desconocido — se DESCARTABA en silencio.
  // Cambiar los argumentos de una cola existente lanza PRECONDITION_FAILED (y mata el canal), por eso
  // migramos en un canal temporal: si la cola ya existe sin DLX, la borramos y se recrea con DLX.
  // (El borrado es one-time en el upgrade; un comando en vuelo en ese instante lo reenvía el backend.)
  const cmdQueueArgs = {
    durable: true,
    arguments: { 'x-dead-letter-exchange': DEAD_LETTER_EXCHANGE, 'x-dead-letter-routing-key': COMMANDS_DLQ_ROUTING_KEY },
  }
  const tmp = await getChannelModel().createChannel()
  tmp.on('error', () => {}) // tragar el error de canal del posible PRECONDITION_FAILED
  try {
    await tmp.assertQueue(queueName, cmdQueueArgs)
    await tmp.close()
  } catch (preconditionErr: any) {
    log.warn(`[Comandante] Migrando la cola "${queueName}" para añadir DLX (se recrea). ${preconditionErr?.message ?? ''}`)
    const tmp2 = await getChannelModel().createChannel()
    tmp2.on('error', () => {})
    try {
      await tmp2.deleteQueue(queueName)
    } finally {
      await tmp2.close().catch(() => {})
    }
  }

  await channel.assertQueue(queueName, cmdQueueArgs)
  await channel.bindQueue(queueName, POS_COMMANDS_EXCHANGE, bindingKey)

  channel.prefetch(1)
  await channel.consume(queueName, handleCommand)

  log.info(`[Comandante] Escuchando en la cola "${queueName}" con el binding key "${bindingKey}"`)
}

export const startCommander = async () => {
  log.info('▶️  Iniciando Comandante (Avoqado -> POS)')

  const config = loadConfig()

  if (config.posVersion.startsWith('11')) {
    adapter = new SoftRestaurant11Adapter()
    log.info('✅ Adaptador SoftRestaurant v11 cargado.')
  } else {
    log.error(`FATAL: Versión de POS no soportada: ${config.posVersion}`)
    return
  }

  // El consumer de comandos se (re)vincula al canal en CADA conexión exitosa
  // (incluida la primera). No vinculamos directo aquí: si RabbitMQ aún no
  // conectó, el canal no existe y antes eso crasheaba el arranque. Un canal
  // nuevo tampoco hereda los consume() del anterior, así que esto también cubre
  // la reconexión tras un blip de red.
  if (!reconnectHandlerRegistered) {
    onReconnect(async () => {
      log.info('[Comandante] Vinculando consumer de comandos al canal...')
      await setupConsumer()
    })
    reconnectHandlerRegistered = true
  }
}
