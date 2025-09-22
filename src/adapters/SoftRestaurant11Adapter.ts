import sql from 'mssql'
import { getDbPool } from '../core/db'
import { log } from '../core/logger'
import { createEmptyOrder } from '../services/Orders/createEmptyOrder'
import { IPOSAdapter, OrderAddItemData, OrderCreateData, PaymentData, ShiftCloseData, ShiftOpenData, IntelligentPaymentData, PaymentResult } from './IPosAdapter'

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
        .input('folio', sql.Int, folio)
        .query('SELECT ISNULL(MAX(movimiento), 0) as maxMovimiento FROM tempcheqdet WHERE foliodet = @folio')
      const nextMovement = movResult.recordset[0].maxMovimiento + 1

      const priceWithoutTax = item.price / 1.16

      const insertQuery = `
        INSERT INTO tempcheqdet (foliodet, movimiento, idproducto, cantidad, precio, preciosinimpuestos, hora, idestacion, impuesto1, idmeseroproducto, comentario) 
        VALUES (@folio, @movimiento, @idproducto, @cantidad, @precio, @preciosinimpuestos, GETDATE(), 'AVOQADO_SYNC', 16.00, @idmesero, @comentario)
      `
      await new sql.Request(transaction)
        .input('folio', sql.Int, folio)
        .input('movimiento', sql.Int, nextMovement)
        .input('idproducto', sql.VarChar, actualPosProductId)
        .input('cantidad', sql.Int, item.quantity)
        .input('precio', sql.Money, item.price * item.quantity)
        .input('preciosinimpuestos', sql.Money, priceWithoutTax * item.quantity)
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
      await new sql.Request(transaction).input('folio', sql.Int, folio).query(updateTotalsQuery)

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
        .input('folio', sql.Int, folio)
        .input('movimiento', sql.Int, movementId)
        .query('SELECT idproducto, cantidad, precio FROM tempcheqdet WHERE foliodet = @folio AND movimiento = @movimiento')

      if (itemDataResult.recordset.length === 0)
        throw new Error(`No se encontró el item con movimiento ${movementId} en el folio ${folio}.`)
      const itemData = itemDataResult.recordset[0]

      await new sql.Request(transaction)
        .input('folio', sql.Int, folio)
        .input('idproducto', sql.VarChar, itemData.idproducto)
        .input('movimiento', sql.Int, movementId)
        .query('UPDATE productosenproduccion SET cancelado=1 WHERE folio=@folio AND idproducto=@idproducto AND movimiento=@movimiento')

      await new sql.Request(transaction)
        .input('folio', sql.Int, folio)
        .input('movimiento', sql.Int, movementId)
        .query('DELETE FROM tempcheqdet WHERE foliodet=@folio AND movimiento=@movimiento')

      await new sql.Request(transaction)
        .input('folio', sql.Int, folio)
        .input('cantidad', sql.Int, itemData.cantidad)
        .input('idproducto', sql.VarChar, itemData.idproducto)
        .input('razon', sql.VarChar, reason)
        .input('usuario', sql.VarChar, user)
        .input('precio', sql.Money, itemData.precio)
        .query(
          'INSERT INTO tempcancela (foliocheque, cantidad, clave, razon, fecha, usuario, precio) VALUES (@folio, @cantidad, @idproducto, @razon, GETDATE(), @usuario, @precio)',
        )

      await new sql.Request(transaction)
        .input('evento', sql.VarChar, `Cancelación de producto en folio ${folio}`)
        .input('valores', sql.VarChar, `Producto: ${itemData.idproducto}, Razón: ${reason}`)
        .input('usuario', sql.VarChar, user)
        .query('INSERT INTO bitacorasistema (fecha, usuario, evento, valores, ...) VALUES(GETDATE(), @usuario, @evento, @valores, ...)')

      await transaction.commit()
      log.info(`[Adapter SR11] Producto movimiento ${movementId} cancelado exitosamente.`)
      // El Trigger del DELETE en tempcheqdet debería haber recalculado los totales en tempcheques.
    } catch (err: any) {
      log.error(`[Adapter SR11] Error en transacción de cancelar producto, haciendo ROLLBACK...`, err.message)
      await transaction.rollback()
      throw err
    }
  }

  // --- MÉTODOS DE PAGOS ---

  /**
   * RECETA #4 (PARCIAL): Registra un pago en una orden.
   */
  async applyPayment(folio: number, payment: PaymentData): Promise<void> {
    log.info(`[Adapter SR11] Aplicando pago de ${payment.amount} al folio ${folio}...`)
    const pool = getDbPool()
    await pool
      .request()
      .input('folio', sql.Int, folio)
      .input('idformadepago', sql.VarChar, payment.posPaymentMethodId)
      .input('importe', sql.Money, payment.amount)
      .input('propina', sql.Money, payment.tip)
      .input('referencia', sql.VarChar, payment.reference || '')
      .query(
        'INSERT INTO tempchequespagos (folio, idformadepago, importe, propina, referencia, ...) VALUES (@folio, @idformadepago, @importe, @propina, @referencia, ...)',
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
        .input('folio', sql.Int, folio)
        .input('numcheque', sql.Int, nextCheckNumber)
        .query('UPDATE tempcheques SET pagado=1, impreso=1, numcheque=@numcheque, cierre=GETDATE() WHERE folio=@folio')

      await new sql.Request(transaction)
        .input('nextCheckNumber', sql.Int, nextCheckNumber)
        .query("UPDATE folios SET ultimofolio = @nextCheckNumber WHERE serie=''")

      await new sql.Request(transaction).input('folio', sql.Int, folio).query('UPDATE cuentas SET procesado = 1 WHERE foliocuenta = @folio')

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
  async openShift(data: ShiftOpenData): Promise<{ shiftId: number }> {
    log.info(`[Adapter SR11] Abriendo nuevo turno para el cajero ${data.posStaffId}...`)
    const pool = getDbPool()
    const transaction = new sql.Transaction(pool)
    try {
      await transaction.begin()

      // Obtenemos el siguiente ID para el turno. Asumimos que es un secuencial.
      const idResult = await new sql.Request(transaction).query('SELECT ISNULL(MAX(idturno), 0) + 1 as nextId FROM turnos')
      const nextShiftId = idResult.recordset[0].nextId

      const insertQuery = `
        INSERT INTO turnos (idturno, fondo, apertura, idestacion, cajero, idempresa, idmesero, WorkspaceId) 
        VALUES (@idturno, @fondo, GETDATE(), 'AVOQADO_SYNC', @cajero, '1', '', NEWID())
      `
      await new sql.Request(transaction)
        .input('idturno', sql.Int, nextShiftId)
        .input('fondo', sql.Money, data.startingCash)
        .input('cajero', sql.VarChar, data.posStaffId)
        .query(insertQuery)

      await new sql.Request(transaction)
        .input('nextShiftId', sql.Int, nextShiftId)
        .query('UPDATE parametros SET ultimoturno = @nextShiftId')

      await transaction.commit()
      log.info(`[Adapter SR11] Turno ${nextShiftId} abierto exitosamente.`)
      return { shiftId: nextShiftId }
    } catch (err: any) {
      log.error('[Adapter SR11] Error en transacción de abrir turno, haciendo ROLLBACK...', err.message)
      await transaction.rollback()
      throw err
    }
  }

  /**
   * RECETA #6: Cierra un turno existente y archiva toda su data.
   */
  async closeShift(shiftId: number, data: ShiftCloseData): Promise<void> {
    log.info(`[Adapter SR11] Iniciando proceso de cierre para el turno ${shiftId}...`)
    const pool = getDbPool()
    const transaction = new sql.Transaction(pool)
    try {
      await transaction.begin()
      log.info(`[Adapter SR11] Paso 1: Archivando datos del turno ${shiftId}...`)

      // --- PROCESO DE ARCHIVADO: Mover datos de tablas 'temp' a tablas permanentes ---
      // Usamos el `idturno_cierre` para marcar a qué cierre pertenecen estos registros.

      const archivalQueries = [
        `INSERT INTO cheques (...) SELECT ..., @shiftId as idturno_cierre, ... FROM tempcheques WHERE idturno = @shiftId`,
        `INSERT INTO cheqdet (...) SELECT ..., @shiftId as idturno_cierre, ... FROM tempcheqdet d JOIN tempcheques t ON d.foliodet = t.folio WHERE t.idturno = @shiftId`,
        `INSERT INTO chequespagos (...) SELECT ..., @shiftId as idturno_cierre, ... FROM tempchequespagos p JOIN tempcheques t ON p.folio = t.folio WHERE t.idturno = @shiftId`,
        // ... (añadir aquí los demás INSERT/SELECT para todas las tablas temp: tempcancela, etc.)
      ]

      for (const query of archivalQueries) {
        await new sql.Request(transaction).input('shiftId', sql.Int, shiftId).query(query)
      }
      log.info(`[Adapter SR11] Paso 2: Limpiando tablas temporales...`)

      // --- PROCESO DE LIMPIEZA ---
      const folioSubquery = `SELECT folio FROM tempcheques WHERE idturno = @shiftId`
      await new sql.Request(transaction)
        .input('shiftId', sql.Int, shiftId)
        .query(`DELETE FROM mesasasignadas WHERE folio IN (${folioSubquery})`)
      await new sql.Request(transaction)
        .input('shiftId', sql.Int, shiftId)
        .query(`DELETE FROM tempchequespagos WHERE folio IN (${folioSubquery})`)
      await new sql.Request(transaction)
        .input('shiftId', sql.Int, shiftId)
        .query(`DELETE FROM tempcheqdet WHERE foliodet IN (${folioSubquery})`)
      await new sql.Request(transaction)
        .input('shiftId', sql.Int, shiftId)
        .query(`DELETE FROM tempcancela WHERE foliocheque IN (${folioSubquery})`)
      await new sql.Request(transaction).input('shiftId', sql.Int, shiftId).query(`DELETE FROM tempcheques WHERE idturno = @shiftId`)

      log.info(`[Adapter SR11] Paso 3: Cerrando el registro del turno...`)

      // --- PROCESO DE CIERRE FINAL ---
      await new sql.Request(transaction)
        .input('shiftId', sql.Int, shiftId)
        .input('cierre', sql.DateTime, new Date())
        .input('efectivo', sql.Money, data.cashDeclared)
        .input('tarjeta', sql.Money, data.cardDeclared)
        .input('vales', sql.Money, data.vouchersDeclared)
        .query('UPDATE turnos SET cierre=@cierre, efectivo=@efectivo, tarjeta=@tarjeta, vales=@vales WHERE idturno=@shiftId')

      await new sql.Request(transaction).query("UPDATE folios SET ultimaorden=0, ultimofolioproduccion=0 WHERE serie=''")

      await transaction.commit()
      log.info(`[Adapter SR11] COMMIT exitoso. Turno ${shiftId} cerrado y archivado.`)
    } catch (err: any) {
      log.error(`[Adapter SR11] Error en transacción de cerrar turno, haciendo ROLLBACK...`, err.message)
      await transaction.rollback()
      throw err
    }
  }

  // =================================================================
  // --- MÉTODOS DE PAGO INTELIGENTE ---
  // =================================================================

  /**
   * ✅ NUEVO: Aplica un pago usando el mecanismo nativo de división de cuenta
   * Esto garantiza que el POS siempre muestre el saldo correcto para sincronización bidireccional
   */
  async applyIntelligentPayment(orderExternalId: string, payment: IntelligentPaymentData): Promise<PaymentResult> {
    log.info(`[Adapter SR11] Aplicando pago con split check para orden ${orderExternalId}, monto: ${payment.amount}`)

    const pool = getDbPool()
    const transaction = new sql.Transaction(pool)

    try {
      await transaction.begin()

      // PASO 1: Obtener el folio desde el orderExternalId
      const folio = await this.resolveOrderFolio(orderExternalId, transaction)
      if (!folio) {
        throw new Error(`No se pudo encontrar la orden con ID externo: ${orderExternalId}`)
      }

      // PASO 2: Obtener datos de la orden
      const orderData = await this.getOrderData(folio, transaction)
      if (!orderData) {
        throw new Error(`No se encontraron datos para el folio: ${folio}`)
      }

      // PASO 3: Verificar que la orden no esté ya pagada
      if (orderData.pagado) {
        throw new Error(`La orden ${folio} ya está pagada completamente`)
      }

      // PASO 4: Calcular pagos existentes
      const existingPayments = await this.getExistingPayments(folio, transaction)
      const totalAfterPayment = existingPayments + payment.amount

      log.info(`[Adapter SR11] Estado de pago - Orden: ${orderData.total}, Ya pagado: ${existingPayments}, Nuevo pago: ${payment.amount}, Total después: ${totalAfterPayment}`)

      // PASO 5: Determinar si la orden está completamente pagada
      if (totalAfterPayment >= orderData.total) {
        // PAGO COMPLETO - Aplicar pago directamente y cerrar
        const change = totalAfterPayment - orderData.total
        await this.insertPaymentToPOS(folio, payment, transaction)
        await this.markOrderAsPaid(folio, transaction)

        await transaction.commit()
        log.info(`[Adapter SR11] ✅ Orden ${folio} pagada completamente. Cambio: ${change}`)

        return {
          closed: true,
          change: change > 0 ? change : undefined,
          totalPaid: totalAfterPayment
        }
      } else {
        // PAGO PARCIAL - Ajustar cantidades en la orden original
        log.info(`[Adapter SR11] 💰 Aplicando pago parcial de ${payment.amount} ajustando cantidades`)

        // Calcular ratio de pago (porcentaje pagado)
        const paymentRatio = payment.amount / orderData.total
        const remainingRatio = 1 - paymentRatio

        log.info(`[Adapter SR11] Ratio de pago: ${paymentRatio}, Ratio restante: ${remainingRatio}`)

        // Ajustar cantidades de todos los items proporcionalmente
        await this.adjustOrderItemQuantities(folio, remainingRatio, transaction)

        // Calcular nuevo total (cantidad restante)
        const newTotal = orderData.total - payment.amount

        // Actualizar el total de la orden con información del pago
        await this.updateOrderTotal(folio, newTotal, payment.amount, payment, transaction)
        log.info(`[Adapter SR11] Total actualizado - Anterior: ${orderData.total}, Nuevo: ${newTotal}`)

        // Registrar el pago para auditoría
        await this.trackPartialPayment(folio, payment.amount, payment, transaction)

        await transaction.commit()
        log.info(`[Adapter SR11] 💰 Pago parcial aplicado. Orden ${folio} restante: ${newTotal}`)

        return {
          closed: false,
          remaining: newTotal,
          totalPaid: existingPayments + payment.amount
        }
      }

    } catch (err: any) {
      log.error(`[Adapter SR11] Error en pago inteligente, haciendo ROLLBACK...`, err.message)
      try {
        await transaction.rollback()
      } catch (rollbackErr: any) {
        log.error('[Adapter SR11] Error en ROLLBACK de pago inteligente', rollbackErr.message)
      }
      throw err
    }
  }

  /**
   * Resuelve el folio de una orden desde su ID externo
   */
  private async resolveOrderFolio(orderExternalId: string, transaction: sql.Transaction): Promise<number | null> {
    const parts = orderExternalId.split(':')

    // Manejar diferentes formatos de Entity ID basado en versión detectada
    if (parts.length === 3) {
      // Formato v10: INSTANCE:TURNO:FOLIO
      const folio = parseInt(parts[2])
      return isNaN(folio) ? null : folio
    } else if (parts.length === 1) {
      // Formato v11: WorkspaceId
      const result = await new sql.Request(transaction)
        .input('workspaceId', sql.UniqueIdentifier, orderExternalId)
        .query('SELECT folio FROM tempcheques WHERE WorkspaceId = @workspaceId')

      return result.recordset.length > 0 ? result.recordset[0].folio : null
    }

    return null
  }

  /**
   * Obtiene los datos básicos de una orden
   */
  private async getOrderData(folio: number, transaction: sql.Transaction): Promise<{ total: number, pagado: boolean } | null> {
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
      .input('referencia', sql.VarChar, payment.reference || '')
      .query(`
        INSERT INTO tempchequespagos (folio, idformadepago, importe, propina, referencia)
        VALUES (@folio, @idformadepago, @importe, @propina, @referencia)
      `)

    log.info(`[Adapter SR11] Pago insertado en tempchequespagos - Folio: ${folio}, Método: ${payment.posPaymentMethodId}, Monto: ${payment.amount}`)
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
    const folioResult = await new sql.Request(transaction)
      .query("SELECT ultimofolio FROM folios WHERE serie=''")

    const nextCheckNumber = folioResult.recordset[0].ultimofolio + 1

    // Marcar la orden como pagada e impresa con número de cheque
    await new sql.Request(transaction)
      .input('folio', sql.BigInt, folio)
      .input('numcheque', sql.Int, nextCheckNumber)
      .query(`
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
    const parentOrder = await new sql.Request(transaction)
      .input('folio', sql.BigInt, parentFolio)
      .query(`
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
    const existingSplits = await new sql.Request(transaction)
      .input('baseMesa', sql.VarChar, parent.mesa + '-%')
      .query(`
        SELECT COUNT(*) as count
        FROM tempcheques
        WHERE mesa LIKE @baseMesa AND pagado = 0
      `)

    const splitCount = existingSplits.recordset[0].count
    const splitSuffix = String.fromCharCode(65 + splitCount) // A, B, C...
    const splitMesa = `${parent.mesa}-${splitSuffix}`

    // 3. Obtener siguiente número de orden
    const ordenResult = await new sql.Request(transaction)
      .query("SELECT ultimaorden FROM folios WHERE serie=''")

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
      .input('idreservacion', sql.VarChar, parent.idreservacion || '')
      .query(`
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
    const parentItems = await new sql.Request(transaction)
      .input('folio', sql.BigInt, parentFolio)
      .query(`
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
        .input('estadomonitor', sql.Int, item.estadomonitor)
        .query(`
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
        .input('preciocatalogo', sql.Money, item.preciocatalogo * (1 - splitRatio))
        .query(`
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
    const items = await new sql.Request(transaction)
      .input('folio', sql.BigInt, folio)
      .query(`
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
        .input('preciocatalogo', sql.Money, newPrecioCatalogo)
        .query(`
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
  private async updateOrderTotal(folio: number, newTotal: number, paymentAmount: number, payment: IntelligentPaymentData, transaction: sql.Transaction): Promise<void> {
    // Obtener los valores originales de la orden para calcular la proporción de impuestos y observaciones actuales
    const originalOrder = await new sql.Request(transaction)
      .input('folio', sql.BigInt, folio)
      .query(`
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
      second: '2-digit'
    })

    const paymentMethod = this.getPaymentMethodName(payment.posPaymentMethodId)
    const newPaymentNote = `Pago parcial: $${paymentAmount.toFixed(2)} (${paymentMethod}) - ${currentDateTime}`

    // Construir las observaciones actualizadas
    const currentObservations = original.observaciones || ''
    const updatedObservations = currentObservations
      ? `${currentObservations} | ${newPaymentNote}`
      : newPaymentNote

    await new sql.Request(transaction)
      .input('folio', sql.BigInt, folio)
      .input('newTotal', sql.Money, newTotal)
      .input('newSubtotal', sql.Money, newSubtotal)
      .input('newTax', sql.Money, newTax)
      .input('observaciones', sql.VarChar, updatedObservations)
      .query(`
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

    log.info(`[Adapter SR11] Total de orden actualizado completamente - Folio: ${folio}, Nuevo total: ${newTotal}, Subtotal: ${newSubtotal}, Impuesto: ${newTax}`)
    log.info(`[Adapter SR11] Observaciones actualizadas: ${updatedObservations}`)
  }

  /**
   * ✅ NUEVO: Registra un pago parcial para auditoría y reconciliación
   * Solo actualiza observaciones SIN modificar totales de la orden
   */
  private async trackPartialPayment(folio: number, amount: number, payment: IntelligentPaymentData, transaction: sql.Transaction): Promise<void> {
    // 1. Agregar pago a observaciones
    await this.addPaymentToObservations(folio, amount, payment, transaction)

    // 2. Verificar si existe la tabla de tracking de pagos parciales y registrar para auditoría
    const tableExists = await new sql.Request(transaction)
      .query(`
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
        .input('reference', sql.VarChar, payment.reference || '')
        .query(`
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
  private async addPaymentToObservations(folio: number, paymentAmount: number, payment: IntelligentPaymentData, transaction: sql.Transaction): Promise<void> {
    // Obtener observaciones actuales
    const currentOrder = await new sql.Request(transaction)
      .input('folio', sql.BigInt, folio)
      .query(`
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
      second: '2-digit'
    })

    const paymentMethod = this.getPaymentMethodName(payment.posPaymentMethodId)
    const newPaymentNote = `Pago parcial: $${paymentAmount.toFixed(2)} (${paymentMethod}) - ${currentDateTime}`

    // Construir las observaciones actualizadas
    const currentObservations = current.observaciones || ''
    const updatedObservations = currentObservations
      ? `${currentObservations} | ${newPaymentNote}`
      : newPaymentNote

    // Solo actualizar observaciones
    await new sql.Request(transaction)
      .input('folio', sql.BigInt, folio)
      .input('observaciones', sql.VarChar, updatedObservations)
      .query(`
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
      'EF': 'Efectivo',
      'CASH': 'Efectivo',
      'ACASH': 'Efectivo Avoqado',
      'CRE': 'Tarjeta de Crédito',
      'DEB': 'Tarjeta de Débito',
      'CARD': 'Tarjeta',
      'ACARD': 'Tarjeta Avoqado',
      'TRANS': 'Transferencia',
      'VALE': 'Vale de Consumo',
      'OTRO': 'Otro'
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
      reference: 'Split order adjustment'
    }
    await this.updateOrderTotal(parentFolio, newTotal, 0, tempPayment, transaction)
  }

}
