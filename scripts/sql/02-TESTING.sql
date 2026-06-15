-- ====================================================================
-- TESTING SCRIPT - Test Avoqado Integration
-- ====================================================================
--
-- USAGE: This script will run on the CURRENT database context.
-- ====================================================================

PRINT '======================================================================'
PRINT ' AVOQADO INTEGRATION TESTING'
PRINT '======================================================================'
PRINT ''
PRINT 'Testing Database: ' + DB_NAME()
PRINT ''

-- Test 1: Test sp_GetPendingChanges
PRINT '📋 TEST 1: Checking sp_GetPendingChanges'
EXEC sp_GetPendingChanges @MaxResults = 5
PRINT ''

-- Test 2: Test entity ID generation
PRINT '📋 TEST 2: Testing Entity ID generation'
DECLARE @TestEntityId VARCHAR(200)

-- Get a real order to test with
DECLARE @TestFolio BIGINT
DECLARE @TestIdTurno BIGINT

SELECT TOP 1
    @TestFolio = folio,
    @TestIdTurno = idturno
FROM tempcheques

IF @TestFolio IS NOT NULL
BEGIN
    SET @TestEntityId = dbo.fn_GetAvoqadoEntityIdWithWorkspace('order', @TestFolio, @TestIdTurno, NULL, NULL)
    PRINT '  Order Entity ID for folio ' + CAST(@TestFolio AS VARCHAR) + ': ' + @TestEntityId
END
ELSE
    PRINT '  ⚠️ No active orders to test with'

PRINT ''

-- Test 3: Test payment methods
PRINT '📋 TEST 3: Checking payment methods'
SELECT idformadepago, descripcion, tipo, visible
FROM formasdepago
WHERE idformadepago IN ('ACASH', 'ACARD')
ORDER BY idformadepago
PRINT ''

-- Test 3.5: Test AVOTEST product
PRINT '📋 TEST 3.5: Checking AVOTEST product'
IF EXISTS (SELECT 1 FROM productos WHERE idproducto = 'AVOTEST')
BEGIN
    SELECT idproducto, descripcion, visible_menu, usarcomedor, usardomicilio, WorkspaceId
    FROM productos
    WHERE idproducto = 'AVOTEST'
    PRINT '  ✅ AVOTEST product exists and is ready for testing'
END
ELSE
    PRINT '  ⚠️ AVOTEST product not found - tests may use random products'
PRINT ''

-- Test 4: Test partial payment procedure (simulation)
PRINT '📋 TEST 4: Testing sp_ApplyPartialPayment structure'
PRINT '  Procedure exists: ' + CASE WHEN OBJECT_ID('sp_ApplyPartialPayment', 'P') IS NOT NULL THEN 'YES' ELSE 'NO' END
PRINT ''

-- Test 5: Show current orders
PRINT '📋 TEST 5: Current active orders'
SELECT
    folio,
    total,
    pagado,
    impreso,
    mesa,
    idturno
FROM tempcheques
WHERE pagado = 0
PRINT ''

-- Test 6: Show shift status
PRINT '📋 TEST 6: Current shift status'
SELECT TOP 1
    idturno,
    idturnointerno,
    apertura,
    cierre,
    CASE WHEN cierre IS NULL THEN 'OPEN' ELSE 'CLOSED' END as Status
FROM turnos
ORDER BY idturno DESC
PRINT ''

-- Test 7: Check trigger status
PRINT '📋 TEST 7: Trigger status'
SELECT
    name,
    is_disabled,
    CASE WHEN is_disabled = 0 THEN 'ENABLED' ELSE 'DISABLED' END as Status
FROM sys.triggers
WHERE name LIKE 'Trg_Avoqado%'
ORDER BY name
PRINT ''

PRINT '======================================================================'
PRINT ' TESTING COMPLETE'
PRINT '======================================================================'
PRINT ''
PRINT 'Next steps to test partial payments:'
PRINT '1. Create a test order with AVOTEST product ($777)'
PRINT '2. Apply $10 partial payment via Avoqado:'
PRINT '   - Should adjust item quantity to 0.9871 (ratio: 767/777)'
PRINT '   - Order total should update to $767'
PRINT '   - Payment record should show $10 in tempchequespagos with unique WorkspaceId'
PRINT '3. Pay remaining $767 from POS'
PRINT '   - Both payments should coexist (each with unique WorkspaceId)'
PRINT '4. Close shift and check report:'
PRINT '   - ACASH payment: $10.00'
PRINT '   - Other payment: $767.00'
PRINT '   - Total: $777.00'
PRINT ''
PRINT '💡 Quantity adjustment works like SoftRestaurant native split bill'
PRINT '   - Each payment gets unique WorkspaceId (SoftRestaurant native behavior)'
PRINT '   - Multiple payments coexist and all get archived during shift close'
PRINT ''

-- ====================================================================
-- TEST 8: REGRESSION — C-1 (partial-payment balance drift) + H-7 (idempotency)
-- ====================================================================
-- The SP inserts into AvoqadoTracking, which carries a filtered index, so the
-- session MUST run with SET QUOTED_IDENTIFIER ON or the INSERT fails (error 1934).
SET QUOTED_IDENTIFIER ON;
GO

PRINT '======================================================================'
PRINT ' 📋 TEST 8: REGRESSION — sp_ApplyPartialPayment (C-1 + H-7)'
PRINT '======================================================================'
PRINT ''
PRINT 'C-1: two $7 partials on a $75 order must leave a running total of $61'
PRINT '     (the OLD bug double-counted prior payments → $54).'
PRINT 'H-7: re-applying the SAME @Reference must NOT insert a second payment row.'
PRINT ''

BEGIN TRY
    -- Self-contained, idempotent setup: drop any leftover from a prior run first.
    DECLARE @TestMesa VARCHAR(20) = 'AVOC1TEST'
    DECLARE @PriorFolio BIGINT

    -- Clean up any stale test order(s) from a previous failed run
    DECLARE cur_prior CURSOR LOCAL FAST_FORWARD FOR
        SELECT folio FROM tempcheques WHERE mesa = @TestMesa
    OPEN cur_prior
    FETCH NEXT FROM cur_prior INTO @PriorFolio
    WHILE @@FETCH_STATUS = 0
    BEGIN
        DELETE FROM tempchequespagos WHERE folio = @PriorFolio
        DELETE FROM tempcheqdet WHERE foliodet = @PriorFolio
        DELETE FROM tempcheques WHERE folio = @PriorFolio
        DELETE FROM AvoqadoTracking WHERE EntityId LIKE '%:' + CAST(@PriorFolio AS VARCHAR) + ':%'
                                       OR EntityId LIKE '%:' + CAST(@PriorFolio AS VARCHAR)
        DELETE FROM AvoqadoDebugLog WHERE Folio = @PriorFolio
        FETCH NEXT FROM cur_prior INTO @PriorFolio
    END
    CLOSE cur_prior
    DEALLOCATE cur_prior

    -- Resolve an open shift (idturno) if one exists; otherwise 0 (SP assigns it,
    -- but with no open shift the SP refuses payment — note that in the output).
    DECLARE @OpenShift BIGINT = (SELECT TOP 1 idturno FROM turnos WHERE cierre IS NULL ORDER BY idturno DESC)
    DECLARE @TestIdTurno BIGINT = ISNULL(@OpenShift, 0)
    IF @OpenShift IS NULL
        PRINT '  ⚠️ No open shift found — SP requires one when idturno=0. Test may abort with "No open shift".'

    -- Build a $75.00 test order (subtotal 64.66 + tax 10.34). folio is IDENTITY.
    DECLARE @TestWs UNIQUEIDENTIFIER = NEWID()
    INSERT INTO tempcheques (
        mesa, nopersonas, idmesero, fecha, orden, pagado, cancelado, impreso,
        idarearestaurant, idempresa, tipodeservicio, idturno,
        estacion, Usuarioapertura, desc_porc_original, WorkspaceId,
        total, subtotal, totalimpuesto1, totalarticulos
    ) VALUES (
        @TestMesa, 1, '', GETDATE(), 0, 0, 0, 0,
        '01', '1', 1, @TestIdTurno,
        'AVOQADO_SYNC', 'AVOQADO', 0, @TestWs,
        75.00, 64.66, 10.34, 1
    )

    DECLARE @Folio BIGINT = (SELECT folio FROM tempcheques WHERE WorkspaceId = @TestWs)
    PRINT '  Created test order folio ' + CAST(@Folio AS VARCHAR) + ' (mesa ' + @TestMesa + ', total $75.00)'

    -- One line item totaling $75.00 (precio is unitario in SoftRestaurant)
    INSERT INTO tempcheqdet (foliodet, movimiento, idproducto, cantidad, precio, preciosinimpuestos, hora, idestacion, impuesto1, idmeseroproducto, comentario)
    VALUES (@Folio, 1, ISNULL((SELECT TOP 1 idproducto FROM productos WHERE idproducto = 'AVOTEST'), (SELECT TOP 1 idproducto FROM productos)), 1, 75.00, 64.66, GETDATE(), 'AVOQADO_SYNC', 16.00, '', '')

    -- ---- Apply two $7 partial payments with distinct references ----
    DECLARE @Success BIT, @Remaining MONEY
    DECLARE @Message NVARCHAR(500)

    EXEC sp_ApplyPartialPayment
        @Folio = @Folio, @PaymentAmount = 7, @TipAmount = 0, @PaymentMethod = 'ACASH',
        @Reference = 'C1REGR-1', @Success = @Success OUTPUT, @Message = @Message OUTPUT, @Remaining = @Remaining OUTPUT
    PRINT '  Partial #1 ($7, ref C1REGR-1): ' + ISNULL(@Message, '(null)') + ' [Remaining=' + CAST(ISNULL(@Remaining, 0) AS VARCHAR) + ']'

    EXEC sp_ApplyPartialPayment
        @Folio = @Folio, @PaymentAmount = 7, @TipAmount = 0, @PaymentMethod = 'ACASH',
        @Reference = 'C1REGR-2', @Success = @Success OUTPUT, @Message = @Message OUTPUT, @Remaining = @Remaining OUTPUT
    PRINT '  Partial #2 ($7, ref C1REGR-2): ' + ISNULL(@Message, '(null)') + ' [Remaining=' + CAST(ISNULL(@Remaining, 0) AS VARCHAR) + ']'

    -- ---- C-1 assertions ----
    DECLARE @RunningTotal MONEY = (SELECT total FROM tempcheques WHERE folio = @Folio)
    DECLARE @SumPaid MONEY = (SELECT ISNULL(SUM(importe), 0) FROM tempchequespagos WHERE folio = @Folio)
    DECLARE @ComputedRemaining MONEY = 75.00 - @SumPaid

    PRINT ''
    PRINT '  After 2x $7 on $75:'
    PRINT '    tempcheques.total      = ' + CAST(@RunningTotal AS VARCHAR) + '  (expected 61.00)'
    PRINT '    SUM(importe)           = ' + CAST(@SumPaid AS VARCHAR) + '  (expected 14.00)'
    PRINT '    75.00 - SUM(importe)   = ' + CAST(@ComputedRemaining AS VARCHAR) + '  (expected 61.00)'

    IF @RunningTotal = 61.00 AND @ComputedRemaining = 61.00
        PRINT '    ✅ C-1 PASS: running balance is $61.00 (no double-counting)'
    ELSE IF @RunningTotal = 54.00
        PRINT '    ❌ C-1 FAIL: total=$54.00 — the OLD double-counting bug is back!'
    ELSE
        PRINT '    ❌ C-1 FAIL: unexpected total=' + CAST(@RunningTotal AS VARCHAR) + ' / computed=' + CAST(@ComputedRemaining AS VARCHAR)

    -- ---- H-7 idempotency assertion: re-apply ref C1REGR-1 ----
    DECLARE @CountBefore INT = (SELECT COUNT(*) FROM tempchequespagos WHERE folio = @Folio)

    EXEC sp_ApplyPartialPayment
        @Folio = @Folio, @PaymentAmount = 7, @TipAmount = 0, @PaymentMethod = 'ACASH',
        @Reference = 'C1REGR-1', @Success = @Success OUTPUT, @Message = @Message OUTPUT, @Remaining = @Remaining OUTPUT
    PRINT ''
    PRINT '  Re-apply ref C1REGR-1 (idempotency): ' + ISNULL(@Message, '(null)')

    DECLARE @CountAfter INT = (SELECT COUNT(*) FROM tempchequespagos WHERE folio = @Folio)
    PRINT '    Payment rows before re-apply = ' + CAST(@CountBefore AS VARCHAR) + ', after = ' + CAST(@CountAfter AS VARCHAR)
    IF @CountAfter = @CountBefore
        PRINT '    ✅ H-7 PASS: duplicate @Reference did not insert a second payment'
    ELSE
        PRINT '    ❌ H-7 FAIL: duplicate @Reference inserted a phantom payment'

    -- ---- CLEAN UP the test order and the rows it generated ----
    DELETE FROM tempchequespagos WHERE folio = @Folio
    DELETE FROM tempcheqdet WHERE foliodet = @Folio
    DELETE FROM AvoqadoTracking WHERE EntityId LIKE '%:' + CAST(@Folio AS VARCHAR) + ':%'
                                   OR EntityId LIKE '%:' + CAST(@Folio AS VARCHAR)
                                   OR EntityId = CAST(@TestWs AS VARCHAR(36))
    DELETE FROM AvoqadoDebugLog WHERE Folio = @Folio
    DELETE FROM tempcheques WHERE folio = @Folio
    PRINT ''
    PRINT '  🧹 Cleaned up test order folio ' + CAST(@Folio AS VARCHAR) + ' (tempcheques/tempcheqdet/tempchequespagos/AvoqadoTracking/AvoqadoDebugLog)'
END TRY
BEGIN CATCH
    PRINT '  ❌ TEST 8 ERROR: ' + ERROR_MESSAGE()
    -- Best-effort cleanup on failure
    DECLARE @CleanFolio BIGINT
    DECLARE cur_clean CURSOR LOCAL FAST_FORWARD FOR
        SELECT folio FROM tempcheques WHERE mesa = 'AVOC1TEST'
    OPEN cur_clean
    FETCH NEXT FROM cur_clean INTO @CleanFolio
    WHILE @@FETCH_STATUS = 0
    BEGIN
        DELETE FROM tempchequespagos WHERE folio = @CleanFolio
        DELETE FROM tempcheqdet WHERE foliodet = @CleanFolio
        DELETE FROM AvoqadoDebugLog WHERE Folio = @CleanFolio
        DELETE FROM tempcheques WHERE folio = @CleanFolio
        FETCH NEXT FROM cur_clean INTO @CleanFolio
    END
    CLOSE cur_clean
    DEALLOCATE cur_clean
END CATCH
PRINT ''