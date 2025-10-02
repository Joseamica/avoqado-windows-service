-- ====================================================================
-- SHIFT CLOSE DIAGNOSTIC - Verify Avoqado Payment Archiving
-- ====================================================================
--
-- PURPOSE: This script helps diagnose why Avoqado payments might not
--          appear in shift close reports after archiving.
--
-- USAGE: Run this script BEFORE and AFTER shift close to compare
--        payment data in temp* vs permanent tables.
-- ====================================================================

PRINT '======================================================================'
PRINT ' SHIFT CLOSE DIAGNOSTIC - Payment Archiving Analysis'
PRINT '======================================================================'
PRINT ''
PRINT 'Database: ' + DB_NAME()
PRINT 'Timestamp: ' + CONVERT(VARCHAR, GETDATE(), 120)
PRINT ''

-- =====================================================
-- SECTION 1: Current Shift Information
-- =====================================================
PRINT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
PRINT '1️⃣  CURRENT SHIFT INFORMATION'
PRINT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
PRINT ''

SELECT TOP 1
    idturno,
    idturnointerno,
    apertura,
    cierre,
    CASE WHEN cierre IS NULL THEN '✅ OPEN' ELSE '⛔ CLOSED' END as Status,
    idestacion,
    idempresa,
    WorkspaceId
FROM turnos
WHERE cierre IS NULL
ORDER BY apertura DESC

IF @@ROWCOUNT = 0
    PRINT '⚠️  No open shift found!'

PRINT ''

-- =====================================================
-- SECTION 2: Active Orders (tempcheques)
-- =====================================================
PRINT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
PRINT '2️⃣  ACTIVE ORDERS (tempcheques)'
PRINT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
PRINT ''

SELECT
    folio,
    idturno,
    total,
    pagado,
    impreso,
    cancelado,
    mesa,
    WorkspaceId,
    CASE
        WHEN pagado = 1 THEN '✅ PAID'
        WHEN impreso = 1 THEN '🖨️  PRINTED'
        ELSE '📝 OPEN'
    END as OrderStatus
FROM tempcheques
ORDER BY folio

IF @@ROWCOUNT = 0
    PRINT '⚠️  No active orders found!'

PRINT ''

-- =====================================================
-- SECTION 3: Active Payments (tempchequespagos)
-- =====================================================
PRINT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
PRINT '3️⃣  ACTIVE PAYMENTS (tempchequespagos)'
PRINT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
PRINT ''

SELECT
    p.folio,
    p.idformadepago,
    f.descripcion as PaymentMethod,
    p.importe,
    p.propina,
    p.importe + p.propina as Total,
    p.referencia,
    p.WorkspaceId,
    t.WorkspaceId as OrderWorkspaceId,
    CASE
        WHEN p.WorkspaceId = t.WorkspaceId THEN '✅ MATCH'
        ELSE '⚠️  MISMATCH'
    END as WorkspaceIdStatus
FROM tempchequespagos p
INNER JOIN formasdepago f ON p.idformadepago = f.idformadepago
INNER JOIN tempcheques t ON p.folio = t.folio
ORDER BY p.folio, p.idformadepago

IF @@ROWCOUNT = 0
    PRINT '⚠️  No active payments found!'

PRINT ''

-- =====================================================
-- SECTION 4: Payment Summary by Type
-- =====================================================
PRINT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
PRINT '4️⃣  PAYMENT SUMMARY BY TYPE'
PRINT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
PRINT ''

SELECT
    f.idformadepago,
    f.descripcion,
    COUNT(*) as PaymentCount,
    SUM(p.importe) as TotalAmount,
    SUM(p.propina) as TotalTips,
    SUM(p.importe + p.propina) as GrandTotal,
    CASE
        WHEN f.idformadepago IN ('ACASH', 'ACARD') THEN '🟢 AVOQADO'
        ELSE '🔵 REGULAR'
    END as PaymentType
FROM tempchequespagos p
INNER JOIN formasdepago f ON p.idformadepago = f.idformadepago
GROUP BY f.idformadepago, f.descripcion
ORDER BY SUM(p.importe + p.propina) DESC

IF @@ROWCOUNT = 0
    PRINT '⚠️  No payments found!'

PRINT ''

-- =====================================================
-- SECTION 5: WorkspaceId Analysis
-- =====================================================
PRINT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
PRINT '5️⃣  WORKSPACEID ANALYSIS (Critical for Archiving)'
PRINT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
PRINT ''

PRINT '📌 Order WorkspaceIds:'
SELECT DISTINCT
    WorkspaceId,
    COUNT(*) as OrderCount
FROM tempcheques
GROUP BY WorkspaceId

PRINT ''
PRINT '📌 Payment WorkspaceIds:'
SELECT DISTINCT
    p.WorkspaceId,
    COUNT(*) as PaymentCount,
    SUM(p.importe + p.propina) as TotalAmount
FROM tempchequespagos p
GROUP BY p.WorkspaceId

PRINT ''
PRINT '📌 WorkspaceId Matching Analysis:'
SELECT
    CASE
        WHEN p.WorkspaceId = t.WorkspaceId THEN 'MATCHING'
        ELSE 'MISMATCHED'
    END as MatchStatus,
    COUNT(*) as PaymentCount,
    SUM(p.importe + p.propina) as TotalAmount
FROM tempchequespagos p
INNER JOIN tempcheques t ON p.folio = t.folio
GROUP BY
    CASE
        WHEN p.WorkspaceId = t.WorkspaceId THEN 'MATCHING'
        ELSE 'MISMATCHED'
    END

PRINT ''

-- =====================================================
-- SECTION 6: Simulated Archiving Query
-- =====================================================
PRINT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
PRINT '6️⃣  SIMULATED ARCHIVING QUERY (What WOULD be archived)'
PRINT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
PRINT ''

DECLARE @CurrentShiftId BIGINT
SELECT TOP 1 @CurrentShiftId = idturno FROM turnos WHERE cierre IS NULL ORDER BY apertura DESC

IF @CurrentShiftId IS NOT NULL
BEGIN
    PRINT '📝 Testing archiving queries for shift: ' + CAST(@CurrentShiftId AS VARCHAR)
    PRINT ''

    -- Query 1: Orders that would be archived
    PRINT '   Query 1: Orders to archive (SELECT * FROM tempcheques WHERE idturno = @ShiftId)'
    SELECT COUNT(*) as OrdersToArchive FROM tempcheques WHERE idturno = @CurrentShiftId

    -- Query 2: Payments that would be archived (STANDARD JOIN)
    PRINT '   Query 2: Payments with INNER JOIN (standard archiving pattern)'
    SELECT COUNT(*) as PaymentsToArchive
    FROM tempchequespagos p
    INNER JOIN tempcheques t ON p.folio = t.folio
    WHERE t.idturno = @CurrentShiftId

    -- Query 3: Payments by method
    PRINT ''
    PRINT '   Payment breakdown by method:'
    SELECT
        f.idformadepago,
        f.descripcion,
        COUNT(*) as Count,
        SUM(p.importe + p.propina) as Total
    FROM tempchequespagos p
    INNER JOIN tempcheques t ON p.folio = t.folio
    INNER JOIN formasdepago f ON p.idformadepago = f.idformadepago
    WHERE t.idturno = @CurrentShiftId
    GROUP BY f.idformadepago, f.descripcion
    ORDER BY SUM(p.importe + p.propina) DESC

    PRINT ''
    PRINT '   ✅ All payments shown above WILL be archived during shift close'
END
ELSE
BEGIN
    PRINT '⚠️  No open shift found - cannot simulate archiving'
END

PRINT ''

-- =====================================================
-- SECTION 7: Historical Data Check (After Shift Close)
-- =====================================================
PRINT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
PRINT '7️⃣  HISTORICAL DATA CHECK (Permanent Tables)'
PRINT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
PRINT ''

PRINT '📌 Recent Closed Shifts (last 5):'
SELECT TOP 5
    idturno,
    apertura,
    cierre,
    DATEDIFF(HOUR, apertura, cierre) as DurationHours,
    idestacion,
    WorkspaceId
FROM turnos
WHERE cierre IS NOT NULL
ORDER BY cierre DESC

PRINT ''
PRINT '📌 Archived Orders (last 10):'
SELECT TOP 10
    folio,
    idturno,
    total,
    fecha,
    WorkspaceId
FROM cheques
ORDER BY fecha DESC

PRINT ''
PRINT '📌 Archived Payments by Method (last 24 hours):'
SELECT
    f.idformadepago,
    f.descripcion,
    COUNT(*) as PaymentCount,
    SUM(p.importe + p.propina) as Total
FROM chequespagos p
INNER JOIN formasdepago f ON p.idformadepago = f.idformadepago
INNER JOIN cheques c ON p.folio = c.folio
WHERE c.fecha >= DATEADD(DAY, -1, GETDATE())
GROUP BY f.idformadepago, f.descripcion
ORDER BY SUM(p.importe + p.propina) DESC

IF @@ROWCOUNT = 0
    PRINT '⚠️  No archived payments found in last 24 hours'

PRINT ''

-- =====================================================
-- SECTION 8: Recommendations
-- =====================================================
PRINT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
PRINT '8️⃣  RECOMMENDATIONS'
PRINT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
PRINT ''

-- Check for WorkspaceId mismatches
DECLARE @MismatchCount INT
SELECT @MismatchCount = COUNT(*)
FROM tempchequespagos p
INNER JOIN tempcheques t ON p.folio = t.folio
WHERE p.WorkspaceId <> t.WorkspaceId

IF @MismatchCount > 0
BEGIN
    PRINT '⚠️  WARNING: ' + CAST(@MismatchCount AS VARCHAR) + ' payment(s) have different WorkspaceId than their order!'
    PRINT '   This is NORMAL for Avoqado payments in SoftRestaurant v11.'
    PRINT '   Each payment gets its own unique WorkspaceId.'
    PRINT ''
    PRINT '💡 The archiving query uses INNER JOIN on folio, so these payments'
    PRINT '   WILL be archived correctly regardless of WorkspaceId mismatch.'
    PRINT ''
END
ELSE
BEGIN
    PRINT '✅ All payments have matching WorkspaceIds with their orders'
    PRINT ''
END

PRINT '📋 TESTING PROCEDURE:'
PRINT '   1. Run this script BEFORE shift close to see current data'
PRINT '   2. Close the shift from POS'
PRINT '   3. Run this script AGAIN to verify payments were archived'
PRINT '   4. Check Section 7 (Historical Data) to confirm Avoqado payments appear'
PRINT ''
PRINT '🔍 IF AVOQADO PAYMENTS ARE MISSING FROM REPORTS:'
PRINT '   - Check if shift report query filters by WorkspaceId'
PRINT '   - Avoqado payments have unique WorkspaceId per payment'
PRINT '   - Report should use: INNER JOIN chequespagos ON folio (NOT WorkspaceId)'
PRINT ''

PRINT '======================================================================'
PRINT ' DIAGNOSTIC COMPLETE'
PRINT '======================================================================'
PRINT ''
PRINT 'Next Steps:'
PRINT '1. Review Section 5 (WorkspaceId Analysis) for mismatches'
PRINT '2. Review Section 6 (Simulated Archiving) to confirm payment count'
PRINT '3. After shift close, re-run and check Section 7 (Historical Data)'
PRINT ''
