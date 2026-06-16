import sql from 'mssql'
import { getDbPool } from '../core/db'
import { log } from '../core/logger'
import { getIvaRate, detectUsesWorkspaceId, getDefaultEmpresa } from '../core/posMeta'
import { createEmptyOrder } from '../services/Orders/createEmptyOrder'
import {
  IPOSAdapter,
  OrderAddItemData,
  OrderCreateData,
  PaymentData,
  ShiftCloseData,
  ShiftOpenData,
  IntelligentPaymentData,
  PaymentResult,
  FastPaymentData,
  FastPaymentResult,
} from './IPosAdapter'

export class SoftRestaurant11Adapter implements IPOSAdapter {
  // =================================================================
  // --- MÉTODOS DE ÓRDENES ---
  // =================================================================

  /**
   * RECETA #1: Crea una orden vacía en la tabla tempcheques.
   */
  async createEmptyOrder(data: OrderCreateData): Promise<{ folio: number }> {
    return createEmptyOrder(data)
  }

  /**
   * RECETA #2: Añade un producto a una orden existente.
   */
  async addItemToOrder(folio: number, item: OrderAddItemData): Promise<void> {
    log.info(`[Adapter SR11] Añadiendo producto '${item.productId}' al folio ${folio}...`)
    console.log(`[Adapter SR11] Añadiendo producto '${item.productId}' al folio ${folio}...`)
    const pool = getDbPool()
    const transaction = new sql.Transaction(pool)
    try {
      // --- PASO 1: LOOKUP DEL PRODUCTO (se mantiene igual) ---
      const productLookupResult = await pool
        .request()
        .input('productIdLookup', sql.VarChar, item.productId)
        .query('SELECT idproducto FROM productos WHERE descripcion = @productIdLookup')

      if (productLookupResult.recordset.length === 0) {
        throw new Error(`Producto con identificador '${item.productId}' no encontrado en el POS.`)
      }
      const actualPosProductId = productLookupResult.recordset[0].idproducto
      log.info(`Producto encontrado. ID del POS: '${actualPosProductId}'`)

      // --- PASO 2: TRANSACCIÓN PARA INSERTAR Y ACTUALIZAR ---
      await transaction.begin()

      const movResult = await new sql.Request(transaction)
        .input('folio', sql.BigInt, folio)
        .query('SELECT ISNULL(MAX(movimiento), 0) as maxMovimiento FROM tempcheqdet WHERE foliodet = @folio')
      const nextMovement = movResult.recordset[0].maxMovimiento + 1

      // 🔧 5d: IVA leído de parametros.impuesto1 (antes hardcodeado 1.16 / 16.00, lo
      // que daba precio-sin-impuesto e impuesto1 MAL en venues con tasa != 16%).
      const ivaRate = await getIvaRate(pool)
      const priceWithoutTax = item.price / (1 + ivaRate / 100)

      const insertQuery = `
        INSERT INTO tempcheqdet (foliodet, movimiento, idproducto, cantidad, precio, preciosinimpuestos, hora, idestacion, impuesto1, idmeseroproducto, comentario)
        VALUES (@folio, @movimiento, @idproducto, @cantidad, @precio, @preciosinimpuestos, GETDATE(), 'AVOQADO_SYNC', @impuesto1, @idmesero, @comentario)
      `
      await new sql.Request(transaction)
        .input('folio', sql.BigInt, folio)
        .input('movimiento', sql.Int, nextMovement)
        .input('idproducto', sql.VarChar, actualPosProductId)
        .input('cantidad', sql.Int, item.quantity)
        // tempcheqdet.precio es UNITARIO en SoftRestaurant (la línea = precio*cantidad,
        // como lo lee el producer). item.price ya es el precio unitario, así que NO
        // se multiplica por cantidad aquí (antes duplicaba totales con cantidad>1).
        .input('precio', sql.Money, item.price)
        .input('preciosinimpuestos', sql.Money, priceWithoutTax)
        .input('impuesto1', sql.Decimal(9, 2), ivaRate)
        .input('idmesero', sql.VarChar, item.waiterPosId)
        .input('comentario', sql.VarChar, item.notes || '')
        .query(insertQuery)

      log.info(`[Adapter SR11] Producto '${actualPosProductId}' insertado en tempcheqdet.`)

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
      `
      await new sql.Request(transaction).input('folio', sql.BigInt, folio).query(updateTotalsQuery)

      log.info(`[Adapter SR11] Totales para el folio ${folio} recalculados y actualizados.`)

      await transaction.commit()
      log.info(`[Adapter SR11] COMMIT exitoso. Producto añadido y totales actualizados.`)
    } catch (err: any) {
      log.error(`[Adapter SR11] Error en transacción de añadir producto, haciendo ROLLBACK...`, err.message)
      try {
        await transaction.rollback()
      } catch (rollbackErr: any) {
        log.error('[Adapter SR11] Falla crítica al intentar hacer ROLLBACK.', rollbackErr.message)
      }
      throw err
    }
  }

  /**
   * RECETA #3: Cancela un producto de una orden existente.
   */
  async cancelOrderItem(folio: number, movementId: number, reason: string, user: string): Promise<void> {
    log.info(`[Adapter SR11] Cancelando producto movimiento ${movementId} del folio ${folio}...`)
    const pool = getDbPool()
    const transaction = new sql.Transaction(pool)
    try {
      await transaction.begin()

      const itemDataResult = await new sql.Request(transaction)
        .input('folio', sql.BigInt, folio)
        .input('movimiento', sql.Int, movementId)
        .query('SELECT idproducto, cantidad, precio FROM tempcheqdet WHERE foliodet = @folio AND movimiento = @movimiento')

      if (itemDataResult.recordset.length === 0)
        throw new Error(`No se encontró el item con movimiento ${movementId} en el folio ${folio}.`)
      const itemData = itemDataResult.recordset[0]

      await new sql.Request(transaction)
        .input('folio', sql.BigInt, folio)
        .input('idproducto', sql.VarChar, itemData.idproducto)
        .input('movimiento', sql.Int, movementId)
        .query('UPDATE productosenproduccion SET cancelado=1 WHERE folio=@folio AND idproducto=@idproducto AND movimiento=@movimiento')

      await new sql.Request(transaction)
        .input('folio', sql.BigInt, folio)
        .input('movimiento', sql.Int, movementId)
        .query('DELETE FROM tempcheqdet WHERE foliodet=@folio AND movimiento=@movimiento')

      await new sql.Request(transaction)
        .input('folio', sql.BigInt, folio)
        .input('cantidad', sql.Int, itemData.cantidad)
        .input('idproducto', sql.VarChar, itemData.idproducto)
        .input('razon', sql.VarChar, reason)
        .input('usuario', sql.VarChar, user)
        .input('precio', sql.Money, itemData.precio)
        .query(
          'INSERT INTO tempcancela (foliocheque, cantidad, clave, razon, fecha, usuario, precio) VALUES (@folio, @cantidad, @idproducto, @razon, GETDATE(), @usuario, @precio)',
        )

      // 🔧 5b: bitacorasistema INSERT eliminado — tenía placeholders '...' (T-SQL inválido) que hacían
      // throw + ROLLBACK de TODA la cancelación, así que cancelOrderItem nunca funcionaba. La auditoría
      // de la cancelación ya queda en `tempcancela` (foliocheque/cantidad/clave/razon/usuario/precio).

      // 🔧 5b: recalcular totales del header tras quitar la línea. Antes NO se hacía (el comentario
      // asumía erróneamente que el trigger lo hacía; el trigger solo escribe tracking) → el total
      // quedaba inflado. ISNULL(...,0) deja la orden en 0 si era la última línea.
      await new sql.Request(transaction).input('folio', sql.BigInt, folio).query(`
        UPDATE tc SET
          tc.totalarticulos = ISNULL(det.total_cantidad, 0),
          tc.subtotal = ISNULL(det.total_precio_sin_imp, 0),
          tc.totalimpuesto1 = ISNULL(det.total_impuestos, 0),
          tc.total = ISNULL(det.total_final, 0),
          tc.totalsindescuento = ISNULL(det.total_precio_sin_imp, 0)
        FROM tempcheques tc
        LEFT JOIN (
          SELECT foliodet, SUM(cantidad) AS total_cantidad, SUM(preciosinimpuestos) AS total_precio_sin_imp,
                 SUM(precio - preciosinimpuestos) AS total_impuestos, SUM(precio) AS total_final
          FROM tempcheqdet WHERE foliodet = @folio GROUP BY foliodet
        ) AS det ON tc.folio = det.foliodet
        WHERE tc.folio = @folio;`)

      await transaction.commit()
      log.info(`[Adapter SR11] Producto movimiento ${movementId} cancelado y totales recalculados.`)
    } catch (err: any) {
      log.error(`[Adapter SR11] Error en transacción de cancelar producto, haciendo ROLLBACK...`, err.message)
      await transaction.rollback()
      throw err
    }
  }

  /**
   * 🔧 5c: Divide una orden (split check). Orquesta los helpers existentes
   * (createSplitOrder + splitOrderItems) en UNA transacción y recalcula ambas
   * cabeceras desde sus líneas. Mueve `splitRatio` (0<r<1) de cada línea del padre
   * a una orden hija nueva. Antes estos helpers existían pero no había método público
   * ni comando que los usara (operación inalcanzable desde Avoqado).
   */
  async splitOrder(parentFolio: number, splitRatio: number): Promise<{ parentFolio: number; childFolio: number }> {
    if (!(splitRatio > 0 && splitRatio < 1)) {
      throw new Error(`splitRatio debe estar entre 0 y 1 (exclusivo). Recibido: ${splitRatio}`)
    }
    log.info(`[Adapter SR11] Dividiendo orden ${parentFolio} con ratio ${splitRatio}...`)
    const pool = getDbPool()
    const transaction = new sql.Transaction(pool)
    try {
      await transaction.begin()

      const totalRes = await new sql.Request(transaction)
        .input('folio', sql.BigInt, parentFolio)
        .query('SELECT total FROM tempcheques WHERE folio=@folio AND pagado=0 AND cancelado=0')
      if (totalRes.recordset.length === 0) {
        throw new Error(`Orden padre ${parentFolio} no encontrada o ya pagada/cancelada — no se puede dividir.`)
      }
      const parentTotal = Number(totalRes.recordset[0].total)

      // El hijo arranca con el monto proporcional; el recálculo final lo deja exacto.
      const childFolio = await this.createSplitOrder(parentFolio, parentTotal * splitRatio, transaction)
      await this.splitOrderItems(parentFolio, childFolio, splitRatio, transaction)

      // Recalcular AMBAS cabeceras desde sus líneas: splitOrderItems mueve líneas pero
      // no actualiza los totales de cabecera, así que sin esto el padre quedaría inflado.
      await this.recalcOrderTotals(parentFolio, transaction)
      await this.recalcOrderTotals(childFolio, transaction)

      await transaction.commit()
      log.info(`[Adapter SR11] Orden ${parentFolio} dividida. Hija: ${childFolio} (ratio ${splitRatio}).`)
      return { parentFolio, childFolio }
    } catch (err: any) {
      log.error(`[Adapter SR11] Error dividiendo orden ${parentFolio}, haciendo ROLLBACK...`, err.message)
      await transaction.rollback()
      throw err
    }
  }

  /**
   * 🔧 5c: Recalcula los totales de cabecera de una orden a partir de sus líneas
   * (mismo patrón SUM que addItemToOrder/cancelOrderItem). ISNULL(...,0) deja la
   * orden en 0 si no tiene líneas.
   */
  private async recalcOrderTotals(folio: number, transaction: sql.Transaction): Promise<void> {
    await new sql.Request(transaction).input('folio', sql.BigInt, folio).query(`
      UPDATE tc SET
        tc.totalarticulos = ISNULL(det.total_cantidad, 0),
        tc.subtotal = ISNULL(det.total_precio_sin_imp, 0),
        tc.totalimpuesto1 = ISNULL(det.total_impuestos, 0),
        tc.total = ISNULL(det.total_final, 0),
        tc.totalsindescuento = ISNULL(det.total_precio_sin_imp, 0)
      FROM tempcheques tc
      LEFT JOIN (
        SELECT foliodet, SUM(cantidad) AS total_cantidad, SUM(preciosinimpuestos) AS total_precio_sin_imp,
               SUM(precio - preciosinimpuestos) AS total_impuestos, SUM(precio) AS total_final
        FROM tempcheqdet WHERE foliodet = @folio GROUP BY foliodet
      ) AS det ON tc.folio = det.foliodet
      WHERE tc.folio = @folio;`)
  }

  // --- MÉTODOS DE PAGOS ---

  /**
   * RECETA #4 (PARCIAL): Registra un pago en una orden.
   */
  async applyPayment(folio: number, payment: PaymentData): Promise<void> {
    log.info(`[Adapter SR11] Aplicando pago de ${payment.amount} al folio ${folio}...`)
    const pool = getDbPool()
    // 🔧 5d: la query tenía placeholders '...' (T-SQL inválido) → SIEMPRE reventaba. Se corrige a
    // un INSERT real con las mismas columnas que insertPaymentToPOS. (Hoy el comando Payment.APPLY
    // usa applyIntelligentPayment/sp_ApplyPartialPayment; este método queda correcto por si se cablea.)
    await pool
      .request()
      .input('folio', sql.BigInt, folio)
      .input('idformadepago', sql.VarChar, payment.posPaymentMethodId)
      .input('importe', sql.Money, payment.amount)
      .input('propina', sql.Money, payment.tip)
      .input('referencia', sql.VarChar, payment.reference || '')
      .query(
        'INSERT INTO tempchequespagos (folio, idformadepago, importe, propina, referencia) VALUES (@folio, @idformadepago, @importe, @propina, @referencia)',
      )
  }

  /**
   * RECETA #4 (COMPLETA): Cierra la orden después de aplicar los pagos.
   */
  async closeAndPayOrder(folio: number): Promise<{ finalCheckNumber: number }> {
    log.info(`[Adapter SR11] Cerrando y pagando la orden folio ${folio}...`)
    const pool = getDbPool()
    const transaction = new sql.Transaction(pool)
    try {
      await transaction.begin()
      const folioResult = await new sql.Request(transaction).query("SELECT ultimofolio FROM folios WHERE serie=''")
      const nextCheckNumber = folioResult.recordset[0].ultimofolio + 1

      await new sql.Request(transaction)
        .input('folio', sql.BigInt, folio)
        .input('numcheque', sql.Int, nextCheckNumber)
        .query('UPDATE tempcheques SET pagado=1, impreso=1, numcheque=@numcheque, cierre=GETDATE() WHERE folio=@folio')

      await new sql.Request(transaction)
        .input('nextCheckNumber', sql.Int, nextCheckNumber)
        .query("UPDATE folios SET ultimofolio = @nextCheckNumber WHERE serie=''")

      await new sql.Request(transaction)
        .input('folio', sql.BigInt, folio)
        .query('UPDATE cuentas SET procesado = 1 WHERE foliocuenta = @folio')

      await transaction.commit()
      log.info(`[Adapter SR11] Orden folio ${folio} cerrada exitosamente con número de cheque ${nextCheckNumber}.`)
      return { finalCheckNumber: nextCheckNumber }
    } catch (err: any) {
      log.error(`[Adapter SR11] Error en transacción de cerrar orden, haciendo ROLLBACK...`, err.message)
      await transaction.rollback()
      throw err
    }
  }

  /**
   * RECETA #5: Abre un nuevo turno en el POS.
   */
  async openShift(data: ShiftOpenData): Promise<{ shiftId: number; staffName: string }> {
    log.info(`[Adapter SR11] Abriendo nuevo turno para el cajero ${data.posStaffId}...`)
    const pool = getDbPool()
    // 🔧 5d: turnos lleva WorkspaceId en v11/v12 pero NO en v10 → el INSERT con NEWID()
    // reventaba en v10 (Shift.OPEN roto). Ramificamos por presencia de la columna.
    // idempresa también estaba hardcodeada '1'; ahora se lee (fallback '1').
    const usesWorkspaceId = await detectUsesWorkspaceId(pool)
    const idempresa = await getDefaultEmpresa(pool)
    const transaction = new sql.Transaction(pool)
    try {
      await transaction.begin()

      // 🔧 5d: el siguiente idturno se calcula contra MAX(turnos) Y parametros.ultimoturno
      // (el contador nativo) para no colisionar con un turno que el POS nativo acabe de emitir.
      // Antes solo miraba MAX(turnos), lo que podía reusar un id ya entregado por el POS.
      // 🔧 review: UPDLOCK+HOLDLOCK sobre parametros toma el lock del contador y lo MANTIENE hasta el
      // commit, serializando el read-modify-write con otro opener (otra instancia o el POS nativo, que
      // también escribe parametros.ultimoturno). idturno NO tiene constraint único (la PK es
      // idturnointerno), así que sin esto dos opens concurrentes podían emitir el MISMO idturno.
      const idResult = await new sql.Request(transaction).query(
        `SELECT CAST(ISNULL((SELECT MAX(idturno) FROM turnos), 0) AS BIGINT) AS maxTurno,
                CAST(ISNULL((SELECT MAX(ultimoturno) FROM parametros WITH (UPDLOCK, HOLDLOCK)), 0) AS BIGINT) AS ultimoTurno`,
      )
      const maxTurno = Number(idResult.recordset[0].maxTurno)
      const ultimoTurno = Number(idResult.recordset[0].ultimoTurno)
      const nextShiftId = Math.max(maxTurno, ultimoTurno) + 1

      // Look up staff name if available
      let staffName = data.posStaffId // Default to ID if name not found
      const staffResult = await new sql.Request(transaction)
        .input('idmesero', sql.VarChar, data.posStaffId)
        .query('SELECT nombre FROM meseros WHERE idmesero = @idmesero')

      if (staffResult.recordset.length > 0) {
        staffName = staffResult.recordset[0].nombre
      }

      const insertQuery = usesWorkspaceId
        ? `INSERT INTO turnos (idturno, fondo, apertura, idestacion, cajero, idempresa, idmesero, WorkspaceId)
           VALUES (@idturno, @fondo, GETDATE(), @idestacion, @cajero, @idempresa, '', NEWID())`
        : `INSERT INTO turnos (idturno, fondo, apertura, idestacion, cajero, idempresa, idmesero)
           VALUES (@idturno, @fondo, GETDATE(), @idestacion, @cajero, @idempresa, '')`
      await new sql.Request(transaction)
        .input('idturno', sql.BigInt, nextShiftId)
        .input('fondo', sql.Money, data.startingCash)
        .input('cajero', sql.VarChar, data.posStaffId)
        .input('idestacion', sql.VarChar, data.stationId || 'AVOQADO_SYNC')
        .input('idempresa', sql.VarChar, idempresa)
        .query(insertQuery)

      await new sql.Request(transaction)
        .input('nextShiftId', sql.BigInt, nextShiftId)
        .query('UPDATE parametros SET ultimoturno = @nextShiftId')

      await transaction.commit()
      log.info(`[Adapter SR11] Turno ${nextShiftId} abierto exitosamente para ${staffName}.`)
      return { shiftId: nextShiftId, staffName: staffName }
    } catch (err: any) {
      log.error('[Adapter SR11] Error en transacción de abrir turno, haciendo ROLLBACK...', err.message)
      await transaction.rollback()
      throw err
    }
  }

  /**
   * RECETA #6: Cierra un turno existente y archiva toda su data.
   */
  async closeShift(shiftId: string, data: ShiftCloseData): Promise<void> {
    const shiftIdNum = parseInt(shiftId)
    if (isNaN(shiftIdNum)) {
      throw new Error(`Invalid shift ID: ${shiftId}`)
    }
    void data // ver nota abajo: el cierre no usa los declarados hasta implementar el archivado real

    // 🔧 5b: Shift.CLOSE NO está soportado de forma segura por el bridge.
    // El cierre nativo de SoftRestaurant archiva ~10 tablas temp*→permanente (cheques, cheqdet,
    // chequespagos, cancela, foliosfacturados, bitacoratarjetacredito, numerostarjetas, cheqpedidos…),
    // libera mesas, limpia PRODUCTOSENPRODUCCION y resetea folios — todo column-exact y version-específico.
    // La implementación previa tenía listas de columnas placeholder ('...') → T-SQL inválido que SIEMPRE
    // lanzaba; y de "completarse" mal habría BORRADO los temp* SIN archivar (pérdida de datos). Hasta
    // tener un archivado completo validado en vivo, fallamos EXPLÍCITO (el comando va a la DLQ de
    // comandos, queda visible para diagnóstico) en lugar de correr código destructivo/incompleto.
    // El cierre de turno lo realiza el POS nativo, y el producer ya lo observa/suprime correctamente.
    throw new Error(
      `Shift.CLOSE no soportado por el bridge (turno ${shiftIdNum}): el cierre/archivado de turno lo hace el POS nativo. ` +
        `Implementarlo en el bridge requiere replicar el archivado completo temp*→permanente, validado en vivo. Comando → DLQ.`,
    )
  }

  // =================================================================
  // --- MÉTODOS DE PAGO INTELIGENTE ---
  // =================================================================

  /**
   * SIMPLIFIED: Apply payment using new stored procedure
   */
  async applyIntelligentPayment(orderExternalId: string, payment: IntelligentPaymentData): Promise<PaymentResult> {
    log.info(`[Adapter SR11] 💳 Applying payment to order ${orderExternalId}, amount: ${payment.amount}`)

    const pool = getDbPool()

    try {
      // Get folio from external ID
      const folio = await this.extractFolioFromExternalId(orderExternalId)
      if (!folio) {
        throw new Error(`Could not resolve folio from external ID: ${orderExternalId}`)
      }

      log.info(`[Adapter SR11] Resolved folio ${folio} from external ID ${orderExternalId}`)

      // Call the new stored procedure
      const result = await pool
        .request()
        .input('Folio', sql.BigInt, folio)
        .input('PaymentAmount', sql.Money, payment.amount)
        .input('TipAmount', sql.Money, payment.tip || 0)
        .input('PaymentMethod', sql.VarChar(50), payment.posPaymentMethodId)
        .input('Reference', sql.VarChar(255), payment.reference || null)
        .output('Success', sql.Bit)
        .output('Message', sql.NVarChar(500))
        .output('Remaining', sql.Money)
        .execute('sp_ApplyPartialPayment')

      const success = result.output.Success
      const message = result.output.Message
      const remaining = result.output.Remaining || 0

      if (!success) {
        throw new Error(`Payment failed: ${message}`)
      }

      log.info(`[Adapter SR11] ✅ ${message}`)

      // Determine if order is closed
      const isClosed = remaining <= 0.01 // Allow for small rounding differences

      if (isClosed) {
        log.info(`[Adapter SR11] ✅ Order ${folio} fully paid`)
        return {
          closed: true,
          change: remaining < 0 ? Math.abs(remaining) : undefined,
          totalPaid: payment.amount,
        }
      } else {
        log.info(`[Adapter SR11] 💰 Partial payment applied. Remaining: $${remaining}`)
        return {
          closed: false,
          remaining: remaining,
          totalPaid: payment.amount,
        }
      }
    } catch (err: any) {
      log.error(`[Adapter SR11] Payment error:`, err.message)
      throw err
    }
  }

  /**
   * Helper: Extract folio from external ID (handles different formats)
   */
  private async extractFolioFromExternalId(orderExternalId: string): Promise<number | null> {
    log.info(`[Adapter SR11] 🔍 extractFolioFromExternalId called with: ${orderExternalId}`)
    const parts = orderExternalId.split(':')
    log.info(`[Adapter SR11] 🔍 Split into ${parts.length} parts`)

    // Handle different Entity ID formats
    if (parts.length === 3) {
      // v10 format: INSTANCE:TURNO:FOLIO
      const folio = parseInt(parts[2])
      log.info(`[Adapter SR11] 🔍 v10 format detected, returning folio: ${folio}`)
      return folio
    } else if (parts.length === 1) {
      // v11 format: WorkspaceId only, need to query
      log.info(`[Adapter SR11] 🔍 v11 format detected, querying database for WorkspaceId: ${orderExternalId}`)
      const pool = getDbPool()
      const query = 'SELECT TOP 1 folio FROM tempcheques WHERE WorkspaceId = @workspaceId ORDER BY folio DESC'
      log.info(`[Adapter SR11] 🔍 Executing query: ${query}`)

      const result = await pool.request().input('workspaceId', sql.UniqueIdentifier, orderExternalId).query(query)

      log.info(`[Adapter SR11] 🔍 Query returned ${result.recordset.length} results`)
      if (result.recordset.length > 0) {
        log.info(`[Adapter SR11] 🔍 Result folio: ${result.recordset[0].folio}`)
      } else {
        log.info(`[Adapter SR11] 🔍 No results found, returning null`)
      }

      return result.recordset[0]?.folio || null
    } else {
      // Try parsing as direct folio
      const folioNum = parseInt(orderExternalId)
      log.info(`[Adapter SR11] 🔍 Parsing as direct folio: ${folioNum}`)
      return isNaN(folioNum) ? null : folioNum
    }
  }

  /**
   * DEPRECATED: Use extractFolioFromExternalId instead
   */
  private async resolveOrderFolio(orderExternalId: string, transaction: sql.Transaction): Promise<number | null> {
    // Redirect to new method
    return this.extractFolioFromExternalId(orderExternalId)
  }

  /**
   * DEPRECATED: Old method kept for compatibility
   */
  private async extractFolioFromOrderId(orderExternalId: string): Promise<number | null> {
    const parts = orderExternalId.split(':')
    if (parts.length === 3) {
      // Formato v10: INSTANCE:TURNO:FOLIO
      const folio = parseInt(parts[2])
      return isNaN(folio) ? null : folio
    } else if (parts.length === 1) {
      // Formato v11: WorkspaceId
      const pool = await getDbPool()
      const result = await pool
        .request()
        .input('workspaceId', sql.UniqueIdentifier, orderExternalId)
        .query('SELECT folio FROM tempcheques WHERE WorkspaceId = @workspaceId')

      return result.recordset.length > 0 ? result.recordset[0].folio : null
    }

    return null
  }

  /**
   * Obtiene los datos básicos de una orden
   */
  private async getOrderData(folio: number, transaction: sql.Transaction): Promise<{ total: number; pagado: boolean } | null> {
    const result = await new sql.Request(transaction)
      .input('folio', sql.BigInt, folio)
      .query('SELECT total, pagado FROM tempcheques WHERE folio = @folio')

    return result.recordset.length > 0 ? result.recordset[0] : null
  }

  /**
   * ✅ NUEVO: Inserta un pago directamente en la tabla de pagos del POS
   */
  private async insertPaymentToPOS(folio: number, payment: IntelligentPaymentData, transaction: sql.Transaction): Promise<void> {
    await new sql.Request(transaction)
      .input('folio', sql.BigInt, folio)
      .input('idformadepago', sql.VarChar, payment.posPaymentMethodId)
      .input('importe', sql.Money, payment.amount)
      .input('propina', sql.Money, payment.tip || 0)
      .input('referencia', sql.VarChar, payment.reference || '').query(`
        INSERT INTO tempchequespagos (folio, idformadepago, importe, propina, referencia)
        VALUES (@folio, @idformadepago, @importe, @propina, @referencia)
      `)

    log.info(
      `[Adapter SR11] Pago insertado en tempchequespagos - Folio: ${folio}, Método: ${payment.posPaymentMethodId}, Monto: ${payment.amount}`,
    )
  }

  /**
   * Obtiene el total de pagos ya aplicados en tempchequespagos
   */
  private async getExistingPayments(folio: number, transaction: sql.Transaction): Promise<number> {
    const result = await new sql.Request(transaction)
      .input('folio', sql.BigInt, folio)
      .query('SELECT ISNULL(SUM(importe), 0) as total FROM tempchequespagos WHERE folio = @folio')

    return result.recordset[0]?.total || 0
  }

  /**
   * ✅ NUEVO: Marca una orden como pagada en el POS
   */
  private async markOrderAsPaid(folio: number, transaction: sql.Transaction): Promise<void> {
    // Obtener el siguiente número de cheque
    const folioResult = await new sql.Request(transaction).query("SELECT ultimofolio FROM folios WHERE serie=''")

    const nextCheckNumber = folioResult.recordset[0].ultimofolio + 1

    // Marcar la orden como pagada e impresa con número de cheque
    await new sql.Request(transaction).input('folio', sql.BigInt, folio).input('numcheque', sql.Int, nextCheckNumber).query(`
        UPDATE tempcheques
        SET pagado = 1,
            impreso = 1,
            numcheque = @numcheque,
            cierre = GETDATE()
        WHERE folio = @folio
      `)

    // Actualizar el contador de folios
    await new sql.Request(transaction)
      .input('nextCheckNumber', sql.Int, nextCheckNumber)
      .query("UPDATE folios SET ultimofolio = @nextCheckNumber WHERE serie=''")

    log.info(`[Adapter SR11] Orden ${folio} marcada como pagada con número de cheque ${nextCheckNumber}`)
  }

  /**
   * ✅ NUEVO: Crea una orden dividida (split check) siguiendo el patrón nativo de SoftRestaurant
   */
  private async createSplitOrder(parentFolio: number, splitAmount: number, transaction: sql.Transaction): Promise<number> {
    // 1. Obtener datos de la orden padre
    const parentOrder = await new sql.Request(transaction).input('folio', sql.BigInt, parentFolio).query(`
        SELECT mesa, idmesero, nopersonas, tipodeservicio, idarearestaurant,
               idempresa, estacion, idcomisionista, idcliente, idreservacion,
               total, fecha, usuarioapertura
        FROM tempcheques
        WHERE folio = @folio
      `)

    if (parentOrder.recordset.length === 0) {
      throw new Error(`No se encontró la orden padre con folio ${parentFolio}`)
    }

    const parent = parentOrder.recordset[0]

    // 2. Generar sufijo para la mesa dividida (A, B, C...)
    const existingSplits = await new sql.Request(transaction).input('baseMesa', sql.VarChar, parent.mesa + '-%').query(`
        SELECT COUNT(*) as count
        FROM tempcheques
        WHERE mesa LIKE @baseMesa AND pagado = 0
      `)

    const splitCount = existingSplits.recordset[0].count
    const splitSuffix = String.fromCharCode(65 + splitCount) // A, B, C...
    const splitMesa = `${parent.mesa}-${splitSuffix}`

    // 3. Obtener siguiente número de orden
    const ordenResult = await new sql.Request(transaction).query("SELECT ultimaorden FROM folios WHERE serie=''")

    const nextOrden = ordenResult.recordset[0].ultimaorden + 1

    // 4. Crear la orden dividida
    const insertResult = await new sql.Request(transaction)
      .input('mesa', sql.VarChar, splitMesa)
      .input('idmesero', sql.VarChar, parent.idmesero)
      .input('nopersonas', sql.Float, parent.nopersonas)
      .input('tipodeservicio', sql.Int, parent.tipodeservicio)
      .input('orden', sql.Float, nextOrden)
      .input('idarearestaurant', sql.VarChar, parent.idarearestaurant)
      .input('idempresa', sql.VarChar, parent.idempresa)
      .input('estacion', sql.VarChar, parent.estacion)
      .input('total', sql.Money, splitAmount)
      .input('fecha', sql.DateTime, parent.fecha)
      .input('usuarioapertura', sql.VarChar, parent.usuarioapertura)
      .input('idcomisionista', sql.VarChar, parent.idcomisionista || '')
      .input('idcliente', sql.VarChar, parent.idcliente || '')
      .input('idreservacion', sql.VarChar, parent.idreservacion || '').query(`
        INSERT INTO tempcheques (
          seriefolio, fecha, mesa, idmesero, nopersonas, tipodeservicio, orden,
          idarearestaurant, idempresa, estacion, total, descuento,
          idcomisionista, idcliente, idreservacion, propinaincluida, propinamanual,
          usuarioapertura, descuentocriterio, desc_imp_original, desc_porc_original
        ) VALUES (
          '', @fecha, @mesa, @idmesero, @nopersonas, @tipodeservicio, @orden,
          @idarearestaurant, @idempresa, @estacion, @total, 0.000000,
          @idcomisionista, @idcliente, @idreservacion, 0.000000, 0,
          @usuarioapertura, 0.000000, 0.000000, 0.000000
        );
        SELECT SCOPE_IDENTITY() as newFolio
      `)

    const newFolio = insertResult.recordset[0].newFolio

    // 5. Actualizar contador de órdenes
    await new sql.Request(transaction)
      .input('nextOrden', sql.Float, nextOrden)
      .query("UPDATE folios SET ultimaorden = @nextOrden WHERE serie=''")

    log.info(`[Adapter SR11] Orden dividida creada - Padre: ${parentFolio}, Hijo: ${newFolio}, Mesa: ${splitMesa}, Monto: ${splitAmount}`)

    return newFolio
  }

  /**
   * ✅ NUEVO: Divide los items de la orden proporcionalmente siguiendo el patrón de SoftRestaurant
   */
  private async splitOrderItems(parentFolio: number, childFolio: number, splitRatio: number, transaction: sql.Transaction): Promise<void> {
    // 1. Obtener todos los items de la orden padre
    const parentItems = await new sql.Request(transaction).input('folio', sql.BigInt, parentFolio).query(`
        SELECT movimiento, comanda, cantidad, idproducto, descuento, precio, preciosinimpuestos,
               comentario, tiempo, mitad, hora, modificador, idestacion, impuesto1, impuesto2, impuesto3,
               usuariodescuento, comentariodescuento, idtipodescuento, idproductocompuesto,
               productocompuestoprincipal, preciocatalogo, marcar, idmeseroproducto, idcortesia,
               numerotarjeta, horaproduccion, estadomonitor
        FROM tempcheqdet
        WHERE foliodet = @folio
        ORDER BY movimiento
      `)

    if (parentItems.recordset.length === 0) {
      log.warn(`[Adapter SR11] No se encontraron items para dividir en folio ${parentFolio}`)
      return
    }

    // 2. Crear items proporcionales en la orden hijo
    for (const item of parentItems.recordset) {
      const splitQuantity = item.cantidad * splitRatio
      const splitPrice = item.precio * splitRatio
      const splitPrecioSinImpuestos = item.preciosinimpuestos * splitRatio

      await new sql.Request(transaction)
        .input('foliodet', sql.BigInt, childFolio)
        .input('movimiento', sql.Int, item.movimiento)
        .input('comanda', sql.VarChar, item.comanda)
        .input('cantidad', sql.Float, splitQuantity)
        .input('idproducto', sql.VarChar, item.idproducto)
        .input('descuento', sql.Money, item.descuento * splitRatio)
        .input('precio', sql.Money, splitPrice)
        .input('preciosinimpuestos', sql.Money, splitPrecioSinImpuestos)
        .input('comentario', sql.VarChar, item.comentario)
        .input('tiempo', sql.VarChar, item.tiempo || '')
        .input('mitad', sql.Float, item.mitad)
        .input('hora', sql.DateTime, item.hora)
        .input('modificador', sql.Bit, item.modificador)
        .input('idestacion', sql.VarChar, item.idestacion)
        .input('impuesto1', sql.Float, item.impuesto1)
        .input('impuesto2', sql.Float, item.impuesto2)
        .input('impuesto3', sql.Float, item.impuesto3)
        .input('usuariodescuento', sql.VarChar, item.usuariodescuento)
        .input('comentariodescuento', sql.VarChar, item.comentariodescuento)
        .input('idtipodescuento', sql.VarChar, item.idtipodescuento)
        .input('idproductocompuesto', sql.VarChar, item.idproductocompuesto)
        .input('productocompuestoprincipal', sql.Bit, item.productocompuestoprincipal)
        .input('preciocatalogo', sql.Money, item.preciocatalogo * splitRatio)
        .input('marcar', sql.Bit, item.marcar)
        .input('idmeseroproducto', sql.VarChar, item.idmeseroproducto)
        .input('idcortesia', sql.VarChar, item.idcortesia)
        .input('numerotarjeta', sql.VarChar, item.numerotarjeta)
        .input('horaproduccion', sql.DateTime, item.horaproduccion)
        .input('estadomonitor', sql.Int, item.estadomonitor).query(`
          INSERT INTO tempcheqdet (
            foliodet, movimiento, comanda, cantidad, idproducto, descuento, precio, preciosinimpuestos,
            comentario, tiempo, mitad, hora, modificador, idestacion, impuesto1, impuesto2, impuesto3,
            usuariodescuento, comentariodescuento, idtipodescuento, idproductocompuesto,
            productocompuestoprincipal, preciocatalogo, marcar, idmeseroproducto, idcortesia,
            numerotarjeta, horaproduccion, estadomonitor
          ) VALUES (
            @foliodet, @movimiento, @comanda, @cantidad, @idproducto, @descuento, @precio, @preciosinimpuestos,
            @comentario, @tiempo, @mitad, @hora, @modificador, @idestacion, @impuesto1, @impuesto2, @impuesto3,
            @usuariodescuento, @comentariodescuento, @idtipodescuento, @idproductocompuesto,
            @productocompuestoprincipal, @preciocatalogo, @marcar, @idmeseroproducto, @idcortesia,
            @numerotarjeta, @horaproduccion, @estadomonitor
          )
        `)
    }

    // 3. Actualizar las cantidades en la orden padre (restar lo que se movió)
    for (const item of parentItems.recordset) {
      const remainingQuantity = item.cantidad * (1 - splitRatio)
      const remainingPrice = item.precio * (1 - splitRatio)
      const remainingPrecioSinImpuestos = item.preciosinimpuestos * (1 - splitRatio)

      await new sql.Request(transaction)
        .input('foliodet', sql.BigInt, parentFolio)
        .input('movimiento', sql.Int, item.movimiento)
        .input('cantidad', sql.Float, remainingQuantity)
        .input('precio', sql.Money, remainingPrice)
        .input('preciosinimpuestos', sql.Money, remainingPrecioSinImpuestos)
        .input('preciocatalogo', sql.Money, item.preciocatalogo * (1 - splitRatio)).query(`
          UPDATE tempcheqdet
          SET cantidad = @cantidad,
              precio = @precio,
              preciosinimpuestos = @preciosinimpuestos,
              preciocatalogo = @preciocatalogo
          WHERE foliodet = @foliodet AND movimiento = @movimiento
        `)
    }

    log.info(`[Adapter SR11] Items divididos - Padre: ${parentFolio}, Hijo: ${childFolio}, Ratio: ${splitRatio}`)
  }

  /**
   * ✅ NUEVO: Ajusta las cantidades de los items de una orden proporcionalmente
   */
  private async adjustOrderItemQuantities(folio: number, remainingRatio: number, transaction: sql.Transaction): Promise<void> {
    // Obtener todos los items de la orden
    const items = await new sql.Request(transaction).input('folio', sql.BigInt, folio).query(`
        SELECT movimiento, cantidad, precio, preciosinimpuestos, preciocatalogo
        FROM tempcheqdet
        WHERE foliodet = @folio
      `)

    // Ajustar cada item proporcionalmente
    for (const item of items.recordset) {
      const newQuantity = item.cantidad * remainingRatio
      const newPrice = item.precio * remainingRatio
      const newPrecioSinImpuestos = item.preciosinimpuestos * remainingRatio
      const newPrecioCatalogo = item.preciocatalogo * remainingRatio

      await new sql.Request(transaction)
        .input('folio', sql.BigInt, folio)
        .input('movimiento', sql.Int, item.movimiento)
        .input('cantidad', sql.Float, newQuantity)
        .input('precio', sql.Money, newPrice)
        .input('preciosinimpuestos', sql.Money, newPrecioSinImpuestos)
        .input('preciocatalogo', sql.Money, newPrecioCatalogo).query(`
          UPDATE tempcheqdet
          SET cantidad = @cantidad,
              precio = @precio,
              preciosinimpuestos = @preciosinimpuestos,
              preciocatalogo = @preciocatalogo
          WHERE foliodet = @folio AND movimiento = @movimiento
        `)
    }

    log.info(`[Adapter SR11] Cantidades ajustadas para ${items.recordset.length} items con ratio ${remainingRatio}`)
  }

  /**
   * ✅ NUEVO: Actualiza el total de una orden y todos los campos relacionados
   * Basado en la lógica del proyecto deprecado que funcionaba correctamente
   */
  private async updateOrderTotal(
    folio: number,
    newTotal: number,
    paymentAmount: number,
    payment: IntelligentPaymentData,
    transaction: sql.Transaction,
  ): Promise<void> {
    // Obtener los valores originales de la orden para calcular la proporción de impuestos y observaciones actuales
    const originalOrder = await new sql.Request(transaction).input('folio', sql.BigInt, folio).query(`
        SELECT total, subtotal, totalimpuesto1, observaciones
        FROM tempcheques
        WHERE folio = @folio
      `)

    if (originalOrder.recordset.length === 0) {
      throw new Error(`No se encontró la orden con folio ${folio}`)
    }

    const original = originalOrder.recordset[0]

    // Calcular la proporción de impuestos basada en el total original
    let taxRate = 0.16 // Default 16%
    if (original.total > 0 && original.totalimpuesto1 > 0) {
      taxRate = original.totalimpuesto1 / original.subtotal
    }

    // Calcular nuevos valores proporcionalmente
    const newSubtotal = newTotal / (1 + taxRate)
    const newTax = newTotal - newSubtotal

    // Crear la nueva observación del pago
    const currentDateTime = new Date().toLocaleString('es-MX', {
      timeZone: 'America/Mexico_City',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
    })

    const paymentMethod = this.getPaymentMethodName(payment.posPaymentMethodId)
    const newPaymentNote = `Pago parcial: $${paymentAmount.toFixed(2)} (${paymentMethod}) - ${currentDateTime}`

    // Construir las observaciones actualizadas
    const currentObservations = original.observaciones || ''
    const updatedObservations = currentObservations ? `${currentObservations} | ${newPaymentNote}` : newPaymentNote

    await new sql.Request(transaction)
      .input('folio', sql.BigInt, folio)
      .input('newTotal', sql.Money, newTotal)
      .input('newSubtotal', sql.Money, newSubtotal)
      .input('newTax', sql.Money, newTax)
      .input('observaciones', sql.VarChar, updatedObservations).query(`
        UPDATE tempcheques SET
          total = @newTotal,
          subtotal = @newSubtotal,
          totalimpuesto1 = @newTax,
          totalconpropina = @newTotal,
          totalsindescuento = @newTotal,
          totalsindescuentoimp = @newTotal,
          totalconpropinacargo = @newTotal,
          totalconcargo = @newTotal,
          subtotalcondescuento = @newSubtotal,
          totalarticulos = 1.0,
          subtotalsinimpuestos = @newSubtotal,
          observaciones = @observaciones
        WHERE folio = @folio
      `)

    log.info(
      `[Adapter SR11] Total de orden actualizado completamente - Folio: ${folio}, Nuevo total: ${newTotal}, Subtotal: ${newSubtotal}, Impuesto: ${newTax}`,
    )
    log.info(`[Adapter SR11] Observaciones actualizadas: ${updatedObservations}`)
  }

  /**
   * ✅ NUEVO: Registra un pago parcial para auditoría y reconciliación
   * Solo actualiza observaciones SIN modificar totales de la orden
   */
  private async trackPartialPayment(
    folio: number,
    amount: number,
    payment: IntelligentPaymentData,
    transaction: sql.Transaction,
  ): Promise<void> {
    // 1. Agregar pago a observaciones
    await this.addPaymentToObservations(folio, amount, payment, transaction)

    // 2. Verificar si existe la tabla de tracking de pagos parciales y registrar para auditoría
    const tableExists = await new sql.Request(transaction).query(`
        SELECT COUNT(*) as count
        FROM INFORMATION_SCHEMA.TABLES
        WHERE TABLE_NAME = 'AvoqadoPartialPayments'
      `)

    if (tableExists.recordset[0].count > 0) {
      // Si existe la tabla, registrar el pago parcial
      await new sql.Request(transaction)
        .input('folio', sql.BigInt, folio)
        .input('amount', sql.Money, amount)
        .input('tip', sql.Money, payment.tip || 0)
        .input('paymentMethodId', sql.VarChar, payment.posPaymentMethodId)
        .input('reference', sql.VarChar, payment.reference || '').query(`
          INSERT INTO AvoqadoPartialPayments (
            Folio, Amount, TipAmount, PaymentMethodId, Reference, IsProcessed
          ) VALUES (
            @folio, @amount, @tip, @paymentMethodId, @reference, 1
          )
        `)

      log.info(`[Adapter SR11] Pago parcial registrado para auditoría - Folio: ${folio}, Monto: ${amount}`)
    } else {
      log.warn(`[Adapter SR11] Tabla AvoqadoPartialPayments no existe, pago no registrado para auditoría`)
    }
  }

  /**
   * ✅ NUEVO: Agrega información de pago a las observaciones SIN modificar totales
   */
  private async addPaymentToObservations(
    folio: number,
    paymentAmount: number,
    payment: IntelligentPaymentData,
    transaction: sql.Transaction,
  ): Promise<void> {
    // Obtener observaciones actuales
    const currentOrder = await new sql.Request(transaction).input('folio', sql.BigInt, folio).query(`
        SELECT observaciones
        FROM tempcheques
        WHERE folio = @folio
      `)

    if (currentOrder.recordset.length === 0) {
      throw new Error(`No se encontró la orden con folio ${folio}`)
    }

    const current = currentOrder.recordset[0]

    // Crear la nueva observación del pago
    const currentDateTime = new Date().toLocaleString('es-MX', {
      timeZone: 'America/Mexico_City',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
    })

    const paymentMethod = this.getPaymentMethodName(payment.posPaymentMethodId)
    const newPaymentNote = `Pago parcial: $${paymentAmount.toFixed(2)} (${paymentMethod}) - ${currentDateTime}`

    // Construir las observaciones actualizadas
    const currentObservations = current.observaciones || ''
    const updatedObservations = currentObservations ? `${currentObservations} | ${newPaymentNote}` : newPaymentNote

    // Solo actualizar observaciones
    await new sql.Request(transaction).input('folio', sql.BigInt, folio).input('observaciones', sql.VarChar, updatedObservations).query(`
        UPDATE tempcheques
        SET observaciones = @observaciones
        WHERE folio = @folio
      `)

    log.info(`[Adapter SR11] Observaciones actualizadas con pago - Folio: ${folio}, Nota: ${newPaymentNote}`)
  }

  /**
   * ✅ NUEVO: Obtiene el nombre legible del método de pago
   */
  private getPaymentMethodName(paymentMethodId: string): string {
    const paymentMethods: { [key: string]: string } = {
      EF: 'Efectivo',
      CASH: 'Efectivo',
      ACASH: 'Efectivo Avoqado',
      CRE: 'Tarjeta de Crédito',
      DEB: 'Tarjeta de Débito',
      CARD: 'Tarjeta',
      ACARD: 'Tarjeta Avoqado',
      TRANS: 'Transferencia',
      VALE: 'Vale de Consumo',
      OTRO: 'Otro',
    }

    return paymentMethods[paymentMethodId] || paymentMethodId
  }

  /**
   * ✅ LEGACY: Actualiza el total de la orden padre después de la división (mantenido para compatibilidad)
   */
  private async updateParentOrderTotal(parentFolio: number, newTotal: number, transaction: sql.Transaction): Promise<void> {
    // Para mantener compatibilidad, crear un objeto de pago temporal
    const tempPayment: IntelligentPaymentData = {
      posPaymentMethodId: 'OTRO',
      amount: 0,
      tip: 0,
      reference: 'Split order adjustment',
    }
    await this.updateOrderTotal(parentFolio, newTotal, 0, tempPayment, transaction)
  }

  /**
   * ✅ NUEVO: Crea un pago rápido (fast payment)
   * Este tipo de pago crea una orden especial con un producto genérico y la cierra inmediatamente.
   * Es útil para registrar transacciones rápidas sin necesidad de crear una orden completa.
   */
  async createFastPayment(data: FastPaymentData): Promise<FastPaymentResult> {
    log.info(`[Adapter SR11] 💰 Creando pago rápido por $${data.amount}`)

    const pool = getDbPool()
    const transaction = new sql.Transaction(pool)

    try {
      await transaction.begin()

      // 1. Obtener información del turno actual
      const shiftResult = await new sql.Request(transaction).query(`
        SELECT TOP 1 idturno, idestacion
        FROM turnos
        WHERE cierre IS NULL
        ORDER BY apertura DESC
      `)

      if (shiftResult.recordset.length === 0) {
        throw new Error('No hay un turno abierto. Debe abrir un turno antes de crear pagos rápidos.')
      }

      const currentShift = shiftResult.recordset[0]
      const idTurno = currentShift.idturno
      const idEstacion = currentShift.idestacion

      // 2. Obtener el próximo número de orden
      const foliosResult = await new sql.Request(transaction).query(`
        SELECT ultimaorden FROM folios WHERE serie = ''
      `)
      const nextOrden = foliosResult.recordset[0]?.ultimaorden + 1 || 1

      // 3. Usar producto por defecto para pagos rápidos o el especificado
      const productId = data.productId || 'FASTPAY'

      // 4. Crear la orden con tipoventarapida = 1
      const insertOrderResult = await new sql.Request(transaction)
        .input('idturno', sql.BigInt, idTurno)
        .input('idmesero', sql.VarChar, data.cashierPosId)
        .input('idestacion', sql.VarChar, idEstacion)
        .input('orden', sql.Numeric, nextOrden)
        .input('total', sql.Money, data.amount)
        .input('observaciones', sql.VarChar, data.notes || `Pago rápido: ${data.reference || ''}`).query(`
          INSERT INTO tempcheques (
            seriefolio, numcheque, fecha, mesa, nopersonas, idmesero,
            pagado, cancelado, impreso, impresiones, cambio, descuento, orden,
            idcliente, idarearestaurant, idempresa, tipodeservicio, idturno,
            estacion, usuarioapertura, tipoventarapida, totalarticulos,
            subtotal, subtotalsinimpuestos, total, totalconpropina,
            totalimpuesto1, cargo, totalconcargo, totalconpropinacargo,
            efectivo, tarjeta, vales, otros, observaciones
          ) VALUES (
            '', 0, GETDATE(), 'FAST', 1, @idmesero,
            0, 0, 0, 0, 0, 0, @orden,
            '', '01', '0000000001', 3, @idturno,  -- tipodeservicio=3 para venta rápida
            @idestacion, @idmesero, 1, 1,  -- tipoventarapida=1
            @total, @total, @total, @total,
            0, 0, @total, @total,
            0, 0, 0, 0, @observaciones
          );
          SELECT SCOPE_IDENTITY() AS newFolio
        `)

      const newFolio = insertOrderResult.recordset[0].newFolio

      // 5. Actualizar contador de órdenes
      await new sql.Request(transaction)
        .input('nextOrden', sql.Numeric, nextOrden)
        .query("UPDATE folios SET ultimaorden = @nextOrden WHERE serie=''")

      // 6. Agregar el producto con el precio del pago
      const movimientoResult = await new sql.Request(transaction)
        .input('folio', sql.BigInt, newFolio)
        .query('SELECT ISNULL(MAX(movimiento), 0) + 1 AS nextMovimiento FROM tempcheqdet WHERE foliodet = @folio')

      const nextMovimiento = movimientoResult.recordset[0].nextMovimiento

      await new sql.Request(transaction)
        .input('foliodet', sql.BigInt, newFolio)
        .input('movimiento', sql.Int, nextMovimiento)
        .input('cantidad', sql.Float, 1)
        .input('idproducto', sql.VarChar, productId)
        .input('precio', sql.Money, data.amount)
        .input('preciosinimpuestos', sql.Money, data.amount)
        .input('idestacion', sql.VarChar, idEstacion).query(`
          INSERT INTO tempcheqdet (
            foliodet, movimiento, comanda, cantidad, idproducto,
            descuento, precio, preciosinimpuestos, tiempo, hora,
            modificador, idestacion, impuesto1, impuesto2, impuesto3
          ) VALUES (
            @foliodet, @movimiento, '', @cantidad, @idproducto,
            0, @precio, @preciosinimpuestos, '', GETDATE(),
            0, @idestacion, 0, 0, 0
          )
        `)

      // 7. Marcar como impreso (requisito para poder pagar)
      const numChequeResult = await new sql.Request(transaction).query(`
        SELECT ISNULL(MAX(numcheque), 0) + 1 AS nextNumCheque
        FROM tempcheques
        WHERE idturno = ${idTurno}
      `)

      const numCheque = numChequeResult.recordset[0].nextNumCheque

      await new sql.Request(transaction).input('folio', sql.BigInt, newFolio).input('numcheque', sql.Numeric, numCheque).query(`
          UPDATE tempcheques
          SET impreso = 1, numcheque = @numcheque, impresiones = 1
          WHERE folio = @folio
        `)

      // 8. Aplicar el pago
      const paymentAmount = data.amount
      const paymentMethod = data.posPaymentMethodId

      // Determinar los campos de pago según el método
      let efectivo = 0,
        tarjeta = 0,
        vales = 0,
        otros = 0
      switch (paymentMethod.toUpperCase()) {
        case 'AEF': // Efectivo en el sistema
        case 'EF':
        case 'CASH':
        case 'ACASH':
          efectivo = paymentAmount
          break
        case 'CRE': // Tarjeta de crédito
        case 'DEB': // Tarjeta de débito
        case 'CARD':
        case 'ACARD':
        case 'SRPC':
        case 'SRPD':
          tarjeta = paymentAmount
          break
        case 'VALE':
          vales = paymentAmount
          break
        default:
          otros = paymentAmount
      }

      // Insertar el pago
      await new sql.Request(transaction)
        .input('folio', sql.BigInt, newFolio)
        .input('idformadepago', sql.VarChar, paymentMethod)
        .input('importe', sql.Money, paymentAmount)
        .input('referencia', sql.VarChar, data.reference || '').query(`
          INSERT INTO tempchequespagos (
            folio, idformadepago, importe, propina, referencia
          ) VALUES (
            @folio, @idformadepago, @importe, 0, @referencia
          )
        `)

      // 9. Marcar la orden como pagada
      await new sql.Request(transaction)
        .input('folio', sql.BigInt, newFolio)
        .input('efectivo', sql.Money, efectivo)
        .input('tarjeta', sql.Money, tarjeta)
        .input('vales', sql.Money, vales)
        .input('otros', sql.Money, otros)
        .input('usuariopago', sql.VarChar, data.cashierPosId).query(`
          UPDATE tempcheques
          SET pagado = 1,
              efectivo = @efectivo,
              tarjeta = @tarjeta,
              vales = @vales,
              otros = @otros,
              usuariopago = @usuariopago
          WHERE folio = @folio
        `)

      // 10. Commit de la transacción
      await transaction.commit()

      log.info(`[Adapter SR11] ✅ Pago rápido creado exitosamente - Folio: ${newFolio}, Cheque: ${numCheque}`)

      return {
        folio: newFolio,
        checkNumber: numCheque,
        transactionTime: new Date(),
        totalAmount: data.amount,
        paymentMethod: this.getPaymentMethodName(paymentMethod),
        success: true,
      }
    } catch (error: any) {
      await transaction.rollback()
      log.error(`[Adapter SR11] Error al crear pago rápido: ${error.message}`)
      throw error
    }
  }
}
