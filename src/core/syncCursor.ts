import fs from 'fs'
import path from 'path'
import { log } from './logger'

/**
 * Cursor de sincronización durable (capa de resiliencia).
 *
 * El Producer lee de AvoqadoTracking vía sp_GetPendingChanges (Modelo A:
 * mark-processed con ProcessedAt). La entrega "at-least-once" la garantiza
 * ProcessedAt; este cursor compuesto (Timestamp, Id) se persiste en disco como
 * red de seguridad adicional: tras un reinicio largo el servicio retoma desde
 * el último punto conocido en vez de re-escanear una ventana ciega.
 */
export interface SyncCursor {
  lastModifiedAt: Date
  lastId: number
}

const DEFAULT_LOOKBACK_MS = 5 * 60 * 1000

/**
 * Ruta del archivo de cursor: junto a la fuente de configuración activa.
 * Desarrollo → raíz del proyecto (junto al .env). Producción → %ProgramData%\AvoqadoSync.
 */
export const getDefaultCursorPath = (): string => {
  if (process.env.NODE_ENV === 'development') {
    return path.resolve(__dirname, '../../sync-cursor.json')
  }
  return path.join(process.env.ProgramData || 'C:/ProgramData', 'AvoqadoSync', 'sync-cursor.json')
}

const fallbackCursor = (): SyncCursor => ({
  lastModifiedAt: new Date(Date.now() - DEFAULT_LOOKBACK_MS),
  lastId: 0,
})

export const loadSyncCursor = (filePath: string = getDefaultCursorPath()): SyncCursor => {
  try {
    if (!fs.existsSync(filePath)) {
      log.info(`[SyncCursor] No hay cursor persistido en ${filePath}. Arrancando con ventana de 5 minutos.`)
      return fallbackCursor()
    }

    const raw = JSON.parse(fs.readFileSync(filePath, 'utf8'))
    const lastModifiedAt = new Date(raw.lastModifiedAt)

    if (isNaN(lastModifiedAt.getTime()) || typeof raw.lastId !== 'number' || !isFinite(raw.lastId)) {
      log.warn(`[SyncCursor] Cursor en ${filePath} es inválido. Usando ventana de 5 minutos.`)
      return fallbackCursor()
    }

    return { lastModifiedAt, lastId: raw.lastId }
  } catch (error) {
    log.warn(`[SyncCursor] No se pudo leer el cursor en ${filePath}. Usando ventana de 5 minutos.`, error)
    return fallbackCursor()
  }
}

/**
 * Escritura atómica: temp + rename para que un corte de luz a media escritura
 * no deje un cursor corrupto (el load haría fallback y re-procesaría 5 min).
 */
export const saveSyncCursor = (cursor: SyncCursor, filePath: string = getDefaultCursorPath()): void => {
  try {
    fs.mkdirSync(path.dirname(filePath), { recursive: true })
    const tmpPath = `${filePath}.${process.pid}.tmp`
    fs.writeFileSync(tmpPath, JSON.stringify({ lastModifiedAt: cursor.lastModifiedAt.toISOString(), lastId: cursor.lastId }))
    fs.renameSync(tmpPath, filePath)
  } catch (error) {
    // No interrumpe el polling: perder una escritura de cursor solo significa
    // re-procesar un lote tras el próximo reinicio (los eventos son idempotentes upstream).
    log.error(`[SyncCursor] No se pudo persistir el cursor en ${filePath}.`, error)
  }
}
