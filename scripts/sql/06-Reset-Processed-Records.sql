-- ================================================
-- 06-Reset-Processed-Records.sql
-- Resets ProcessedAt for records to allow reprocessing
-- ================================================

-- Display current status
PRINT '=== CURRENT TRACKING STATUS ==='
SELECT
    EntityType,
    COUNT(*) as TotalRecords,
    COUNT(ProcessedAt) as ProcessedRecords,
    COUNT(*) - COUNT(ProcessedAt) as UnprocessedRecords
FROM AvoqadoTracking
GROUP BY EntityType
ORDER BY EntityType

-- Show recent shift records
PRINT ''
PRINT '=== RECENT SHIFT RECORDS ==='
SELECT TOP 5
    EntityType,
    EntityId,
    Operation,
    Timestamp,
    ProcessedAt,
    RetryCount
FROM AvoqadoTracking
WHERE EntityType = 'shift'
ORDER BY Timestamp DESC

-- Reset ProcessedAt for recent records (last 24 hours)
PRINT ''
PRINT '=== RESETTING RECENT PROCESSED RECORDS ==='

DECLARE @ResetCount INT
DECLARE @CutoffTime DATETIME2 = DATEADD(HOUR, -24, GETDATE())

UPDATE AvoqadoTracking
SET
    ProcessedAt = NULL,
    RetryCount = 0,
    ErrorMsg = NULL
WHERE
    ProcessedAt IS NOT NULL
    AND Timestamp > @CutoffTime

SET @ResetCount = @@ROWCOUNT

PRINT 'Records reset for reprocessing: ' + CAST(@ResetCount AS VARCHAR(10))

-- Optionally reset specific shift ID (uncomment and replace with actual ID)
-- UPDATE AvoqadoTracking
-- SET ProcessedAt = NULL, RetryCount = 0, ErrorMsg = NULL
-- WHERE EntityId = 'E0FFDBCF-BA0E-4A62-A895-A5CB85D7227B'

-- Display updated status
PRINT ''
PRINT '=== UPDATED TRACKING STATUS ==='
SELECT
    EntityType,
    COUNT(*) as TotalRecords,
    COUNT(ProcessedAt) as ProcessedRecords,
    COUNT(*) - COUNT(ProcessedAt) as UnprocessedRecords
FROM AvoqadoTracking
GROUP BY EntityType
ORDER BY EntityType

PRINT ''
PRINT '✅ Reset complete. The Windows service should pick up these records in the next polling cycle.'
PRINT 'Note: If records are immediately processed again but backend still doesn''t receive them,'
PRINT 'check RabbitMQ routing configuration and backend consumption settings.'