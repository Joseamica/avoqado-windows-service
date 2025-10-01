-- =============================================
-- SOFTRESTAURANT PAYMENT TEST SCENARIOS
-- For Quick Testing Without UI
-- Date: 2025-09-23
-- Author: Claude
-- =============================================

/*
USAGE:
------
1. Connect to test database:
   export SQLCMDPASSWORD='National09'
   sqlcmd -S "tcp:100.80.118.68,49759" -d avov2 -U sa

2. Run specific scenarios or the entire script

3. Check results in tracking table

IMPORTANT:
----------
- Requires an open shift in turnos table
- Uses real payment method IDs from formasdepago table
- Creates real entries in tracking table
*/

-- =============================================
-- CONFIGURATION
-- =============================================
DECLARE @TestPrefix VARCHAR(50) = 'TEST_PAY_' + CONVERT(VARCHAR, GETDATE(), 112); -- Today's date
DECLARE @CurrentShiftId BIGINT;
DECLARE @CurrentStation VARCHAR(50);

-- Get current open shift
SELECT TOP 1
    @CurrentShiftId = idturno,
    @CurrentStation = idestacion
FROM turnos
WHERE cierre IS NULL
ORDER BY apertura DESC;

IF @CurrentShiftId IS NULL
BEGIN
    PRINT 'ERROR: No open shift found. Please open a shift first.';
    RETURN;
END

PRINT '✅ Using Shift ID: ' + CAST(@CurrentShiftId AS VARCHAR);
PRINT '✅ Station: ' + @CurrentStation;
PRINT '';

-- =============================================
-- SCENARIO 1: SIMPLE FULL PAYMENT (CASH)
-- =============================================
PRINT '========================================';
PRINT 'SCENARIO 1: Simple Full Payment (Cash)';
PRINT '========================================';

DECLARE @Folio1 BIGINT;
DECLARE @WorkspaceId1 UNIQUEIDENTIFIER = NEWID();

BEGIN TRANSACTION;

-- 1. Create order
INSERT INTO tempcheques (
    seriefolio, numcheque, fecha, mesa, nopersonas, idmesero,
    pagado, cancelado, impreso, impresiones, cambio, descuento, orden,
    idcliente, idarearestaurant, idempresa, tipodeservicio, idturno,
    estacion, usuarioapertura, tipoventarapida, totalarticulos,
    subtotal, subtotalsinimpuestos, total, totalconpropina,
    totalimpuesto1, cargo, totalconcargo, totalconpropinacargo,
    efectivo, tarjeta, vales, otros, observaciones, WorkspaceId
) VALUES (
    '', 0, GETDATE(), '100', 2, '1',
    0, 0, 0, 0, 0, 0, 2000,
    '', '01', '0000000001', 1, @CurrentShiftId,
    @CurrentStation, '1', 0, 2,
    250, 250, 250, 250,
    0, 0, 250, 250,
    0, 0, 0, 0, 'Test Payment Scenario 1', @WorkspaceId1
);
SELECT @Folio1 = SCOPE_IDENTITY();

-- 2. Add items
INSERT INTO tempcheqdet (
    foliodet, movimiento, comanda, cantidad, idproducto,
    descuento, precio, preciosinimpuestos, tiempo, hora,
    modificador, idestacion, impuesto1, impuesto2, impuesto3, WorkspaceId
) VALUES
    (@Folio1, 1, '', 1, '001', 0, 100, 100, '', GETDATE(), 0, @CurrentStation, 0, 0, 0, @WorkspaceId1),
    (@Folio1, 2, '', 1, '002', 0, 150, 150, '', GETDATE(), 0, @CurrentStation, 0, 0, 0, @WorkspaceId1);

-- 3. Print order (required for payment)
UPDATE tempcheques
SET impreso = 1, numcheque = 2000, impresiones = 1
WHERE folio = @Folio1;

PRINT '✅ Order created - Folio: ' + CAST(@Folio1 AS VARCHAR);

-- 4. Apply payment
INSERT INTO tempchequespagos (
    folio, idformadepago, importe, propina, referencia, WorkspaceId
) VALUES (
    @Folio1, 'AEF', 250, 0, 'Full cash payment test', @WorkspaceId1
);

-- 5. Mark as paid
UPDATE tempcheques
SET
    pagado = 1,
    efectivo = 250,
    usuariopago = '1'
WHERE folio = @Folio1;

COMMIT;

PRINT '✅ Payment applied - $250 cash';
PRINT '✅ Order status: PAID';

-- Verify
SELECT
    'Order' as Type,
    folio, mesa, total, pagado, efectivo,
    CASE WHEN pagado = 1 THEN 'PAID' ELSE 'UNPAID' END as Status
FROM tempcheques WHERE folio = @Folio1;

PRINT '';

-- =============================================
-- SCENARIO 2: PARTIAL PAYMENTS
-- =============================================
PRINT '========================================';
PRINT 'SCENARIO 2: Partial Payments';
PRINT '========================================';

DECLARE @Folio2 BIGINT;
DECLARE @WorkspaceId2 UNIQUEIDENTIFIER = NEWID();

BEGIN TRANSACTION;

-- 1. Create larger order
INSERT INTO tempcheques (
    seriefolio, numcheque, fecha, mesa, nopersonas, idmesero,
    pagado, cancelado, impreso, impresiones, cambio, descuento, orden,
    idcliente, idarearestaurant, idempresa, tipodeservicio, idturno,
    estacion, usuarioapertura, tipoventarapida, totalarticulos,
    subtotal, subtotalsinimpuestos, total, totalconpropina,
    totalimpuesto1, cargo, totalconcargo, totalconpropinacargo,
    efectivo, tarjeta, vales, otros, observaciones, WorkspaceId
) VALUES (
    '', 0, GETDATE(), '101', 4, '1',
    0, 0, 0, 0, 0, 0, 2001,
    '', '01', '0000000001', 1, @CurrentShiftId,
    @CurrentStation, '1', 0, 3,
    500, 500, 500, 500,
    0, 0, 500, 500,
    0, 0, 0, 0, 'Test Partial Payment Scenario', @WorkspaceId2
);
SELECT @Folio2 = SCOPE_IDENTITY();

-- 2. Add items
INSERT INTO tempcheqdet (
    foliodet, movimiento, comanda, cantidad, idproducto,
    descuento, precio, preciosinimpuestos, tiempo, hora,
    modificador, idestacion, impuesto1, impuesto2, impuesto3, WorkspaceId
) VALUES
    (@Folio2, 1, '', 2, '001', 0, 200, 200, '', GETDATE(), 0, @CurrentStation, 0, 0, 0, @WorkspaceId2),
    (@Folio2, 2, '', 1, '002', 0, 300, 300, '', GETDATE(), 0, @CurrentStation, 0, 0, 0, @WorkspaceId2);

-- 3. Print order
UPDATE tempcheques
SET impreso = 1, numcheque = 2001, impresiones = 1
WHERE folio = @Folio2;

PRINT '✅ Order created - Folio: ' + CAST(@Folio2 AS VARCHAR) + ' - Total: $500';

-- 4. First partial payment (cash)
INSERT INTO tempchequespagos (
    folio, idformadepago, importe, propina, referencia, WorkspaceId
) VALUES (
    @Folio2, 'AEF', 200, 0, 'Partial payment 1 - Cash', @WorkspaceId2
);

UPDATE tempcheques
SET
    efectivo = 200,
    observaciones = observaciones + ' | Partial: $200 cash'
WHERE folio = @Folio2;

PRINT '✅ Partial payment 1: $200 cash';

-- 5. Second partial payment (card)
INSERT INTO tempchequespagos (
    folio, idformadepago, importe, propina, referencia, WorkspaceId
) VALUES (
    @Folio2, 'CRE', 150, 0, 'Partial payment 2 - Card', @WorkspaceId2
);

UPDATE tempcheques
SET
    tarjeta = 150,
    observaciones = observaciones + ' | Partial: $150 card'
WHERE folio = @Folio2;

PRINT '✅ Partial payment 2: $150 card';

-- 6. Final payment
INSERT INTO tempchequespagos (
    folio, idformadepago, importe, propina, referencia, WorkspaceId
) VALUES (
    @Folio2, 'AEF', 150, 0, 'Final payment - Cash', @WorkspaceId2
);

UPDATE tempcheques
SET
    pagado = 1,
    efectivo = efectivo + 150,
    usuariopago = '1',
    observaciones = observaciones + ' | Final: $150 cash'
WHERE folio = @Folio2;

COMMIT;

PRINT '✅ Final payment: $150 cash';
PRINT '✅ Order status: FULLY PAID';

-- Verify payments
SELECT
    'Payments' as Type,
    idformadepago, importe, referencia
FROM tempchequespagos
WHERE folio = @Folio2;

PRINT '';

-- =============================================
-- SCENARIO 3: MIXED PAYMENT METHODS
-- =============================================
PRINT '========================================';
PRINT 'SCENARIO 3: Mixed Payment Methods';
PRINT '========================================';

DECLARE @Folio3 BIGINT;
DECLARE @WorkspaceId3 UNIQUEIDENTIFIER = NEWID();

BEGIN TRANSACTION;

-- 1. Create order
INSERT INTO tempcheques (
    seriefolio, numcheque, fecha, mesa, nopersonas, idmesero,
    pagado, cancelado, impreso, impresiones, cambio, descuento, orden,
    idcliente, idarearestaurant, idempresa, tipodeservicio, idturno,
    estacion, usuarioapertura, tipoventarapida, totalarticulos,
    subtotal, subtotalsinimpuestos, total, totalconpropina,
    totalimpuesto1, cargo, totalconcargo, totalconpropinacargo,
    efectivo, tarjeta, vales, otros, observaciones, WorkspaceId
) VALUES (
    '', 0, GETDATE(), '102', 3, '1',
    0, 0, 0, 0, 0, 0, 2002,
    '', '01', '0000000001', 1, @CurrentShiftId,
    @CurrentStation, '1', 0, 2,
    400, 400, 400, 400,
    0, 0, 400, 400,
    0, 0, 0, 0, 'Test Mixed Payment Methods', @WorkspaceId3
);
SELECT @Folio3 = SCOPE_IDENTITY();

-- 2. Add items
INSERT INTO tempcheqdet (
    foliodet, movimiento, comanda, cantidad, idproducto,
    descuento, precio, preciosinimpuestos, tiempo, hora,
    modificador, idestacion, impuesto1, impuesto2, impuesto3, WorkspaceId
) VALUES
    (@Folio3, 1, '', 2, '001', 0, 400, 400, '', GETDATE(), 0, @CurrentStation, 0, 0, 0, @WorkspaceId3);

-- 3. Print order
UPDATE tempcheques
SET impreso = 1, numcheque = 2002, impresiones = 1
WHERE folio = @Folio3;

-- 4. Apply mixed payments
-- Cash: $100
INSERT INTO tempchequespagos (
    folio, idformadepago, importe, propina, referencia, WorkspaceId
) VALUES (
    @Folio3, 'AEF', 100, 0, 'Cash portion', @WorkspaceId3
);

-- Credit Card: $200
INSERT INTO tempchequespagos (
    folio, idformadepago, importe, propina, referencia, WorkspaceId
) VALUES (
    @Folio3, 'CRE', 200, 0, 'Credit card portion', @WorkspaceId3
);

-- Debit Card: $100
INSERT INTO tempchequespagos (
    folio, idformadepago, importe, propina, referencia, WorkspaceId
) VALUES (
    @Folio3, 'DEB', 100, 0, 'Debit card portion', @WorkspaceId3
);

-- 5. Update order totals
UPDATE tempcheques
SET
    pagado = 1,
    efectivo = 100,
    tarjeta = 300,  -- Credit + Debit
    usuariopago = '1'
WHERE folio = @Folio3;

COMMIT;

PRINT '✅ Order created - Folio: ' + CAST(@Folio3 AS VARCHAR);
PRINT '✅ Payments applied:';
PRINT '   - Cash: $100';
PRINT '   - Credit: $200';
PRINT '   - Debit: $100';
PRINT '✅ Order status: PAID';
PRINT '';

-- =============================================
-- VERIFICATION QUERIES
-- =============================================
PRINT '========================================';
PRINT 'VERIFICATION RESULTS';
PRINT '========================================';

-- Check all test orders
SELECT
    tc.folio,
    tc.mesa,
    tc.total,
    tc.efectivo,
    tc.tarjeta,
    tc.vales,
    tc.otros,
    tc.pagado,
    CASE WHEN tc.pagado = 1 THEN 'PAID' ELSE 'UNPAID' END as Status,
    COUNT(tp.folio) as PaymentCount,
    SUM(tp.importe) as TotalPaid
FROM tempcheques tc
LEFT JOIN tempchequespagos tp ON tc.folio = tp.folio
WHERE tc.observaciones LIKE '%Test%Payment%'
GROUP BY tc.folio, tc.mesa, tc.total, tc.efectivo, tc.tarjeta,
         tc.vales, tc.otros, tc.pagado
ORDER BY tc.folio DESC;

-- Check tracking table
PRINT '';
PRINT 'Tracking Table Entries:';
SELECT TOP 10
    EntityId,
    EntityType,
    Operation,
    Timestamp
FROM AvoqadoTracking
WHERE EntityId IN (
    CAST(@WorkspaceId1 AS VARCHAR(50)),
    CAST(@WorkspaceId2 AS VARCHAR(50)),
    CAST(@WorkspaceId3 AS VARCHAR(50))
)
ORDER BY Timestamp DESC;

-- =============================================
-- CLEANUP (OPTIONAL - UNCOMMENT TO RUN)
-- =============================================
/*
-- Remove test data
DELETE FROM tempchequespagos WHERE folio IN (@Folio1, @Folio2, @Folio3);
DELETE FROM tempcheqdet WHERE foliodet IN (@Folio1, @Folio2, @Folio3);
DELETE FROM tempcheques WHERE folio IN (@Folio1, @Folio2, @Folio3);
PRINT 'Test data cleaned up';
*/

-- =============================================
-- USEFUL QUERIES FOR TESTING
-- =============================================
PRINT '';
PRINT '========================================';
PRINT 'USEFUL TESTING QUERIES:';
PRINT '========================================';
PRINT '';
PRINT '-- Check specific order payment status:';
PRINT 'SELECT folio, total, pagado, efectivo, tarjeta FROM tempcheques WHERE folio = [FOLIO];';
PRINT '';
PRINT '-- View all payments for an order:';
PRINT 'SELECT * FROM tempchequespagos WHERE folio = [FOLIO];';
PRINT '';
PRINT '-- Calculate remaining balance:';
PRINT 'SELECT tc.total - ISNULL(SUM(tp.importe), 0) as Remaining';
PRINT 'FROM tempcheques tc';
PRINT 'LEFT JOIN tempchequespagos tp ON tc.folio = tp.folio';
PRINT 'WHERE tc.folio = [FOLIO]';
PRINT 'GROUP BY tc.total;';
PRINT '';
PRINT '-- Test stored procedure:';
PRINT 'DECLARE @Success BIT, @Message NVARCHAR(500), @Remaining MONEY;';
PRINT 'EXEC sp_ApplyPartialPayment @Folio=[FOLIO], @PaymentAmount=100, @TipAmount=0,';
PRINT '     @PaymentMethod=''AEF'', @Reference=''Test'',';
PRINT '     @Success=@Success OUTPUT, @Message=@Message OUTPUT, @Remaining=@Remaining OUTPUT;';
PRINT 'SELECT @Success as Success, @Message as Message, @Remaining as Remaining;';