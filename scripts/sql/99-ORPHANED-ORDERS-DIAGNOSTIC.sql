-- ===============================================================
-- ORPHANED ORDERS DIAGNOSTIC
-- Identifies orders with idturno=0 that won't appear in shift reports
-- ===============================================================
-- Created: 2025-10-01
-- Purpose: Find orders that need to be assigned to a shift
-- ===============================================================

PRINT '======================================================================='
PRINT ' ORPHANED ORDERS DIAGNOSTIC'
PRINT '======================================================================='
PRINT ''
PRINT 'Current Database: ' + DB_NAME()
PRINT 'Analysis Date: ' + CONVERT(VARCHAR, GETDATE(), 120)
PRINT ''

-- ===============================================================
-- SECTION 1: Current Open Shift
-- ===============================================================
PRINT '-----------------------------------------------------------------------'
PRINT ' SECTION 1: Current Open Shift'
PRINT '-----------------------------------------------------------------------'
PRINT ''

SELECT
    idturno as OpenShiftId,
    apertura as OpenedAt,
    DATEDIFF(HOUR, apertura, GETDATE()) as HoursOpen
FROM turnos
WHERE cierre IS NULL

PRINT ''

-- ===============================================================
-- SECTION 2: Orphaned Orders (idturno=0)
-- ===============================================================
PRINT '-----------------------------------------------------------------------'
PRINT ' SECTION 2: Orphaned Orders (idturno=0)'
PRINT '-----------------------------------------------------------------------'
PRINT ''

DECLARE @OrphanedCount INT
SELECT @OrphanedCount = COUNT(*) FROM tempcheques WHERE idturno = 0

IF @OrphanedCount = 0
BEGIN
    PRINT '✅ NO ORPHANED ORDERS FOUND'
    PRINT '   All orders are correctly assigned to shifts.'
END
ELSE
BEGIN
    PRINT '⚠️  FOUND ' + CAST(@OrphanedCount AS VARCHAR) + ' ORPHANED ORDER(S)'
    PRINT ''

    SELECT
        folio,
        idturno as CurrentShift,
        total,
        pagado as IsPaid,
        impreso as IsPrinted,
        cancelado as IsCanceled,
        observaciones as Notes,
        WorkspaceId
    FROM tempcheques
    WHERE idturno = 0
    ORDER BY folio
END

PRINT ''

-- ===============================================================
-- SECTION 3: Payments for Orphaned Orders
-- ===============================================================
PRINT '-----------------------------------------------------------------------'
PRINT ' SECTION 3: Payments for Orphaned Orders'
PRINT '-----------------------------------------------------------------------'
PRINT ''

SELECT
    p.folio,
    p.idformadepago as PaymentMethod,
    p.importe as Amount,
    p.propina as Tip,
    p.referencia as Reference,
    t.idturno as OrderShift,
    t.total as OrderTotal
FROM tempchequespagos p
INNER JOIN tempcheques t ON p.folio = t.folio
WHERE t.idturno = 0
ORDER BY p.folio, p.importe

IF @@ROWCOUNT = 0
    PRINT '✅ No payments found for orphaned orders'

PRINT ''

-- ===============================================================
-- SECTION 4: Impact Analysis
-- ===============================================================
PRINT '-----------------------------------------------------------------------'
PRINT ' SECTION 4: Impact Analysis'
PRINT '-----------------------------------------------------------------------'
PRINT ''

-- Count payments that won't appear in shift reports
DECLARE @HiddenPaymentsCount INT, @HiddenPaymentsTotal MONEY
SELECT
    @HiddenPaymentsCount = COUNT(*),
    @HiddenPaymentsTotal = ISNULL(SUM(p.importe), 0)
FROM tempchequespagos p
INNER JOIN tempcheques t ON p.folio = t.folio
WHERE t.idturno = 0

PRINT 'Hidden Payments (won''t appear in shift reports):'
PRINT '  Count: ' + CAST(@HiddenPaymentsCount AS VARCHAR)
PRINT '  Total: $' + CAST(@HiddenPaymentsTotal AS VARCHAR)

PRINT ''

-- ===============================================================
-- SECTION 5: Fix Recommendations
-- ===============================================================
PRINT '-----------------------------------------------------------------------'
PRINT ' SECTION 5: Recommendations'
PRINT '-----------------------------------------------------------------------'
PRINT ''

IF @OrphanedCount > 0
BEGIN
    PRINT '⚠️  ACTION REQUIRED:'
    PRINT ''
    PRINT '1. Manual Fix (Assign to Current Shift):'
    PRINT '   Run this query to assign all orphaned orders to current shift:'
    PRINT ''
    PRINT '   DECLARE @OpenShift BIGINT'
    PRINT '   SELECT @OpenShift = idturno FROM turnos WHERE cierre IS NULL'
    PRINT '   UPDATE tempcheques SET idturno = @OpenShift WHERE idturno = 0'
    PRINT ''
    PRINT '2. Automatic Fix (Already Implemented):'
    PRINT '   ✅ sp_ApplyPartialPayment now automatically assigns orders to current shift'
    PRINT '   ✅ New payments will automatically fix orphaned orders'
    PRINT ''
    PRINT '3. Prevention:'
    PRINT '   ✅ Ensure sp_ApplyPartialPayment is deployed (01-COMPLETE-INSTALL.sql)'
    PRINT '   ✅ Test payment flow after deployment'
END
ELSE
BEGIN
    PRINT '✅ NO ACTION NEEDED'
    PRINT '   All orders are correctly assigned to shifts'
    PRINT '   Payments will appear in shift reports'
END

PRINT ''

-- ===============================================================
-- SECTION 6: Historical Analysis (Last 3 Closed Shifts)
-- ===============================================================
PRINT '-----------------------------------------------------------------------'
PRINT ' SECTION 6: Historical Analysis (Last 3 Closed Shifts)'
PRINT '-----------------------------------------------------------------------'
PRINT ''

SELECT TOP 3
    t.idturno as ShiftId,
    t.apertura as Opened,
    t.cierre as Closed,
    COUNT(DISTINCT c.folio) as OrderCount,
    COUNT(p.folio) as PaymentCount,
    ISNULL(SUM(p.importe), 0) as TotalPayments
FROM turnos t
LEFT JOIN cheques c ON t.idturno = c.idturno
LEFT JOIN chequespagos p ON c.folio = p.folio
WHERE t.cierre IS NOT NULL
GROUP BY t.idturno, t.apertura, t.cierre
ORDER BY t.idturno DESC

PRINT ''
PRINT '======================================================================='
PRINT ' END OF DIAGNOSTIC'
PRINT '======================================================================='
