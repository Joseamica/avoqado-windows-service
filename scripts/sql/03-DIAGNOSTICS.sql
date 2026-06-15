-- ====================================================================
-- DIAGNOSTICS - Troubleshooting & Monitoring
-- ====================================================================
--
-- USAGE: This script will run on the CURRENT database context.
-- ====================================================================

PRINT '======================================================================'
PRINT ' AVOQADO DIAGNOSTICS & MONITORING'
PRINT '======================================================================'
PRINT ''
PRINT 'Diagnosing Database: ' + DB_NAME()
PRINT ''

-- System Info
PRINT '📊 SYSTEM INFORMATION'
PRINT '--------------------------------------------------------------------'

DECLARE @Version VARCHAR(50)
SELECT @Version = versiondb FROM parametros2
PRINT 'SoftRestaurant Version: ' + ISNULL(@Version, 'UNKNOWN')

DECLARE @HasWorkspace BIT = 0
IF COL_LENGTH('tempcheques', 'WorkspaceId') IS NOT NULL
    SET @HasWorkspace = 1
PRINT 'WorkspaceId Support: ' + CASE WHEN @HasWorkspace = 1 THEN 'YES (v11+)' ELSE 'NO (v10)' END

DECLARE @InstanceId UNIQUEIDENTIFIER
SELECT @InstanceId = InstanceId FROM AvoqadoInstanceInfo
PRINT 'Instance ID: ' + CAST(@InstanceId AS VARCHAR(36))

PRINT ''

-- Tracking Statistics
PRINT '📈 TRACKING STATISTICS'
PRINT '--------------------------------------------------------------------'

SELECT
    EntityType,
    COUNT(*) as Total,
    COUNT(CASE WHEN ProcessedAt IS NULL THEN 1 END) as Pending,
    COUNT(CASE WHEN ProcessedAt IS NOT NULL THEN 1 END) as Processed,
    COUNT(CASE WHEN RetryCount > 0 THEN 1 END) as Retried,
    COUNT(CASE WHEN RetryCount >= 5 THEN 1 END) as Failed
FROM AvoqadoTracking
GROUP BY EntityType
ORDER BY EntityType

PRINT ''

-- Recent Events
PRINT '📝 RECENT EVENTS (Last 10)'
PRINT '--------------------------------------------------------------------'

SELECT TOP 10
    Id,
    EntityType,
    LEFT(EntityId, 50) as EntityId,
    Operation,
    Timestamp,
    ProcessedAt,
    RetryCount
FROM AvoqadoTracking
ORDER BY Timestamp DESC

PRINT ''

-- Trigger Errors
PRINT '🚨 TRIGGER ERRORS (Sync Issues)'
PRINT '--------------------------------------------------------------------'

SELECT
    Id,
    EntityType,
    LEFT(EntityId, 50) as EntityId,
    Timestamp,
    LEFT(ErrorMsg, 100) as Error
FROM AvoqadoTracking
WHERE RetryCount = 99 AND Operation = 'ERROR'
ORDER BY Timestamp DESC

IF NOT EXISTS (SELECT 1 FROM AvoqadoTracking WHERE RetryCount = 99 AND Operation = 'ERROR')
    PRINT '✅ No trigger errors'

PRINT ''

-- Pending Changes
PRINT '⏳ PENDING CHANGES'
PRINT '--------------------------------------------------------------------'

SELECT
    Id,
    EntityType,
    LEFT(EntityId, 50) as EntityId,
    Operation,
    Timestamp,
    RetryCount,
    LEFT(ISNULL(ErrorMsg, ''), 100) as Error
FROM AvoqadoTracking
WHERE ProcessedAt IS NULL
ORDER BY Timestamp

PRINT ''

-- Active Orders
PRINT '🛒 ACTIVE ORDERS'
PRINT '--------------------------------------------------------------------'

SELECT
    t.folio,
    t.total,
    t.pagado,
    t.impreso,
    t.mesa,
    t.idturno,
    ISNULL(SUM(p.importe + p.propina), 0) as PaidAmount,
    t.total - ISNULL(SUM(p.importe + p.propina), 0) as Remaining
FROM tempcheques t
LEFT JOIN tempchequespagos p ON t.folio = p.folio
WHERE t.pagado = 0
GROUP BY t.folio, t.total, t.pagado, t.impreso, t.mesa, t.idturno
ORDER BY t.folio

PRINT ''

-- Recent Payments
PRINT '💳 RECENT PAYMENTS'
PRINT '--------------------------------------------------------------------'

SELECT TOP 10
    p.folio,
    p.idformadepago,
    f.descripcion,
    p.importe,
    p.propina,
    p.referencia
FROM tempchequespagos p
INNER JOIN formasdepago f ON p.idformadepago = f.idformadepago
ORDER BY p.folio DESC

PRINT ''

-- Current Shift
PRINT '🕐 CURRENT SHIFT'
PRINT '--------------------------------------------------------------------'

SELECT TOP 1
    idturno,
    idturnointerno,
    apertura,
    cierre,
    CASE WHEN cierre IS NULL THEN 'OPEN' ELSE 'CLOSED' END as Status,
    DATEDIFF(HOUR, apertura, GETDATE()) as HoursOpen
FROM turnos
WHERE cierre IS NULL
ORDER BY idturno DESC

PRINT ''

-- Configuration
PRINT '⚙️ CONFIGURATION'
PRINT '--------------------------------------------------------------------'

SELECT
    VenueId,
    PosVersion,
    HasWorkspaceId,
    LastHeartbeat
FROM AvoqadoConfig

PRINT ''

-- Avoqado Components
PRINT '🔧 AVOQADO COMPONENTS'
PRINT '--------------------------------------------------------------------'

PRINT 'Payment Methods:'
IF EXISTS (SELECT 1 FROM formasdepago WHERE idformadepago = 'ACASH')
    PRINT '  ✅ ACASH - Configured'
ELSE
    PRINT '  ❌ ACASH - Missing'

IF EXISTS (SELECT 1 FROM formasdepago WHERE idformadepago = 'ACARD')
    PRINT '  ✅ ACARD - Configured'
ELSE
    PRINT '  ❌ ACARD - Missing'

PRINT ''
PRINT 'Test Product:'
IF EXISTS (SELECT 1 FROM productos WHERE idproducto = 'AVOTEST')
    PRINT '  ✅ AVOTEST - Available for testing'
ELSE
    PRINT '  ⚠️ AVOTEST - Not found'

PRINT ''

-- Health Check
PRINT '🏥 HEALTH CHECK'
PRINT '--------------------------------------------------------------------'

DECLARE @IssueCount INT = 0

-- Check for stuck records
DECLARE @StuckRecords INT
SELECT @StuckRecords = COUNT(*)
FROM AvoqadoTracking
WHERE ProcessedAt IS NULL
  AND Timestamp < DATEADD(MINUTE, -5, GETDATE())
  AND RetryCount < 5

IF @StuckRecords > 0
BEGIN
    PRINT '⚠️ ' + CAST(@StuckRecords AS VARCHAR) + ' records stuck (>5 min, not processed)'
    SET @IssueCount = @IssueCount + 1
END

-- Check for failed records
DECLARE @FailedRecords INT, @TriggerErrors INT
SELECT @FailedRecords = COUNT(*)
FROM AvoqadoTracking
WHERE RetryCount >= 5 AND RetryCount < 99

SELECT @TriggerErrors = COUNT(*)
FROM AvoqadoTracking
WHERE RetryCount = 99 AND Operation = 'ERROR'

IF @FailedRecords > 0
BEGIN
    PRINT '❌ ' + CAST(@FailedRecords AS VARCHAR) + ' records failed (retry count >= 5)'
    SET @IssueCount = @IssueCount + 1
END

IF @TriggerErrors > 0
BEGIN
    PRINT '🚨 ' + CAST(@TriggerErrors AS VARCHAR) + ' TRIGGER ERRORS - POS/Avoqado OUT OF SYNC!'
    PRINT '   Check AvoqadoTracking WHERE RetryCount=99 for details'
    SET @IssueCount = @IssueCount + 1
END

-- Check for missing triggers
IF OBJECT_ID('Trg_Avoqado_Orders', 'TR') IS NULL
BEGIN
    PRINT '❌ Trg_Avoqado_Orders trigger missing'
    SET @IssueCount = @IssueCount + 1
END

IF OBJECT_ID('Trg_Avoqado_OrderItems', 'TR') IS NULL
BEGIN
    PRINT '❌ Trg_Avoqado_OrderItems trigger missing'
    SET @IssueCount = @IssueCount + 1
END

IF OBJECT_ID('Trg_Avoqado_Payments', 'TR') IS NULL
BEGIN
    PRINT '❌ Trg_Avoqado_Payments trigger missing'
    SET @IssueCount = @IssueCount + 1
END

IF @IssueCount = 0
    PRINT '✅ All systems healthy'

-- Check for partial payment quantity adjustments
PRINT ''
PRINT '🔢 PARTIAL PAYMENT QUANTITY ADJUSTMENTS'
PRINT '--------------------------------------------------------------------'
PRINT 'Orders with fractional quantities (indicating partial payments):'
PRINT ''

SELECT
    t.folio,
    d.movimiento,
    d.idproducto,
    d.cantidad,
    d.precio,
    d.cantidad * d.precio as LineTotal,
    t.total as OrderTotal
FROM tempcheqdet d
INNER JOIN tempcheques t ON d.foliodet = t.folio
WHERE d.cantidad <> CAST(d.cantidad AS INT)  -- Find fractional quantities
ORDER BY t.folio, d.movimiento

PRINT ''
PRINT '💡 Fractional quantities indicate SoftRestaurant-style partial payments'
PRINT '   Example: Quantity 0.9871 = $767 paid on $777 order'
PRINT ''

PRINT '======================================================================'
PRINT ' 🧹 MAINTENANCE RECOMMENDATION'
PRINT '======================================================================'
PRINT ''

-- Check if cleanup is needed
DECLARE @OldProcessed INT, @OldErrors INT, @OldFailed INT
SELECT @OldProcessed = COUNT(*)
FROM AvoqadoTracking
WHERE ProcessedAt IS NOT NULL
  AND ProcessedAt < DATEADD(DAY, -7, GETUTCDATE())

SELECT @OldErrors = COUNT(*)
FROM AvoqadoTracking
WHERE RetryCount = 99
  AND Operation = 'ERROR'
  AND Timestamp < DATEADD(DAY, -7, GETUTCDATE())

SELECT @OldFailed = COUNT(*)
FROM AvoqadoTracking
WHERE RetryCount >= 5
  AND RetryCount < 99
  AND Timestamp < DATEADD(DAY, -7, GETUTCDATE())

IF @OldProcessed > 0 OR @OldErrors > 0 OR @OldFailed > 0
BEGIN
    PRINT '⚠️ Old records found that can be cleaned up:'
    PRINT '   Processed records (>7 days): ' + CAST(@OldProcessed AS VARCHAR)
    PRINT '   Trigger errors (>7 days): ' + CAST(@OldErrors AS VARCHAR)
    PRINT '   Failed records (>7 days): ' + CAST(@OldFailed AS VARCHAR)
    PRINT ''
    PRINT '💡 Run cleanup:'
    PRINT '   EXEC sp_CleanupOldTrackingRecords @DaysToKeep = 7'
END
ELSE
    PRINT '✅ No old records to clean up'

PRINT ''

-- Partial Payment Health (C-1 / H-7 monitoring)
PRINT '💵 PARTIAL PAYMENT HEALTH (sp_ApplyPartialPayment)'
PRINT '--------------------------------------------------------------------'

-- 1) Recent sp_ApplyPartialPayment errors logged to AvoqadoDebugLog (last 7 days)
PRINT 'Recent payment errors in AvoqadoDebugLog (Message LIKE ''%ERROR%'', last 7 days):'

SELECT TOP 50
    Timestamp,
    Folio,
    PaymentAmount,
    Reference,
    LEFT(Message, 200) as Message
FROM AvoqadoDebugLog
WHERE Message LIKE '%ERROR%'
  AND Timestamp >= DATEADD(DAY, -7, GETDATE())
ORDER BY Timestamp DESC

IF NOT EXISTS (
    SELECT 1 FROM AvoqadoDebugLog
    WHERE Message LIKE '%ERROR%' AND Timestamp >= DATEADD(DAY, -7, GETDATE())
)
    PRINT '✅ No sp_ApplyPartialPayment errors in the last 7 days'

PRINT ''

-- 2) Integrity review: active orders that carry partial payments.
--    NOTE: the ORIGINAL total cannot be recovered from temp* tables (the SP
--    rewrites tempcheques.total to the running balance), so this is a MANUAL
--    review list, not a hard pass/fail. After the C-1 fix the running `total`
--    should equal (original total - SUM(importe)); a mismatch here vs. the
--    expected balance for the venue is a red flag worth investigating.
PRINT 'Active orders with partial payments (pagado=0 AND payments exist) — manual review:'

SELECT
    t.folio,
    t.mesa,
    t.idturno,
    t.total                              as RunningTotal,
    COUNT(p.folio)                       as PaymentRows,
    ISNULL(SUM(p.importe), 0)            as SumImporte,
    ISNULL(SUM(p.propina), 0)            as SumPropina,
    t.total + ISNULL(SUM(p.importe), 0)  as ImpliedOriginalTotal
FROM tempcheques t
INNER JOIN tempchequespagos p ON p.folio = t.folio
WHERE t.pagado = 0
GROUP BY t.folio, t.mesa, t.idturno, t.total
ORDER BY t.folio

IF NOT EXISTS (
    SELECT 1
    FROM tempcheques t
    INNER JOIN tempchequespagos p ON p.folio = t.folio
    WHERE t.pagado = 0
)
    PRINT '✅ No active orders with partial payments'

PRINT ''
PRINT '💡 RunningTotal should equal (originalTotal - SumImporte). ImpliedOriginalTotal'
PRINT '   (RunningTotal + SumImporte) is a sanity figure for manual cross-check.'
PRINT ''

PRINT '======================================================================'
PRINT ' DIAGNOSTICS COMPLETE'
PRINT '======================================================================'