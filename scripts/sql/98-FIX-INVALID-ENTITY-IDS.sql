-- ====================================================================
-- FIX INVALID ENTITY IDs
-- Removes records with v10 format EntityIds in a v11 system
-- ====================================================================

USE avov2;
GO

PRINT '======================================================================'
PRINT ' FIXING INVALID ENTITY IDs'
PRINT '======================================================================'
PRINT ''

-- Detect system version
DECLARE @HasWorkspace BIT = 0
IF COL_LENGTH('tempcheques', 'WorkspaceId') IS NOT NULL
    SET @HasWorkspace = 1

PRINT '📌 System Type: ' + CASE WHEN @HasWorkspace = 1 THEN 'v11 (WorkspaceId)' ELSE 'v10' END
PRINT ''

IF @HasWorkspace = 1
BEGIN
    PRINT '🔍 Searching for v10 format EntityIds in v11 system...'
    PRINT ''

    -- Show invalid records
    PRINT '❌ Invalid EntityId records found:'
    SELECT
        Id,
        EntityType,
        LEFT(EntityId, 60) as EntityId,
        Operation,
        Timestamp
    FROM AvoqadoTracking
    WHERE EntityType = 'orderitem'
      AND EntityId LIKE '%:%:%:%'  -- v10 format: InstanceId:IdTurno:Folio:Movimiento
      AND ProcessedAt IS NULL

    DECLARE @InvalidCount INT
    SELECT @InvalidCount = COUNT(*)
    FROM AvoqadoTracking
    WHERE EntityType = 'orderitem'
      AND EntityId LIKE '%:%:%:%'
      AND ProcessedAt IS NULL

    PRINT ''
    PRINT '📊 Found ' + CAST(@InvalidCount AS VARCHAR) + ' invalid records'
    PRINT ''

    IF @InvalidCount > 0
    BEGIN
        PRINT '🗑️ Deleting invalid records...'

        DELETE FROM AvoqadoTracking
        WHERE EntityType = 'orderitem'
          AND EntityId LIKE '%:%:%:%'  -- v10 format

        PRINT '   ✅ Deleted ' + CAST(@@ROWCOUNT AS VARCHAR) + ' invalid orderitem records'

        -- Also clean up invalid order records
        DELETE FROM AvoqadoTracking
        WHERE EntityType = 'order'
          AND EntityId LIKE '%:%:%'  -- v10 format: InstanceId:IdTurno:Folio
          AND EntityId NOT LIKE '________-____-____-____-____________'  -- Not a GUID

        IF @@ROWCOUNT > 0
            PRINT '   ✅ Deleted ' + CAST(@@ROWCOUNT AS VARCHAR) + ' invalid order records'

        PRINT ''
    END
    ELSE
    BEGIN
        PRINT '✅ No invalid records found'
        PRINT ''
    END
END
ELSE
BEGIN
    PRINT '✅ System is v10, no EntityId format mismatch expected'
    PRINT ''
END

-- Show final status
PRINT '📊 CURRENT TRACKING STATUS:'
SELECT
    EntityType,
    COUNT(*) as Total,
    COUNT(CASE WHEN ProcessedAt IS NULL THEN 1 END) as Pending
FROM AvoqadoTracking
GROUP BY EntityType

PRINT ''
PRINT '======================================================================'
PRINT ' ✅ FIX COMPLETE'
PRINT '======================================================================'
PRINT ''
PRINT 'Invalid EntityId records have been removed.'
PRINT 'Service should now work without EntityId validation errors.'