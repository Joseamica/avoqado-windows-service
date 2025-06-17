import sql from 'mssql';
import { getDbPool } from '../core/db';
import { log } from '../core/logger';
import { createEmptyOrder } from '../services/Orders/createEmptyOrder';
import { IPOSAdapter, OrderAddItemData, OrderCreateData, PaymentData, ShiftCloseData, ShiftOpenData } from './IPosAdapter';

export class SoftRestaurant11Adapter implements IPOSAdapter {

  // =================================================================
  // --- MÉTODOS DE ÓRDENES ---
  // =================================================================

  /**
   * RECETA #1: Crea una orden vacía en la tabla tempcheques.
   */
  async createEmptyOrder(data: OrderCreateData): Promise<{ folio: number }> {
    return createEmptyOrder(data);
  }

  /**
   * RECETA #2: Añade un producto a una orden existente.
   */
  async addItemToOrder(folio: number, item: OrderAddItemData): Promise<void> {
    log.info(`[Adapter SR11] Añadiendo producto '${item.productId}' al folio ${folio}...`);
    console.log(`[Adapter SR11] Añadiendo producto '${item.productId}' al folio ${folio}...`);
    const pool = getDbPool();
    const transaction = new sql.Transaction(pool)
    try {
      // --- PASO 1: LOOKUP DEL PRODUCTO (se mantiene igual) ---
      const productLookupResult = await pool.request()
        .input('productIdLookup', sql.VarChar, item.productId)
        .query("SELECT idproducto FROM productos WHERE descripcion = @productIdLookup");
      
      if (productLookupResult.recordset.length === 0) {
        throw new Error(`Producto con identificador '${item.productId}' no encontrado en el POS.`);
      }
      const actualPosProductId = productLookupResult.recordset[0].idproducto;
      log.info(`Producto encontrado. ID del POS: '${actualPosProductId}'`);
      
      // --- PASO 2: TRANSACCIÓN PARA INSERTAR Y ACTUALIZAR ---
      await transaction.begin();

      const movResult = await new sql.Request(transaction)
        .input('folio', sql.Int, folio)
        .query("SELECT ISNULL(MAX(movimiento), 0) as maxMovimiento FROM tempcheqdet WHERE foliodet = @folio");
      const nextMovement = movResult.recordset[0].maxMovimiento + 1;
      
      const priceWithoutTax = item.price / 1.16;
      
      const insertQuery = `
        INSERT INTO tempcheqdet (foliodet, movimiento, idproducto, cantidad, precio, preciosinimpuestos, hora, idestacion, impuesto1, idmeseroproducto, comentario) 
        VALUES (@folio, @movimiento, @idproducto, @cantidad, @precio, @preciosinimpuestos, GETDATE(), 'AVOQADO_SYNC', 16.00, @idmesero, @comentario)
      `;
      await new sql.Request(transaction)
        .input('folio', sql.Int, folio)
        .input('movimiento', sql.Int, nextMovement)
        .input('idproducto', sql.VarChar, actualPosProductId)
        .input('cantidad', sql.Int, item.quantity)
        .input('precio', sql.Money, item.price * item.quantity)
        .input('preciosinimpuestos', sql.Money, priceWithoutTax * item.quantity)
        .input('idmesero', sql.VarChar, item.waiterPosId)
        .input('comentario', sql.VarChar, item.notes || '')
        .query(insertQuery);
      
      log.info(`[Adapter SR11] Producto '${actualPosProductId}' insertado en tempcheqdet.`);

      // ✅ PASO 3: RECALCULAR Y ACTUALIZAR TOTALES EN tempcheques
      const updateTotalsQuery = `
        UPDATE tc
        SET 
          tc.totalarticulos = ISNULL(det.total_cantidad, 0),
          tc.subtotal = ISNULL(det.total_precio_sin_imp, 0),
          tc.totalimpuesto1 = ISNULL(det.total_impuestos, 0),
          tc.total = ISNULL(det.total_final, 0),
          tc.totalsindescuento = ISNULL(det.total_precio_sin_imp, 0) -- Asumiendo que el descuento se aplica después
        FROM 
          tempcheques tc
        LEFT JOIN 
          (SELECT
              foliodet,
              SUM(cantidad) as total_cantidad,
              SUM(preciosinimpuestos) as total_precio_sin_imp,
              SUM(precio - preciosinimpuestos) as total_impuestos,
              SUM(precio) as total_final
           FROM 
              tempcheqdet
           WHERE 
              foliodet = @folio
           GROUP BY 
              foliodet
          ) as det ON tc.folio = det.foliodet
        WHERE 
          tc.folio = @folio;
      `;
      await new sql.Request(transaction)
        .input('folio', sql.Int, folio)
        .query(updateTotalsQuery);
      
      log.info(`[Adapter SR11] Totales para el folio ${folio} recalculados y actualizados.`);

      await transaction.commit();
      log.info(`[Adapter SR11] COMMIT exitoso. Producto añadido y totales actualizados.`);
        
    } catch (err: any) {
      log.error(`[Adapter SR11] Error en transacción de añadir producto, haciendo ROLLBACK...`, err.message);
      try {
        await transaction.rollback();
      } catch (rollbackErr: any) {
        log.error('[Adapter SR11] Falla crítica al intentar hacer ROLLBACK.', rollbackErr.message);
      }
      throw err;
    }
  }

  /**
   * RECETA #3: Cancela un producto de una orden existente.
   */
  async cancelOrderItem(folio: number, movementId: number, reason: string, user: string): Promise<void> {
    log.info(`[Adapter SR11] Cancelando producto movimiento ${movementId} del folio ${folio}...`);
    const pool = getDbPool();
    const transaction = new sql.Transaction(pool);
    try {
      await transaction.begin();
      
      const itemDataResult = await new sql.Request(transaction)
        .input('folio', sql.Int, folio)
        .input('movimiento', sql.Int, movementId)
        .query('SELECT idproducto, cantidad, precio FROM tempcheqdet WHERE foliodet = @folio AND movimiento = @movimiento');
      
      if (itemDataResult.recordset.length === 0) throw new Error(`No se encontró el item con movimiento ${movementId} en el folio ${folio}.`);
      const itemData = itemDataResult.recordset[0];
      
      await new sql.Request(transaction)
        .input('folio', sql.Int, folio)
        .input('idproducto', sql.VarChar, itemData.idproducto)
        .input('movimiento', sql.Int, movementId)
        .query('UPDATE productosenproduccion SET cancelado=1 WHERE folio=@folio AND idproducto=@idproducto AND movimiento=@movimiento');
      
      await new sql.Request(transaction)
        .input('folio', sql.Int, folio)
        .input('movimiento', sql.Int, movementId)
        .query('DELETE FROM tempcheqdet WHERE foliodet=@folio AND movimiento=@movimiento');
        
      await new sql.Request(transaction)
        .input('folio', sql.Int, folio)
        .input('cantidad', sql.Int, itemData.cantidad)
        .input('idproducto', sql.VarChar, itemData.idproducto)
        .input('razon', sql.VarChar, reason)
        .input('usuario', sql.VarChar, user)
        .input('precio', sql.Money, itemData.precio)
        .query("INSERT INTO tempcancela (foliocheque, cantidad, clave, razon, fecha, usuario, precio) VALUES (@folio, @cantidad, @idproducto, @razon, GETDATE(), @usuario, @precio)");
        
      await new sql.Request(transaction)
        .input('evento', sql.VarChar, `Cancelación de producto en folio ${folio}`)
        .input('valores', sql.VarChar, `Producto: ${itemData.idproducto}, Razón: ${reason}`)
        .input('usuario', sql.VarChar, user)
        .query("INSERT INTO bitacorasistema (fecha, usuario, evento, valores, ...) VALUES(GETDATE(), @usuario, @evento, @valores, ...)");
      
      await transaction.commit();
      log.info(`[Adapter SR11] Producto movimiento ${movementId} cancelado exitosamente.`);
      // El Trigger del DELETE en tempcheqdet debería haber recalculado los totales en tempcheques.
    } catch (err: any) {
      log.error(`[Adapter SR11] Error en transacción de cancelar producto, haciendo ROLLBACK...`, err.message);
      await transaction.rollback();
      throw err;
    }
  }

  // --- MÉTODOS DE PAGOS ---

  /**
   * RECETA #4 (PARCIAL): Registra un pago en una orden.
   */
  async applyPayment(folio: number, payment: PaymentData): Promise<void> {
    log.info(`[Adapter SR11] Aplicando pago de ${payment.amount} al folio ${folio}...`);
    const pool = getDbPool();
    await pool.request()
      .input('folio', sql.Int, folio)
      .input('idformadepago', sql.VarChar, payment.posPaymentMethodId)
      .input('importe', sql.Money, payment.amount)
      .input('propina', sql.Money, payment.tip)
      .input('referencia', sql.VarChar, payment.reference || '')
      .query('INSERT INTO tempchequespagos (folio, idformadepago, importe, propina, referencia, ...) VALUES (@folio, @idformadepago, @importe, @propina, @referencia, ...)')
  }

  /**
   * RECETA #4 (COMPLETA): Cierra la orden después de aplicar los pagos.
   */
  async closeAndPayOrder(folio: number): Promise<{ finalCheckNumber: number; }> {
    log.info(`[Adapter SR11] Cerrando y pagando la orden folio ${folio}...`);
    const pool = getDbPool();
    const transaction = new sql.Transaction(pool);
    try {
      await transaction.begin();
      const folioResult = await new sql.Request(transaction).query("SELECT ultimofolio FROM folios WHERE serie=''");
      const nextCheckNumber = folioResult.recordset[0].ultimofolio + 1;
      
      await new sql.Request(transaction)
        .input('folio', sql.Int, folio)
        .input('numcheque', sql.Int, nextCheckNumber)
        .query("UPDATE tempcheques SET pagado=1, impreso=1, numcheque=@numcheque, cierre=GETDATE() WHERE folio=@folio");
        
      await new sql.Request(transaction)
        .input('nextCheckNumber', sql.Int, nextCheckNumber)
        .query("UPDATE folios SET ultimofolio = @nextCheckNumber WHERE serie=''");
        
      await new sql.Request(transaction)
        .input('folio', sql.Int, folio)
        .query("UPDATE cuentas SET procesado = 1 WHERE foliocuenta = @folio");
      
      await transaction.commit();
      log.info(`[Adapter SR11] Orden folio ${folio} cerrada exitosamente con número de cheque ${nextCheckNumber}.`);
      return { finalCheckNumber: nextCheckNumber };
    } catch (err: any) {
      log.error(`[Adapter SR11] Error en transacción de cerrar orden, haciendo ROLLBACK...`, err.message);
      await transaction.rollback();
      throw err;
    }
  }

  /**
   * RECETA #5: Abre un nuevo turno en el POS.
   */
  async openShift(data: ShiftOpenData): Promise<{ shiftId: number }> {
    log.info(`[Adapter SR11] Abriendo nuevo turno para el cajero ${data.posStaffId}...`);
    const pool = getDbPool();
    const transaction = new sql.Transaction(pool);
    try {
      await transaction.begin();

      // Obtenemos el siguiente ID para el turno. Asumimos que es un secuencial.
      const idResult = await new sql.Request(transaction).query("SELECT ISNULL(MAX(idturno), 0) + 1 as nextId FROM turnos");
      const nextShiftId = idResult.recordset[0].nextId;

      const insertQuery = `
        INSERT INTO turnos (idturno, fondo, apertura, idestacion, cajero, idempresa, idmesero, WorkspaceId) 
        VALUES (@idturno, @fondo, GETDATE(), 'AVOQADO_SYNC', @cajero, '1', '', NEWID())
      `;
      await new sql.Request(transaction)
        .input('idturno', sql.Int, nextShiftId)
        .input('fondo', sql.Money, data.startingCash)
        .input('cajero', sql.VarChar, data.posStaffId)
        .query(insertQuery);

      await new sql.Request(transaction)
        .input('nextShiftId', sql.Int, nextShiftId)
        .query("UPDATE parametros SET ultimoturno = @nextShiftId");
      
      await transaction.commit();
      log.info(`[Adapter SR11] Turno ${nextShiftId} abierto exitosamente.`);
      return { shiftId: nextShiftId };

    } catch (err: any) {
      log.error("[Adapter SR11] Error en transacción de abrir turno, haciendo ROLLBACK...", err.message);
      await transaction.rollback();
      throw err;
    }
  }
  
  /**
   * RECETA #6: Cierra un turno existente y archiva toda su data.
   */
  async closeShift(shiftId: number, data: ShiftCloseData): Promise<void> {
    log.info(`[Adapter SR11] Iniciando proceso de cierre para el turno ${shiftId}...`);
    const pool = getDbPool();
    const transaction = new sql.Transaction(pool);
    try {
      await transaction.begin();
      log.info(`[Adapter SR11] Paso 1: Archivando datos del turno ${shiftId}...`);

      // --- PROCESO DE ARCHIVADO: Mover datos de tablas 'temp' a tablas permanentes ---
      // Usamos el `idturno_cierre` para marcar a qué cierre pertenecen estos registros.
      
      const archivalQueries = [
        `INSERT INTO cheques (...) SELECT ..., @shiftId as idturno_cierre, ... FROM tempcheques WHERE idturno = @shiftId`,
        `INSERT INTO cheqdet (...) SELECT ..., @shiftId as idturno_cierre, ... FROM tempcheqdet d JOIN tempcheques t ON d.foliodet = t.folio WHERE t.idturno = @shiftId`,
        `INSERT INTO chequespagos (...) SELECT ..., @shiftId as idturno_cierre, ... FROM tempchequespagos p JOIN tempcheques t ON p.folio = t.folio WHERE t.idturno = @shiftId`,
        // ... (añadir aquí los demás INSERT/SELECT para todas las tablas temp: tempcancela, etc.)
      ];

      for (const query of archivalQueries) {
        await new sql.Request(transaction).input('shiftId', sql.Int, shiftId).query(query);
      }
      log.info(`[Adapter SR11] Paso 2: Limpiando tablas temporales...`);

      // --- PROCESO DE LIMPIEZA ---
      const folioSubquery = `SELECT folio FROM tempcheques WHERE idturno = @shiftId`;
      await new sql.Request(transaction).input('shiftId', sql.Int, shiftId).query(`DELETE FROM mesasasignadas WHERE folio IN (${folioSubquery})`);
      await new sql.Request(transaction).input('shiftId', sql.Int, shiftId).query(`DELETE FROM tempchequespagos WHERE folio IN (${folioSubquery})`);
      await new sql.Request(transaction).input('shiftId', sql.Int, shiftId).query(`DELETE FROM tempcheqdet WHERE foliodet IN (${folioSubquery})`);
      await new sql.Request(transaction).input('shiftId', sql.Int, shiftId).query(`DELETE FROM tempcancela WHERE foliocheque IN (${folioSubquery})`);
      await new sql.Request(transaction).input('shiftId', sql.Int, shiftId).query(`DELETE FROM tempcheques WHERE idturno = @shiftId`);

      log.info(`[Adapter SR11] Paso 3: Cerrando el registro del turno...`);
      
      // --- PROCESO DE CIERRE FINAL ---
      await new sql.Request(transaction)
        .input('shiftId', sql.Int, shiftId)
        .input('cierre', sql.DateTime, new Date())
        .input('efectivo', sql.Money, data.cashDeclared)
        .input('tarjeta', sql.Money, data.cardDeclared)
        .input('vales', sql.Money, data.vouchersDeclared)
        .query("UPDATE turnos SET cierre=@cierre, efectivo=@efectivo, tarjeta=@tarjeta, vales=@vales WHERE idturno=@shiftId");

      await new sql.Request(transaction).query("UPDATE folios SET ultimaorden=0, ultimofolioproduccion=0 WHERE serie=''");
      
      await transaction.commit();
      log.info(`[Adapter SR11] COMMIT exitoso. Turno ${shiftId} cerrado y archivado.`);

    } catch (err: any) {
      log.error(`[Adapter SR11] Error en transacción de cerrar turno, haciendo ROLLBACK...`, err.message);
      await transaction.rollback();
      throw err;
    }
  }
}
