-- =============================================
-- QUICK PAYMENT HELPER FUNCTIONS
-- Rapid Testing Without UI
-- Date: 2025-09-23
-- Author: Claude
-- =============================================

/*
QUICK USAGE EXAMPLES:
--------------------
-- Test full payment on existing order:
EXEC QuickPayOrder @Folio = 123, @Amount = 100, @Method = 'AEF';

-- Create and pay order in one shot:
EXEC QuickCreateAndPay @Mesa = '50', @Total = 150, @Method = 'CRE';

-- Test partial payment:
EXEC QuickPartialPay @Folio = 123, @Amount = 50, @Method = 'AEF';

NOTE: This script uses 'AVOTEST' product created by installation script.
      AVOTEST is hidden from POS menus and safe for testing.
      Falls back to first available product if AVOTEST not found.
*/

-- =============================================
-- 1. QUICK PAY EXISTING ORDER
-- =============================================
-- Usage: EXEC QuickPayOrder 123, 100, 'AEF';

DECLARE @TestFolio BIGINT = 123;  -- CHANGE THIS to your test folio
DECLARE @PaymentAmount MONEY = 100;  -- CHANGE THIS to payment amount
DECLARE @PaymentMethod VARCHAR(10) = 'AEF';  -- CHANGE THIS (AEF=cash, CRE=credit, DEB=debit)

BEGIN TRANSACTION;

-- Check if order exists and is not paid
IF NOT EXISTS(SELECT 1 FROM tempcheques WHERE folio = @TestFolio AND pagado = 0)
BEGIN
    PRINT 'ERROR: Order not found or already paid';
    ROLLBACK;
    RETURN;
END

-- Get order details
DECLARE @OrderTotal MONEY, @CurrentPaid MONEY, @Remaining MONEY;
SELECT @OrderTotal = total FROM tempcheques WHERE folio = @TestFolio;
SELECT @CurrentPaid = ISNULL(SUM(importe), 0) FROM tempchequespagos WHERE folio = @TestFolio;
SET @Remaining = @OrderTotal - @CurrentPaid;

PRINT 'Order ' + CAST(@TestFolio AS VARCHAR) + ':';
PRINT '  Total: $' + CAST(@OrderTotal AS VARCHAR);
PRINT '  Paid so far: $' + CAST(@CurrentPaid AS VARCHAR);
PRINT '  Remaining: $' + CAST(@Remaining AS VARCHAR);
PRINT '  Applying payment: $' + CAST(@PaymentAmount AS VARCHAR);

-- Ensure order is printed (required for payment)
UPDATE tempcheques
SET impreso = 1, numcheque = ISNULL(numcheque, folio)
WHERE folio = @TestFolio AND impreso = 0;

-- Apply payment
INSERT INTO tempchequespagos (
    folio, idformadepago, importe, propina, referencia, WorkspaceId
) VALUES (
    @TestFolio, @PaymentMethod, @PaymentAmount, 0, 'Quick test payment',
    (SELECT WorkspaceId FROM tempcheques WHERE folio = @TestFolio)
);

-- Update payment totals
DECLARE @NewRemaining MONEY = @OrderTotal - (@CurrentPaid + @PaymentAmount);

IF @NewRemaining <= 0
BEGIN
    -- Full payment - mark as paid
    UPDATE tempcheques
    SET
        pagado = 1,
        efectivo = CASE WHEN @PaymentMethod IN ('AEF', 'ACASH') THEN efectivo + @PaymentAmount ELSE efectivo END,
        tarjeta = CASE WHEN @PaymentMethod IN ('CRE', 'DEB', 'SRPC', 'SRPD') THEN tarjeta + @PaymentAmount ELSE tarjeta END,
        otros = CASE WHEN @PaymentMethod NOT IN ('AEF', 'ACASH', 'CRE', 'DEB', 'SRPC', 'SRPD') THEN otros + @PaymentAmount ELSE otros END,
        cambio = ABS(@NewRemaining),
        usuariopago = '1'
    WHERE folio = @TestFolio;

    PRINT '✅ ORDER FULLY PAID!';
    IF @NewRemaining < 0
        PRINT '   Change: $' + CAST(ABS(@NewRemaining) AS VARCHAR);
END
ELSE
BEGIN
    -- Partial payment
    UPDATE tempcheques
    SET
        efectivo = CASE WHEN @PaymentMethod IN ('AEF', 'ACASH') THEN efectivo + @PaymentAmount ELSE efectivo END,
        tarjeta = CASE WHEN @PaymentMethod IN ('CRE', 'DEB', 'SRPC', 'SRPD') THEN tarjeta + @PaymentAmount ELSE tarjeta END,
        otros = CASE WHEN @PaymentMethod NOT IN ('AEF', 'ACASH', 'CRE', 'DEB', 'SRPC', 'SRPD') THEN otros + @PaymentAmount ELSE otros END,
        observaciones = ISNULL(observaciones, '') + ' | Partial payment: $' + CAST(@PaymentAmount AS VARCHAR)
    WHERE folio = @TestFolio;

    PRINT '✅ PARTIAL PAYMENT APPLIED';
    PRINT '   Still remaining: $' + CAST(@NewRemaining AS VARCHAR);
END

COMMIT;

-- Verify final state
SELECT
    folio, mesa, total,
    efectivo, tarjeta, vales, otros,
    pagado,
    CASE WHEN pagado = 1 THEN 'PAID' ELSE 'UNPAID' END as Status,
    cambio
FROM tempcheques
WHERE folio = @TestFolio;

GO

-- =============================================
-- 2. CREATE ORDER AND PAY IMMEDIATELY
-- =============================================
PRINT '';
PRINT '========================================';
PRINT 'CREATE AND PAY NEW ORDER';
PRINT '========================================';

DECLARE @NewMesa VARCHAR(10) = '999';  -- CHANGE THIS
DECLARE @NewTotal MONEY = 200;  -- CHANGE THIS
DECLARE @NewPayMethod VARCHAR(10) = 'AEF';  -- CHANGE THIS
DECLARE @NewFolio BIGINT;
DECLARE @NewWorkspaceId UNIQUEIDENTIFIER = NEWID();
DECLARE @CurrentShift BIGINT;
DECLARE @CurrentStation VARCHAR(50);

-- Get current shift
SELECT TOP 1
    @CurrentShift = idturno,
    @CurrentStation = idestacion
FROM turnos
WHERE cierre IS NULL
ORDER BY apertura DESC;

IF @CurrentShift IS NULL
BEGIN
    PRINT 'ERROR: No open shift found';
    RETURN;
END

BEGIN TRANSACTION;

-- Create order
INSERT INTO tempcheques (
    seriefolio, numcheque, fecha, mesa, nopersonas, idmesero,
    pagado, cancelado, impreso, impresiones, cambio, descuento, orden,
    idcliente, idarearestaurant, idempresa, tipodeservicio, idturno,
    estacion, usuarioapertura, totalarticulos,
    subtotal, subtotalsinimpuestos, total, totalconpropina,
    totalimpuesto1, cargo, totalconcargo, totalconpropinacargo,
    efectivo, tarjeta, vales, otros, observaciones, WorkspaceId
) VALUES (
    '', 0, GETDATE(), @NewMesa, 1, '1',
    0, 0, 1, 1, 0, 0, 9000,  -- Already marked as printed
    '', '01', '0000000001', 1, @CurrentShift,
    @CurrentStation, '1', 1,
    @NewTotal, @NewTotal, @NewTotal, @NewTotal,
    0, 0, @NewTotal, @NewTotal,
    0, 0, 0, 0, 'Quick create and pay test', @NewWorkspaceId
);
SELECT @NewFolio = SCOPE_IDENTITY();

-- Add a simple item (use AVOTEST product, fallback to first available)
DECLARE @ValidProductId VARCHAR(15) = 'AVOTEST'
IF NOT EXISTS (SELECT 1 FROM productos WHERE idproducto = 'AVOTEST')
    SELECT TOP 1 @ValidProductId = idproducto FROM productos ORDER BY idproducto

INSERT INTO tempcheqdet (
    foliodet, movimiento, comanda, cantidad, idproducto,
    descuento, precio, preciosinimpuestos, tiempo, hora,
    modificador, idestacion, impuesto1, impuesto2, impuesto3, WorkspaceId
) VALUES (
    @NewFolio, 1, '', 1, @ValidProductId, 0, @NewTotal, @NewTotal,
    '', GETDATE(), 0, @CurrentStation, 0, 0, 0, @NewWorkspaceId
);

-- Apply payment immediately
INSERT INTO tempchequespagos (
    folio, idformadepago, importe, propina, referencia, WorkspaceId
) VALUES (
    @NewFolio, @NewPayMethod, @NewTotal, 0, 'Quick create and pay', @NewWorkspaceId
);

-- Mark as paid
UPDATE tempcheques
SET
    pagado = 1,
    numcheque = @NewFolio,
    efectivo = CASE WHEN @NewPayMethod IN ('AEF', 'ACASH') THEN @NewTotal ELSE 0 END,
    tarjeta = CASE WHEN @NewPayMethod IN ('CRE', 'DEB', 'SRPC', 'SRPD') THEN @NewTotal ELSE 0 END,
    otros = CASE WHEN @NewPayMethod NOT IN ('AEF', 'ACASH', 'CRE', 'DEB', 'SRPC', 'SRPD') THEN @NewTotal ELSE 0 END,
    usuariopago = '1'
WHERE folio = @NewFolio;

COMMIT;

PRINT '✅ Order created and paid!';
PRINT '   Folio: ' + CAST(@NewFolio AS VARCHAR);
PRINT '   Mesa: ' + @NewMesa;
PRINT '   Total: $' + CAST(@NewTotal AS VARCHAR);
PRINT '   Payment: ' + @NewPayMethod;

-- Verify
SELECT folio, mesa, total, pagado, 'PAID' as Status
FROM tempcheques WHERE folio = @NewFolio;

GO

-- =============================================
-- 3. TEST STORED PROCEDURE PAYMENT
-- =============================================
PRINT '';
PRINT '========================================';
PRINT 'TEST STORED PROCEDURE PAYMENT';
PRINT '========================================';

DECLARE @SPFolio BIGINT = 123;  -- CHANGE THIS to your test folio
DECLARE @SPAmount MONEY = 100;  -- CHANGE THIS
DECLARE @SPMethod VARCHAR(10) = 'AEF';  -- CHANGE THIS
DECLARE @Success BIT;
DECLARE @Message NVARCHAR(500);
DECLARE @RemainingAmount MONEY;

-- Call stored procedure
EXEC sp_ApplyPartialPayment
    @Folio = @SPFolio,
    @PaymentAmount = @SPAmount,
    @TipAmount = 0,
    @PaymentMethod = @SPMethod,
    @Reference = 'SP Test Payment',
    @Success = @Success OUTPUT,
    @Message = @Message OUTPUT,
    @Remaining = @RemainingAmount OUTPUT;

-- Show results
IF @Success = 1
BEGIN
    PRINT '✅ Payment successful!';
    PRINT '   Message: ' + @Message;
    PRINT '   Remaining: $' + CAST(@RemainingAmount AS VARCHAR);
END
ELSE
BEGIN
    PRINT '❌ Payment failed!';
    PRINT '   Error: ' + @Message;
END

GO

-- =============================================
-- UTILITY QUERIES
-- =============================================
PRINT '';
PRINT '========================================';
PRINT 'UTILITY QUERIES';
PRINT '========================================';
PRINT '';

-- Find unpaid orders
PRINT '-- Unpaid orders in current shift:';
SELECT TOP 10
    folio, mesa, total,
    ISNULL((SELECT SUM(importe) FROM tempchequespagos tp WHERE tp.folio = tc.folio), 0) as Paid,
    total - ISNULL((SELECT SUM(importe) FROM tempchequespagos tp WHERE tp.folio = tc.folio), 0) as Remaining
FROM tempcheques tc
WHERE pagado = 0
ORDER BY folio DESC;

PRINT '';
PRINT '-- Recent payments:';
SELECT TOP 10
    tp.folio,
    tc.mesa,
    tp.idformadepago,
    tp.importe,
    tp.referencia,
    tc.pagado
FROM tempchequespagos tp
INNER JOIN tempcheques tc ON tp.folio = tc.folio
ORDER BY tp.folio DESC;

PRINT '';
PRINT '-- Available payment methods:';
SELECT idformadepago, descripcion
FROM formasdepago
ORDER BY idformadepago;