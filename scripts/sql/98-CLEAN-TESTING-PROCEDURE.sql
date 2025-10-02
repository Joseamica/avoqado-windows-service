-- ====================================================================
-- CLEAN TESTING PROCEDURE - Step-by-Step Avoqado Payment Test
-- ====================================================================
--
-- PURPOSE: This script provides a complete testing procedure for
--          Avoqado payment integration with clean data.
--
-- USAGE: Follow the steps in order, executing each section separately.
-- ====================================================================

PRINT '======================================================================'
PRINT ' CLEAN TESTING PROCEDURE - Avoqado Payment Integration'
PRINT '======================================================================'
PRINT ''
PRINT 'Database: ' + DB_NAME()
PRINT 'Timestamp: ' + CONVERT(VARCHAR, GETDATE(), 120)
PRINT ''

-- =====================================================
-- STEP 0: CLEAN SLATE (Optional - use if needed)
-- =====================================================
PRINT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
PRINT 'STEP 0: CLEAN SLATE (Optional)'
PRINT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
PRINT ''
PRINT '⚠️  WARNING: This will DELETE ALL active orders and payments!'
PRINT '⚠️  Only run this in TEST environment!'
PRINT ''
PRINT '-- To clean all temp tables, uncomment and run:'
PRINT '/*'
PRINT 'DELETE FROM tempcheqdet'
PRINT 'DELETE FROM tempchequespagos'
PRINT 'DELETE FROM tempcheques'
PRINT 'PRINT ''✅ All temp tables cleaned'''
PRINT '*/'
PRINT ''

-- =====================================================
-- STEP 1: VERIFY INSTALLATION
-- =====================================================
PRINT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
PRINT 'STEP 1: VERIFY INSTALLATION'
PRINT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
PRINT ''

-- Check payment methods
IF EXISTS (SELECT 1 FROM formasdepago WHERE idformadepago = 'ACASH')
    PRINT '✅ ACASH payment method exists'
ELSE
    PRINT '❌ ACASH payment method missing - run 01-COMPLETE-INSTALL.sql'

IF EXISTS (SELECT 1 FROM formasdepago WHERE idformadepago = 'ACARD')
    PRINT '✅ ACARD payment method exists'
ELSE
    PRINT '❌ ACARD payment method missing - run 01-COMPLETE-INSTALL.sql'

-- Check stored procedure
IF OBJECT_ID('sp_ApplyPartialPayment', 'P') IS NOT NULL
    PRINT '✅ sp_ApplyPartialPayment exists'
ELSE
    PRINT '❌ sp_ApplyPartialPayment missing - run 01-COMPLETE-INSTALL.sql'

-- Check debug table
IF OBJECT_ID('AvoqadoDebugLog', 'U') IS NOT NULL
    PRINT '✅ AvoqadoDebugLog table exists'
ELSE
    PRINT '❌ AvoqadoDebugLog missing - run 01-COMPLETE-INSTALL.sql'

PRINT ''

-- =====================================================
-- STEP 2: CREATE TEST ORDER (From POS)
-- =====================================================
PRINT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
PRINT 'STEP 2: CREATE TEST ORDER FROM POS'
PRINT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
PRINT ''
PRINT '👉 ACTION REQUIRED: From SoftRestaurant POS:'
PRINT '   1. Open a shift (if not already open)'
PRINT '   2. Create a new order'
PRINT '   3. Add products totaling at least $100'
PRINT '   4. Print the bill (impreso=1) but DO NOT pay yet'
PRINT ''
PRINT '⏸️  Press Enter when order is created and printed...'
PRINT ''

-- Show current orders
PRINT '📋 Current Active Orders:'
SELECT
    folio,
    idturno,
    total,
    pagado,
    impreso,
    cancelado,
    mesa,
    LEFT(CAST(WorkspaceId AS VARCHAR(36)), 36) as WorkspaceId
FROM tempcheques
WHERE pagado = 0
ORDER BY folio DESC

IF @@ROWCOUNT = 0
BEGIN
    PRINT ''
    PRINT '⚠️  No active orders found!'
    PRINT '   Please create an order from the POS first.'
END

PRINT ''

-- =====================================================
-- STEP 3: APPLY AVOQADO PARTIAL PAYMENT
-- =====================================================
PRINT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
PRINT 'STEP 3: APPLY AVOQADO PARTIAL PAYMENT'
PRINT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
PRINT ''
PRINT '👉 ACTION REQUIRED: Send payment command via RabbitMQ:'
PRINT '   - Use Avoqado mobile app or backend to send payment'
PRINT '   - Amount should be LESS than order total (e.g., $50 on $100 order)'
PRINT '   - This will trigger sp_ApplyPartialPayment via Windows Service'
PRINT ''
PRINT '⏸️  Press Enter after sending payment command...'
PRINT ''

-- Show payments after Avoqado payment
PRINT '📋 Current Payments:'
SELECT
    p.folio,
    p.idformadepago,
    f.descripcion as PaymentMethod,
    p.importe,
    p.propina,
    p.importe + p.propina as Total,
    p.referencia,
    LEFT(CAST(p.WorkspaceId AS VARCHAR(36)), 36) as PaymentWorkspaceId
FROM tempchequespagos p
INNER JOIN formasdepago f ON p.idformadepago = f.idformadepago
ORDER BY p.folio, p.idformadepago

IF @@ROWCOUNT = 0
BEGIN
    PRINT ''
    PRINT '⚠️  No payments found yet!'
    PRINT '   Payment may have failed or not been processed yet.'
    PRINT '   Check Windows Service logs for errors.'
END

PRINT ''

-- Show debug log
PRINT '📋 Debug Log (sp_ApplyPartialPayment execution):'
SELECT TOP 5
    Folio,
    PaymentAmount,
    Message,
    Timestamp
FROM AvoqadoDebugLog
ORDER BY Timestamp DESC

IF @@ROWCOUNT = 0
    PRINT '⚠️  No debug log entries - payment may not have been processed'

PRINT ''

-- =====================================================
-- STEP 4: VERIFY PARTIAL PAYMENT STATE
-- =====================================================
PRINT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
PRINT 'STEP 4: VERIFY PARTIAL PAYMENT STATE'
PRINT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
PRINT ''

SELECT
    t.folio,
    t.total as OrderTotal,
    ISNULL(SUM(p.importe + p.propina), 0) as PaidAmount,
    t.total - ISNULL(SUM(p.importe + p.propina), 0) as Remaining,
    CASE
        WHEN t.pagado = 1 THEN '✅ FULLY PAID'
        WHEN t.impreso = 1 AND ISNULL(SUM(p.importe + p.propina), 0) > 0 THEN '⏳ PARTIALLY PAID'
        WHEN t.impreso = 1 THEN '🖨️  PRINTED (No Payments)'
        ELSE '📝 OPEN'
    END as Status
FROM tempcheques t
LEFT JOIN tempchequespagos p ON t.folio = p.folio
WHERE t.pagado = 0
GROUP BY t.folio, t.total, t.pagado, t.impreso
ORDER BY t.folio DESC

PRINT ''
PRINT '✅ Expected Result:'
PRINT '   - Order should show as PARTIALLY PAID'
PRINT '   - Remaining should be positive (Total - PaidAmount)'
PRINT '   - Order should NOT be marked as pagado=1 yet'
PRINT ''

-- =====================================================
-- STEP 5: COMPLETE PAYMENT FROM POS
-- =====================================================
PRINT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
PRINT 'STEP 5: COMPLETE PAYMENT FROM POS'
PRINT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
PRINT ''
PRINT '👉 ACTION REQUIRED: From SoftRestaurant POS:'
PRINT '   1. Open the payment screen for the order'
PRINT '   2. POS should show the remaining amount (not full amount)'
PRINT '   3. Complete payment for remaining amount using any method (cash, card, etc.)'
PRINT '   4. Order should be marked as paid'
PRINT ''
PRINT '⏸️  Press Enter after completing payment from POS...'
PRINT ''

-- Show final payment state
PRINT '📋 Final Payment Summary:'
SELECT
    p.folio,
    p.idformadepago,
    f.descripcion as PaymentMethod,
    p.importe + p.propina as Amount,
    CASE
        WHEN p.idformadepago IN ('ACASH', 'ACARD') THEN '🟢 AVOQADO'
        ELSE '🔵 POS'
    END as Source
FROM tempchequespagos p
INNER JOIN formasdepago f ON p.idformadepago = f.idformadepago
ORDER BY p.folio, p.idformadepago

PRINT ''

-- Show order final state
PRINT '📋 Order Final State:'
SELECT
    t.folio,
    t.total as OrderTotal,
    ISNULL(SUM(p.importe + p.propina), 0) as TotalPaid,
    t.total - ISNULL(SUM(p.importe + p.propina), 0) as Remaining,
    CASE WHEN t.pagado = 1 THEN '✅ PAID' ELSE '❌ NOT PAID' END as Status
FROM tempcheques t
LEFT JOIN tempchequespagos p ON t.folio = p.folio
GROUP BY t.folio, t.total, t.pagado
ORDER BY t.folio DESC

PRINT ''
PRINT '✅ Expected Result:'
PRINT '   - Order should be marked as PAID (pagado=1)'
PRINT '   - Total payments should equal order total'
PRINT '   - Should see both Avoqado payment(s) AND POS payment(s)'
PRINT ''

-- =====================================================
-- STEP 6: PRE-SHIFT-CLOSE DIAGNOSTIC
-- =====================================================
PRINT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
PRINT 'STEP 6: PRE-SHIFT-CLOSE DIAGNOSTIC'
PRINT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
PRINT ''
PRINT '👉 ACTION: Run 99-SHIFT-CLOSE-DIAGNOSTIC.sql NOW'
PRINT '   This will capture the current state before shift close'
PRINT ''

-- =====================================================
-- STEP 7: CLOSE SHIFT FROM POS
-- =====================================================
PRINT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
PRINT 'STEP 7: CLOSE SHIFT FROM POS'
PRINT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
PRINT ''
PRINT '👉 ACTION REQUIRED: From SoftRestaurant POS:'
PRINT '   1. Close the shift'
PRINT '   2. View the shift report'
PRINT '   3. Verify if Avoqado payments appear in the report'
PRINT ''
PRINT '⏸️  Press Enter after shift is closed...'
PRINT ''

-- =====================================================
-- STEP 8: POST-SHIFT-CLOSE VERIFICATION
-- =====================================================
PRINT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
PRINT 'STEP 8: POST-SHIFT-CLOSE VERIFICATION'
PRINT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
PRINT ''
PRINT '👉 ACTION: Run 99-SHIFT-CLOSE-DIAGNOSTIC.sql AGAIN'
PRINT '   Compare Section 7 (Historical Data) with pre-close data'
PRINT ''

-- Check if data was archived
PRINT '📋 Quick Verification - Archived Payments (last hour):'
SELECT
    p.folio,
    f.idformadepago,
    f.descripcion as PaymentMethod,
    p.importe + p.propina as Amount,
    c.fecha,
    CASE
        WHEN f.idformadepago IN ('ACASH', 'ACARD') THEN '🟢 AVOQADO'
        ELSE '🔵 POS'
    END as Source
FROM chequespagos p
INNER JOIN formasdepago f ON p.idformadepago = f.idformadepago
INNER JOIN cheques c ON p.folio = c.folio
WHERE c.fecha >= DATEADD(HOUR, -1, GETDATE())
ORDER BY c.fecha DESC, p.folio, p.idformadepago

IF @@ROWCOUNT = 0
BEGIN
    PRINT ''
    PRINT '⚠️  No archived payments found in last hour!'
    PRINT '   This could indicate an archiving problem.'
END
ELSE
BEGIN
    PRINT ''
    PRINT '✅ Payments were archived successfully'
    PRINT ''
    PRINT '📊 Payment Summary (last hour):'
    SELECT
        f.descripcion as PaymentMethod,
        COUNT(*) as Count,
        SUM(p.importe + p.propina) as Total,
        CASE
            WHEN f.idformadepago IN ('ACASH', 'ACARD') THEN '🟢 AVOQADO'
            ELSE '🔵 POS'
        END as Source
    FROM chequespagos p
    INNER JOIN formasdepago f ON p.idformadepago = f.idformadepago
    INNER JOIN cheques c ON p.folio = c.folio
    WHERE c.fecha >= DATEADD(HOUR, -1, GETDATE())
    GROUP BY f.idformadepago, f.descripcion
    ORDER BY SUM(p.importe + p.propina) DESC
END

PRINT ''

-- =====================================================
-- STEP 9: TROUBLESHOOTING
-- =====================================================
PRINT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
PRINT 'STEP 9: TROUBLESHOOTING'
PRINT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
PRINT ''
PRINT '🔍 IF AVOQADO PAYMENTS ARE MISSING FROM SHIFT REPORT:'
PRINT ''
PRINT '   Possible Causes:'
PRINT '   1. Report filters by WorkspaceId (excluding Avoqado payments with different WorkspaceId)'
PRINT '   2. Report queries formasdepago table with incorrect filters'
PRINT '   3. Report doesn''t recognize ACASH/ACARD as valid payment methods'
PRINT ''
PRINT '   Solutions:'
PRINT '   A. Verify shift report query uses: INNER JOIN chequespagos ON folio'
PRINT '      (NOT: INNER JOIN chequespagos ON WorkspaceId)'
PRINT ''
PRINT '   B. Check if report has payment method filter excluding ACASH/ACARD'
PRINT ''
PRINT '   C. Verify formasdepago.visible = 1 for ACASH and ACARD'
SELECT
    idformadepago,
    descripcion,
    visible,
    CASE WHEN visible = 1 THEN '✅ VISIBLE' ELSE '❌ HIDDEN' END as Status
FROM formasdepago
WHERE idformadepago IN ('ACASH', 'ACARD')

PRINT ''
PRINT '   D. Check if Avoqado payments were actually archived:'
PRINT '      Run: SELECT * FROM chequespagos WHERE idformadepago IN (''ACASH'', ''ACARD'')'
PRINT ''

PRINT '======================================================================'
PRINT ' TESTING PROCEDURE COMPLETE'
PRINT '======================================================================'
PRINT ''
PRINT '📝 Summary of Test:'
PRINT '   1. ✅ Created order from POS'
PRINT '   2. ✅ Applied partial Avoqado payment'
PRINT '   3. ✅ Completed remaining payment from POS'
PRINT '   4. ✅ Closed shift'
PRINT '   5. ✅ Verified payments were archived'
PRINT ''
PRINT '🎯 Expected Outcome:'
PRINT '   - Both Avoqado and POS payments appear in archived data (chequespagos)'
PRINT '   - Shift report should include ALL payments regardless of source'
PRINT '   - If report excludes Avoqado payments, the issue is in the REPORT QUERY'
PRINT '     not in the archiving process.'
PRINT ''
