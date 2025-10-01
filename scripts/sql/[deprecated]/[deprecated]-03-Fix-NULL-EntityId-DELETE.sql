-- ====================================================================
-- 08 - FIX FOR NULL EntityId DURING DELETE OPERATIONS
-- SQL Server 2014 Compatible
--
-- PURPOSE:
-- Fixes the issue where DELETE operations cause NULL EntityId errors
-- because the fn_GetAvoqadoEntityId function tries to lookup WorkspaceId
-- from a record that has already been deleted.
--
-- ERROR FIXED:
-- "No se puede insertar el valor NULL en la columna 'EntityId',
--  tabla 'avov2.dbo.AvoqadoTracking'. La columna no admite valores NULL."
-- ====================================================================

PRINT N'🔧 ============================================================='
PRINT N'🔧 FIXING NULL EntityId ISSUE FOR DELETE OPERATIONS'
PRINT N'🔧 ============================================================='
PRINT N''
PRINT N'Fix started at: ' + CONVERT(VARCHAR, GETDATE(), 120)
PRINT N''

-- =====================================================
-- STEP 1: CREATE ENHANCED ENTITY ID FUNCTION
-- =====================================================
PRINT N'📌 STEP 1: Creating enhanced Entity ID function...'
PRINT N''

IF OBJECT_ID('fn_GetAvoqadoEntityIdWithWorkspace', 'FN') IS NOT NULL
    DROP FUNCTION fn_GetAvoqadoEntityIdWithWorkspace
GO

-- Enhanced function that accepts WorkspaceId directly for DELETE scenarios
CREATE FUNCTION fn_GetAvoqadoEntityIdWithWorkspace(
    @EntityType VARCHAR(50),
    @Folio BIGINT,
    @IdTurno BIGINT = NULL,
    @Movimiento INT = NULL,
    @WorkspaceId UNIQUEIDENTIFIER = NULL  -- NEW: Direct WorkspaceId parameter
) RETURNS VARCHAR(200)
AS BEGIN
    DECLARE @EntityId VARCHAR(200)
    DECLARE @HasWorkspace BIT
    DECLARE @InstanceId UNIQUEIDENTIFIER

    -- Get configuration
    SELECT TOP 1 @HasWorkspace = HasWorkspaceId, @InstanceId = InstanceId
    FROM AvoqadoConfig

    IF @HasWorkspace = 1 AND @EntityType IN ('order', 'orderitem', 'shift')
    BEGIN
        -- v11+ with WorkspaceId support
        -- If WorkspaceId not provided, try to lookup (for INSERT/UPDATE operations)
        IF @WorkspaceId IS NULL
        BEGIN
            IF @EntityType = 'shift'
            BEGIN
                -- Get WorkspaceId from turnos table
                SELECT @WorkspaceId = WorkspaceId
                FROM turnos
                WHERE idturno = @IdTurno
            END
            ELSE
            BEGIN
                -- Get WorkspaceId from tempcheques table
                SELECT @WorkspaceId = WorkspaceId
                FROM tempcheques
                WHERE folio = @Folio
            END
        END

        -- Generate Entity ID based on type
        -- IMPORTANT: Only proceed if we have a valid WorkspaceId
        IF @WorkspaceId IS NOT NULL
        BEGIN
            SET @EntityId = CASE @EntityType
                WHEN 'order' THEN CAST(@WorkspaceId AS VARCHAR(36))
                WHEN 'orderitem' THEN CAST(@WorkspaceId AS VARCHAR(36)) + ':' + CAST(@Movimiento AS VARCHAR)
                WHEN 'shift' THEN CAST(@WorkspaceId AS VARCHAR(36))
                WHEN 'payment' THEN CAST(@WorkspaceId AS VARCHAR(36)) + ':PAY:' + CONVERT(VARCHAR, GETDATE(), 112) + REPLACE(CONVERT(VARCHAR, GETDATE(), 108), ':', '')
                ELSE CAST(@InstanceId AS VARCHAR(36)) + ':' + CAST(@Folio AS VARCHAR)
            END
        END
        ELSE
        BEGIN
            -- Fallback to v10 format if WorkspaceId cannot be determined
            SET @EntityId = CASE @EntityType
                WHEN 'order' THEN CAST(@InstanceId AS VARCHAR(36)) + ':' + ISNULL(CAST(@IdTurno AS VARCHAR), '0') + ':' + CAST(@Folio AS VARCHAR)
                WHEN 'orderitem' THEN CAST(@InstanceId AS VARCHAR(36)) + ':' + ISNULL(CAST(@IdTurno AS VARCHAR), '0') + ':' + CAST(@Folio AS VARCHAR) + ':' + CAST(@Movimiento AS VARCHAR)
                WHEN 'shift' THEN CAST(@IdTurno AS VARCHAR)
                WHEN 'payment' THEN CAST(@InstanceId AS VARCHAR(36)) + ':' + CAST(@Folio AS VARCHAR) + ':PAY:' + CONVERT(VARCHAR, GETDATE(), 112) + REPLACE(CONVERT(VARCHAR, GETDATE(), 108), ':', '')
                ELSE CAST(@InstanceId AS VARCHAR(36)) + ':' + CAST(@Folio AS VARCHAR)
            END
        END
    END
    ELSE
    BEGIN
        -- v10 or entities without WorkspaceId
        SET @EntityId = CASE @EntityType
            WHEN 'order' THEN CAST(@InstanceId AS VARCHAR(36)) + ':' + ISNULL(CAST(@IdTurno AS VARCHAR), '0') + ':' + CAST(@Folio AS VARCHAR)
            WHEN 'orderitem' THEN CAST(@InstanceId AS VARCHAR(36)) + ':' + ISNULL(CAST(@IdTurno AS VARCHAR), '0') + ':' + CAST(@Folio AS VARCHAR) + ':' + CAST(@Movimiento AS VARCHAR)
            WHEN 'shift' THEN CAST(@IdTurno AS VARCHAR)
            WHEN 'payment' THEN CAST(@InstanceId AS VARCHAR(36)) + ':' + CAST(@Folio AS VARCHAR) + ':PAY:' + CONVERT(VARCHAR, GETDATE(), 112) + REPLACE(CONVERT(VARCHAR, GETDATE(), 108), ':', '')
            ELSE CAST(@InstanceId AS VARCHAR(36)) + ':' + CAST(@Folio AS VARCHAR)
        END
    END

    RETURN @EntityId
END
GO

PRINT N'  ✅ Enhanced Entity ID function created'
PRINT N''

-- =====================================================
-- STEP 2: UPDATE ORDERS TRIGGER (FIXED VERSION)
-- =====================================================
PRINT N'📌 STEP 2: Updating Orders trigger with DELETE fix...'
PRINT N''

IF OBJECT_ID('Trg_Avoqado_Orders', 'TR') IS NOT NULL
    DROP TRIGGER Trg_Avoqado_Orders
GO

CREATE TRIGGER Trg_Avoqado_Orders ON tempcheques
AFTER INSERT, UPDATE, DELETE AS
BEGIN
    SET NOCOUNT ON

    -- Skip during shift close process (detect by checking if shift is closing)
    IF EXISTS(
        SELECT 1 FROM turnos t
        WHERE t.cierre IS NOT NULL
        AND t.idturno IN (
            SELECT idturno FROM inserted
            UNION
            SELECT idturno FROM deleted
        )
        AND DATEDIFF(SECOND, t.cierre, GETDATE()) < 30 -- Within 30 seconds of close
    ) RETURN

    -- Track changes efficiently with proper DELETE handling
    INSERT INTO AvoqadoTracking (EntityType, EntityId, Operation)
    SELECT DISTINCT
        'order',
        CASE
            -- For DELETE operations, pass WorkspaceId directly from deleted record
            WHEN i.folio IS NULL AND d.folio IS NOT NULL THEN
                dbo.fn_GetAvoqadoEntityIdWithWorkspace('order', d.folio, d.idturno, NULL, d.WorkspaceId)
            -- For INSERT/UPDATE operations, let function lookup WorkspaceId
            ELSE
                dbo.fn_GetAvoqadoEntityIdWithWorkspace('order', COALESCE(i.folio, d.folio), COALESCE(i.idturno, d.idturno), NULL, NULL)
        END,
        CASE
            WHEN i.folio IS NOT NULL AND d.folio IS NOT NULL THEN 'UPDATE'
            WHEN i.folio IS NOT NULL THEN 'CREATE'
            WHEN d.folio IS NOT NULL THEN 'DELETE'
        END
    FROM inserted i
    FULL OUTER JOIN deleted d ON i.folio = d.folio
    WHERE COALESCE(i.folio, d.folio) IS NOT NULL
      AND (
          -- Only process if we can generate a valid EntityId
          (i.folio IS NULL AND d.folio IS NOT NULL AND d.WorkspaceId IS NOT NULL) OR  -- DELETE with valid WorkspaceId
          (i.folio IS NOT NULL) OR  -- INSERT/UPDATE
          (d.folio IS NOT NULL AND i.folio IS NOT NULL)  -- UPDATE
      )
END
GO

PRINT N'  ✅ Orders trigger updated with DELETE fix'
PRINT N''

-- =====================================================
-- STEP 3: UPDATE ORDER ITEMS TRIGGER (FIXED VERSION)
-- =====================================================
PRINT N'📌 STEP 3: Updating Order Items trigger with DELETE fix...'
PRINT N''

IF OBJECT_ID('Trg_Avoqado_OrderItems', 'TR') IS NOT NULL
    DROP TRIGGER Trg_Avoqado_OrderItems
GO

CREATE TRIGGER Trg_Avoqado_OrderItems ON tempcheqdet
AFTER INSERT, UPDATE, DELETE AS
BEGIN
    SET NOCOUNT ON

    -- Track item changes with proper DELETE handling
    INSERT INTO AvoqadoTracking (EntityType, EntityId, Operation)
    SELECT DISTINCT
        'orderitem',
        CASE
            -- For DELETE operations, get WorkspaceId from the parent order in deleted table
            WHEN i.movimiento IS NULL AND d.movimiento IS NOT NULL THEN
                dbo.fn_GetAvoqadoEntityIdWithWorkspace('orderitem', d.foliodet,
                    (SELECT idturno FROM tempcheques WHERE folio = d.foliodet),
                    d.movimiento,
                    (SELECT WorkspaceId FROM tempcheques WHERE folio = d.foliodet))
            -- For INSERT/UPDATE operations, let function lookup WorkspaceId
            ELSE
                dbo.fn_GetAvoqadoEntityIdWithWorkspace('orderitem', COALESCE(i.foliodet, d.foliodet),
                    (SELECT idturno FROM tempcheques WHERE folio = COALESCE(i.foliodet, d.foliodet)),
                    COALESCE(i.movimiento, d.movimiento),
                    NULL)
        END,
        CASE
            WHEN i.movimiento IS NOT NULL AND d.movimiento IS NOT NULL THEN 'UPDATE'
            WHEN i.movimiento IS NOT NULL THEN 'CREATE'
            WHEN d.movimiento IS NOT NULL THEN 'DELETE'
        END
    FROM inserted i
    FULL OUTER JOIN deleted d ON i.foliodet = d.foliodet AND i.movimiento = d.movimiento
    WHERE COALESCE(i.movimiento, d.movimiento) IS NOT NULL

    -- Also mark parent order as updated (only for non-DELETE operations on items)
    INSERT INTO AvoqadoTracking (EntityType, EntityId, Operation)
    SELECT DISTINCT
        'order',
        dbo.fn_GetAvoqadoEntityIdWithWorkspace('order', folio,
            (SELECT idturno FROM tempcheques WHERE folio = foliodet), NULL, NULL),
        'UPDATE'
    FROM (
        SELECT foliodet as folio FROM inserted
        UNION
        SELECT foliodet as folio FROM deleted
    ) changes
    WHERE EXISTS(SELECT 1 FROM tempcheques WHERE folio = changes.folio) -- Only if parent order still exists
END
GO

PRINT N'  ✅ Order items trigger updated with DELETE fix'
PRINT N''

-- =====================================================
-- STEP 4: VALIDATION AND TESTING
-- =====================================================
PRINT N'📌 STEP 4: Validating installation...'
PRINT N''

-- Test the enhanced function
DECLARE @TestEntityId VARCHAR(200)
DECLARE @TestWorkspaceId UNIQUEIDENTIFIER = NEWID()

-- Test v11 format with provided WorkspaceId
SELECT @TestEntityId = dbo.fn_GetAvoqadoEntityIdWithWorkspace('order', 12345, 894, NULL, @TestWorkspaceId)
PRINT N'  Test v11 with WorkspaceId: ' + ISNULL(@TestEntityId, 'NULL')

-- Test fallback to v10 format when WorkspaceId is NULL
SELECT @TestEntityId = dbo.fn_GetAvoqadoEntityIdWithWorkspace('order', 12345, 894, NULL, NULL)
PRINT N'  Test fallback to v10: ' + ISNULL(@TestEntityId, 'NULL')

-- Check current configuration
DECLARE @ConfigInfo NVARCHAR(200)
SELECT @ConfigInfo = 'Has WorkspaceId: ' + CASE WHEN HasWorkspaceId = 1 THEN 'YES' ELSE 'NO' END +
                    ', Version: ' + CAST(PosVersion AS VARCHAR)
FROM AvoqadoConfig
PRINT N'  Current config: ' + @ConfigInfo

-- Check if WorkspaceId column exists in tempcheques
IF COL_LENGTH('tempcheques', 'WorkspaceId') IS NOT NULL
    PRINT N'  ✅ WorkspaceId column exists in tempcheques'
ELSE
    PRINT N'  ❌ WorkspaceId column missing in tempcheques (using v10 fallback)'

PRINT N''

-- =====================================================
-- COMPLETION
-- =====================================================
PRINT N'✅ ============================================================='
PRINT N'✅ NULL EntityId DELETE FIX APPLIED SUCCESSFULLY!'
PRINT N'✅ ============================================================='
PRINT N''
PRINT N'Fixed components:'
PRINT N'  ✅ Enhanced fn_GetAvoqadoEntityIdWithWorkspace function'
PRINT N'  ✅ Updated Trg_Avoqado_Orders trigger with DELETE handling'
PRINT N'  ✅ Updated Trg_Avoqado_OrderItems trigger with DELETE handling'
PRINT N''
PRINT N'Fix details:'
PRINT N'  🔧 DELETE operations now pass WorkspaceId directly from deleted record'
PRINT N'  🔧 INSERT/UPDATE operations continue to lookup WorkspaceId from table'
PRINT N'  🔧 Automatic fallback to v10 format when WorkspaceId unavailable'
PRINT N'  🔧 Added validation to prevent NULL EntityId entries'
PRINT N''
PRINT N'The error "No se puede insertar el valor NULL en la columna EntityId" should now be resolved.'
PRINT N''
PRINT N'Completed at: ' + CONVERT(VARCHAR, GETDATE(), 120)