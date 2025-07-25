import sql from 'mssql'
import { getDbPool } from '../core/db'
import { log } from '../core/logger'
import { publishMessage, POS_EVENTS_EXCHANGE } from '../core/rabbitmq'
import { loadConfig } from '../config'
import { serviceStateManager } from '../core/serviceState'

const PRODUCER_VERSION = '2.2.0-debounced'
const POLLING_INTERVAL_MS = 2000
const HEARTBEAT_INTERVAL_MS = 60000
// ✅ NUEVA CONSTANTE: Tiempo de espera en milisegundos antes de enviar una actualización de orden.
const ORDER_DEBOUNCE_MS = 2500 // 2.5 segundos

let lastSyncTimestamp = new Date(Date.now() - 5 * 60 * 1000)
let isProducerHealthy = true
let heartbeatInterval: NodeJS.Timeout | null = null
let pollingInterval: NodeJS.Timeout | null = null

// ✅ NUEVO MAPA: Almacena los temporizadores para cada orden que está en "debounce".
// La clave es el EntityId de la orden, el valor es el temporizador de Node.js.
const debouncedOrders = new Map<string, NodeJS.Timeout>()

interface ChangeNotification {
  EntityType: string
  EntityId: string
  LastModifiedAt: Date
  ChangeReason: string
}

async function sendHeartbeat() {
  try {
    // Verificar si el servicio puede enviar heartbeats
    if (!serviceStateManager.canSendHeartbeats()) {
      log.warn('[Heartbeat] ⚠️ Heartbeat omitido - servicio no en estado operativo')
      return
    }

    const pool = getDbPool()
    const { venueId, posType } = loadConfig()
    const result = await pool.request().query('SELECT TOP 1 InstanceId FROM dbo.AvoqadoInstanceInfo')
    if (result.recordset.length === 0) throw new Error('Tabla AvoqadoInstanceInfo no encontrada.')
    const instanceId = result.recordset[0].InstanceId
    const heartbeatPayload = {
      venueId,
      instanceId,
      producerVersion: PRODUCER_VERSION,
      timestamp: new Date().toISOString(),
      status: 'ONLINE',
    }
    await publishMessage(POS_EVENTS_EXCHANGE, `pos.${posType}.system.heartbeat`, heartbeatPayload)
    log.info(`[Heartbeat] ❤️ Latido enviado con InstanceId: ${instanceId}`)
    isProducerHealthy = true
  } catch (error) {
    log.error('[Heartbeat] 💔 FALLO CRÍTICO AL ENVIAR LATIDO.', error)
    isProducerHealthy = false
  }
}

/**
 * Nueva función que maneja el debouncing para las actualizaciones de órdenes.
 */
async function debounceAndSendOrderUpdate(change: ChangeNotification) {
  // Si ya hay un temporizador para esta orden, lo cancelamos.
  if (debouncedOrders.has(change.EntityId)) {
    clearTimeout(debouncedOrders.get(change.EntityId)!)
  }

  log.info(`[Debouncer] ⏳ Recibido cambio para la orden ${change.EntityId}. Iniciando temporizador de ${ORDER_DEBOUNCE_MS}ms...`)

  // Creamos un nuevo temporizador.
  const timer = setTimeout(async () => {
    try {
      log.info(`[Debouncer] 🔥 ¡Temporizador para la orden ${change.EntityId} finalizado! Enviando actualización...`)
      const { venueId, posType } = loadConfig()

      // Obtenemos el estado FINAL de la orden y lo enviamos.
      const result = await processOrderChange(change, venueId)
      if (result && result.payload) {
        const routingKey = `pos.${posType}.order.updated`
        await publishMessage(POS_EVENTS_EXCHANGE, routingKey, result.payload)
        log.info(`[Debouncer] ✅ Evento enviado: ${routingKey} para ${change.EntityId}`)
      }
    } catch (error) {
      log.error(`[Debouncer] Error al enviar la actualización debounced para la orden ${change.EntityId}`, error)
    } finally {
      // Limpiamos el mapa una vez que el trabajo está hecho.
      debouncedOrders.delete(change.EntityId)
    }
  }, ORDER_DEBOUNCE_MS)

  // Guardamos el nuevo temporizador en el mapa.
  debouncedOrders.set(change.EntityId, timer)
}

/**
 * Busca cambios en la base de datos del POS.
 */
async function pollForChanges() {
  if (!isProducerHealthy) {
    log.warn('[Producer] El polling está en pausa debido a un fallo en el heartbeat.')
    return
  }
  try {
    const pool = getDbPool()
    const result = await pool
      .request()
      .input('lastSyncTimestamp', sql.DateTime2, lastSyncTimestamp)
      .input('maxResults', sql.Int, 100)
      .execute('sp_GetEntityChanges')

    const changes = result.recordset as ChangeNotification[]
    if (changes.length === 0) return

    log.info(`[Producer] 🎯 ${changes.length} nuevos cambios detectados.`)
    const { venueId, posType } = loadConfig()
    // ✅ PASO 1: Detectar los IDs de los turnos cerrados en este lote específico.
    const closedShiftIdsInBatch = new Set<string>()
    for (const change of changes) {
      if (change.EntityType === 'shift' && change.ChangeReason.includes('updated')) {
        const shiftRes = await pool
          .request()
          .input('idturno', sql.BigInt, change.EntityId)
          .query('SELECT cierre FROM turnos WHERE idturno = @idturno')
        if (shiftRes.recordset[0] && shiftRes.recordset[0].cierre) {
          // Si el turno tiene una fecha de cierre, lo consideramos cerrado en este lote.
          log.info(`[Producer-Context] Detectado cierre de turno en este lote: ${change.EntityId}`)
          closedShiftIdsInBatch.add(change.EntityId)
        }
      }
    }
    // ✅ PASO 2: Procesar cada cambio con el contexto que acabamos de obtener.

    for (const change of changes) {
      try {
        let result: { payload: object } | null = null
        const eventType = change.ChangeReason.split('_').pop() || 'updated'

        switch (change.EntityType) {
          case 'order':
            // ✅ CAMBIO EN LA LÓGICA: En lugar de enviar inmediatamente, llamamos al debouncer.
            // Esto se aplica si el cambio es 'updated' o el genérico 'item_change'.
            if (eventType === 'updated' || eventType === 'change') {
              await debounceAndSendOrderUpdate(change)
            } else {
              // Para 'created' o 'deleted', enviamos inmediatamente.
              if (debouncedOrders.has(change.EntityId)) {
                log.info(`[Producer] 🚫 Cancelando actualización debounced para ${change.EntityId} debido a un evento inmediato.`)
                clearTimeout(debouncedOrders.get(change.EntityId)!)
                debouncedOrders.delete(change.EntityId)
              }
              // ✅ LÓGICA DE DECISIÓN INTELIGENTE PARA EVITAR ELIMINACION DE ORDENES EN TURNOS CERRADOS
              if (eventType === 'deleted') {
                const orderIdParts = change.EntityId.split(':') // Formato: INSTANCE:TURNO:FOLIO
                const shiftIdForOrder = orderIdParts[1]

                if (closedShiftIdsInBatch.has(shiftIdForOrder)) {
                  log.info(
                    `[Producer-Context] Ignorando eliminación de la orden ${change.EntityId} porque pertenece al turno cerrado ${shiftIdForOrder}.`,
                  )
                  continue // Saltamos al siguiente cambio en el bucle.
                }
              }
              result = await processOrderChange(change, venueId)
              if (result) {
                const routingKey = `pos.${posType}.order.${eventType}`
                await publishMessage(POS_EVENTS_EXCHANGE, routingKey, result.payload)
                log.info(`[Producer] ✅ Evento inmediato enviado: ${routingKey} para ${change.EntityId}`)
              }
            }
            break

          case 'orderitem':
            // Los items siempre se envían inmediatamente porque cada uno es un evento discreto.
            result = await processOrderItemChange(change, venueId)
            if (result) {
              const routingKey = `pos.${posType}.orderitem.${eventType}`
              await publishMessage(POS_EVENTS_EXCHANGE, routingKey, result.payload)
              log.info(`[Producer] ✅ Evento enviado: ${routingKey} para ${change.EntityId}`)
            }
            break

          case 'shift':
            result = await processShiftChange(change, venueId)
            if (result) {
              const finalEventType = eventType === 'updated' ? 'closed' : eventType

              const routingKey = `pos.${posType}.shift.${finalEventType}`
              await publishMessage(POS_EVENTS_EXCHANGE, routingKey, result.payload)
              log.info(`[Producer] ✅ Evento enviado: ${routingKey} para ${change.EntityId}`)
            }
            break
        }
      } catch (error) {
        log.error(`[Producer] Error procesando la entidad ${change.EntityType}:${change.EntityId}`, error)
      }
    }

    lastSyncTimestamp = changes[changes.length - 1].LastModifiedAt
  } catch (error) {
    log.error('[Producer] Error en el ciclo de polling principal.', error)
  }
}

/**
 * Obtiene los datos de shift correctos para una orden.
 * Si idturno es 0 o null, busca el shift abierto más reciente.
 * Si idturno tiene valor, busca ese shift específico.
 */
async function getShiftDataForOrder(pool: any, orderIdTurno: any): Promise<{ externalId: string }> {
  try {
    let query: string
    let shiftRes: any

    if (!orderIdTurno || orderIdTurno === 0 || orderIdTurno === '0') {
      // Si la orden no tiene idturno asignado, buscar el shift abierto más reciente
      log.info('[Order Processor] Orden sin idturno asignado. Buscando shift abierto...')
      query = 'SELECT TOP 1 WorkspaceId FROM turnos WHERE cierre IS NULL ORDER BY apertura DESC'
      shiftRes = await pool.request().query(query)
    } else {
      // Si la orden tiene idturno, buscar ese shift específico
      log.info(`[Order Processor] Buscando shift específico con idturno: ${orderIdTurno}`)
      query = 'SELECT WorkspaceId FROM turnos WHERE idturno = @idturno'
      shiftRes = await pool.request().input('idturno', sql.BigInt, orderIdTurno).query(query)
    }

    if (shiftRes.recordset[0] && shiftRes.recordset[0].WorkspaceId) {
      const workspaceId = shiftRes.recordset[0].WorkspaceId
      log.info(`[Order Processor] Shift encontrado con WorkspaceId: ${workspaceId}`)
      return { externalId: workspaceId }
    } else {
      log.warn('[Order Processor] No se encontró shift válido. Usando idturno como fallback.')
      return { externalId: orderIdTurno?.toString() || '0' }
    }
  } catch (error) {
    log.error('[Order Processor] Error buscando shift data:', error)
    return { externalId: orderIdTurno?.toString() || '0' }
  }
}

// ... (Las funciones processOrderChange, processOrderItemChange y processShiftChange no necesitan cambios) ...
async function processOrderChange(change: ChangeNotification, venueId: string): Promise<{ payload: object } | null> {
  try {
    const parts = change.EntityId.split(':')
    if (parts.length !== 3) {
      log.error(`[Order Processor] EntityId inválido: ${change.EntityId}`)
      return null
    }
    const [instanceId, idturno, folio] = parts

    if (change.ChangeReason.includes('deleted')) {
      return { payload: { venueId, orderData: { externalId: change.EntityId, status: 'CANCELLED' } } }
    }

    const pool = getDbPool()
    const request = pool.request()
    let query: string

    // Si idturno está presente y no es una cadena vacía, buscamos con él.
    if (idturno && idturno !== 'null') {
      log.info(`[Order Processor] Buscando orden con idturno ${idturno} y folio ${folio}`)
      request.input('idturno', sql.BigInt, idturno)
      request.input('folio', sql.Int, folio)
      query = 'SELECT * FROM tempcheques WHERE idturno = @idturno AND folio = @folio'
    } else {
      // Si idturno es nulo o una cadena vacía, buscamos la orden sin turno asignado.
      log.info(`[Order Processor] Buscando orden con idturno NULO y folio ${folio}`)
      request.input('folio', sql.Int, folio)
      query = 'SELECT * FROM tempcheques WHERE idturno IS NULL AND folio = @folio'
    }

    const orderRes = await request.query(query)
    if (!orderRes.recordset[0]) {
      log.warn(`[Order Processor] No se encontraron datos para ${change.EntityId}.`)
      return null
    }
    const posData = orderRes.recordset[0]
    let posStaff = null
    if (posData.idmesero) {
      try {
        const staffRes = await pool
          .request()
          .input('idmesero', sql.VarChar, posData.idmesero)
          .query('SELECT nombre, contraseña FROM meseros WHERE idmesero = @idmesero')
        posStaff = staffRes.recordset[0]
      } catch (e) {
        log.warn(`No se pudo obtener staff para mesero ${posData.idmesero}`)
      }
    }
    let posArea = null
    if (posData.idarearestaurant) {
      try {
        const areaRes = await pool
          .request()
          .input('idarea', sql.VarChar, posData.idarearestaurant)
          .query('SELECT descripcion FROM areasrestaurant WHERE idarearestaurant = @idarea')
        posArea = areaRes.recordset[0]
      } catch (e) {
        log.warn(`No se pudo obtener area ${posData.idarearestaurant}`)
      }
    }
    let paymentsData: any[] = []
    if (posData.pagado) {
      // Si la bandera `pagado` es true...
      log.info(`[Order Processor] Orden ${folio} marcada como pagada. Buscando detalles del pago...`)
      const paymentsRes = await pool
        .request()
        .input('folio', sql.Int, folio)
        .query('SELECT idformadepago, importe, propina, referencia FROM tempchequespagos WHERE folio = @folio')

      if (paymentsRes.recordset.length > 0) {
        paymentsData = paymentsRes.recordset.map(p => ({
          methodExternalId: p.idformadepago.trim(), // 'CRE'
          amount: parseFloat(p.importe || 0),
          tipAmount: parseFloat(p.propina || 0),
          reference: p.referencia?.trim() || null,
          posRawData: p,
        }))
        log.info(`[Order Processor] Se encontraron ${paymentsData.length} pagos para la orden ${folio}.`)
      }
    }
    log.info(`[Order Processor] Obteniendo catálogo de formas de pago...`)
    const paymentMethodsRes = await pool.request().query('SELECT idformadepago, descripcion, tipo FROM formasdepago')
    const paymentMethodsCatalog = paymentMethodsRes.recordset
    const payload = {
      venueId,
      orderData: {
        externalId: change.EntityId,
        orderNumber: posData.folio.toString(),
        status: posData.cancelado ? 'CANCELLED' : posData.pagado ? 'COMPLETED' : 'CONFIRMED',
        paymentStatus: posData.pagado ? 'PAID' : 'PENDING',
        subtotal: parseFloat(posData.subtotal || 0),
        taxAmount: parseFloat(posData.totalimpuesto1 || 0),
        discountAmount: parseFloat(posData.descuentoimporte || 0),
        tipAmount: parseFloat(posData.propina || 0),
        total: parseFloat(posData.total || 0),
        createdAt: posData.fecha ? new Date(posData.fecha).toISOString() : new Date().toISOString(),
        completedAt: posData.cierre ? new Date(posData.cierre).toISOString() : null,
        posRawData: posData,
      },
      staffData: {
        externalId: posData.idmesero,
        name: posStaff?.nombre || `Mesero ${posData.idmesero}`,
        pin: posStaff?.contraseña || null,
      },
      tableData: { externalId: posData.mesa?.toString() || `Mesa ${folio}`, posAreaId: posData.idarearestaurant },
      areaData: { externalId: posData.idarearestaurant, name: posArea?.descripcion || `Área ${posData.idarearestaurant}` },
      shiftData: await getShiftDataForOrder(pool, posData.idturno),
      payments: paymentsData, // Se añade el array de pagos, estará vacío si la orden no está pagada.
      paymentMethodsCatalog: paymentMethodsCatalog,
    }
    return { payload }
  } catch (error) {
    log.error(`[Order Processor] Error fatal procesando orden ${change.EntityId}:`, error)
    return null
  }
}
async function processOrderItemChange(change: ChangeNotification, venueId: string): Promise<{ payload: object } | null> {
  try {
    const parts = change.EntityId.split(':')
    if (parts.length !== 4) {
      log.error(`[OrderItem Processor] EntityId inválido: ${change.EntityId}`)
      return null
    }
    const [instanceId, idturno, folio, movimiento] = parts
    const parentOrderExternalId = `${instanceId}:${idturno}:${folio}`
    if (change.ChangeReason.includes('deleted')) {
      return { payload: { venueId, parentOrderExternalId, itemData: { externalId: change.EntityId, deleted: true } } }
    }
    const pool = getDbPool()
    const itemRes = await pool
      .request()
      .input('folio', sql.BigInt, folio)
      .input('movimiento', sql.Int, movimiento)
      .query(
        `SELECT td.*, p.descripcion as nombreproducto FROM tempcheqdet td LEFT JOIN productos p ON td.idproducto = p.idproducto WHERE td.foliodet = @folio AND td.movimiento = @movimiento`,
      )
    if (!itemRes.recordset[0]) {
      log.warn(`[OrderItem Processor] No se encontraron datos para el item ${change.EntityId}.`)
      return null
    }
    const posItemData = itemRes.recordset[0]
    const payload = {
      venueId,
      parentOrderExternalId,
      itemData: {
        externalId: change.EntityId,
        sequence: parseInt(movimiento),
        productExternalId: posItemData.idproducto,
        productName: posItemData.nombreproducto || 'Producto Desconocido',
        quantity: parseFloat(posItemData.cantidad || 0),
        unitPrice: parseFloat(posItemData.precio || 0),
        discountAmount: parseFloat(posItemData.descuento || 0),
        taxAmount: (parseFloat(posItemData.precio) || 0) - (parseFloat(posItemData.preciosinimpuestos) || 0),
        total: parseFloat(posItemData.precio || 0) * parseFloat(posItemData.cantidad || 0),
        notes: posItemData.comentario,
        deleted: false,
        posRawData: posItemData,
      },
    }
    return { payload }
  } catch (error) {
    log.error(`[OrderItem Processor] Error fatal procesando item ${change.EntityId}:`, error)
    return null
  }
}
async function processShiftChange(change: ChangeNotification, venueId: string): Promise<{ payload: object } | null> {
  try {
    const idturno = change.EntityId
    if (change.ChangeReason.includes('deleted')) {
      // Para deletes, necesitamos buscar el WorkspaceId antes de que se elimine
      const pool = getDbPool()
      const shiftRes = await pool.request().input('idturno', sql.BigInt, idturno).query('SELECT WorkspaceId FROM turnos WHERE idturno = @idturno')
      const workspaceId = shiftRes.recordset[0]?.WorkspaceId || idturno // Fallback al idturno si no se encuentra
      return { payload: { venueId, shiftData: { externalId: workspaceId, status: 'DELETED' } } }
    }
    const pool = getDbPool()
    const shiftRes = await pool.request().input('idturno', sql.BigInt, idturno).query('SELECT * FROM turnos WHERE idturno = @idturno')
    if (!shiftRes.recordset[0]) {
      log.warn(`[Shift Processor] No se encontraron datos para el turno ${idturno}.`)
      return null
    }
    const posShift = shiftRes.recordset[0]
    return {
      payload: {
        venueId,
        shiftData: {
          externalId: posShift.WorkspaceId,
          startTime: posShift.apertura ? new Date(posShift.apertura).toISOString() : null,
          endTime: posShift.cierre ? new Date(posShift.cierre).toISOString() : null,
          staffId: posShift.idmesero,
          status: posShift.cierre ? 'CLOSED' : 'OPEN',
          posRawData: posShift,
        },
      },
    }
  } catch (error) {
    log.error(`[Shift Processor] Error fatal procesando turno ${change.EntityId}:`, error)
    return null
  }
}

/**
 * Obtiene el instanceId de la base de datos
 */
export const getInstanceId = async (): Promise<string> => {
  try {
    const pool = getDbPool()
    const result = await pool.request().query('SELECT TOP 1 InstanceId FROM dbo.AvoqadoInstanceInfo')
    if (result.recordset.length === 0) throw new Error('Tabla AvoqadoInstanceInfo no encontrada.')
    return result.recordset[0].InstanceId
  } catch (error) {
    log.error('[Producer] Error obteniendo instanceId:', error)
    throw error
  }
}

/**
 * Detiene los heartbeats
 */
export const stopHeartbeat = (): void => {
  if (heartbeatInterval) {
    clearInterval(heartbeatInterval)
    heartbeatInterval = null
    log.info('[Producer] ⏹️ Heartbeats detenidos')
  }
}

/**
 * Inicia los heartbeats
 */
export const startHeartbeat = (): void => {
  if (heartbeatInterval) {
    clearInterval(heartbeatInterval)
  }
  
  sendHeartbeat() // Enviar inmediatamente
  heartbeatInterval = setInterval(sendHeartbeat, HEARTBEAT_INTERVAL_MS)
  log.info('[Producer] ❤️ Heartbeats iniciados')
}

/**
 * Detiene el polling de cambios
 */
export const stopPolling = (): void => {
  if (pollingInterval) {
    clearInterval(pollingInterval)
    pollingInterval = null
    log.info('[Producer] ⏹️ Polling detenido')
  }
}

/**
 * Inicia el polling de cambios
 */
export const startPolling = (): void => {
  if (pollingInterval) {
    clearInterval(pollingInterval)
  }
  
  pollingInterval = setInterval(pollForChanges, POLLING_INTERVAL_MS)
  log.info('[Producer] 🔄 Polling iniciado')
}

/**
 * Detiene completamente el producer
 */
export const stopProducer = (): void => {
  stopHeartbeat()
  stopPolling()
  serviceStateManager.stop('Producer detenido manualmente')
  log.info('[Producer] ⏹️ Producer completamente detenido')
}

/**
 * Reinicia el producer con nueva configuración
 */
export const restartProducer = (): void => {
  log.info('[Producer] 🔄 Reiniciando producer...')
  stopProducer()
  
  // Esperar un momento antes de reiniciar
  setTimeout(() => {
    startProducer()
  }, 2000)
}

/**
 * Inicia el servicio del producer.
 */
export const startProducer = () => {
  log.info(`🛡️ Iniciando Producer Resiliente v${PRODUCER_VERSION} (con Debounce y Heartbeat)...`)
  
  // Establecer estado inicial
  serviceStateManager.start()
  
  // Iniciar componentes
  startPolling()
  startHeartbeat()
}
