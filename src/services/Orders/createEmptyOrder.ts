// services/Orders/createEmptyOrder.ts
import sql from 'mssql'
import { v4 as uuidv4 } from 'uuid'
import { OrderCreateData } from '../../adapters/IPosAdapter'
import { getDbPool } from '../../core/db'
import { log } from '../../core/logger'
import { detectUsesWorkspaceId, getDefaultEmpresa } from '../../core/posMeta'
import { claimCommand, CommandAlreadyProcessedError } from '../../core/commandDedup'

export async function createEmptyOrder(data: OrderCreateData, commandKey?: string): Promise<{ folio: number }> {
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

  let committed = false
  try {
    await transaction.begin()

    // 🔧 review: claim de idempotencia DENTRO de la tx (atómico con el efecto). Va PRIMERO para que
    // un duplicado se detecte antes que el chequeo de ocupación (ack+skip, no "mesa ocupada").
    if (commandKey) await claimCommand(transaction, commandKey)

    // 🔧 H-11: chequeo de ocupación DENTRO de la tx con UPDLOCK+HOLDLOCK → check-then-insert atómico.
    // Antes corría FUERA de la tx (pool.request), dejando una carrera TOCTOU: dos creaciones
    // concurrentes en la misma mesa pasaban ambas el chequeo y abrían dos órdenes.
    log.info(`[Adapter SR11] Verificando si la mesa ${data.tableNumber} está ocupada...`)
    const tableCheckResult = await new sql.Request(transaction)
      .input('mesa', sql.VarChar, data.tableNumber)
      .query('SELECT folio FROM tempcheques WITH (UPDLOCK, HOLDLOCK) WHERE pagado = 0 AND cancelado = 0 AND mesa = @mesa')

    if (tableCheckResult.recordset.length > 0) {
      const existingFolio = tableCheckResult.recordset[0].folio
      throw new Error(`La mesa ${data.tableNumber} ya está ocupada por el folio ${existingFolio}.`)
    }
    log.info(`[Adapter SR11] Mesa ${data.tableNumber} está libre. Procediendo...`)

    const folioResult = await new sql.Request(transaction).query("SELECT ultimaorden FROM folios WHERE serie=''")
    const nextOrderNumber = folioResult.recordset[0].ultimaorden + 1

    let newFolio: number

    if (usesWorkspaceId) {
      // v11/v12: incluimos WorkspaceId y recuperamos el folio por ese GUID (cada
      // entidad tiene el suyo, así que es un lookup exacto).
      // 🔧 M-17: totales en 0 dentro del MISMO INSERT (antes se hacía un UPDATE post-commit FUERA
      // de la tx → fila medio-inicializada visible y posible rollback() tras commit).
      const insertQuery = `
        INSERT INTO tempcheques(
          mesa, nopersonas, idmesero, fecha, orden, pagado, cancelado, impreso,
          idarearestaurant, idempresa, tipodeservicio, idturno,
          estacion, Usuarioapertura, desc_porc_original,
          totalarticulos, subtotal, total, totalimpuesto1, WorkspaceId
        ) VALUES (
          @mesa, @nopersonas, @idmesero, GETDATE(), @orden, 0, 0, 0,
          @idarea, @idempresa, 1, 0,
          'AVOQADO_SYNC', 'AVOQADO', 0,
          0, 0, 0, 0, @workspaceId
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
      // 🔧 M-17: totales en 0 dentro del MISMO INSERT (ver nota en la rama v11/v12).
      const insertQuery = `
        INSERT INTO tempcheques(
          mesa, nopersonas, idmesero, fecha, orden, pagado, cancelado, impreso,
          idarearestaurant, idempresa, tipodeservicio, idturno,
          estacion, Usuarioapertura, desc_porc_original,
          totalarticulos, subtotal, total, totalimpuesto1
        ) VALUES (
          @mesa, @nopersonas, @idmesero, GETDATE(), @orden, 0, 0, 0,
          @idarea, @idempresa, 1, 0,
          'AVOQADO_SYNC', 'AVOQADO', 0,
          0, 0, 0, 0
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
    committed = true
    log.info(`[Adapter SR11] COMMIT exitoso. Orden creada con folio: ${newFolio}`)

    return { folio: newFolio }
  } catch (err: any) {
    // 🔧 M-17: solo revertir si NO se commiteó (antes el UPDATE de totales post-commit podía lanzar
    // y disparar rollback() sobre una tx ya commiteada, enmascarando el error real). El duplicado
    // idempotente (sentinela) no es un error real → no se loguea como tal.
    if (!(err instanceof CommandAlreadyProcessedError)) {
      log.error('[Adapter SR11] Error en transacción de creación de orden, haciendo ROLLBACK...', err.message)
    }
    if (!committed) {
      try {
        await transaction.rollback()
      } catch {
        /* la tx pudo abortarse sola (abortTransactionOnError) */
      }
    }
    throw err
  }
}
