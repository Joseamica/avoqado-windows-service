// services/Orders/createEmptyOrder.ts
import sql from 'mssql'
import { v4 as uuidv4 } from 'uuid'
import { OrderCreateData } from '../../adapters/IPosAdapter'
import { getDbPool } from '../../core/db'
import { log } from '../../core/logger'
import { detectUsesWorkspaceId, getDefaultEmpresa } from '../../core/posMeta'

export async function createEmptyOrder(data: OrderCreateData): Promise<{ folio: number }> {
  log.info(`[Adapter SR11] Iniciando transacción para crear orden en mesa ${data.tableNumber}...`)

  log.info(`[Adapter SR11] Datos de la orden: ${JSON.stringify(data)}`)
  const pool = getDbPool()
  const transaction = new sql.Transaction(pool)
  const newWorkspaceId = uuidv4().toUpperCase()

  // 🔧 5d: el INSERT debe funcionar en v11/v12 (CON WorkspaceId) y en v10 (SIN la
  // columna). Decidimos por PRESENCIA de la columna (igual que el producer), no por
  // número de versión. En v10 referenciar WorkspaceId reventaba el INSERT → la
  // creación de orden vía bridge estaba 100% rota en v10.
  const usesWorkspaceId = await detectUsesWorkspaceId(pool)

  // 🔧 5d: el área venía en data.posAreaId pero se IGNORABA (estaba hardcodeada '01').
  // idempresa también estaba hardcodeada '1'; ahora se lee de empresas (fallback '1').
  const idarea = data.posAreaId && data.posAreaId.length > 0 ? data.posAreaId : '01'
  const idempresa = await getDefaultEmpresa(pool)

  try {
    log.info(`[Adapter SR11] Verificando si la mesa ${data.tableNumber} está ocupada...`)
    const checkTableQuery = `
      SELECT folio FROM tempcheques
      WHERE pagado = 0 AND cancelado = 0 AND mesa = @mesa
    `

    const tableCheckResult = await pool.request().input('mesa', sql.VarChar, data.tableNumber).query(checkTableQuery)

    if (tableCheckResult.recordset.length > 0) {
      // Si la consulta devuelve algo, la mesa está ocupada. Lanzamos un error.
      const existingFolio = tableCheckResult.recordset[0].folio
      throw new Error(`La mesa ${data.tableNumber} ya está ocupada por el folio ${existingFolio}.`)
    }
    log.info(`[Adapter SR11] Mesa ${data.tableNumber} está libre. Procediendo...`)

    await transaction.begin()

    const folioResult = await new sql.Request(transaction).query("SELECT ultimaorden FROM folios WHERE serie=''")
    const nextOrderNumber = folioResult.recordset[0].ultimaorden + 1

    let newFolio: number

    if (usesWorkspaceId) {
      // v11/v12: incluimos WorkspaceId y recuperamos el folio por ese GUID (cada
      // entidad tiene el suyo, así que es un lookup exacto).
      const insertQuery = `
        INSERT INTO tempcheques(
          mesa, nopersonas, idmesero, fecha, orden, pagado, cancelado, impreso,
          idarearestaurant, idempresa, tipodeservicio, idturno,
          estacion, Usuarioapertura, desc_porc_original, WorkspaceId
        ) VALUES (
          @mesa, @nopersonas, @idmesero, GETDATE(), @orden, 0, 0, 0,
          @idarea, @idempresa, 1, 0,
          'AVOQADO_SYNC', 'AVOQADO', 0, @workspaceId
        )
      `
      await new sql.Request(transaction)
        .input('mesa', sql.VarChar, data.tableNumber)
        .input('nopersonas', sql.Int, data.customerCount)
        .input('idmesero', sql.VarChar, data.waiterPosId)
        .input('orden', sql.Int, nextOrderNumber)
        .input('idarea', sql.VarChar, idarea)
        .input('idempresa', sql.VarChar, idempresa)
        .input('workspaceId', sql.UniqueIdentifier, newWorkspaceId)
        .query(insertQuery)

      const identityResult = await new sql.Request(transaction)
        .input('workspaceId', sql.UniqueIdentifier, newWorkspaceId)
        .query('SELECT folio FROM tempcheques WHERE WorkspaceId = @workspaceId')

      if (!identityResult.recordset[0] || !identityResult.recordset[0].folio) {
        throw new Error('No se pudo obtener el folio de la orden recién creada.')
      }
      newFolio = identityResult.recordset[0].folio
    } else {
      // v10: SIN columna WorkspaceId. folio es IDENTITY, así que lo recuperamos con
      // SCOPE_IDENTITY() en el mismo request. (Camino menos probado: validar en una
      // DB v10 real antes de producción.)
      const insertQuery = `
        INSERT INTO tempcheques(
          mesa, nopersonas, idmesero, fecha, orden, pagado, cancelado, impreso,
          idarearestaurant, idempresa, tipodeservicio, idturno,
          estacion, Usuarioapertura, desc_porc_original
        ) VALUES (
          @mesa, @nopersonas, @idmesero, GETDATE(), @orden, 0, 0, 0,
          @idarea, @idempresa, 1, 0,
          'AVOQADO_SYNC', 'AVOQADO', 0
        );
        SELECT CAST(SCOPE_IDENTITY() AS BIGINT) AS folio;
      `
      const insertResult = await new sql.Request(transaction)
        .input('mesa', sql.VarChar, data.tableNumber)
        .input('nopersonas', sql.Int, data.customerCount)
        .input('idmesero', sql.VarChar, data.waiterPosId)
        .input('orden', sql.Int, nextOrderNumber)
        .input('idarea', sql.VarChar, idarea)
        .input('idempresa', sql.VarChar, idempresa)
        .query(insertQuery)

      newFolio = insertResult.recordset[0]?.folio
      if (!newFolio) {
        throw new Error('No se pudo obtener el folio (SCOPE_IDENTITY) de la orden recién creada.')
      }
    }

    await new sql.Request(transaction)
      .input('nextOrderNumber', sql.Int, nextOrderNumber)
      .query("UPDATE folios SET ultimaorden = @nextOrderNumber WHERE serie=''")

    await transaction.commit()
    log.info(`[Adapter SR11] COMMIT exitoso. Orden creada con folio: ${newFolio}`)

    await pool
      .request()
      .input('folio', sql.BigInt, newFolio)
      .query('UPDATE tempcheques SET totalarticulos=0, subtotal=0, total=0, totalimpuesto1=0 WHERE folio=@folio')

    return { folio: newFolio }
  } catch (err: any) {
    log.error('[Adapter SR11] Error en transacción de creación de orden, haciendo ROLLBACK...', err.message)
    await transaction.rollback()
    throw err
  }
}
