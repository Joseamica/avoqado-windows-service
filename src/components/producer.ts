import fs from 'fs/promises';
import path from 'path';
import { getDbPool } from '../core/db';
import { log } from '../core/logger';
import { publishMessage, POS_EVENTS_EXCHANGE } from '../core/rabbitmq';
import { loadConfig } from '../config';
import crypto from 'crypto'; // ✅ Importamos el módulo de criptografía

const POLLING_INTERVAL_MS = 15000; // 15 segundos
const STAFF_POLLING_INTERVAL_MS = 300000; // Lo bajamos a 1 minuto para que veas los cambios más rápido
const SHIFT_POLLING_INTERVAL_MS = 15000; // 15 segundos

const stateFilePath = path.resolve(__dirname, '../../syncState.json');

log.info('stateFilePath: ', stateFilePath);
interface SyncState {
  lastOrderCreationTimestamp: string;
  lastOrderUpdateTimestamp: string;
  staffState: { [posStaffId: string]: string }; // ej: { '01': 'hash123', '02': 'hash456' }
  lastShiftOpenTimestamp: string; // ✅ NUEVO
  lastShiftCloseTimestamp: string; // ✅ NUEVO
  // ... aquí añadiremos los otros timestamps más tarde
}

// --- Funciones para manejar el estado ---
async function loadSyncState(): Promise<SyncState> {
  try {
    const data = await fs.readFile(stateFilePath, 'utf-8');
    const state = JSON.parse(data);
    if (!state.staffState) {
      state.staffState = {}; // Inicializamos si no existe
    }
    return state;
  } catch (error: any) {
    if (error.code === 'ENOENT') {
      log.warn('syncState.json no encontrado, se creará uno nuevo.');
      const initialState: SyncState = { 
        lastOrderCreationTimestamp: new Date(0).toISOString(),
        lastOrderUpdateTimestamp: new Date(0).toISOString(),
        staffState: {},
        lastShiftOpenTimestamp: new Date(0).toISOString(), // ✅ NUEVO
        lastShiftCloseTimestamp: new Date(0).toISOString(), // ✅ NUEVO
      };
      await saveSyncState(initialState);
      return initialState;
    }
    throw error;
  }
}

function createStaffHash(staff: { nombre: string, contraseña?: string }): string {
  const data = `${staff.nombre}|${staff.contraseña || ''}`;
  return crypto.createHash('md5').update(data).digest('hex');
}

async function saveSyncState(state: SyncState): Promise<void> {
  await fs.writeFile(stateFilePath, JSON.stringify(state, null, 2), 'utf-8');
}

// --- Lógica de Polling ---
async function pollForNewOrders() {
    try {
      log.info('[Productor] Buscando nuevas órdenes...');
      const pool = getDbPool();
      const state = await loadSyncState();
      const lastTimestamp = state.lastOrderCreationTimestamp;
      
      // ✅ QUERY DEFINITIVA CON LOS NOMBRES DE COLUMNA CORRECTOS
      const query = `
      SELECT 
        tc.*, 
        m.nombre as meseroNombre,
        m.contraseña as meseroPin,    -- CORRECCIÓN: Usamos 'contraseña'
        mesas.personas as mesaCapacidad -- CORRECCIÓN: Usamos 'personas' para la capacidad
      FROM tempcheques tc
      LEFT JOIN meseros m ON tc.idmesero = m.idmesero
      LEFT JOIN mesas ON tc.mesa = mesas.idmesa AND tc.idarearestaurant = mesas.idarearestaurant
      WHERE tc.fecha > @lastSyncTimestamp 
      ORDER BY tc.fecha ASC
    `;
    const result = await pool.request().input('lastSyncTimestamp', lastTimestamp).query(query);

    if (result.recordset.length > 0) {
        log.info(`[Productor] Encontradas ${result.recordset.length} órdenes nuevas.`);
        
        for (const posOrder of result.recordset) {
          
          // ✅ PAYLOAD DEFINITIVO Y ENRIQUECIDO
          const avoqadoPayload = {
            venueId: loadConfig().venueId,
            
            orderData: {
                externalId: posOrder.WorkspaceId,
                orderNumber: posOrder.folio.toString(),
                status: posOrder.cancelado ? 'CANCELLED' : (posOrder.pagado ? 'COMPLETED' : 'PENDING'),
                paymentStatus: posOrder.pagado ? 'PAID' : 'PENDING',
                subtotal: posOrder.subtotal,
                taxAmount: posOrder.totalimpuesto1,
                discountAmount: posOrder.descuentoimporte || 0,
                tipAmount: posOrder.propina || 0,
                total: posOrder.total,
                createdAt: new Date(posOrder.fecha).toISOString(),
                completedAt: posOrder.cierre ? new Date(posOrder.cierre).toISOString() : null,
                posRawData: posOrder,
            
              },
          
              // --- Datos para las entidades relacionadas ---
              staffData: {
                externalId: posOrder.idmesero,
                name: posOrder.meseroNombre,
                pin: posOrder.meseroPin, // Mapeado desde 'contraseña'
              },
              tableData: {
                externalId: posOrder.mesa,
                capacity: posOrder.personas, // Mapeado desde 'personas'
              },
              shiftData: {
                externalId: posOrder.idturno.toString(),
                startTime: posOrder.turnoApertura,
              }
            
          };
          
          const { posType } = loadConfig();
          const routingKey = `pos.${posType}.order.created`; 
          await publishMessage(POS_EVENTS_EXCHANGE, routingKey, avoqadoPayload);
        }
  
        const newTimestamp = result.recordset[result.recordset.length - 1].fecha;
        state.lastOrderCreationTimestamp = new Date(newTimestamp).toISOString();
        await saveSyncState(state);
        log.info(`[Productor] Sincronización de nuevas órdenes actualizada hasta ${state.lastOrderCreationTimestamp}`);
      }
    } catch (error: any) {
      log.error('[Productor] Error durante el polling de nuevas órdenes:', error);
    }
  }

  /**
 * Job para sondear y sincronizar cambios en la tabla de meseros.
 * Usa la estrategia de "snapshotting" al no haber timestamps.
 */
  async function pollForStaffChanges() {
    try {
      log.info('[Productor-Staff] Revisando sincronización de meseros...');
      const pool = getDbPool();
      let state = await loadSyncState();
      
      const query = 'SELECT idmesero, nombre, contraseña FROM meseros WHERE visible = 1';
      const result = await pool.request().query(query);
      const currentStaffList: { idmesero: string, nombre: string, contraseña: string }[] = result.recordset;
  
      const currentStaffMap = new Map(currentStaffList.map(s => [s.idmesero, s]));
      let stateWasModified = false;
  
      // --- LÓGICA DE DETECCIÓN ---
      for (const posStaff of currentStaffList) {
        const oldHash = state.staffState[posStaff.idmesero];
        const newHash = createStaffHash(posStaff);
  
        if (!oldHash) {
          // 1. DETECTAR NUEVOS: Si no había un hash, es un mesero nuevo.
          log.info(`[Productor-Staff] NUEVO mesero detectado: ${posStaff.nombre} (${posStaff.idmesero})`);
          const payload = { venueId: loadConfig().venueId, staffData: { ...posStaff, externalId: posStaff.idmesero, pin: posStaff.contraseña } };
          await publishMessage(POS_EVENTS_EXCHANGE, `pos.${loadConfig().posType}.staff.created`, payload);
          state.staffState[posStaff.idmesero] = newHash;
          stateWasModified = true;
        } else if (oldHash !== newHash) {
          // 2. DETECTAR MODIFICACIONES: Si el hash cambió, los datos cambiaron.
          log.info(`[Productor-Staff] MODIFICACIÓN detectada en mesero: ${posStaff.nombre} (${posStaff.idmesero})`);
          const payload = { venueId: loadConfig().venueId, staffData: { ...posStaff, externalId: posStaff.idmesero, pin: posStaff.contraseña } };
          await publishMessage(POS_EVENTS_EXCHANGE, `pos.${loadConfig().posType}.staff.updated`, payload);
          state.staffState[posStaff.idmesero] = newHash;
          stateWasModified = true;
        }
      }
  
      // 3. DETECTAR ELIMINADOS
      for (const oldId in state.staffState) {
        if (!currentStaffMap.has(oldId)) {
          log.info(`[Productor-Staff] ELIMINACIÓN detectada para mesero con ID: ${oldId}`);
          const payload = { venueId: loadConfig().venueId, staffData: { externalId: oldId } };
          await publishMessage(POS_EVENTS_EXCHANGE, `pos.${loadConfig().posType}.staff.deleted`, payload);
          delete state.staffState[oldId]; // Lo borramos de nuestro estado
          stateWasModified = true;
        }
      }
  
      if (stateWasModified) {
        await saveSyncState(state);
        log.info(`[Productor-Staff] Estado de meseros actualizado y guardado en disco.`);
      }
  
    } catch (error: any) {
      log.error('[Productor-Staff] Error durante el polling de meseros:', error);
    }
  }
  
  async function pollForShiftChanges() {
    try {
      log.info('[Productor-Turnos] Revisando sincronización de turnos...');
      const pool = getDbPool();
      let state = await loadSyncState();
  
      // Query para turnos recién abiertos
      const openShiftsResult = await pool.request()
        .input('lastOpen', state.lastShiftOpenTimestamp)
        .query('SELECT * FROM turnos WHERE apertura > @lastOpen AND cierre IS NULL');
  
      // Query para turnos recién cerrados
      const closedShiftsResult = await pool.request()
        .input('lastClose', state.lastShiftCloseTimestamp)
        .query('SELECT * FROM turnos WHERE cierre > @lastClose');
      
      const { venueId, posType } = loadConfig();
      let stateWasModified = false;
  
      // Procesar turnos abiertos
      if (openShiftsResult.recordset.length > 0) {
        log.info(`[Productor-Turnos] Detectados ${openShiftsResult.recordset.length} turnos nuevos.`);
        for (const posShift of openShiftsResult.recordset) {
          const payload = { venueId, shiftData: posShift };
          await publishMessage(POS_EVENTS_EXCHANGE, `pos.${posType}.shift.opened`, payload);
        }
        state.lastShiftOpenTimestamp = new Date(openShiftsResult.recordset[openShiftsResult.recordset.length - 1].apertura).toISOString();
        stateWasModified = true;
      }
  
      // Procesar turnos cerrados
      if (closedShiftsResult.recordset.length > 0) {
        log.info(`[Productor-Turnos] Detectados ${closedShiftsResult.recordset.length} turnos cerrados.`);
        for (const posShift of closedShiftsResult.recordset) {
          const payload = { venueId, shiftData: posShift };
          await publishMessage(POS_EVENTS_EXCHANGE, `pos.${posType}.shift.closed`, payload);
        }
        state.lastShiftCloseTimestamp = new Date(closedShiftsResult.recordset[closedShiftsResult.recordset.length - 1].cierre).toISOString();
        stateWasModified = true;
      }
  
      if (stateWasModified) {
        await saveSyncState(state);
      }
  
    } catch (error: any) {
      log.error('[Productor-Turnos] Error durante el polling de turnos:', error);
    }
  }


export const startProducer = () => {
  log.info('▶️  Iniciando Productor (POS -> Avoqado)');


  setInterval(pollForNewOrders, POLLING_INTERVAL_MS);
  setInterval(pollForStaffChanges, STAFF_POLLING_INTERVAL_MS);
  setInterval(pollForShiftChanges, SHIFT_POLLING_INTERVAL_MS);
  
  // TODO: Iniciar aquí los otros bucles (órdenes actualizadas, turnos, etc.)
};