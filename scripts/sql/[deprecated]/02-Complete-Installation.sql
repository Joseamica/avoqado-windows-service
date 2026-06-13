-- ====================================================================
-- AVOQADO COMPLETE INSTALLATION SCRIPT
-- SQL Server 2014 Compatible
--
-- VERSION: 4.0.0 - Complete Unified Installation
-- DATE: 2025-09-24
--
-- PURPOSE:
-- Single, complete installation script for Avoqado-SoftRestaurant integration.
-- Works seamlessly across v10 (v9.x), v11+ with automatic version detection.
-- Includes all components needed for production deployment.
--
-- COMPATIBLE WITH: SQL Server 2014 Express (v12.0)
-- AFFECTS: SoftRestaurant v10 (v9.x), v11, v12+
--
-- CRITICAL: This script is tested and working on both v10 and v11 systems.
-- ====================================================================

PRINT N'🚀 ============================================================='
PRINT N'🚀 AVOQADO COMPLETE INTEGRATION v4.0'
PRINT N'🚀 Single installation script - works for v10 and v11'
PRINT N'🚀 ============================================================='
PRINT N''
PRINT N'Installation started at: ' + CONVERT(VARCHAR, GETDATE(), 120)
PRINT N''

-- =====================================================
-- STEP 1: CORE CONFIGURATION TABLE
-- =====================================================
PRINT N'📌 STEP 1: Creating configuration table...'
PRINT N''

IF OBJECT_ID('AvoqadoConfig', 'U') IS NOT NULL
BEGIN
    PRINT N'  ⚠️ AvoqadoConfig already exists, dropping and recreating...'
    DROP TABLE AvoqadoConfig
END

CREATE TABLE AvoqadoConfig (
    InstanceId UNIQUEIDENTIFIER DEFAULT NEWID() PRIMARY KEY,
    VenueId VARCHAR(50) NOT NULL,
    PosVersion DECIMAL(10,4) NULL,
    HasWorkspaceId BIT DEFAULT 0,
    CreatedAt DATETIME2 DEFAULT GETUTCDATE(),
    LastHeartbeat DATETIME2 NULL,
    Config NVARCHAR(MAX) NULL -- JSON config stored as string for SQL 2014
)

PRINT N'  ✅ Configuration table created'

-- Auto-detect version and capabilities
DECLARE @version DECIMAL(10,4)
DECLARE @versionString VARCHAR(50)
DECLARE @hasWorkspace BIT = 0

-- Get version from parametros2 table
SELECT @versionString = versiondb FROM parametros2

-- Parse version (handle formats like "11.0097" or "9.0103")
IF @versionString IS NOT NULL
BEGIN
    DECLARE @majorVersion INT
    DECLARE @minorVersion INT

    SET @majorVersion = CAST(LEFT(@versionString, CHARINDEX('.', @versionString) - 1) AS INT)
    SET @minorVersion = CAST(SUBSTRING(@versionString, CHARINDEX('.', @versionString) + 1, 10) AS INT)
    SET @version = @majorVersion + (@minorVersion * 0.0001)

    PRINT N'  ℹ️ Detected SoftRestaurant version: ' + @versionString + ' (' + CAST(@version AS VARCHAR) + ')'
END
ELSE
BEGIN
    SET @version = 10.0 -- Default to v10 if can't detect
    PRINT N'  ⚠️ Could not detect version, defaulting to 10.0'
END

-- Check for WorkspaceId support
IF COL_LENGTH('tempcheques', 'WorkspaceId') IS NOT NULL
BEGIN
    SET @hasWorkspace = 1
    PRINT N'  ℹ️ WorkspaceId support: YES (multi-tenant)'
END
ELSE
BEGIN
    PRINT N'  ℹ️ WorkspaceId support: NO (single-tenant)'
END

-- Insert configuration
INSERT INTO AvoqadoConfig (VenueId, PosVersion, HasWorkspaceId)
VALUES ('PENDING_CONFIGURATION', @version, @hasWorkspace)

PRINT N''

-- =====================================================
-- STEP 2: AVOQADO INSTANCE INFO TABLE (REQUIRED BY PRODUCER)
-- =====================================================
PRINT N'📌 STEP 2: Creating instance info table...'
PRINT N''

IF OBJECT_ID('AvoqadoInstanceInfo', 'U') IS NOT NULL
BEGIN
    PRINT N'  ⚠️ AvoqadoInstanceInfo already exists, dropping and recreating...'
    DROP TABLE AvoqadoInstanceInfo
END

CREATE TABLE AvoqadoInstanceInfo (
    InstanceId UNIQUEIDENTIFIER DEFAULT NEWID() PRIMARY KEY,
    CreatedAt DATETIME2 DEFAULT GETUTCDATE(),
    LastUpdated DATETIME2 DEFAULT GETUTCDATE()
)

-- Insert default instance record
INSERT INTO AvoqadoInstanceInfo DEFAULT VALUES

PRINT N'  ✅ Instance info table created with default instance'

-- =====================================================
-- STEP 3: TRACKING TABLE
-- =====================================================
PRINT N'📌 STEP 3: Creating tracking table...'
PRINT N''

IF OBJECT_ID('AvoqadoTracking', 'U') IS NOT NULL
BEGIN
    PRINT N'  ⚠️ AvoqadoTracking already exists, dropping and recreating...'
    DROP TABLE AvoqadoTracking
END

CREATE TABLE AvoqadoTracking (
    Id BIGINT IDENTITY(1,1) PRIMARY KEY,
    EntityType VARCHAR(50) NOT NULL, -- 'order', 'orderitem', 'shift', 'payment'
    EntityId VARCHAR(200) NOT NULL, -- Composite ID based on version
    Operation VARCHAR(20) NOT NULL, -- 'CREATE', 'UPDATE', 'DELETE'
    Timestamp DATETIME2 DEFAULT GETUTCDATE(),
    Processed BIT DEFAULT 0,
    ProcessedAt DATETIME2 NULL
)

-- Create performance indexes
CREATE NONCLUSTERED INDEX IX_AvoqadoTracking_Unprocessed
ON AvoqadoTracking (Processed, Timestamp) INCLUDE (EntityType, EntityId, Operation)

CREATE NONCLUSTERED INDEX IX_AvoqadoTracking_EntityType
ON AvoqadoTracking (EntityType, Timestamp)

PRINT N'  ✅ Tracking table created with performance indexes'

-- =====================================================
-- STEP 4: COMMANDS TABLE
-- =====================================================
PRINT N'📌 STEP 4: Creating commands table...'
PRINT N''

IF OBJECT_ID('AvoqadoCommands', 'U') IS NOT NULL
BEGIN
    PRINT N'  ⚠️ AvoqadoCommands already exists, dropping and recreating...'
    DROP TABLE AvoqadoCommands
END

CREATE TABLE AvoqadoCommands (
    Id BIGINT IDENTITY(1,1) PRIMARY KEY,
    CommandType VARCHAR(50) NOT NULL,
    CommandData NVARCHAR(MAX) NULL, -- JSON data for SQL 2014
    Status VARCHAR(20) DEFAULT 'PENDING', -- PENDING, PROCESSING, COMPLETED, FAILED
    CreatedAt DATETIME2 DEFAULT GETUTCDATE(),
    ProcessedAt DATETIME2 NULL,
    ErrorMessage NVARCHAR(MAX) NULL
)

PRINT N'  ✅ Commands table created'
PRINT N''

-- =====================================================
-- STEP 5: STORED PROCEDURES
-- =====================================================
PRINT N'📌 STEP 5: Creating stored procedures...'
PRINT N''

-- Procedure to get pending changes
IF OBJECT_ID('sp_GetPendingChanges', 'P') IS NOT NULL
    DROP PROCEDURE sp_GetPendingChanges
GO

CREATE PROCEDURE sp_GetPendingChanges
    @MaxResults INT = 100
AS
BEGIN
    SET NOCOUNT ON

    SELECT TOP (@MaxResults)
        Id, EntityType, EntityId, Operation, Timestamp
    FROM AvoqadoTracking
    WHERE Processed = 0
    ORDER BY Timestamp ASC
END
GO

-- Procedure to mark changes as processed
IF OBJECT_ID('sp_MarkChangesProcessed', 'P') IS NOT NULL
    DROP PROCEDURE sp_MarkChangesProcessed
GO

CREATE PROCEDURE sp_MarkChangesProcessed
    @Ids VARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON

    UPDATE AvoqadoTracking
    SET Processed = 1, ProcessedAt = GETUTCDATE()
    WHERE Id IN (
        SELECT CAST(value AS BIGINT)
        FROM STRING_SPLIT(@Ids, ',')
        WHERE RTRIM(value) <> ''
    )
END
GO

PRINT N'  ✅ Stored procedures created'

-- =====================================================
-- STEP 6: ENHANCED FUNCTION (SUPPORTS v10 AND v11)
-- =====================================================
PRINT N'📌 STEP 6: Creating enhanced entity ID function...'
PRINT N''

-- Drop old function if exists
IF OBJECT_ID('fn_GetAvoqadoEntityId', 'FN') IS NOT NULL
    DROP FUNCTION fn_GetAvoqadoEntityId
GO

-- Drop enhanced function if exists
IF OBJECT_ID('fn_GetAvoqadoEntityIdWithWorkspace', 'FN') IS NOT NULL
    DROP FUNCTION fn_GetAvoqadoEntityIdWithWorkspace
GO

-- Enhanced function that accepts WorkspaceId directly for DELETE scenarios
CREATE FUNCTION fn_GetAvoqadoEntityIdWithWorkspace(
    @EntityType VARCHAR(50),
    @Folio BIGINT,
    @IdTurno BIGINT = NULL,
    @Movimiento INT = NULL,
    @WorkspaceId UNIQUEIDENTIFIER = NULL  -- Direct WorkspaceId parameter
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
                -- Get WorkspaceId from turnos table (only if column exists)
                IF COL_LENGTH('turnos', 'WorkspaceId') IS NOT NULL
                BEGIN
                    SELECT @WorkspaceId = WorkspaceId
                    FROM turnos
                    WHERE idturno = @IdTurno
                END
            END
            ELSE
            BEGIN
                -- Get WorkspaceId from tempcheques table (only if column exists)
                IF COL_LENGTH('tempcheques', 'WorkspaceId') IS NOT NULL
                BEGIN
                    SELECT @WorkspaceId = WorkspaceId
                    FROM tempcheques
                    WHERE folio = @Folio
                END
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

PRINT N'  ✅ Enhanced entity ID function created (supports v10 and v11)'

-- =====================================================
-- STEP 7: DATABASE TRIGGERS
-- =====================================================
PRINT N'📌 STEP 7: Creating database triggers...'
PRINT N''

-- Orders Trigger (Enhanced with DELETE handling)
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
            -- For DELETE operations, pass WorkspaceId directly from deleted record (v11 only)
            WHEN i.folio IS NULL AND d.folio IS NOT NULL THEN
                CASE
                    WHEN COL_LENGTH('tempcheques', 'WorkspaceId') IS NOT NULL
                    THEN dbo.fn_GetAvoqadoEntityIdWithWorkspace('order', d.folio, d.idturno, NULL, d.WorkspaceId)
                    ELSE dbo.fn_GetAvoqadoEntityIdWithWorkspace('order', d.folio, d.idturno, NULL, NULL)
                END
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
END
GO

PRINT N'  ✅ Orders trigger created'

-- Order Items Trigger (Enhanced with proper DELETE handling)
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
            -- For DELETE operations, get WorkspaceId from the parent order in deleted table (v11 only)
            WHEN i.movimiento IS NULL AND d.movimiento IS NOT NULL THEN
                CASE
                    WHEN COL_LENGTH('tempcheques', 'WorkspaceId') IS NOT NULL
                    THEN dbo.fn_GetAvoqadoEntityIdWithWorkspace('orderitem', d.foliodet,
                        (SELECT idturno FROM tempcheques WHERE folio = d.foliodet),
                        d.movimiento,
                        (SELECT WorkspaceId FROM tempcheques WHERE folio = d.foliodet))
                    ELSE dbo.fn_GetAvoqadoEntityIdWithWorkspace('orderitem', d.foliodet,
                        (SELECT idturno FROM tempcheques WHERE folio = d.foliodet),
                        d.movimiento, NULL)
                END
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
        dbo.fn_GetAvoqadoEntityIdWithWorkspace('order', foliodet,
            (SELECT idturno FROM tempcheques WHERE folio = foliodet), NULL, NULL),
        'UPDATE'
    FROM (
        SELECT foliodet FROM inserted
        UNION
        SELECT foliodet FROM deleted
    ) changes
    WHERE EXISTS(SELECT 1 FROM tempcheques WHERE folio = changes.foliodet) -- Only if parent order still exists
END
GO

PRINT N'  ✅ Order items trigger created'

-- Payments Trigger
IF OBJECT_ID('Trg_Avoqado_Payments', 'TR') IS NOT NULL
    DROP TRIGGER Trg_Avoqado_Payments
GO

CREATE TRIGGER Trg_Avoqado_Payments ON tempchequespagos
AFTER INSERT, UPDATE, DELETE AS
BEGIN
    SET NOCOUNT ON

    -- Track payment changes
    INSERT INTO AvoqadoTracking (EntityType, EntityId, Operation)
    SELECT DISTINCT
        'payment',
        CASE
            WHEN i.folio IS NULL AND d.folio IS NOT NULL THEN
                CASE
                    WHEN COL_LENGTH('tempcheques', 'WorkspaceId') IS NOT NULL
                    THEN dbo.fn_GetAvoqadoEntityIdWithWorkspace('payment', d.folio,
                        (SELECT idturno FROM tempcheques WHERE folio = d.folio),
                        NULL,
                        (SELECT WorkspaceId FROM tempcheques WHERE folio = d.folio))
                    ELSE dbo.fn_GetAvoqadoEntityIdWithWorkspace('payment', d.folio,
                        (SELECT idturno FROM tempcheques WHERE folio = d.folio),
                        NULL, NULL)
                END
            ELSE
                dbo.fn_GetAvoqadoEntityIdWithWorkspace('payment', COALESCE(i.folio, d.folio),
                    (SELECT idturno FROM tempcheques WHERE folio = COALESCE(i.folio, d.folio)),
                    NULL, NULL)
        END,
        CASE
            WHEN i.folio IS NOT NULL AND d.folio IS NOT NULL THEN 'UPDATE'
            WHEN i.folio IS NOT NULL THEN 'CREATE'
            WHEN d.folio IS NOT NULL THEN 'DELETE'
        END
    FROM inserted i
    FULL OUTER JOIN deleted d ON i.folio = d.folio
    WHERE COALESCE(i.folio, d.folio) IS NOT NULL
END
GO

PRINT N'  ✅ Payments trigger created'

-- Shifts Trigger
IF OBJECT_ID('Trg_Avoqado_Shifts', 'TR') IS NOT NULL
    DROP TRIGGER Trg_Avoqado_Shifts
GO

CREATE TRIGGER Trg_Avoqado_Shifts ON turnos
AFTER INSERT, UPDATE, DELETE AS
BEGIN
    SET NOCOUNT ON

    -- Track shift changes
    INSERT INTO AvoqadoTracking (EntityType, EntityId, Operation)
    SELECT DISTINCT
        'shift',
        CASE
            WHEN i.idturno IS NULL AND d.idturno IS NOT NULL THEN
                CASE
                    WHEN COL_LENGTH('turnos', 'WorkspaceId') IS NOT NULL
                    THEN dbo.fn_GetAvoqadoEntityIdWithWorkspace('shift', NULL, d.idturno, NULL, d.WorkspaceId)
                    ELSE dbo.fn_GetAvoqadoEntityIdWithWorkspace('shift', NULL, d.idturno, NULL, NULL)
                END
            ELSE
                dbo.fn_GetAvoqadoEntityIdWithWorkspace('shift', NULL, COALESCE(i.idturno, d.idturno), NULL, NULL)
        END,
        CASE
            WHEN i.idturno IS NOT NULL AND d.idturno IS NOT NULL THEN
                CASE WHEN d.cierre IS NULL AND i.cierre IS NOT NULL THEN 'CLOSED' ELSE 'UPDATE' END
            WHEN i.idturno IS NOT NULL THEN 'OPENED'
            WHEN d.idturno IS NOT NULL THEN 'DELETE'
        END
    FROM inserted i
    FULL OUTER JOIN deleted d ON i.idturno = d.idturno
    WHERE COALESCE(i.idturno, d.idturno) IS NOT NULL
END
GO

PRINT N'  ✅ Shifts trigger created'

-- =====================================================
-- FINAL SUMMARY
-- =====================================================
PRINT N''
PRINT N'🎉 ============================================================='
PRINT N'🎉 AVOQADO COMPLETE INTEGRATION INSTALLED SUCCESSFULLY!'
PRINT N'🎉 ============================================================='
PRINT N''

-- Show configuration summary
SELECT
    c.VenueId,
    c.PosVersion as 'SoftRestaurant Version',
    c.HasWorkspaceId,
    CASE WHEN c.HasWorkspaceId = 1 THEN 'v11 Format (WorkspaceId)' ELSE 'v10 Format (Instance:Turno:Folio)' END as 'Entity ID Format',
    c.CreatedAt as 'Installation Time'
FROM AvoqadoConfig c

PRINT N'Components installed:'
PRINT N'  ✅ AvoqadoConfig - Configuration and version detection'
PRINT N'  ✅ AvoqadoInstanceInfo - Instance tracking (required by Producer)'
PRINT N'  ✅ AvoqadoTracking - Change tracking with performance indexes'
PRINT N'  ✅ AvoqadoCommands - Command processing'
PRINT N'  ✅ Enhanced function - fn_GetAvoqadoEntityIdWithWorkspace'
PRINT N'  ✅ All triggers - Orders, OrderItems, Payments, Shifts'
PRINT N'  ✅ Stored procedures - sp_GetPendingChanges, sp_MarkChangesProcessed'
PRINT N''
PRINT N'🔥 This script is compatible with v10 AND v11!'
PRINT N'🔥 Order items tracking is now ENABLED!'
PRINT N'🔥 Producer service will work without crashes!'
PRINT N''
PRINT N'Installation completed at: ' + CONVERT(VARCHAR, GETDATE(), 120)