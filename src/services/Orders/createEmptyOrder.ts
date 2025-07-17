// services/Orders/createEmptyOrder.ts
import sql from 'mssql';
import { v4 as uuidv4 } from 'uuid';
import { OrderCreateData } from '../../adapters/IPosAdapter';
import { getDbPool } from '../../core/db';
import { log } from '../../core/logger';

export async function createEmptyOrder(data: OrderCreateData): Promise<{ folio: number }> {
  log.info(`[Adapter SR11] Iniciando transacción para crear orden en mesa ${data.tableNumber}...`);

  log.info(`[Adapter SR11] Datos de la orden: ${JSON.stringify(data)}`);
  const pool = getDbPool();
  const transaction = new sql.Transaction(pool);
  const newWorkspaceId = uuidv4().toUpperCase();

  try {
    log.info(`[Adapter SR11] Verificando si la mesa ${data.tableNumber} está ocupada...`);
    const checkTableQuery = `
      SELECT folio FROM tempcheques 
      WHERE pagado = 0 AND cancelado = 0 AND mesa = @mesa
    `;
    
    const tableCheckResult = await pool.request()
      .input('mesa', sql.VarChar, data.tableNumber)
      .query(checkTableQuery);

    if (tableCheckResult.recordset.length > 0) {
      // Si la consulta devuelve algo, la mesa está ocupada. Lanzamos un error.
      const existingFolio = tableCheckResult.recordset[0].folio;
      throw new Error(`La mesa ${data.tableNumber} ya está ocupada por el folio ${existingFolio}.`);
    }
    log.info(`[Adapter SR11] Mesa ${data.tableNumber} está libre. Procediendo...`);


    await transaction.begin();

    const folioResult = await new sql.Request(transaction)
      .query("SELECT ultimaorden FROM folios WHERE serie=''");
    const nextOrderNumber = folioResult.recordset[0].ultimaorden + 1;

    const insertQuery = `
      INSERT INTO tempcheques(
        mesa, nopersonas, idmesero, fecha, orden, pagado, cancelado, impreso, 
        idarearestaurant, idempresa, tipodeservicio, idturno, 
        estacion, Usuarioapertura, desc_porc_original, WorkspaceId
      ) VALUES (
        @mesa, @nopersonas, @idmesero, GETDATE(), @orden, 0, 0, 0, 
        '01', '1', 1, 0, 
        'AVOQADO_SYNC', 'AVOQADO', 0, @workspaceId 
      )
    `;

    await new sql.Request(transaction)
      .input('mesa', sql.VarChar, data.tableNumber)
      .input('nopersonas', sql.Int, data.customerCount)
      .input('idmesero', sql.VarChar, data.waiterPosId)
      .input('orden', sql.Int, nextOrderNumber)
      .input('workspaceId', sql.UniqueIdentifier, newWorkspaceId)
      .query(insertQuery);

    const identityResult = await new sql.Request(transaction)
      .input('workspaceId', sql.UniqueIdentifier, newWorkspaceId)
      .query("SELECT folio FROM tempcheques WHERE WorkspaceId = @workspaceId");

    if (!identityResult.recordset[0] || !identityResult.recordset[0].folio) {
      throw new Error("No se pudo obtener el folio de la orden recién creada.");
    }

    const newFolio = identityResult.recordset[0].folio;

    await new sql.Request(transaction)
      .input('nextOrderNumber', sql.Int, nextOrderNumber)
      .query("UPDATE folios SET ultimaorden = @nextOrderNumber WHERE serie=''");

    await transaction.commit();
    log.info(`[Adapter SR11] COMMIT exitoso. Orden creada con folio: ${newFolio}`);

    await pool.request()
      .input('folio', sql.Int, newFolio)
      .query("UPDATE tempcheques SET totalarticulos=0, subtotal=0, total=0, totalimpuesto1=0 WHERE folio=@folio");

    return { folio: newFolio };
  } catch (err: any) {
    log.error("[Adapter SR11] Error en transacción de creación de orden, haciendo ROLLBACK...", err.message);
    await transaction.rollback();
    throw err;
  }
}
