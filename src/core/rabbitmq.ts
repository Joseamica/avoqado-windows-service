import amqp, { connect } from 'amqplib'
import { loadConfig } from '../config'
import { log } from './logger'
import { ChannelModel, Connection, ConfirmChannel } from 'amqplib'
// Declaramos las variables que mantendrán el estado de la conexión
let channelModel: ChannelModel | null = null
let connection: Connection | null = null
let channel: ConfirmChannel | null = null
let isConnecting = false // Una bandera para evitar múltiples intentos de reconexión simultáneos
let hasConnectedOnce = false
let isShuttingDown = false

type ReconnectHandler = () => void | Promise<void>
const reconnectHandlers: ReconnectHandler[] = []

/**
 * Registra un handler que corre tras CADA conexión exitosa, incluida la primera.
 * Un canal nuevo NO hereda los consume() del canal muerto: todo consumer
 * (Comandante, errores de configuración) debe registrarse aquí o dejará de
 * recibir mensajes silenciosamente tras un blip de red.
 *
 * Cada handler corre exactamente una vez por conexión: si ya estamos conectados
 * al registrarlo (consumer que arranca tarde), se ejecuta de inmediato; si no,
 * lo ejecutará attemptConnect cuando la conexión se establezca.
 */
export const onReconnect = (handler: ReconnectHandler): void => {
  reconnectHandlers.push(handler)
  if (channel) {
    Promise.resolve()
      .then(handler)
      .catch(err => log.error('❌ Error ejecutando handler de conexión de RabbitMQ:', err))
  }
}

export const POS_EVENTS_EXCHANGE = 'pos_events_exchange'
export const POS_COMMANDS_EXCHANGE = 'pos_commands_exchange'
export const AVOQADO_EVENTS_QUEUE = 'avoqado_events_queue'
const DEAD_LETTER_EXCHANGE = 'dead_letter_exchange'
const AVOQADO_EVENTS_DLQ = 'avoqado_events_dead_letter_queue'

export const publishMessage = async (exchange: string, routingKey: string, payload: object): Promise<void> => {
  const channel = getRabbitMQChannel()
  const message = Buffer.from(JSON.stringify(payload))

  try {
    console.log(`📤 Publicando mensaje en exchange [${exchange}] con routing key [${routingKey}]`)

    const published = channel.publish(exchange, routingKey, message, { persistent: true })

    if (published) {
      await channel.waitForConfirms()
      console.log(`✅ Mensaje [${routingKey}] confirmado por el bróker.`)
    } else {
      throw new Error('El buffer del canal de RabbitMQ está lleno.')
    }
  } catch (error) {
    console.error(`🔥 Error al publicar y confirmar mensaje [${routingKey}]:`, error)
    throw error
  }
}

const assertTopology = async (ch: ConfirmChannel): Promise<void> => {
  await ch.assertExchange(DEAD_LETTER_EXCHANGE, 'direct', { durable: true })
  await ch.assertQueue(AVOQADO_EVENTS_DLQ, { durable: true })
  await ch.bindQueue(AVOQADO_EVENTS_DLQ, DEAD_LETTER_EXCHANGE, 'dead-letter')
  await ch.assertExchange(POS_EVENTS_EXCHANGE, 'topic', { durable: true })
  await ch.assertExchange(POS_COMMANDS_EXCHANGE, 'topic', { durable: true })
  await ch.assertQueue(AVOQADO_EVENTS_QUEUE, {
    durable: true,
    arguments: {
      'x-dead-letter-exchange': DEAD_LETTER_EXCHANGE,
      'x-dead-letter-routing-key': 'dead-letter',
    },
  })
}

/**
 * Un intento de conexión: abre el canal, asegura la topología, cablea el evento
 * de cierre (para reconectar en background) y ejecuta los handlers de consumers
 * para que se (re)vinculen al canal nuevo. Lanza si algo falla.
 */
const attemptConnect = async (): Promise<void> => {
  const { rabbitMqUrl } = loadConfig()
  channelModel = await connect(rabbitMqUrl)
  connection = channelModel.connection
  channel = await channelModel.createConfirmChannel()
  if (!channel || !connection) {
    throw new Error('No se pudo crear el canal o la conexión de RabbitMQ.')
  }

  log.info('✅ Conexión con RabbitMQ establecida.')

  await assertTopology(channel)
  log.info('✅ Topología de RabbitMQ asegurada.')

  connection.on('error', err => log.error('❌ Error de conexión con RabbitMQ:', err.message))
  connection.on('close', () => {
    if (isShuttingDown) {
      log.info('🚪 Conexión RabbitMQ cerrada (apagado del servicio).')
      return
    }
    log.warn('🚪 Conexión con RabbitMQ cerrada. Reintentando en background...')
    connection = null
    channel = null
    scheduleReconnect()
  })

  hasConnectedOnce = true

  // (Re)vincular todos los consumers al canal nuevo. El canal anterior murió con
  // sus consume(), así que esto nunca duplica consumers dentro de una conexión.
  if (reconnectHandlers.length > 0) {
    log.info(`🔁 Vinculando ${reconnectHandlers.length} consumer(s) al canal de RabbitMQ...`)
    for (const handler of reconnectHandlers) {
      try {
        await handler()
      } catch (err) {
        log.error('❌ Error vinculando un consumer:', err)
      }
    }
  }
}

/**
 * Loop de conexión/reconexión en background: reintenta cada 5s hasta lograrlo
 * (o hasta apagar). No bloquea a quien lo dispara — el arranque del servicio
 * continúa y los consumers se vinculan vía onReconnect cuando la conexión queda.
 */
const scheduleReconnect = (): void => {
  if (isShuttingDown || isConnecting) return
  isConnecting = true
  const tryOnce = async (): Promise<void> => {
    if (isShuttingDown) {
      isConnecting = false
      return
    }
    try {
      await attemptConnect()
      isConnecting = false
    } catch (error) {
      log.error('🔥 Falla al conectar con RabbitMQ, reintentando en 5s...', error)
      channelModel = null
      connection = null
      channel = null
      setTimeout(tryOnce, 5000)
    }
  }
  void tryOnce()
}

/**
 * Arranca la conexión a RabbitMQ SIN bloquear ni crashear. Antes, si el primer
 * intento fallaba, el código tragaba el error y devolvía OK aunque no hubiera
 * canal: el arranque logueaba un "✅ establecida" falso y luego se caía al usar
 * el canal nulo. Ahora la conexión vive en un loop de reintento en background y
 * los consumers se vinculan cuando conecta.
 */
export const connectToRabbitMQ = async (): Promise<void> => {
  isShuttingDown = false
  if (channel) return
  scheduleReconnect()
}

/** True si hay un canal de RabbitMQ activo (para diferir publish si está caído). */
export const isRabbitConnected = (): boolean => channel !== null

export const getRabbitMQChannel = (): amqp.ConfirmChannel => {
  if (!channel) {
    throw new Error('El canal de RabbitMQ no ha sido inicializado.')
  }
  return channel
}

export const closeRabbitMQConnection = async (): Promise<void> => {
  isShuttingDown = true
  try {
    if (channel) await channel.close()
  } catch (error) {
    log.warn('Error cerrando el canal de RabbitMQ:', error)
  }
  try {
    if (channelModel) await channelModel.close()
  } catch (error) {
    log.warn('Error cerrando la conexión de RabbitMQ:', error)
  }
  channel = null
  connection = null
  channelModel = null
  log.info('🚪 Conexión RabbitMQ cerrada.')
}
