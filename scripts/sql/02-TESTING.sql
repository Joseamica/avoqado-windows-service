-- ====================================================================
-- TESTING SCRIPT - Test Avoqado Integration
-- ====================================================================

USE avov2;
GO

PRINT '======================================================================'
PRINT ' AVOQADO INTEGRATION TESTING'
PRINT '======================================================================'
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