import sql from 'mssql'
import { getDbPool } from '../core/db'
import { log } from '../core/logger'
import { publishMessage, POS_EVENTS_EXCHANGE, isRabbitConnected } from '../core/rabbitmq'
import { loadConfig, updateDetectedVersion } from '../config'
import { serviceStateManager } from '../core/serviceState'
import { loadSyncCursor, saveSyncCursor } from '../core/syncCursor'
import { recordSuccessfulHeartbeat } from './configurationErrorConsumer'

const PRODUCER_VERSION = '2.5.0-durable-cursor+version-detection'
const POLLING_INTERVAL_MS = 2000
const HEARTBEAT_INTERVAL_MS = 60000
// ✅ NUEVA CONSTANTE: Tiempo de espera en milisegundos antes de enviar una actualización de orden.
const ORDER_DEBOUNCE_MS = 2500 // 2.5 segundos
const PURGE_INTERVAL_MS = 24 * 60 * 60 * 1000 // Purga de tracking: una vez al día
const PURGE_DAYS_TO_KEEP = 30

// Cursor compuesto (LastModifiedAt, Id): persistido en disco para no perder
// eventos cuando el servicio se reinicia (antes solo miraba 5 min hacia atrás).
let lastSyncTimestamp = new Date(Date.now() - 5 * 60 * 1000)
let lastSyncId = 0
let isProducerHealthy = true
let isPollInProgress = false
let lastPurgeAt = Date.now()
let heartbeatInterval: NodeJS.Timeout | null = null
let pollingInterval: NodeJS.Timeout | null = null

// ✅ NUEVO MAPA: Almacena los temporizadores para cada orden que está en "debounce".
// La clave es el EntityId de la orden, el valor es el temporizador de Node.js.
// EntityId → estado de debounce: el timer pendiente, los Id de AvoqadoTracking
// acumulados (se marcan procesados SOLO cuando el publish confirma) y el último
// cambio a publicar.
interface DebounceEntry {
  timer: NodeJS.Timeout
  ids: Set<number | string>
  change: ChangeNotification
}
const debouncedOrders = new Map<string, DebounceEntry>()

// ✅ VERSIÓN DETECTADA: Variable global para almacenar la versión detectada
let detectedVersion: number | null = null
// El formato de entity-id lo decide la PRESENCIA de WorkspaceId (igual que el SQL
// de instalación), NO el número de versión: existen DBs con versiondb=10.x que SÍ
// tienen WorkspaceId (los triggers generan GUIDs); el path v10 no podría parsearlos.
// Ramificar por esto mantiene al producer alineado con los triggers/SQL.
let usesWorkspaceId = false

interface ChangeNotification {
  Id: number | string // BIGINT: el driver mssql lo entrega como string
  EntityType: string
  EntityId: string
  Timestamp: Date
  Operation: string
  RetryCount: number
}

async function sendHeartbeat() {
  try {
    // Verificar si el servicio puede enviar heartbeats
    if (!serviceStateManager.canSendHeartbeats()) {
      log.warn('[Heartbeat] ⚠️ Heartbeat omitido - servicio no en estado operativo')
      return
    }

    // RabbitMQ aún conectando (el connect es no-bloqueante por diseño): esto NO es
    // un fallo del producer. Omitimos este latido SIN marcar isProducerHealthy=false,
    // para no pausar el polling ~60s (hasta el siguiente heartbeat) en cada arranque.
    // El guard de RabbitMQ en pollForChanges() ya difiere el polling de forma suave
    // hasta que el canal sube, y el próximo heartbeat (o el de los 60s) se enviará solo.
    if (!isRabbitConnected()) {
      log.warn('[Heartbeat] ⏳ Heartbeat omitido - RabbitMQ aún no conectado (se reintentará).')
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

    // Record successful heartbeat to reset any error tracking
    recordSuccessfulHeartbeat()
  } catch (error) {
    log.error('[Heartbeat] 💔 FALLO CRÍTICO AL ENVIAR LATIDO.', error)
    isProducerHealthy = false
  }
}

/**
 * Marca como procesados (ProcessedAt) SOLO los Id cuyo publish ya se confirmó.
 * Los que fallaron quedan ProcessedAt NULL y el próximo poll los reintenta.
 */
async function markProcessed(ids: Array<number | string>): Promise<void> {
  if (ids.length === 0) return
  const pool = getDbPool()
  await pool.request().input('Ids', sql.VarChar(sql.MAX), ids.join(',')).execute('sp_MarkChangesProcessed')
}

const GUID_RE = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/

/**
 * 🔧 SHIFT-CLOSE SUPPRESSION (H-4/H-13/H-17): returns true if a DELETEd temp* entity was ARCHIVED
 * to its permanent counterpart (cheques/cheqdet/chequespagos) — i.e. the DELETE is part of a shift
 * close, NOT a real cancellation. Version-agnostic (v11 WorkspaceId, v10 idturno:folio) and
 * timing-robust: the shift-close archives (INSERT into the permanent table) BEFORE deleting from
 * temp*, so by the time we process the delete-tracking row the archived row already exists. This
 * replaces the old closedShiftIdsInBatch heuristic (v10-only and broken: it matched
 * Operation.includes('UPDATE') but the trigger emits 'CLOSED', so the set was always empty).
 * On a malformed EntityId it returns false (publish, don't risk swallowing a real cancellation);
 * DB errors propagate so the per-change handler leaves the row unprocessed and retries next poll.
 */
async function wasArchived(pool: sql.ConnectionPool, entityType: string, entityId: string): Promise<boolean> {
  const table =
    entityType === 'order' ? 'cheques' : entityType === 'orderitem' ? 'cheqdet' : entityType === 'payment' ? 'chequespagos' : null
  if (!table) return false

  if (usesWorkspaceId) {
    // v11/v12: EntityId is the entity's own WorkspaceId (items may be "WorkspaceId:movimiento").
    const wid = entityId.split(':')[0]
    if (!GUID_RE.test(wid)) return false
    const res = await pool
      .request()
      .input('wid', sql.UniqueIdentifier, wid)
      .query(`SELECT TOP 1 1 AS x FROM ${table} WHERE WorkspaceId = @wid`)
    return res.recordset.length > 0
  }

  // v10: order = Instance:Turno:Folio ; orderitem = Instance:Turno:Folio:Mov ; payment = Instance:Folio:PAY
  const parts = entityId.split(':')
  if (entityType === 'order' && parts.length === 3) {
    const res = await pool
      .request()
      .input('t', sql.BigInt, parts[1])
      .input('f', sql.BigInt, parts[2])
      .query('SELECT TOP 1 1 AS x FROM cheques WHERE idturno = @t AND folio = @f')
    return res.recordset.length > 0
  }
  if (entityType === 'orderitem' && parts.length === 4) {
    const res = await pool
      .request()
      .input('f', sql.BigInt, parts[2])
      .input('m', sql.Int, parts[3])
      .query('SELECT TOP 1 1 AS x FROM cheqdet WHERE folio = @f AND movimiento = @m')
    return res.recordset.length > 0
  }
  if (entityType === 'payment' && parts.length >= 2) {
    const res = await pool
      .request()
      .input('f', sql.BigInt, parts[parts.length - 2])
      .query('SELECT TOP 1 1 AS x FROM chequespagos WHERE folio = @f')
    return res.recordset.length > 0
  }
  return false
}

/**
 * Debouncing de actualizaciones de orden. CLAVE de durabilidad: los Id de
 * tracking NO se marcan procesados en el poll; este timer los marca SOLO tras
 * un publish confirmado. Si el publish falla (o el proceso muere antes), las
 * filas siguen ProcessedAt NULL y el próximo poll las reintenta → no se pierde
 * el evento. Acumula los Id de cada re-lectura del mismo cambio y NO reinicia
 * el timer en re-lecturas (el poll re-lee filas pendientes cada 2s; reiniciar
 * el timer de 2.5s en cada una lo dejaría sin disparar nunca = inanición).
 */
async function debounceAndSendOrderUpdate(change: ChangeNotification) {
  const existing = debouncedOrders.get(change.EntityId)
  if (existing && existing.ids.has(change.Id)) {
    // Re-lectura de una fila ya en cola (aún sin marcar): no reiniciar el timer.
    existing.change = change
    return
  }

  const ids = existing ? existing.ids : new Set<number | string>()
  ids.add(change.Id)
  if (existing) clearTimeout(existing.timer)

  log.info(`[Debouncer] ⏳ Cambio para la orden ${change.EntityId}. Temporizador de ${ORDER_DEBOUNCE_MS}ms...`)

  const timer = setTimeout(async () => {
    const entry = debouncedOrders.get(change.EntityId)
    debouncedOrders.delete(change.EntityId)
    if (!entry) return
    try {
      const { venueId, posType } = loadConfig()
      const result = await processOrderChange(entry.change, venueId)
      if (result && result.payload) {
        const routingKey = `pos.${posType}.order.updated`
        await publishMessage(POS_EVENTS_EXCHANGE, routingKey, result.payload)
        log.info(`[Debouncer] ✅ Evento enviado: ${routingKey} para ${change.EntityId}`)
      }
      // Publish confirmado (o sin payload que enviar): recién ahora marcamos.
      await markProcessed([...entry.ids])
    } catch (error) {
      // No marcamos: el próximo poll re-lee (ProcessedAt NULL) y reintenta.
      log.error(`[Debouncer] Error en publish debounced de ${change.EntityId}; se reintentará en el próximo poll.`, error)
    }
  }, ORDER_DEBOUNCE_MS)

  debouncedOrders.set(change.EntityId, { timer, ids, change })
}

/**
 * Busca cambios en la base de datos del POS.
 */
async function pollForChanges() {
  if (!isProducerHealthy) {
    log.warn('[Producer] El polling está en pausa debido a un fallo en el heartbeat.')
    return
  }
  // ✅ GUARD ANTI-SOLAPE: setInterval no espera al ciclo anterior. Sin esto,
  // un lote lento (>2s) provocaba polls concurrentes leyendo la misma ventana
  // del cursor → eventos duplicados y carreras sobre lastSyncTimestamp.
  if (isPollInProgress) {
    return
  }
  // Sin RabbitMQ no podemos publicar: diferimos el polling para NO marcar
  // cambios como procesados sin haberlos enviado (se perderían). Quedan en
  // AvoqadoTracking (ProcessedAt NULL) y se envían cuando la conexión vuelve.
  if (!isRabbitConnected()) {
    return
  }
  isPollInProgress = true
  try {
    const pool = getDbPool()
    const result = await pool.request().input('MaxResults', sql.Int, 100).execute('sp_GetPendingChanges')

    const changes = result.recordset as ChangeNotification[]
    await maybePurgeTracking(pool)
    if (changes.length === 0) return

    log.info(`[Producer] 🎯 ${changes.length} nuevos cambios detectados.`)
    const { venueId, posType } = loadConfig()
    // 🔧 SHIFT-CLOSE SUPPRESSION moved to a robust, version-agnostic per-change check (wasArchived):
    // a temp* DELETE is archival (not a real cancellation) iff the entity exists in its permanent
    // table. The old closedShiftIdsInBatch heuristic was v10-only and broken — it matched
    // Operation.includes('UPDATE') but the shift trigger emits 'CLOSED', so the set was always empty.
    // Solo marcaremos procesados los Id cuyo publish se confirme (los debounced
    // los marca su propio timer). Los fallidos quedan pendientes → se reintentan.
    const succeededIds: Array<number | string> = []

    for (const change of changes) {
      let deferredToDebounce = false
      try {
        let result: { payload: object } | null = null
        // Map CREATE -> created, UPDATE -> updated, DELETE -> deleted, CLOSED -> closed, OPENED -> created
        const operationMap: { [key: string]: string } = {
          CREATE: 'created',
          UPDATE: 'updated',
          DELETE: 'deleted',
          CLOSED: 'closed',
          OPENED: 'created',
        }
        const eventType = operationMap[change.Operation] || 'updated'

        // 🔧 SHIFT-CLOSE SUPPRESSION (H-4/H-13/H-17): a temp* DELETE whose entity was archived to its
        // permanent table (cheques/cheqdet/chequespagos) is part of a shift close, NOT a real
        // cancellation — suppress the spurious deleted/CANCELLED event. Applies uniformly to
        // order/orderitem/payment, for v11 (WorkspaceId) and v10 (idturno:folio).
        if (eventType === 'deleted' && (await wasArchived(pool, change.EntityType, change.EntityId))) {
          log.info(
            `[Producer-Context] 🗄️ ${change.EntityType} ${change.EntityId} fue archivado (cierre de turno) — suprimiendo borrado espurio.`,
          )
          succeededIds.push(change.Id)
          continue
        }

        switch (change.EntityType) {
          case 'order':
            // ✅ CAMBIO EN LA LÓGICA: En lugar de enviar inmediatamente, llamamos al debouncer.
            // Esto se aplica si el cambio es 'updated' o el genérico 'item_change'.
            if (eventType === 'updated' || eventType === 'change') {
              await debounceAndSendOrderUpdate(change)
              deferredToDebounce = true
            } else {
              // Para 'created' o 'deleted', enviamos inmediatamente.
              const pendingDebounce = debouncedOrders.get(change.EntityId)
              if (pendingDebounce) {
                log.info(`[Producer] 🚫 Cancelando actualización debounced para ${change.EntityId} debido a un evento inmediato.`)
                clearTimeout(pendingDebounce.timer)
                debouncedOrders.delete(change.EntityId)
              }
              // (Shift-close delete suppression is handled uniformly before the switch via wasArchived.)
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
              // Use the eventType directly since we now map CLOSED -> closed and OPENED -> created
              let finalEventType = eventType

              // Only override for 'updated' events if we need to check the actual status
              if (eventType === 'updated') {
                // For updated shifts, check if they're actually closed based on the shift data
                const shiftStatus = (result.payload as any).shiftData.status
                finalEventType = shiftStatus === 'CLOSED' ? 'closed' : 'updated'
              }

              const routingKey = `pos.${posType}.shift.${finalEventType}`
              await publishMessage(POS_EVENTS_EXCHANGE, routingKey, result.payload)
              log.info(`[Producer] ✅ Evento enviado: ${routingKey} para ${change.EntityId}`)
            }
            break

          case 'payment':
            // 🔧 H-3: payment changes reach the backend via the accompanying order.updated event,
            // which now ALWAYS carries the payments[] array (including partials, pagado=0). We ack
            // here (previously this row fell through and was silently marked processed). A dedicated
            // pos.*.payment.* event can be added later if/when the backend consumes one.
            log.info(`[Producer] 💳 Cambio de pago ${change.EntityId} (${change.Operation}) → reflejado vía order.updated.`)
            break
        }
        // Llegamos aquí sin excepción: el publish (o el skip intencional) tuvo
        // éxito. Los debounced se marcan en su propio timer, no aquí.
        if (!deferredToDebounce) succeededIds.push(change.Id)
      } catch (error) {
        // El publish lanzó: NO marcamos esta fila → el próximo poll la reintenta.
        log.error(`[Producer] Error procesando la entidad ${change.EntityType}:${change.EntityId}; se reintentará.`, error)
      }
    }

    // Marcar procesados SOLO los cambios cuyo publish se confirmó. Los fallidos
    // y los diferidos al debounce NO se marcan aquí → no se pierden eventos.
    await markProcessed(succeededIds)

    // Avanzar el cursor compuesto y persistirlo en disco: capa de resiliencia
    // adicional al ProcessedAt. Si el servicio muere aquí en adelante, al
    // reiniciar retoma desde el último lote confirmado en lugar de mirar solo
    // 5 minutos hacia atrás (que perdía eventos de caídas largas).
    const lastChange = changes[changes.length - 1]
    lastSyncTimestamp = lastChange.Timestamp
    // El driver mssql devuelve BIGINT como string: normalizar a número.
    lastSyncId = Number(lastChange.Id ?? 0)
    saveSyncCursor({ lastModifiedAt: lastSyncTimestamp, lastId: lastSyncId })
  } catch (error) {
    log.error('[Producer] Error en el ciclo de polling principal.', error)
  } finally {
    isPollInProgress = false
  }
}

/**
 * Purga diaria de AvoqadoTracking: sin esto la tabla crece para siempre y el
 * poll de cada 2 segundos paga un scan cada vez más caro en el SQL Express del
 * venue. Borra los registros ya procesados (ProcessedAt) y los errores de
 * trigger más antiguos que PURGE_DAYS_TO_KEEP días, vía sp_CleanupOldTrackingRecords
 * (Modelo A, instalado por 01-COMPLETE-INSTALL.sql).
 */
async function maybePurgeTracking(pool: sql.ConnectionPool): Promise<void> {
  if (Date.now() - lastPurgeAt < PURGE_INTERVAL_MS) return
  lastPurgeAt = Date.now()
  try {
    await pool.request().input('DaysToKeep', sql.Int, PURGE_DAYS_TO_KEEP).execute('sp_CleanupOldTrackingRecords')
    log.info(`[Producer] 🧹 Limpieza de tracking ejecutada (registros procesados/errores con más de ${PURGE_DAYS_TO_KEEP} días).`)
  } catch (error) {
    log.warn('[Producer] No se pudo ejecutar sp_CleanupOldTrackingRecords (¿falta 01-COMPLETE-INSTALL.sql?).', error)
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

    // ✅ Validar que orderIdTurno sea un número válido
    const numericIdTurno = parseInt(orderIdTurno)
    const isValidNumber = !isNaN(numericIdTurno) && isFinite(numericIdTurno)

    if (!orderIdTurno || orderIdTurno === 0 || orderIdTurno === '0' || !isValidNumber || numericIdTurno === 0) {
      // Si la orden no tiene idturno asignado o es inválido, buscar el shift abierto más reciente
      log.info(`[Order Processor] Orden sin idturno válido (${orderIdTurno}). Buscando shift abierto...`)
      query = 'SELECT TOP 1 WorkspaceId FROM turnos WHERE cierre IS NULL ORDER BY apertura DESC'
      shiftRes = await pool.request().query(query)
    } else {
      // Si la orden tiene idturno válido, buscar ese shift específico
      log.info(`[Order Processor] Buscando shift específico con idturno: ${numericIdTurno}`)
      query = 'SELECT WorkspaceId FROM turnos WHERE idturno = @idturno'
      shiftRes = await pool.request().input('idturno', sql.BigInt, numericIdTurno).query(query)
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

async function getShiftDataForOrderV11(pool: any, orderIdTurno: any, orderWorkspaceId: string): Promise<{ externalId: string }> {
  try {
    // In v11, shifts have their own WorkspaceId and orders might have idturno=0
    // We need to find the appropriate shift for this order
    let query: string
    let shiftRes: any

    // ✅ Validar que orderIdTurno sea un número válido
    const numericIdTurno = parseInt(orderIdTurno)
    const isValidNumber = !isNaN(numericIdTurno) && isFinite(numericIdTurno)

    if (!orderIdTurno || orderIdTurno === 0 || orderIdTurno === '0' || !isValidNumber || numericIdTurno === 0) {
      // For orders with idturno=0 or invalid, find the most recent open shift
      log.info(`[Order Processor v11] Orden sin idturno válido (${orderIdTurno}). Buscando shift abierto más reciente...`)
      query = 'SELECT TOP 1 WorkspaceId, idturno FROM turnos WHERE cierre IS NULL ORDER BY apertura DESC'
      shiftRes = await pool.request().query(query)
    } else {
      // For orders with a real idturno, find that specific shift
      log.info(`[Order Processor v11] Buscando shift específico con idturno: ${numericIdTurno}`)
      query = 'SELECT WorkspaceId, idturno FROM turnos WHERE idturno = @idturno'
      shiftRes = await pool.request().input('idturno', sql.BigInt, numericIdTurno).query(query)
    }

    if (shiftRes.recordset[0] && shiftRes.recordset[0].WorkspaceId) {
      const shiftWorkspaceId = shiftRes.recordset[0].WorkspaceId
      const shiftIdTurno = shiftRes.recordset[0].idturno
      log.info(`[Order Processor v11] Shift encontrado - WorkspaceId: ${shiftWorkspaceId}, idturno: ${shiftIdTurno}`)

      // In v11, we use the shift's WorkspaceId as the externalId
      return { externalId: shiftWorkspaceId }
    } else {
      log.warn('[Order Processor v11] No se encontró shift válido. Usando idturno como fallback.')
      return { externalId: orderIdTurno?.toString() || '0' }
    }
  } catch (error) {
    log.error('[Order Processor v11] Error buscando shift data:', error)
    return { externalId: orderIdTurno?.toString() || '0' }
  }
}

async function processOrderChange(change: ChangeNotification, venueId: string): Promise<{ payload: object } | null> {
  try {
    // Use detected version instead of EntityId format detection
    if (detectedVersion === null) {
      log.error('[Order Processor] Versión no detectada. No se puede procesar la orden.')
      return null
    }

    if (usesWorkspaceId) {
      // v11 format: WorkspaceId
      return await processOrderChangeV11(change, venueId, change.EntityId)
    } else {
      // v10 format: INSTANCE:TURNO:FOLIO
      const parts = change.EntityId.split(':')
      if (parts.length !== 3) {
        log.error(`[Order Processor] EntityId v10 inválido: ${change.EntityId}`)
        return null
      }
      return await processOrderChangeV10(change, venueId, parts)
    }
  } catch (error) {
    log.error(`[Order Processor] Error fatal procesando orden ${change.EntityId}:`, error)
    return null
  }
}

async function processOrderChangeV10(change: ChangeNotification, venueId: string, parts: string[]): Promise<{ payload: object } | null> {
  try {
    const [instanceId, idturno, folio] = parts

    if (change.Operation === 'DELETE') {
      return { payload: { venueId, orderData: { externalId: change.EntityId, status: 'CANCELLED' } } }
    }

    const pool = getDbPool()
    const request = pool.request()
    let query: string

    // ✅ Validar que idturno sea un número válido
    const numericIdTurno = parseInt(idturno)
    const isValidIdTurno = !isNaN(numericIdTurno) && isFinite(numericIdTurno)

    // Si idturno está presente y es válido, buscamos con él.
    if (idturno && idturno !== 'null' && isValidIdTurno) {
      log.info(`[Order Processor] Buscando orden con idturno ${numericIdTurno} y folio ${folio}`)
      request.input('idturno', sql.BigInt, numericIdTurno)
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
    // 🔧 H-3 FIX: include recorded payments ALWAYS (not only when pagado=1). Partial payments leave
    // pagado=0, so the old guard hid them from the backend until the order was fully paid. The query
    // returns 0 rows for unpaid orders, so this stays empty when there are genuinely no payments.
    {
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
        log.info(`[Order Processor] ${paymentsData.length} pago(s) para la orden ${folio} (pagado=${posData.pagado ? 1 : 0}).`)
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
    log.error(`[Order Processor v10] Error fatal procesando orden ${change.EntityId}:`, error)
    return null
  }
}

async function processOrderChangeV11(
  change: ChangeNotification,
  venueId: string,
  workspaceId: string,
): Promise<{ payload: object } | null> {
  try {
    if (change.Operation === 'DELETE') {
      return { payload: { venueId, orderData: { externalId: change.EntityId, status: 'CANCELLED' } } }
    }

    const pool = getDbPool()

    // For v11, we query by WorkspaceId instead of idturno+folio
    log.info(`[Order Processor v11] Buscando orden con WorkspaceId ${workspaceId}`)
    const orderRes = await pool
      .request()
      .input('workspaceId', sql.UniqueIdentifier, workspaceId)
      .query('SELECT * FROM tempcheques WHERE WorkspaceId = @workspaceId')

    if (!orderRes.recordset[0]) {
      log.warn(`[Order Processor v11] No se encontraron datos para WorkspaceId ${workspaceId}.`)
      return null
    }

    const posData = orderRes.recordset[0]

    // Get staff data (same as v10)
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

    // Get area data (same as v10)
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

    // Get payments data (same as v10)
    let paymentsData: any[] = []
    // 🔧 H-3 FIX: include recorded payments ALWAYS (not only when pagado=1) so PARTIAL payments
    // reach the backend. Empty for orders with no payments.
    {
      const paymentsRes = await pool
        .request()
        .input('folio', sql.Int, posData.folio)
        .query('SELECT idformadepago, importe, propina, referencia FROM tempchequespagos WHERE folio = @folio')

      if (paymentsRes.recordset.length > 0) {
        paymentsData = paymentsRes.recordset.map(p => ({
          methodExternalId: p.idformadepago.trim(),
          amount: parseFloat(p.importe || 0),
          tipAmount: parseFloat(p.propina || 0),
          reference: p.referencia?.trim() || null,
          posRawData: p,
        }))
        log.info(`[Order Processor v11] ${paymentsData.length} pago(s) para la orden ${posData.folio} (pagado=${posData.pagado ? 1 : 0}).`)
      }
    }

    // Get payment methods catalog (same as v10)
    log.info(`[Order Processor v11] Obteniendo catálogo de formas de pago...`)
    const paymentMethodsRes = await pool.request().query('SELECT idformadepago, descripcion, tipo FROM formasdepago')
    const paymentMethodsCatalog = paymentMethodsRes.recordset

    // For v11, shift data is more complex - we need to find the shift by looking up relationships
    const shiftData = await getShiftDataForOrderV11(pool, posData.idturno, workspaceId)

    const payload = {
      venueId,
      orderData: {
        externalId: change.EntityId, // This is the WorkspaceId
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
      tableData: { externalId: posData.mesa?.toString() || `Mesa ${posData.folio}`, posAreaId: posData.idarearestaurant },
      areaData: { externalId: posData.idarearestaurant, name: posArea?.descripcion || `Área ${posData.idarearestaurant}` },
      shiftData: shiftData,
      payments: paymentsData,
      paymentMethodsCatalog: paymentMethodsCatalog,
    }
    return { payload }
  } catch (error) {
    log.error(`[Order Processor v11] Error fatal procesando orden ${change.EntityId}:`, error)
    return null
  }
}
async function processOrderItemChange(change: ChangeNotification, venueId: string): Promise<{ payload: object } | null> {
  try {
    // Use detected version instead of EntityId format detection
    if (detectedVersion === null) {
      log.error('[OrderItem Processor] Versión no detectada. No se puede procesar el item.')
      return null
    }

    if (usesWorkspaceId) {
      // 🔧 FIX: v11 format is JUST the WorkspaceId (no colon, no sequence)
      // Each order item has its own unique WorkspaceId
      const parts = change.EntityId.split(':')
      if (parts.length !== 1) {
        log.error(`[OrderItem Processor] EntityId v11 inválido: ${change.EntityId} (expected just WorkspaceId, got ${parts.length} parts)`)
        return null
      }
      return await processOrderItemChangeV11(change, venueId, parts)
    } else {
      // v10 format: INSTANCE:TURNO:FOLIO:MOVIMIENTO
      const parts = change.EntityId.split(':')
      if (parts.length !== 4) {
        log.error(`[OrderItem Processor] EntityId v10 inválido: ${change.EntityId}`)
        return null
      }
      return await processOrderItemChangeV10(change, venueId, parts)
    }
  } catch (error) {
    log.error(`[OrderItem Processor] Error fatal procesando item ${change.EntityId}:`, error)
    return null
  }
}

async function processOrderItemChangeV10(
  change: ChangeNotification,
  venueId: string,
  parts: string[],
): Promise<{ payload: object } | null> {
  try {
    const [instanceId, idturno, folio, movimiento] = parts
    const parentOrderExternalId = `${instanceId}:${idturno}:${folio}`

    if (change.Operation === 'DELETE') {
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
      log.warn(`[OrderItem Processor v10] No se encontraron datos para el item ${change.EntityId}.`)
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
    log.error(`[OrderItem Processor v10] Error fatal procesando item ${change.EntityId}:`, error)
    return null
  }
}

async function processOrderItemChangeV11(
  change: ChangeNotification,
  venueId: string,
  parts: string[],
): Promise<{ payload: object } | null> {
  try {
    // 🔧 FIX: In v11, EntityId IS the item's WorkspaceId (not order WorkspaceId + sequence)
    const itemWorkspaceId = parts[0]

    if (change.Operation === 'DELETE') {
      // For DELETE, we can't look up the item anymore, so just return minimal info
      // Backend will handle linking to parent order
      return { payload: { venueId, parentOrderExternalId: null, itemData: { externalId: change.EntityId, deleted: true } } }
    }

    const pool = getDbPool()

    // 🔧 FIX: Query by item's WorkspaceId directly (not by order + movimiento)
    const itemRes = await pool
      .request()
      .input('itemWorkspaceId', sql.UniqueIdentifier, itemWorkspaceId)
      .query(
        `SELECT td.*, p.descripcion as nombreproducto, tc.WorkspaceId as orderWorkspaceId
         FROM tempcheqdet td
         LEFT JOIN productos p ON td.idproducto = p.idproducto
         INNER JOIN tempcheques tc ON td.foliodet = tc.folio
         WHERE td.WorkspaceId = @itemWorkspaceId`,
      )

    if (!itemRes.recordset[0]) {
      log.warn(`[OrderItem Processor v11] No se encontraron datos para el item ${change.EntityId}.`)
      return null
    }

    const posItemData = itemRes.recordset[0]
    const parentOrderExternalId = posItemData.orderWorkspaceId

    const payload = {
      venueId,
      parentOrderExternalId,
      itemData: {
        externalId: change.EntityId,
        sequence: parseInt(posItemData.movimiento || 0), // Get sequence from DB, not from EntityId
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
    log.error(`[OrderItem Processor v11] Error fatal procesando item ${change.EntityId}:`, error)
    return null
  }
}
async function processShiftChange(change: ChangeNotification, venueId: string): Promise<{ payload: object } | null> {
  try {
    // Use detected version instead of EntityId format detection
    if (detectedVersion === null) {
      log.error('[Shift Processor] Versión no detectada. No se puede procesar el turno.')
      return null
    }

    if (usesWorkspaceId) {
      // v11 format: Entity ID is WorkspaceId
      return await processShiftChangeV11(change, venueId, change.EntityId)
    } else {
      // v10 format: Entity ID is idturno (numeric)
      return await processShiftChangeV10(change, venueId, change.EntityId)
    }
  } catch (error) {
    log.error(`[Shift Processor] Error fatal procesando turno ${change.EntityId}:`, error)
    return null
  }
}

async function processShiftChangeV10(change: ChangeNotification, venueId: string, idturno: string): Promise<{ payload: object } | null> {
  try {
    // ✅ Validar que idturno sea un número válido
    const numericIdTurno = parseInt(idturno)
    if (isNaN(numericIdTurno) || !isFinite(numericIdTurno)) {
      log.error(`[Shift Processor V10] IdTurno inválido: ${idturno}`)
      return null
    }

    if (change.Operation === 'DELETE') {
      // Para deletes, necesitamos buscar el WorkspaceId antes de que se elimine
      const pool = getDbPool()
      const shiftRes = await pool
        .request()
        .input('idturno', sql.BigInt, numericIdTurno)
        .query('SELECT WorkspaceId FROM turnos WHERE idturno = @idturno')
      const workspaceId = shiftRes.recordset[0]?.WorkspaceId || idturno // Fallback al idturno si no se encuentra
      return { payload: { venueId, shiftData: { externalId: workspaceId, status: 'DELETED' } } }
    }

    const pool = getDbPool()
    const shiftRes = await pool
      .request()
      .input('idturno', sql.BigInt, numericIdTurno)
      .query('SELECT * FROM turnos WHERE idturno = @idturno')
    if (!shiftRes.recordset[0]) {
      log.warn(`[Shift Processor v10] No se encontraron datos para el turno ${idturno}.`)
      return null
    }

    const posShift = shiftRes.recordset[0]
    return {
      payload: {
        venueId,
        shiftData: {
          externalId: posShift.WorkspaceId || idturno, // Use WorkspaceId if available, fallback to idturno
          startTime: posShift.apertura ? new Date(posShift.apertura).toISOString() : null,
          endTime: posShift.cierre ? new Date(posShift.cierre).toISOString() : null,
          staffId: posShift.idmesero,
          status: posShift.cierre ? 'CLOSED' : 'OPEN',
          posRawData: posShift,
        },
      },
    }
  } catch (error) {
    log.error(`[Shift Processor v10] Error fatal procesando turno ${idturno}:`, error)
    return null
  }
}

async function processShiftChangeV11(
  change: ChangeNotification,
  venueId: string,
  workspaceId: string,
): Promise<{ payload: object } | null> {
  try {
    if (change.Operation === 'DELETE') {
      // For v11 deletes, EntityId is already the WorkspaceId
      return { payload: { venueId, shiftData: { externalId: workspaceId, status: 'DELETED' } } }
    }

    const pool = getDbPool()
    const shiftRes = await pool
      .request()
      .input('workspaceId', sql.UniqueIdentifier, workspaceId)
      .query('SELECT * FROM turnos WHERE WorkspaceId = @workspaceId')

    if (!shiftRes.recordset[0]) {
      log.warn(`[Shift Processor v11] No se encontraron datos para el turno ${workspaceId}.`)
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
    log.error(`[Shift Processor v11] Error fatal procesando turno ${workspaceId}:`, error)
    return null
  }
}

/**
 * Detecta la versión de SoftRestaurant desde la base de datos
 */
const detectSoftRestaurantVersion = async (): Promise<number> => {
  try {
    const pool = getDbPool()
    const result = await pool.request().query('SELECT versiondb FROM parametros2')
    if (result.recordset.length === 0) {
      log.warn('[Producer] No se encontró versión en parametros2, asumiendo v10.0')
      return 10.0
    }
    const version = parseFloat(result.recordset[0].versiondb) || 10.0
    log.info(`[Producer] 🔍 Versión de SoftRestaurant detectada: ${version}`)
    return version
  } catch (error) {
    log.error('[Producer] Error detectando versión, asumiendo v10.0:', error)
    return 10.0
  }
}

/**
 * Detecta si la DB usa WorkspaceId (presencia de la columna en tempcheques).
 * Es el MISMO criterio que usa el SQL de instalación para elegir el formato de
 * entity-id, así producer y triggers nunca se contradicen (p. ej. una DB
 * versiondb=10.x que sí tiene WorkspaceId genera GUIDs y debe ir por el path v11).
 */
const detectWorkspaceIdSupport = async (): Promise<boolean> => {
  try {
    const pool = getDbPool()
    const result = await pool.request().query("SELECT COL_LENGTH('tempcheques','WorkspaceId') AS wid")
    return result.recordset[0]?.wid != null
  } catch (error) {
    log.error('[Producer] Error detectando soporte de WorkspaceId, asumiendo que NO:', error)
    return false
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
export const startProducer = async () => {
  log.info(`🛡️ Iniciando Producer Resiliente v${PRODUCER_VERSION} (con Debounce, Detección de Versión y Cursor Durable)...`)

  try {
    // ✅ NUEVO: Detectar versión de SoftRestaurant al iniciar
    detectedVersion = await detectSoftRestaurantVersion()
    log.info(`[Producer] ✅ Versión detectada y configurada: ${detectedVersion}`)

    // ✅ NUEVO: Actualizar la configuración con la versión detectada
    updateDetectedVersion(detectedVersion)

    // Decidir el formato de entity-id por presencia de WorkspaceId (alineado con el
    // SQL/triggers), no por el número de versión: hay DBs versiondb=10.x CON WorkspaceId.
    usesWorkspaceId = await detectWorkspaceIdSupport()
    log.info(`[Producer] 🔑 Formato de entity-id: ${usesWorkspaceId ? 'WorkspaceId' : 'v10 (Instance:Turno:Folio)'}`)

    // Recuperar el cursor durable ANTES de empezar a poll-ear: si el servicio
    // estuvo caído horas, retoma desde el último lote confirmado y no pierde nada.
    const cursor = loadSyncCursor()
    lastSyncTimestamp = cursor.lastModifiedAt
    lastSyncId = cursor.lastId
    log.info(`[Producer] 📍 Cursor de sincronización: ${lastSyncTimestamp.toISOString()} (Id ${lastSyncId})`)

    // Establecer estado inicial
    serviceStateManager.start()

    // Iniciar componentes
    startPolling()
    startHeartbeat()
  } catch (error) {
    log.error('[Producer] Error fatal al inicializar producer:', error)
    serviceStateManager.stop('Error al detectar versión de SoftRestaurant')
  }
}
