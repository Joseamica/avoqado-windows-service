-- ====================================================================
-- FIX TRIGGER ERRORS - Manual Sync Recovery
-- Use when diagnostics shows trigger errors (RetryCount=99)
-- ====================================================================

USE avov2;
GO

PRINT '======================================================================'
PRINT ' TRIGGER ERROR RECOVERY'
PRINT '======================================================================'
PRINT ''

-- Show trigger errors
PRINT '🚨 CURRENT TRIGGER ERRORS:'
PRINT '--------------------------------------------------------------------'

SELECT
    Id,
    EntityType,
    EntityId,
    Timestamp,
    ErrorMsg
FROM AvoqadoTracking
WHERE RetryCount = 99 AND Operation = 'ERROR'
ORDER BY Timestamp

DECLARE @ErrorCount INT
SELECT @ErrorCount = COUNT(*)
FROM AvoqadoTracking
WHERE RetryCount = 99 AND Operation = 'ERROR'

PRINT ''
PRINT '📊 Found ' + CAST(@ErrorCount AS VARCHAR) + ' trigger errors'
PRINT ''

IF @ErrorCount = 0
BEGIN
    PRINT '✅ No trigger errors to fix'
    RETURN
END

-- Option 1: Mark as processed (ignore the errors)
PRINT '📌 OPTION 1: Mark errors as processed (will NOT send to Avoqado)'
PRINT '   WARNING: This will cause POS and Avoqado to be out of sync!'
PRINT '   Only use if you manually synced the data or these are test records.'
PRINT ''
PRINT '   Uncomment this block to execute:'
PRINT ''
/*
UPDATE AvoqadoTracking
SET ProcessedAt = GETUTCDATE(),
    ErrorMsg = 'Manually marked as processed - ' + ErrorMsg
WHERE RetryCount = 99 AND Operation = 'ERROR'

PRINT '   ✅ Marked ' + CAST(@@ROWCOUNT AS VARCHAR) + ' errors as processed'
*/

-- Option 2: Delete error records (will lose tracking history)
PRINT '📌 OPTION 2: Delete error records (lose tracking history)'
PRINT '   WARNING: This will permanently delete the error records!'
PRINT '   Only use if these records are irrelevant or duplicates.'
PRINT ''
PRINT '   Uncomment this block to execute:'
PRINT ''
/*
DELETE FROM AvoqadoTracking
WHERE RetryCount = 99 AND Operation = 'ERROR'

PRINT '   ✅ Deleted ' + CAST(@@ROWCOUNT AS VARCHAR) + ' error records'
*/

-- Option 3: Manual investigation guide
PRINT '📌 OPTION 3: Manual investigation (recommended)'
PRINT '   Review each error and manually create correct tracking records:'
PRINT ''
PRINT '   1. Check the ErrorMsg column for details'
PRINT '   2. Identify which POS operation failed to track'
PRINT '   3. Manually create correct tracking record'
PRINT '   4. Mark error record as processed'
PRINT ''
PRINT '   Example to manually track a shift close:'
PRINT '   INSERT INTO AvoqadoTracking (EntityType, EntityId, Operation, RetryCount)'
PRINT '   VALUES (''shift'', ''<WorkspaceId>'', ''CLOSED'', 0)'
PRINT ''

PRINT '======================================================================'
PRINT ' RECOVERY OPTIONS DISPLAYED'
PRINT '======================================================================'
PRINT ''
PRINT 'Review the errors above and choose an option.'
PRINT 'Uncomment the appropriate block and re-run this script.'