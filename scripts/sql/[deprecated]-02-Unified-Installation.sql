-- ====================================================================
-- AVOQADO UNIFIED INSTALLATION SCRIPT
-- SQL Server 2014 Compatible
--
-- VERSION: 3.0.0
-- DATE: 2025-09-23
--
-- PURPOSE:
-- Single source of truth for Avoqado-SoftRestaurant integration.
-- Works seamlessly across v10, v11, v12+ with automatic version detection.
-- Minimal database footprint with maximum reliability.
--
-- COMPATIBLE WITH: SQL Server 2014 Express (v12.0)
-- AFFECTS: SoftRestaurant v10, v11, v12+
-- ====================================================================

PRINT N'🚀 ============================================================='
PRINT N'🚀 AVOQADO UNIFIED INTEGRATION v3.0'
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

-- Parse version (handle formats like "11.0097" or "10.15")
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
-- STEP 2: MINIMAL TRACKING TABLE
-- =====================================================
PRINT N'📌 STEP 2: Creating tracking table...'
PRINT N''

IF OBJECT_ID('AvoqadoTracking', 'U') IS NOT NULL
BEGIN
    PRINT N'  ⚠️ AvoqadoTracking already exists, dropping and recreating...'
    DROP TABLE AvoqadoTracking
END

CREATE TABLE AvoqadoTracking (
    Id BIGINT IDENTITY(1,1) PRIMARY KEY,
    EntityType VARCHAR(50) NOT NULL,
    EntityId VARCHAR(200) NOT NULL,
    Operation VARCHAR(20) NOT NULL,
    Timestamp DATETIME2 DEFAULT GETUTCDATE(),
    ProcessedAt DATETIME2 NULL,
    RetryCount INT DEFAULT 0,
    ErrorMsg NVARCHAR(MAX) NULL
)

-- Create separate index for pending records
CREATE INDEX IX_Pending ON AvoqadoTracking(ProcessedAt, Timestamp)

PRINT N'  ✅ Tracking table created with optimized index'
PRINT N''

-- =====================================================
-- STEP 3: COMMAND QUEUE TABLE
-- =====================================================
PRINT N'📌 STEP 3: Creating command queue...'
PRINT N''

IF OBJECT_ID('AvoqadoCommands', 'U') IS NOT NULL
BEGIN
    PRINT N'  ⚠️ AvoqadoCommands already exists, dropping and recreating...'
    DROP TABLE AvoqadoCommands
END

CREATE TABLE AvoqadoCommands (
    Id BIGINT IDENTITY(1,1) PRIMARY KEY,
    CommandId UNIQUEIDENTIFIER DEFAULT NEWID(),
    CommandType VARCHAR(50) NOT NULL,
    Payload NVARCHAR(MAX) NOT NULL,
    ReceivedAt DATETIME2 DEFAULT GETUTCDATE(),
    ExecutedAt DATETIME2 NULL,
    Status VARCHAR(20) DEFAULT 'PENDING',
    Result NVARCHAR(MAX) NULL
)

-- Create separate index for pending commands
CREATE INDEX IX_Commands_Pending ON AvoqadoCommands(Status, ReceivedAt)

PRINT N'  ✅ Command queue created'
PRINT N''

-- =====================================================
-- STEP 4: VERSION-ADAPTIVE ENTITY ID FUNCTION
-- =====================================================
PRINT N'📌 STEP 4: Creating Entity ID function...'
PRINT N''

IF OBJECT_ID('fn_GetAvoqadoEntityId', 'FN') IS NOT NULL
    DROP FUNCTION fn_GetAvoqadoEntityId
GO

CREATE FUNCTION fn_GetAvoqadoEntityId(
    @EntityType VARCHAR(50),
    @Folio BIGINT,
    @IdTurno BIGINT = NULL,
    @Movimiento INT = NULL
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
        DECLARE @WorkspaceId UNIQUEIDENTIFIER

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

        -- Generate Entity ID based on type
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

PRINT N'  ✅ Entity ID function created (version-adaptive)'
PRINT N''

-- =====================================================
-- STEP 5: SMART TRIGGERS (MINIMAL & EFFICIENT)
-- =====================================================
PRINT N'📌 STEP 5: Creating smart triggers...'
PRINT N''

-- Orders Trigger
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

    -- Track changes efficiently
    INSERT INTO AvoqadoTracking (EntityType, EntityId, Operation)
    SELECT DISTINCT
        'order',
        dbo.fn_GetAvoqadoEntityId('order', COALESCE(i.folio, d.folio), COALESCE(i.idturno, d.idturno), NULL),
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

-- Order Items Trigger (simplified)
IF OBJECT_ID('Trg_Avoqado_OrderItems', 'TR') IS NOT NULL
    DROP TRIGGER Trg_Avoqado_OrderItems
GO

CREATE TRIGGER Trg_Avoqado_OrderItems ON tempcheqdet
AFTER INSERT, UPDATE, DELETE AS
BEGIN
    SET NOCOUNT ON

    -- Track item changes
    INSERT INTO AvoqadoTracking (EntityType, EntityId, Operation)
    SELECT DISTINCT
        'orderitem',
        dbo.fn_GetAvoqadoEntityId('orderitem', COALESCE(i.foliodet, d.foliodet),
            (SELECT idturno FROM tempcheques WHERE folio = COALESCE(i.foliodet, d.foliodet)),
            COALESCE(i.movimiento, d.movimiento)),
        CASE
            WHEN i.movimiento IS NOT NULL AND d.movimiento IS NOT NULL THEN 'UPDATE'
            WHEN i.movimiento IS NOT NULL THEN 'CREATE'
            WHEN d.movimiento IS NOT NULL THEN 'DELETE'
        END
    FROM inserted i
    FULL OUTER JOIN deleted d ON i.foliodet = d.foliodet AND i.movimiento = d.movimiento
    WHERE COALESCE(i.movimiento, d.movimiento) IS NOT NULL

    -- Also mark order as updated
    INSERT INTO AvoqadoTracking (EntityType, EntityId, Operation)
    SELECT DISTINCT
        'order',
        dbo.fn_GetAvoqadoEntityId('order', folio,
            (SELECT idturno FROM tempcheques WHERE folio = foliodet), NULL),
        'UPDATE'
    FROM (
        SELECT foliodet as folio FROM inserted
        UNION
        SELECT foliodet as folio FROM deleted
    ) changes
END
GO

PRINT N'  ✅ Order items trigger created'

-- Payment Trigger (for reconciliation)
IF OBJECT_ID('Trg_Avoqado_Payments', 'TR') IS NOT NULL
    DROP TRIGGER Trg_Avoqado_Payments
GO

CREATE TRIGGER Trg_Avoqado_Payments ON tempchequespagos
AFTER INSERT AS
BEGIN
    SET NOCOUNT ON

    -- Track payment for reconciliation
    INSERT INTO AvoqadoTracking (EntityType, EntityId, Operation)
    SELECT
        'payment',
        dbo.fn_GetAvoqadoEntityId('payment', i.folio, NULL, NULL),
        'CREATE'
    FROM inserted i
END
GO

PRINT N'  ✅ Payment trigger created'

-- Shift Trigger (open/close events only)
IF OBJECT_ID('Trg_Avoqado_Shifts', 'TR') IS NOT NULL
    DROP TRIGGER Trg_Avoqado_Shifts
GO

CREATE TRIGGER Trg_Avoqado_Shifts ON turnos
AFTER INSERT, UPDATE AS
BEGIN
    SET NOCOUNT ON

    -- Track shift open
    IF EXISTS(SELECT 1 FROM inserted WHERE cierre IS NULL)
    BEGIN
        INSERT INTO AvoqadoTracking (EntityType, EntityId, Operation)
        SELECT
            'shift',
            dbo.fn_GetAvoqadoEntityId('shift', NULL, i.idturno, NULL),
            'OPENED'
        FROM inserted i
        WHERE i.cierre IS NULL
    END

    -- Track shift close
    IF UPDATE(cierre)
    BEGIN
        INSERT INTO AvoqadoTracking (EntityType, EntityId, Operation)
        SELECT
            'shift',
            dbo.fn_GetAvoqadoEntityId('shift', NULL, i.idturno, NULL),
            'CLOSED'
        FROM inserted i
        INNER JOIN deleted d ON i.idturno = d.idturno
        WHERE d.cierre IS NULL AND i.cierre IS NOT NULL
    END
END
GO

PRINT N'  ✅ Shift trigger created'
PRINT N''

-- =====================================================
-- STEP 6: PARTIAL PAYMENT STORED PROCEDURE
-- =====================================================
PRINT N'📌 STEP 6: Creating partial payment procedure...'
PRINT N''

IF OBJECT_ID('sp_ApplyPartialPayment', 'P') IS NOT NULL
    DROP PROCEDURE sp_ApplyPartialPayment
GO

CREATE PROCEDURE sp_ApplyPartialPayment
    @Folio BIGINT,
    @PaymentAmount MONEY,
    @TipAmount MONEY = 0,
    @PaymentMethod VARCHAR(50),
    @Reference VARCHAR(255) = NULL,
    @Success BIT OUTPUT,
    @Message NVARCHAR(500) OUTPUT,
    @Remaining MONEY OUTPUT
AS
BEGIN
    SET NOCOUNT ON

    BEGIN TRY
        BEGIN TRANSACTION

        -- Validate order exists
        IF NOT EXISTS(SELECT 1 FROM tempcheques WHERE folio = @Folio)
        BEGIN
            SET @Success = 0
            SET @Message = 'Order not found: ' + CAST(@Folio AS VARCHAR)
            SET @Remaining = 0
            ROLLBACK
            RETURN
        END

        -- Get current order state
        DECLARE @OrderTotal MONEY, @PaidSoFar MONEY, @CurrentObservaciones VARCHAR(250)

        SELECT
            @OrderTotal = total,
            @CurrentObservaciones = ISNULL(observaciones, '')
        FROM tempcheques
        WHERE folio = @Folio

        SELECT @PaidSoFar = ISNULL(SUM(importe), 0)
        FROM tempchequespagos
        WHERE folio = @Folio

        -- Calculate remaining after this payment
        SET @Remaining = @OrderTotal - (@PaidSoFar + @PaymentAmount)

        IF @Remaining > 0.01  -- Partial payment (allowing for rounding)
        BEGIN
            -- PARTIAL PAYMENT: Adjust quantities proportionally
            DECLARE @RemainingRatio DECIMAL(10,6) = @Remaining / @OrderTotal

            -- Update item quantities to reflect remaining amount
            UPDATE tempcheqdet
            SET cantidad = CAST(cantidad * @RemainingRatio AS DECIMAL(10,4))
            WHERE foliodet = @Folio

            -- Update order totals
            DECLARE @NewSubtotal MONEY = @Remaining / 1.16  -- Assuming 16% tax
            DECLARE @NewTax MONEY = @Remaining - @NewSubtotal

            -- Build payment note for observaciones
            DECLARE @PaymentNote VARCHAR(50)
            SET @PaymentNote = 'Pago: $' + CAST(@PaymentAmount AS VARCHAR) +
                              ' (' + LEFT(@PaymentMethod, 3) + ') ' +
                              CONVERT(VARCHAR(5), GETDATE(), 108)

            -- Update order with new totals and payment note
            UPDATE tempcheques
            SET total = @Remaining,
                subtotal = @NewSubtotal,
                totalimpuesto1 = @NewTax,
                totalconpropina = @Remaining,
                totalsindescuento = @Remaining,
                totalsindescuentoimp = @Remaining,
                totalconpropinacargo = @Remaining,
                totalconcargo = @Remaining,
                subtotalcondescuento = @NewSubtotal,
                subtotalsinimpuestos = @NewSubtotal,
                observaciones = CASE
                    WHEN LEN(@CurrentObservaciones + ' | ' + @PaymentNote) <= 250
                    THEN @CurrentObservaciones + CASE WHEN @CurrentObservaciones = '' THEN '' ELSE ' | ' END + @PaymentNote
                    ELSE @PaymentNote  -- Start fresh if too long
                END
            WHERE folio = @Folio

            SET @Success = 1
            SET @Message = 'Partial payment applied. Remaining: $' + CAST(@Remaining AS VARCHAR)
        END
        ELSE
        BEGIN
            -- FULL PAYMENT: Insert payment and close order
            INSERT INTO tempchequespagos (folio, idformadepago, importe, propina, referencia)
            VALUES (@Folio, @PaymentMethod, @PaymentAmount, @TipAmount, @Reference)

            -- Mark order as paid
            UPDATE tempcheques
            SET pagado = 1,
                observaciones = CASE
                    WHEN LEN(@CurrentObservaciones) < 200
                    THEN @CurrentObservaciones + CASE WHEN @CurrentObservaciones = '' THEN '' ELSE ' | ' END + 'PAGADO'
                    ELSE 'PAGADO'
                END
            WHERE folio = @Folio

            SET @Success = 1
            SET @Message = 'Order fully paid'
            SET @Remaining = 0
        END

        -- Track this payment in Avoqado system
        INSERT INTO AvoqadoTracking (EntityType, EntityId, Operation)
        VALUES ('payment', dbo.fn_GetAvoqadoEntityId('payment', @Folio, NULL, NULL), 'APPLIED')

        COMMIT TRANSACTION

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK

        SET @Success = 0
        SET @Message = ERROR_MESSAGE()
        SET @Remaining = -1
    END CATCH
END
GO

PRINT N'  ✅ Partial payment procedure created'
PRINT N''

-- =====================================================
-- STEP 7: HELPER STORED PROCEDURES
-- =====================================================
PRINT N'📌 STEP 7: Creating helper procedures...'
PRINT N''

-- Get pending changes for sync
IF OBJECT_ID('sp_GetPendingChanges', 'P') IS NOT NULL
    DROP PROCEDURE sp_GetPendingChanges
GO

CREATE PROCEDURE sp_GetPendingChanges
    @MaxResults INT = 100
AS
BEGIN
    SET NOCOUNT ON

    SELECT TOP (@MaxResults)
        Id,
        EntityType,
        EntityId,
        Operation,
        Timestamp,
        RetryCount
    FROM AvoqadoTracking
    WHERE ProcessedAt IS NULL
      AND RetryCount < 5  -- Max 5 retries
    ORDER BY Timestamp ASC
END
GO

PRINT N'  ✅ GetPendingChanges procedure created'

-- Mark changes as processed
IF OBJECT_ID('sp_MarkChangesProcessed', 'P') IS NOT NULL
    DROP PROCEDURE sp_MarkChangesProcessed
GO

CREATE PROCEDURE sp_MarkChangesProcessed
    @Ids VARCHAR(MAX)  -- Comma-separated list of IDs
AS
BEGIN
    SET NOCOUNT ON

    -- Update using dynamic SQL (safe for SQL 2014)
    DECLARE @sql NVARCHAR(MAX)
    SET @sql = 'UPDATE AvoqadoTracking SET ProcessedAt = GETUTCDATE() WHERE Id IN (' + @Ids + ')'
    EXEC sp_executesql @sql
END
GO

PRINT N'  ✅ MarkChangesProcessed procedure created'
PRINT N''

-- =====================================================
-- STEP 8: INITIAL CONFIGURATION
-- =====================================================
PRINT N'📌 STEP 8: Setting initial configuration...'
PRINT N''

-- Display configuration instructions
PRINT N'  ⚠️ IMPORTANT: Update VenueId in AvoqadoConfig table'
PRINT N'     Run: UPDATE AvoqadoConfig SET VenueId = ''your-venue-id'''
PRINT N''

-- Show current configuration
DECLARE @configInfo NVARCHAR(500)
SELECT @configInfo = 'InstanceId: ' + CAST(InstanceId AS VARCHAR(36)) +
                    ', Version: ' + CAST(PosVersion AS VARCHAR) +
                    ', WorkspaceId: ' + CASE WHEN HasWorkspaceId = 1 THEN 'YES' ELSE 'NO' END
FROM AvoqadoConfig

PRINT N'  Current config: ' + @configInfo
PRINT N''

-- =====================================================
-- COMPLETION
-- =====================================================
PRINT N'✅ ============================================================='
PRINT N'✅ INSTALLATION COMPLETE!'
PRINT N'✅ ============================================================='
PRINT N''
PRINT N'Installed components:'
PRINT N'  ✅ 1 Configuration table (AvoqadoConfig)'
PRINT N'  ✅ 1 Tracking table (AvoqadoTracking)'
PRINT N'  ✅ 1 Command queue (AvoqadoCommands)'
PRINT N'  ✅ 1 Entity ID function (fn_GetAvoqadoEntityId)'
PRINT N'  ✅ 4 Smart triggers (Orders, Items, Payments, Shifts)'
PRINT N'  ✅ 3 Stored procedures (Partial payments + helpers)'
PRINT N''
PRINT N'Version support:'
DECLARE @versionInfo VARCHAR(100)
SELECT @versionInfo = 'SoftRestaurant v' + CAST(PosVersion AS VARCHAR) +
                     CASE WHEN HasWorkspaceId = 1 THEN ' (Multi-tenant)' ELSE ' (Single-tenant)' END
FROM AvoqadoConfig
PRINT N'  ' + @versionInfo
PRINT N''
PRINT N'Next steps:'
PRINT N'  1. UPDATE AvoqadoConfig SET VenueId = ''your-venue-id'''
PRINT N'  2. Start Windows Service'
PRINT N'  3. Test with a simple order'
PRINT N''
PRINT N'Completed at: ' + CONVERT(VARCHAR, GETDATE(), 120)