// core/posMeta.ts
// Metadatos del POS que la dirección de EJECUCIÓN (Avoqado->SoftRestaurant) necesita
// leer de la base en vez de hardcodear. Se cachean tras la primera lectura porque
// son de configuración (no cambian durante la vida del servicio) y los toca cada
// comando de creación de orden / alta de producto.
import sql from 'mssql'
import { log } from './logger'

let cachedIvaRate: number | null = null
let cachedUsesWorkspaceId: boolean | null = null
let cachedDefaultEmpresa: string | null = null

/**
 * Tasa de IVA global del POS (parametros.impuesto1, p. ej. 16.00 = 16%).
 * Antes el adapter hardcodeaba 1.16 / 16.00, lo que daba IVA y precio-sin-impuesto
 * MAL en venues con tasa distinta (frontera 8%, exentos). SoftRestaurant aplica
 * esta tasa global salvo override por producto (productosindicadorimpuesto), que
 * hoy no usamos. Fallback 16 si parametros no trae un valor > 0.
 */
export async function getIvaRate(pool: sql.ConnectionPool): Promise<number> {
  if (cachedIvaRate !== null) return cachedIvaRate
  try {
    const res = await pool.request().query('SELECT TOP 1 impuesto1 FROM parametros')
    const raw = res.recordset[0]?.impuesto1
    const rate = raw != null ? Number(raw) : NaN
    cachedIvaRate = Number.isFinite(rate) && rate > 0 ? rate : 16
  } catch (error) {
    log.warn('[posMeta] No se pudo leer parametros.impuesto1, usando 16% por defecto:', error)
    cachedIvaRate = 16
  }
  log.info(`[posMeta] Tasa de IVA del POS: ${cachedIvaRate}%`)
  return cachedIvaRate
}

/**
 * True si la DB usa WorkspaceId (v11/v12 y v10-híbridos). El formato de identidad y
 * el INSERT de órdenes lo decide la PRESENCIA de la columna, NO el número de versión
 * (hay DBs versiondb=10.x CON WorkspaceId). Idéntico criterio que el producer y el
 * SQL de instalación, para no divergir.
 */
export async function detectUsesWorkspaceId(pool: sql.ConnectionPool): Promise<boolean> {
  if (cachedUsesWorkspaceId !== null) return cachedUsesWorkspaceId
  try {
    const res = await pool.request().query("SELECT COL_LENGTH('tempcheques','WorkspaceId') AS wid")
    cachedUsesWorkspaceId = res.recordset[0]?.wid != null
  } catch (error) {
    log.warn('[posMeta] Error detectando WorkspaceId, asumiendo que NO:', error)
    cachedUsesWorkspaceId = false
  }
  return cachedUsesWorkspaceId
}

/**
 * idempresa por defecto del POS. Casi siempre '1', pero algunos venues lo configuran
 * distinto; leer empresas evita misatribuir la orden en esos casos. Fallback '1'.
 */
export async function getDefaultEmpresa(pool: sql.ConnectionPool): Promise<string> {
  if (cachedDefaultEmpresa !== null) return cachedDefaultEmpresa
  try {
    const res = await pool.request().query('SELECT TOP 1 idempresa FROM empresas ORDER BY idempresa')
    const id = res.recordset[0]?.idempresa
    cachedDefaultEmpresa = id != null && String(id).length > 0 ? String(id) : '1'
  } catch (error) {
    log.warn('[posMeta] No se pudo leer empresas.idempresa, usando "1" por defecto:', error)
    cachedDefaultEmpresa = '1'
  }
  return cachedDefaultEmpresa
}
