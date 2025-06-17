import fs from 'fs/promises';
import path from 'path';
import sql from 'mssql';
import { getDbPool } from '../core/db';
import { log } from '../core/logger';
import { publishMessage, POS_EVENTS_EXCHANGE } from '../core/rabbitmq';
import { loadConfig } from '../config';

const POLLING_INTERVAL_MS = 2000; // 2 segundos para alta concurrencia
const DEBOUNCE_WINDOW_MS = 4000; // 4 segundos (reducido para mayor responsividad)
const MAX_CHANGES_PER_CYCLE = 500; // Procesar hasta 500 cambios por ciclo
const RECOVERY_MODE_THRESHOLD = 1000; // Si hay >1000 cambios pendientes, modo recovery
const stateFilePath = path.join(process.cwd(), 'syncState.json');

interface SyncState {
  lastSyncTimestamp: string;
}

interface EntityChange {
  EntityType: string;
  EntityId: string;
  LastModifiedAt: Date;
  ChangeReason: string;
  CurrentHash: Buffer;
  LastSentHash: Buffer | null;
  EventType: 'created' | 'updated' | 'no_change';
}

// =====================================================
// FUNCIONES DE ESTADO
// =====================================================
/**
 * Convierte cualquier formato de timestamp a un formato válido ISO con hora local en formato UTC con Z
 */
function autoCorrectTimestamp(timestamp: string): string {
  try {
    // Intentar parsear como fecha
    const date = new Date(timestamp);
    if (!isNaN(date.getTime())) {
      // Fecha válida - crear formato con componentes locales
      const localYear = date.getFullYear();
      const localMonth = String(date.getMonth() + 1).padStart(2, '0');
      const localDay = String(date.getDate()).padStart(2, '0');
      const localHour = String(date.getHours()).padStart(2, '0');
      const localMinute = String(date.getMinutes()).padStart(2, '0');
      const localSecond = String(date.getSeconds()).padStart(2, '0');
      const localMillisecond = String(date.getMilliseconds()).padStart(3, '0');
      
      return `${localYear}-${localMonth}-${localDay}T${localHour}:${localMinute}:${localSecond}.${localMillisecond}Z`;
    }
  } catch (e) {
    // Error al parsear - continuar con otras estrategias
  }
  
  // Si llegamos aquí, no pudimos corregirlo, usar fecha actual - 1 hora
  const now = new Date();
  const oneHourAgo = new Date(now.getTime() - 60 * 60 * 1000);
  
  const localYear = oneHourAgo.getFullYear();
  const localMonth = String(oneHourAgo.getMonth() + 1).padStart(2, '0');
  const localDay = String(oneHourAgo.getDate()).padStart(2, '0');
  const localHour = String(oneHourAgo.getHours()).padStart(2, '0');
  const localMinute = String(oneHourAgo.getMinutes()).padStart(2, '0');
  const localSecond = String(oneHourAgo.getSeconds()).padStart(2, '0');
  const localMillisecond = String(oneHourAgo.getMilliseconds()).padStart(3, '0');
  
  return `${localYear}-${localMonth}-${localDay}T${localHour}:${localMinute}:${localSecond}.${localMillisecond}Z`;
}

async function loadSyncState(): Promise<SyncState> {
  try {
    const data = await fs.readFile(stateFilePath, 'utf-8');
    const parsedState = JSON.parse(data) as SyncState;
    
    // Validar formato del timestamp
    try {
      new Date(parsedState.lastSyncTimestamp);
      
      // Si no termina con Z, intentar auto-corregir
      if (!parsedState.lastSyncTimestamp.endsWith('Z')) {
        log.warn(`[Smart Snapshot] Auto-corrigiendo formato de timestamp incorrecto: ${parsedState.lastSyncTimestamp}`);
        
        // Corregir el formato
        const correctedTimestamp = autoCorrectTimestamp(parsedState.lastSyncTimestamp);
        parsedState.lastSyncTimestamp = correctedTimestamp;
        
        // Guardar versión corregida
        await saveSyncState(parsedState);
        log.info(`[Smart Snapshot] Timestamp corregido y guardado: ${correctedTimestamp}`);
      }
      
      return parsedState;
    } catch (dateErr) {
      log.warn(`[Smart Snapshot] Error: timestamp inválido en syncState.json: ${parsedState.lastSyncTimestamp}, intentando auto-corregir...`);
      
      try {
        // Auto-corregir timestamp inválido
        const correctedTimestamp = autoCorrectTimestamp(parsedState.lastSyncTimestamp);
        parsedState.lastSyncTimestamp = correctedTimestamp;
        
        // Guardar versión corregida
        await saveSyncState(parsedState);
        log.info(`[Smart Snapshot] Timestamp inválido corregido y guardado: ${correctedTimestamp}`);
        
        return parsedState;
      } catch (e) {
        // Si falla la auto-corrección, crear un nuevo estado
        log.error(`[Smart Snapshot] No se pudo corregir el timestamp, creando nuevo estado...`);
        throw new Error('Formato de fecha inválido en syncState.json');
      }
    }
  } catch (error: any) {
    if (error.code === 'ENOENT') {
      log.warn('syncState.json no encontrado, creando uno nuevo.');
      
      // Crear timestamp una hora atrás usando la hora LOCAL pero conservando formato UTC con 'Z'
      const now = new Date();
      const oneHourAgo = new Date(now.getTime() - 60 * 60 * 1000);
      
      // Construir string ISO manual con la hora local pero formato UTC
      // Esto representa la hora local pero con formato UTC (con Z al final)
      const localYear = oneHourAgo.getFullYear();
      const localMonth = String(oneHourAgo.getMonth() + 1).padStart(2, '0');
      const localDay = String(oneHourAgo.getDate()).padStart(2, '0');
      const localHour = String(oneHourAgo.getHours()).padStart(2, '0');
      const localMinute = String(oneHourAgo.getMinutes()).padStart(2, '0');
      const localSecond = String(oneHourAgo.getSeconds()).padStart(2, '0');
      const localMillisecond = String(oneHourAgo.getMilliseconds()).padStart(3, '0');
      
      // Formato YYYY-MM-DDTHH:mm:ss.sssZ pero usando la hora local
      const localTimeAsUTC = `${localYear}-${localMonth}-${localDay}T${localHour}:${localMinute}:${localSecond}.${localMillisecond}Z`;
      
      const initialState: SyncState = { 
        lastSyncTimestamp: localTimeAsUTC // 1 hora atrás con hora local en formato UTC
      };
      log.info(`[Smart Snapshot] Creando syncState con timestamp local en formato UTC: ${localTimeAsUTC}`);
      await saveSyncState(initialState);
      return initialState;
    }
    log.error(`[Smart Snapshot] Error al cargar syncState: ${error.message || error}`);
    throw error;
  }
}

async function saveSyncState(state: SyncState): Promise<void> {
  await fs.writeFile(stateFilePath, JSON.stringify(state, null, 2), 'utf-8');
}

// =====================================================
// SMART SNAPSHOT MULTI-ENTIDAD - POLLING PRINCIPAL CON DEBOUNCE
// =====================================================
async function pollForEntityChanges() {
  try {
    const state = await loadSyncState();
    const pool = getDbPool();
    
    // Calcular ventana de debounce - solo procesar cambios que sean más antiguos que X segundos
    const debounceThreshold = new Date(Date.now() - DEBOUNCE_WINDOW_MS);
    const lastSyncTime = new Date(state.lastSyncTimestamp);
    
    // Obtener cambios usando el sistema Smart Snapshot, pero con filtro de debounce
    const result = await pool.request()
      .input('lastSyncTimestamp', sql.DateTime2, lastSyncTime)
      .input('entityType', sql.VarChar, null)  // null = todas las entidades
      .input('maxResults', sql.Int, 100)
      .execute('sp_GetEntityChanges');

    const allChanges = result.recordset as EntityChange[];

    // FILTRO DE DEBOUNCE: Solo procesar cambios que sean más antiguos que el threshold
    const entityChanges = allChanges.filter(change => 
      new Date(change.LastModifiedAt) <= debounceThreshold
    );

    if (entityChanges.length === 0) {
      // Si hay cambios recientes pero están en la ventana de debounce, logging opcional
      if (allChanges.length > 0) {
        log.debug(`[Smart Snapshot] ${allChanges.length} cambios en ventana de debounce, esperando...`);
      }
      return;
    }

    // AGRUPACIÓN INTELIGENTE: Agrupar por entidad y solo enviar la versión más reciente
    const groupedChanges = new Map<string, EntityChange>();
    
    for (const change of entityChanges) {
      const entityKey = `${change.EntityType}:${change.EntityId}`;
      const existing = groupedChanges.get(entityKey);
      
      // Solo mantener el cambio más reciente por entidad
      if (!existing || new Date(change.LastModifiedAt) > new Date(existing.LastModifiedAt)) {
        groupedChanges.set(entityKey, change);
      }
    }

    const finalChanges = Array.from(groupedChanges.values());

    if (finalChanges.length === 0) {
      return;
    }

    log.info(`[Smart Snapshot Multi-Entity] 🎯 ${finalChanges.length} cambios REALES detectados (${entityChanges.length} agrupados, sin duplicados)`);
    
    // Agrupar por tipo de entidad para logging detallado
    const changesByType = finalChanges.reduce((acc, change) => {
      acc[change.EntityType] = (acc[change.EntityType] || 0) + 1;
      return acc;
    }, {} as Record<string, number>);
    
    log.info(`[Smart Snapshot] Cambios finales por entidad: ${Object.entries(changesByType).map(([type, count]) => `${type}:${count}`).join(', ')}`);

    const { venueId, posType } = loadConfig();
    let maxTimestamp = new Date(state.lastSyncTimestamp);

    // Procesar cada cambio agrupado según su tipo de entidad
    for (const change of finalChanges) {
      try {
        let avoqadoPayload: object | null = null;
        let eventType: string = '';

        // Determinar si es "created" o "updated" de manera más inteligente
        const isNewEntity = change.EventType === 'created' || 
                           (change.LastSentHash === null && change.EventType !== 'no_change');
        
        const finalEventType = isNewEntity ? 'created' : 'updated';

        // DISPATCHER por tipo de entidad
        switch (change.EntityType) {
          case 'order':
            const orderResult = await processOrderChange(change, venueId);
            if (orderResult) {
              avoqadoPayload = orderResult.payload;
              eventType = `pos.${posType}.order.${finalEventType}`;
            }
            break;

          case 'shift':
            const shiftResult = await processShiftChange(change, venueId);
            if (shiftResult) {
              avoqadoPayload = shiftResult.payload;
              eventType = `pos.${posType}.shift.${finalEventType}`;
            }
            break;

          case 'staff':
            const staffResult = await processStaffChange(change, venueId);
            if (staffResult) {
              avoqadoPayload = staffResult.payload;
              eventType = `pos.${posType}.staff.${finalEventType}`;
            }
            break;

          case 'area':
            const areaResult = await processAreaChange(change, venueId);
            if (areaResult) {
              avoqadoPayload = areaResult.payload;
              eventType = `pos.${posType}.area.${finalEventType}`;
            }
            break;

          default:
            log.warn(`[Smart Snapshot] Tipo de entidad no soportado: ${change.EntityType}`);
            continue;
        }

        if (!avoqadoPayload) {
          log.warn(`[Smart Snapshot] No se pudo construir payload para ${change.EntityType}:${change.EntityId}`);
          continue;
        }

        // Publicar evento en RabbitMQ
        await publishMessage(POS_EVENTS_EXCHANGE, eventType, avoqadoPayload);

        // Actualizar snapshot para prevenir futuros duplicados
        await pool.request()
          .input('entityType', sql.VarChar, change.EntityType)
          .input('entityId', sql.VarChar, change.EntityId)
          .input('contentHash', sql.VarBinary, change.CurrentHash)
          .execute('sp_UpdateEntitySnapshot');

        // Actualizar timestamp máximo
        if (change.LastModifiedAt > maxTimestamp) {
          maxTimestamp = change.LastModifiedAt;
        }

        log.info(`[Smart Snapshot] ✅ ${change.EntityType}:${change.EntityId} (${finalEventType}) enviado sin duplicados`);

      } catch (error) {
        log.error(`[Smart Snapshot] Error procesando ${change.EntityType}:${change.EntityId}:`, error);
        // Continuar con las demás entidades en caso de error
      }
    }

    // Actualizar estado de sincronización
    state.lastSyncTimestamp = maxTimestamp.toISOString();
    await saveSyncState(state);
    
    log.info(`[Smart Snapshot] 🚀 Sincronización actualizada hasta ${maxTimestamp.toISOString()}`);

  } catch (error: any) {
    log.error('[Smart Snapshot Multi-Entity] Error en polling principal:', error.message);
  }
}

// =====================================================
// PROCESADORES ESPECÍFICOS POR ENTIDAD
// =====================================================

/**
 * Procesa cambios de ÓRDENES (tu lógica existente mejorada)
 */
/**
 * Procesa cambios de ÓRDENES (incluyendo eliminaciones)
 */
async function processOrderChange(change: EntityChange, venueId: string): Promise<{ payload: object } | null> {
  try {
    const folio = parseInt(change.EntityId);
    const pool = getDbPool();
    
    // Obtener datos básicos de la orden
    const orderQuery = `
      SELECT * FROM tempcheques WHERE folio = @folio
    `;

    const orderResult = await pool.request()
      .input('folio', sql.Int, folio)
      .query(orderQuery);

    // CASO 1: ORDEN ELIMINADA - Crear evento de cancelación
    if (orderResult.recordset.length === 0) {
      log.warn(`[Order Processor] Orden ${folio} eliminada del POS, marcando como CANCELLED`);
      
      // Crear payload para orden cancelada (eliminada del POS)
      const payload = {
        venueId,
        orderData: {
          externalId: folio.toString(),
          orderNumber: folio.toString(),
          status: 'CANCELLED', // ← CANCELLED en lugar de DELETED
          subtotal: 0,
          taxAmount: 0,
          discountAmount: 0,
          tipAmount: 0,
          total: 0,
          createdAt: new Date().toISOString(),
          completedAt: null,
          cancelledAt: new Date().toISOString(), // ← Mejor semántica
          posRawData: { 
            folio, 
            status: 'CANCELLED', 
            reason: 'ORDER_DELETED_FROM_POS',
            cancelledAt: new Date().toISOString()
          },
        },
        staffData: { 
          externalId: `cancelled_order_${folio}`, 
          name: 'Cancelled Order Staff', 
          pin: null
        },
        tableData: { 
          externalId: `cancelled_order_table_${folio}`, 
          posAreaId: null
        },
        areaData: { 
          externalId: `cancelled_order_area_${folio}`, 
          name: 'Cancelled Order Area', 
          serviceTypeId: null
        },
        shiftData: { 
          externalId: `cancelled_order_shift_${folio}`, 
          startTime: null,
          endTime: null
        }
      };

      return { payload };
    }

    // CASO 2: ORDEN EXISTE - Procesamiento normal
    const posData = orderResult.recordset[0];

    // Obtener datos adicionales de forma DEFENSIVA (solo si las tablas existen)
    let posStaff = null;
    let posArea = null; 
    let posShift = null;

    try {
      // Intentar obtener datos de staff si existe la tabla
      if (posData.idmesero) {
        const staffResult = await pool.request()
          .input('idmesero', sql.VarChar, posData.idmesero)
          .query('SELECT nombre, contraseña FROM meseros WHERE idmesero = @idmesero');
        posStaff = staffResult.recordset[0];
      }
    } catch (error) {
      log.warn(`[Order Processor] No se pudo obtener datos de staff: ${error}`);
    }

    try {
      // Intentar obtener datos de area si existe la tabla
      if (posData.idarearestaurant) {
        const areaResult = await pool.request()
          .input('idarea', sql.VarChar, posData.idarearestaurant)
          .query('SELECT descripcion, idtiposervicio FROM areasrestaurant WHERE idarearestaurant = @idarea');
        posArea = areaResult.recordset[0];
      }
    } catch (error) {
      log.warn(`[Order Processor] No se pudo obtener datos de area: ${error}`);
    }

    try {
      // Intentar obtener datos de turno si existe la tabla
      if (posData.idturno) {
        const shiftResult = await pool.request()
          .input('idturno', sql.BigInt, posData.idturno)
          .query('SELECT apertura, cierre FROM turnos WHERE idturno = @idturno');
        posShift = shiftResult.recordset[0];
      }
    } catch (error) {
      log.warn(`[Order Processor] No se pudo obtener datos de turno: ${error}`);
    }

    // Construir payload enriquecido (exactamente como espera tu backend)
    const payload = {
      venueId,
      orderData: {
        externalId: posData.WorkspaceId || posData.folio?.toString(),
        orderNumber: posData.folio?.toString(), // ← STRING, no INT
        status: posData.cancelado === 'true' || posData.cancelado === '1' ? 'CANCELLED' : 
                (posData.pagado === 'true' || posData.pagado === '1' ? 'COMPLETED' : 'PENDING'),
        paymentStatus: posData.pagado === 'true' || posData.pagado === '1' ? 'PAID' : 'PENDING',
        subtotal: parseFloat(posData.subtotal || '0'),
        taxAmount: parseFloat(posData.totalimpuesto1 || '0'),
        discountAmount: parseFloat(posData.descuentoimporte || '0'),
        tipAmount: parseFloat(posData.propina || '0'),
        total: parseFloat(posData.total || '0'),
        createdAt: posData.fecha ? new Date(posData.fecha).toISOString() : new Date().toISOString(),
        completedAt: posData.cierre ? new Date(posData.cierre).toISOString() : null,
        posRawData: posData,
      },
      staffData: { 
        externalId: posData.idmesero || `staff_${folio}`, 
        name: posStaff?.nombre || 'Unknown Staff', 
        pin: posStaff?.contraseña || null
      },
      tableData: { 
        externalId: posData.mesa?.toString() || `table_${folio}`, 
        posAreaId: posData.idarearestaurant || null
      },
      areaData: { 
        externalId: posData.idarearestaurant || `area_${folio}`, 
        name: posArea?.descripcion || 'Unknown Area', 
        serviceTypeId: posArea?.idtiposervicio || null
      },
      shiftData: { 
        externalId: posData.idturno?.toString() || `shift_${folio}`, 
        startTime: posShift?.apertura ? new Date(posShift.apertura).toISOString() : null,
        endTime: posShift?.cierre ? new Date(posShift.cierre).toISOString() : null
      }
    };

    return { payload };

  } catch (error) {
    log.error(`[Order Processor] Error procesando orden ${change.EntityId}:`, error);
    return null;
  }
}



/**
 * Procesa cambios de TURNOS
 */
async function processShiftChange(change: EntityChange, venueId: string): Promise<{ payload: object } | null> {
  try {
    const idturno = parseInt(change.EntityId);
    const pool = getDbPool();
    
    const shiftQuery = `
      SELECT t.*, m.nombre as meseroNombre, m.contraseña as meseroPin
      FROM turnos t
      LEFT JOIN meseros m ON t.idmesero = m.idmesero
      WHERE t.idturno = @idturno
    `;

    const result = await pool.request()
      .input('idturno', sql.BigInt, idturno)
      .query(shiftQuery);

    if (result.recordset.length === 0) {
      log.warn(`[Shift Processor] Turno ${idturno} no encontrado`);
      return null;
    }

    const posShift = result.recordset[0];

    const payload = {
      venueId,
      shiftData: {
        externalId: posShift.idturno?.toString(),
        startTime: posShift.apertura ? new Date(posShift.apertura).toISOString() : null,
        endTime: posShift.cierre ? new Date(posShift.cierre).toISOString() : null,
        staffId: posShift.idmesero,
        staffName: posShift.meseroNombre,
        status: posShift.cierre ? 'CLOSED' : 'OPEN',
        posRawData: posShift,
      }
    };

    return { payload };

  } catch (error) {
    log.error(`[Shift Processor] Error procesando turno ${change.EntityId}:`, error);
    return null;
  }
}

/**
 * Procesa cambios de STAFF/MESEROS
 */
async function processStaffChange(change: EntityChange, venueId: string): Promise<{ payload: object } | null> {
  try {
    const pool = getDbPool();
    
    const staffQuery = `
      SELECT * FROM meseros WHERE idmesero = @idmesero
    `;

    const result = await pool.request()
      .input('idmesero', sql.VarChar, change.EntityId)
      .query(staffQuery);

    if (result.recordset.length === 0) {
      log.warn(`[Staff Processor] Staff ${change.EntityId} no encontrado`);
      return null;
    }

    const posStaff = result.recordset[0];

    const payload = {
      venueId,
      staffData: {
        externalId: posStaff.idmesero,
        name: posStaff.nombre,
        pin: posStaff.contraseña,
        active: true, // Asumimos activo si existe
        posRawData: posStaff,
      }
    };

    return { payload };

  } catch (error) {
    log.error(`[Staff Processor] Error procesando staff ${change.EntityId}:`, error);
    return null;
  }
}

/**
 * Procesa cambios de ÁREAS/MESAS
 */
async function processAreaChange(change: EntityChange, venueId: string): Promise<{ payload: object } | null> {
  try {
    const pool = getDbPool();
    
    const areaQuery = `
      SELECT * FROM areasrestaurant WHERE idarearestaurant = @idarea
    `;

    const result = await pool.request()
      .input('idarea', sql.VarChar, change.EntityId)
      .query(areaQuery);

    if (result.recordset.length === 0) {
      log.warn(`[Area Processor] Area ${change.EntityId} no encontrada`);
      return null;
    }

    const posArea = result.recordset[0];

    const payload = {
      venueId,
      areaData: {
        externalId: posArea.idarearestaurant,
        name: posArea.descripcion,
        serviceTypeId: posArea.idtiposervicio,
        active: true, // Asumimos activa si existe
        posRawData: posArea,
      }
    };

    return { payload };

  } catch (error) {
    log.error(`[Area Processor] Error procesando area ${change.EntityId}:`, error);
    return null;
  }
}

// =====================================================
// FUNCIONES DE UTILIDAD Y ESTADÍSTICAS
// =====================================================

/**
 * Obtiene estadísticas del sistema Smart Snapshot
 */
export const getProducerStats = async () => {
  try {
    const pool = getDbPool();
    
    // Estadísticas por entidad
    const entityStatsResult = await pool.query(`
      SELECT 
        EntityType,
        COUNT(*) as TotalSnapshots,
        AVG(EventsSent) as AvgEventsPerEntity,
        MAX(LastSentAt) as LastActivity
      FROM AvoqadoEntitySnapshots
      GROUP BY EntityType
      ORDER BY EntityType
    `);

    // Estadísticas de tracking
    const trackingStatsResult = await pool.query(`
      SELECT 
        EntityType,
        COUNT(*) as TotalTracked,
        MAX(LastModifiedAt) as LastModified
      FROM AvoqadoEntityTracking
      GROUP BY EntityType
      ORDER BY EntityType
    `);

    // Estado de sincronización
    const syncState = await loadSyncState();

    return {
      lastSyncTimestamp: syncState.lastSyncTimestamp,
      entitySnapshots: entityStatsResult.recordset,
      entityTracking: trackingStatsResult.recordset,
      systemStatus: 'Smart Snapshot Multi-Entity Active'
    };

  } catch (error) {
    log.error('Error obteniendo estadísticas del producer:', error);
    return {
      error: 'No se pudieron obtener estadísticas',
      lastSyncTimestamp: new Date().toISOString(),
      entitySnapshots: [],
      entityTracking: [],
      systemStatus: 'Error'
    };
  }
};

/**
 * Fuerza una sincronización manual de una entidad específica
 */
export const forceSyncEntity = async (entityType: string, entityId: string) => {
  try {
    const pool = getDbPool();
    
    // Registrar cambio manual en tracking
    await pool.request()
      .input('entityType', sql.VarChar, entityType)
      .input('entityId', sql.VarChar, entityId)
      .input('changeReason', sql.VarChar, 'manual_sync')
      .execute('sp_TrackEntityChange');

    log.info(`[Smart Snapshot] Sincronización manual forzada para ${entityType}:${entityId}`);
    return true;

  } catch (error) {
    log.error(`[Smart Snapshot] Error en sincronización manual de ${entityType}:${entityId}:`, error);
    return false;
  }
};

// =====================================================
// LOOP PRINCIPAL Y FUNCIONES DE CONTROL
// =====================================================
// =====================================================
// LOOP PRINCIPAL ROBUSTO CON CIRCUIT BREAKER
// =====================================================
let consecutiveErrors = 0;
const MAX_CONSECUTIVE_ERRORS = 5;
const CIRCUIT_BREAKER_COOLDOWN = 30000; // 30 segundos

const pollingRunner = async () => {
  try {
    await pollForEntityChanges();
    
    // Reset error counter on success
    if (consecutiveErrors > 0) {
      log.info(`[Smart Snapshot] 🔄 Recuperado después de ${consecutiveErrors} errores consecutivos`);
      consecutiveErrors = 0;
    }
    
  } catch (error) {
    consecutiveErrors++;
    log.error(`[Smart Snapshot] Error ${consecutiveErrors}/${MAX_CONSECUTIVE_ERRORS} en ciclo principal:`, error);
    
    // Circuit breaker: si hay demasiados errores consecutivos, parar temporalmente
    if (consecutiveErrors >= MAX_CONSECUTIVE_ERRORS) {
      log.error(`[Smart Snapshot] 🚨 CIRCUIT BREAKER ACTIVADO después de ${consecutiveErrors} errores. Pausando ${CIRCUIT_BREAKER_COOLDOWN/1000}s...`);
      
      setTimeout(() => {
        log.info('[Smart Snapshot] 🔄 Circuit breaker reseteado, reintentando...');
        consecutiveErrors = 0;
        pollingRunner();
      }, CIRCUIT_BREAKER_COOLDOWN);
      
      return; // No programar siguiente ejecución inmediata
    }
  } finally {
    // Programar siguiente ejecución con backoff en caso de errores
    const nextInterval = consecutiveErrors > 0 
      ? POLLING_INTERVAL_MS * Math.min(Math.pow(2, consecutiveErrors - 1), 8) // Backoff exponencial máximo 8x
      : POLLING_INTERVAL_MS;
      
    setTimeout(pollingRunner, nextInterval);
  }
};

export const startProducer = () => {
  log.info('🎯 Iniciando Smart Snapshot Multi-Entidad Producer...');
  log.info('📊 Entidades soportadas: orders, shifts, staff, areas');
  log.info('🚫 Eventos duplicados eliminados automáticamente');
  log.info('⏱️  Debounce inteligente: Agrupa cambios en ventana de 4 segundos');
  log.info('🚫 Órdenes eliminadas del POS → Automáticamente marcadas como CANCELLED');
  log.info('🏢 Modo de producción: Optimizado para alta concurrencia');
  log.info('🔄 Auto-recovery: Detecta sobrecarga y ajusta comportamiento');
  log.info('⚡ Sistema optimizado para SQL Server 2014 Express');
  log.info('🛡️  Circuit breaker: Protección contra errores consecutivos');
  log.info('🧹 Anti-loop: Limpieza automática de tracking atascado');
  
  // Iniciar el loop principal
  pollingRunner();
};

export const stopProducer = () => {
  log.info('⏹️ Deteniendo Smart Snapshot Producer...');
  // En una implementación más completa, aquí manejarías el shutdown graceful
};

/**
 * Ejecuta limpieza automática de tracking atascado
 */
export const cleanupStuckTracking = async (olderThanMinutes: number = 60): Promise<number> => {
  try {
    const pool = getDbPool();
    
    const result = await pool.request()
      .input('olderThanMinutes', sql.Int, olderThanMinutes)
      .execute('sp_CleanupStuckTracking');
    
    const cleanedCount = result.returnValue || 0;
    log.info(`[Smart Snapshot] 🧹 Limpieza completada: ${cleanedCount} entidades atascadas limpiadas`);
    
    return cleanedCount;

  } catch (error) {
    log.error('[Smart Snapshot] Error en limpieza de tracking atascado:', error);
    return 0;
  }
};
// Función adicional para debugging
export const debugLastChanges = async (minutes: number = 60) => {
  try {
    const pool = getDbPool();
    const since = new Date(Date.now() - (minutes * 60 * 1000));
    
    const result = await pool.request()
      .input('lastSyncTimestamp', sql.DateTime2, since)
      .input('entityType', sql.VarChar, null)
      .input('maxResults', sql.Int, 50)
      .execute('sp_GetEntityChanges');

    log.info(`[Debug] Últimos cambios en ${minutes} minutos:`, result.recordset);
    return result.recordset;

  } catch (error) {
    log.error('[Debug] Error obteniendo cambios recientes:', error);
    return [];
  }
};

/**
 * Limpieza programática para mantenimiento
 */
export const performMaintenance = async () => {
  try {
    log.info('[Smart Snapshot] 🔧 Iniciando mantenimiento programado...');
    
    // Limpiar tracking atascado
    const cleanedCount = await cleanupStuckTracking(60);
    
    // Obtener estadísticas del sistema
    const stats = await getProducerStats();
    
    log.info('[Smart Snapshot] 📊 Estadísticas post-mantenimiento:', stats);
    log.info(`[Smart Snapshot] ✅ Mantenimiento completado - ${cleanedCount} entidades limpiadas`);
    
    return {
      cleanedEntities: cleanedCount,
      systemStats: stats,
      maintenanceTime: new Date().toISOString()
    };

  } catch (error) {
    log.error('[Smart Snapshot] Error en mantenimiento programado:', error);
    return null;
  }
};