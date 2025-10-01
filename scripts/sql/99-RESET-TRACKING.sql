-- ====================================================================
-- RESET TRACKING - Clean up stuck/invalid records
-- Use this when service reports invalid EntityId errors
-- ====================================================================

USE avov2;
GO

PRINT '======================================================================'
PRINT ' RESET AVOQADO TRACKING'
PRINT '======================================================================'
PRINT ''

-- Show current status
PRINT '📊 CURRENT STATUS:'
SELECT
    EntityType,
    COUNT(*) as Total,
    COUNT(CASE WHEN ProcessedAt IS NULL THEN 1 END) as Pending,
    COUNT(CASE WHEN ProcessedAt IS NOT NULL THEN 1 END) as Processed,
    COUNT(CASE WHEN RetryCount >= 5 THEN 1 END) as Failed
FROM AvoqadoTracking
GROUP BY EntityType

PRINT ''

-- Option 1: Mark all as processed (keeps history)
PRINT '📌 OPTION 1: Marking all pending records as processed...'
UPDATE AvoqadoTracking
SET ProcessedAt = GETUTCDATE()
WHERE ProcessedAt IS NULL

DECLARE @MarkedCount INT = @@ROWCOUNT
PRINT '   ✅ Marked ' + CAST(@MarkedCount AS VARCHAR) + ' records as processed'

PRINT ''

-- Option 2: Delete old/invalid records (optional - uncomment if needed)
/*
PRINT '📌 OPTION 2: Deleting old records (>24 hours)...'
DELETE FROM AvoqadoTracking
WHERE Timestamp < DATEADD(HOUR, -24, GETDATE())

DECLARE @DeletedCount INT = @@ROWCOUNT
PRINT '   ✅ Deleted ' + CAST(@DeletedCount AS VARCHAR) + ' old records'
PRINT ''
*/

-- Option 3: Complete cleanup (uncomment to clear ALL tracking history)
/*
PRINT '⚠️ OPTION 3: COMPLETE CLEANUP - Deleting ALL tracking records...'
DELETE FROM AvoqadoTracking
DECLARE @AllDeletedCount INT = @@ROWCOUNT
PRINT '   ✅ Deleted ' + CAST(@AllDeletedCount AS VARCHAR) + ' records'
PRINT ''
*/

-- Show updated status
PRINT '📊 UPDATED STATUS:'
SELECT
    EntityType,
    COUNT(*) as Total,
    COUNT(CASE WHEN ProcessedAt IS NULL THEN 1 END) as Pending,
    COUNT(CASE WHEN ProcessedAt IS NOT NULL THEN 1 END) as Processed
FROM AvoqadoTracking
GROUP BY EntityType

PRINT ''
PRINT '======================================================================'
PRINT ' ✅ RESET COMPLETE'
PRINT '======================================================================'
PRINT ''
PRINT 'The Windows service should now work without EntityId errors.'
PRINT 'Restart the service if needed: npm run dev'