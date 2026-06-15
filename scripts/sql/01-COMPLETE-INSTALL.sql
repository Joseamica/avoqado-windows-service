-- ====================================================================
-- REQUERIDO: la tabla AvoqadoTracking tiene un índice filtrado (IX_Pending).
-- Crear ese índice y hacer DML sobre la tabla (incl. dentro de triggers/SPs)
-- exige QUOTED_IDENTIFIER ON. sqlcmd por defecto lo deja OFF → error 1934.
-- Fijarlo aquí garantiza que TODO el script (y los objetos que crea, que
-- capturan estas opciones al crearse) corra correctamente, con o sin -I.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
-- ====================================================================
-- COMPLETE AVOQADO INSTALLATION - ALL IN ONE
-- Includes: Base + NULL Fix + SQL 2014 Fix + Payment Methods
-- SQL Server 2014 Compatible
-- ====================================================================
--
-- USAGE: This script will run on the CURRENT database context.
--        Make sure you're connected to the correct database before running!
--        Example: USE your_database_name; GO
-- ====================================================================

PRINT '======================================================================'
PRINT ' COMPLETE AVOQADO INSTALLATION - ALL IN ONE'
PRINT ' Includes: Tables, Functions, Procedures, Triggers, Payment Methods'
PRINT '======================================================================'
PRINT ''
PRINT 'Current Database: ' + DB_NAME()
PRINT 'Installation started at: ' + CONVERT(VARCHAR, GETDATE(), 120)
PRINT ''

-- =====================================================
-- STEP 1: CREATE PAYMENT METHODS
-- =====================================================
PRINT '📌 STEP 1: Creating payment methods...'

-- Create ACASH (based on cash/efectivo)
IF NOT EXISTS (SELECT 1 FROM formasdepago WHERE idformadepago = 'ACASH')
BEGIN
    DECLARE @RefCashId VARCHAR(10), @RefCashTipo INT, @RefCashTC DECIMAL(10,4), @RefCashWS UNIQUEIDENTIFIER
    DECLARE @RefCashSubtipo TINYINT
    SELECT TOP 1
        @RefCashId = idformadepago,
        @RefCashTipo = tipo,
        @RefCashTC = tipodecambio,
        @RefCashWS = WorkspaceId,
        @RefCashSubtipo = ISNULL(subtipo, 0)
    FROM formasdepago
    WHERE UPPER(descripcion) LIKE '%EFECTIVO%' OR UPPER(descripcion) LIKE '%CASH%' OR idformadepago IN ('AEF', '01', 'EF')

    IF @RefCashId IS NOT NULL
        INSERT INTO formasdepago (idformadepago, descripcion, tipo, tipodecambio, solicitareferencia, visible, subtipo, WorkspaceId)
        VALUES ('ACASH', 'AVOQADO CASH', @RefCashTipo, @RefCashTC, 0, 1, @RefCashSubtipo, @RefCashWS)
    ELSE
        INSERT INTO formasdepago (idformadepago, descripcion, tipo, tipodecambio, solicitareferencia, visible, subtipo)
        VALUES ('ACASH', 'AVOQADO CASH', 1, 1, 0, 1, 0)
    PRINT '  ✅ Created ACASH payment method'
END
ELSE
    PRINT '  ✅ ACASH already exists'

-- Create ACARD (based on AMEX)
IF NOT EXISTS (SELECT 1 FROM formasdepago WHERE idformadepago = 'ACARD')
BEGIN
    DECLARE @RefCardId VARCHAR(10), @RefCardTipo INT, @RefCardTC DECIMAL(10,4), @RefCardWS UNIQUEIDENTIFIER
    DECLARE @RefCardSubtipo TINYINT, @RefCardTipoBancaria TINYINT
    SELECT TOP 1
        @RefCardId = idformadepago,
        @RefCardTipo = tipo,
        @RefCardTC = tipodecambio,
        @RefCardWS = WorkspaceId,
        @RefCardSubtipo = subtipo,
        @RefCardTipoBancaria = tipoTarjetaBancaria
    FROM formasdepago
    WHERE idformadepago = 'AMEX' OR idformadepago = '09' OR UPPER(descripcion) LIKE '%AMEX%' OR UPPER(descripcion) LIKE '%AMERICAN EXPRESS%'

    IF @RefCardId IS NOT NULL
        INSERT INTO formasdepago (idformadepago, descripcion, tipo, tipodecambio, solicitareferencia, visible, subtipo, tipoTarjetaBancaria, WorkspaceId)
        VALUES ('ACARD', 'AVOQADO CARD', @RefCardTipo, @RefCardTC, 0, 1, @RefCardSubtipo, @RefCardTipoBancaria, @RefCardWS)
    ELSE
        INSERT INTO formasdepago (idformadepago, descripcion, tipo, tipodecambio, solicitareferencia, visible, subtipo, tipoTarjetaBancaria)
        VALUES ('ACARD', 'AVOQADO CARD', 2, 1, 0, 1, 0, 1)
    PRINT '  ✅ Created ACARD payment method'
END
ELSE
    PRINT '  ✅ ACARD already exists'

PRINT ''

-- =====================================================
-- STEP 1.5: CREATE AVOQADO TEST PRODUCT
-- =====================================================
PRINT '📌 STEP 1.5: Creating Avoqado test product...'

-- Create AVOTEST product (hidden from POS, for testing only)
IF NOT EXISTS (SELECT 1 FROM productos WHERE idproducto = 'AVOTEST')
BEGIN
    DECLARE @RefProductWS UNIQUEIDENTIFIER, @RefProductGroup VARCHAR(15)
    SELECT TOP 1 @RefProductWS = WorkspaceId FROM productos WHERE WorkspaceId IS NOT NULL
    SELECT TOP 1 @RefProductGroup = idgrupo FROM grupos ORDER BY idgrupo

    INSERT INTO productos (
        idproducto, descripcion, idgrupo, nombrecorto,
        nofacturable, usarcomedor, usardomicilio, usarrapido, usarcedis,
        usarmenuelectronico, visible_menu, WorkspaceId
    ) VALUES (
        'AVOTEST',
        '⚠️ AVOQADO TEST PRODUCT - DO NOT USE IN REAL ORDERS',
        @RefProductGroup,  -- Use first available group
        'AVOTEST',
        0,  -- Not billable
        0,  -- Not for dine-in
        0,  -- Not for delivery
        0,  -- Not for quick service
        0,  -- Not for CEDIS
        0,  -- Not for electronic menu
        0,  -- Hidden from menu
        @RefProductWS
    )
    PRINT '  ✅ Created AVOTEST product (hidden, for testing only)'
END
ELSE
    PRINT '  ✅ AVOTEST product already exists'

PRINT ''

-- =====================================================
-- STEP 2: SQL SERVER 2014 COMPATIBILITY
-- =====================================================
PRINT '📌 STEP 2: SQL Server 2014 compatibility...'

IF OBJECT_ID('fn_SplitString', 'TF') IS NOT NULL
    DROP FUNCTION fn_SplitString
GO

CREATE FUNCTION fn_SplitString (@String NVARCHAR(MAX), @Delimiter CHAR(1))
RETURNS @Result TABLE (value NVARCHAR(MAX))
AS BEGIN
    DECLARE @StartIndex INT, @EndIndex INT
    SET @StartIndex = 1
    IF SUBSTRING(@String, LEN(@String) - 1, LEN(@String)) <> @Delimiter
        SET @String = @String + @Delimiter
    WHILE CHARINDEX(@Delimiter, @String) > 0
    BEGIN
        SET @EndIndex = CHARINDEX(@Delimiter, @String)
        INSERT INTO @Result(value) SELECT SUBSTRING(@String, @StartIndex, @EndIndex - 1)
        SET @String = SUBSTRING(@String, @EndIndex + 1, LEN(@String))
    END
    RETURN
END
GO
PRINT '  ✅ Created fn_SplitString'

-- =====================================================
-- STEP 3: CORE TABLES
-- =====================================================
PRINT '📌 STEP 3: Creating core tables...'

IF OBJECT_ID('AvoqadoInstanceInfo', 'U') IS NULL
BEGIN
    CREATE TABLE AvoqadoInstanceInfo (
        InstanceId UNIQUEIDENTIFIER DEFAULT NEWID() PRIMARY KEY,
        CreatedAt DATETIME2 DEFAULT GETUTCDATE()
    )
    INSERT INTO AvoqadoInstanceInfo DEFAULT VALUES
    PRINT '  ✅ Created AvoqadoInstanceInfo'
END

IF OBJECT_ID('AvoqadoConfig', 'U') IS NOT NULL DROP TABLE AvoqadoConfig
CREATE TABLE AvoqadoConfig (
    InstanceId UNIQUEIDENTIFIER DEFAULT NEWID() PRIMARY KEY,
    VenueId VARCHAR(50) NOT NULL,
    PosVersion DECIMAL(10,4) NULL,
    HasWorkspaceId BIT DEFAULT 0,
    CreatedAt DATETIME2 DEFAULT GETUTCDATE(),
    LastHeartbeat DATETIME2 NULL,
    Config NVARCHAR(MAX) NULL
)

DECLARE @version DECIMAL(10,4), @versionString VARCHAR(50), @hasWorkspace BIT = 0
SELECT @versionString = versiondb FROM parametros2
IF @versionString IS NOT NULL
BEGIN
    DECLARE @majorVersion INT, @minorVersion INT
    SET @majorVersion = CAST(LEFT(@versionString, CHARINDEX('.', @versionString) - 1) AS INT)
    SET @minorVersion = CAST(SUBSTRING(@versionString, CHARINDEX('.', @versionString) + 1, 10) AS INT)
    SET @version = @majorVersion + (@minorVersion * 0.0001)
    PRINT '  ℹ️ Detected version: ' + @versionString
END
ELSE
    SET @version = 10.0

IF COL_LENGTH('tempcheques', 'WorkspaceId') IS NOT NULL
BEGIN
    SET @hasWorkspace = 1
    PRINT '  ℹ️ WorkspaceId: YES (v11)'
END
ELSE
    PRINT '  ℹ️ WorkspaceId: NO (v10)'

INSERT INTO AvoqadoConfig (VenueId, PosVersion, HasWorkspaceId)
VALUES ('PENDING_CONFIGURATION', @version, @hasWorkspace)
PRINT '  ✅ Created AvoqadoConfig'

IF OBJECT_ID('AvoqadoTracking', 'U') IS NOT NULL DROP TABLE AvoqadoTracking
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
CREATE INDEX IX_Pending ON AvoqadoTracking(ProcessedAt, Timestamp)
PRINT '  ✅ Created AvoqadoTracking'

IF OBJECT_ID('AvoqadoCommands', 'U') IS NOT NULL DROP TABLE AvoqadoCommands
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
CREATE INDEX IX_Commands_Pending ON AvoqadoCommands(Status, ReceivedAt)
PRINT '  ✅ Created AvoqadoCommands'

IF OBJECT_ID('AvoqadoDebugLog', 'U') IS NOT NULL DROP TABLE AvoqadoDebugLog
CREATE TABLE AvoqadoDebugLog (
    Id BIGINT IDENTITY(1,1) PRIMARY KEY,
    Folio BIGINT NULL,
    PaymentAmount MONEY NULL,
    TipAmount MONEY NULL,
    PaymentMethod VARCHAR(50) NULL,
    Reference VARCHAR(255) NULL,
    Message NVARCHAR(MAX) NULL,
    Timestamp DATETIME2 DEFAULT GETUTCDATE()
)
CREATE INDEX IX_DebugLog_Timestamp ON AvoqadoDebugLog(Timestamp DESC)
PRINT '  ✅ Created AvoqadoDebugLog'

IF OBJECT_ID('AvoqadoPartialPayments', 'U') IS NOT NULL DROP TABLE AvoqadoPartialPayments
CREATE TABLE AvoqadoPartialPayments (
    Id BIGINT IDENTITY(1,1) PRIMARY KEY,
    Folio BIGINT NOT NULL,
    Amount MONEY NOT NULL,
    TipAmount MONEY DEFAULT 0,
    PaymentMethodId VARCHAR(50) NOT NULL,
    Reference VARCHAR(255) NULL,
    CreatedAt DATETIME2 DEFAULT GETUTCDATE(),
    IsProcessed BIT DEFAULT 0,
    ProcessedAt DATETIME2 NULL
)
CREATE INDEX IX_PartialPayments_Folio ON AvoqadoPartialPayments(Folio, IsProcessed)
CREATE INDEX IX_PartialPayments_Processed ON AvoqadoPartialPayments(IsProcessed, CreatedAt)
PRINT '  ✅ Created AvoqadoPartialPayments'

IF OBJECT_ID('AvoqadoShiftArchiving', 'U') IS NOT NULL DROP TABLE AvoqadoShiftArchiving
CREATE TABLE AvoqadoShiftArchiving (
    IdTurno BIGINT PRIMARY KEY,
    IsArchiving BIT DEFAULT 1,
    StartedAt DATETIME2 DEFAULT GETUTCDATE(),
    CompletedAt DATETIME2 NULL
)
CREATE INDEX IX_ShiftArchiving_Active ON AvoqadoShiftArchiving(IsArchiving, StartedAt) WHERE IsArchiving = 1
PRINT '  ✅ Created AvoqadoShiftArchiving'

PRINT ''

-- =====================================================
-- STEP 4: ENTITY ID FUNCTION WITH NULL FIX
-- =====================================================
PRINT '📌 STEP 4: Creating Entity ID function (with NULL fix)...'

IF OBJECT_ID('fn_GetAvoqadoEntityIdWithWorkspace', 'FN') IS NOT NULL
    DROP FUNCTION fn_GetAvoqadoEntityIdWithWorkspace
GO

CREATE FUNCTION fn_GetAvoqadoEntityIdWithWorkspace(
    @EntityType VARCHAR(50),
    @Folio BIGINT,
    @IdTurno BIGINT = NULL,
    @Movimiento INT = NULL,
    @WorkspaceId UNIQUEIDENTIFIER = NULL
) RETURNS VARCHAR(200)
AS BEGIN
    DECLARE @EntityId VARCHAR(200), @HasWorkspace BIT, @InstanceId UNIQUEIDENTIFIER

    SELECT TOP 1 @HasWorkspace = HasWorkspaceId, @InstanceId = InstanceId FROM AvoqadoConfig

    IF @HasWorkspace = 1 AND @EntityType IN ('order', 'orderitem', 'shift', 'payment')
    BEGIN
        IF @WorkspaceId IS NULL
        BEGIN
            -- 🔧 FIX: Get WorkspaceId from the CORRECT table for each entity type
            IF @EntityType = 'shift'
                SELECT @WorkspaceId = WorkspaceId FROM turnos WHERE idturno = @IdTurno
            ELSE IF @EntityType = 'orderitem'
                SELECT @WorkspaceId = WorkspaceId FROM tempcheqdet WHERE foliodet = @Folio AND movimiento = @Movimiento
            ELSE IF @EntityType = 'payment'
                SELECT TOP 1 @WorkspaceId = WorkspaceId FROM tempchequespagos WHERE folio = @Folio ORDER BY WorkspaceId DESC
            ELSE
                SELECT @WorkspaceId = WorkspaceId FROM tempcheques WHERE folio = @Folio
        END

        IF @WorkspaceId IS NOT NULL
        BEGIN
            -- 🔧 FIX: For v11, Entity ID is JUST the WorkspaceId (no suffixes!)
            -- Each entity has its own unique WorkspaceId
            SET @EntityId = CAST(@WorkspaceId AS VARCHAR(36))
        END
        ELSE
        BEGIN
            SET @EntityId = CASE @EntityType
                WHEN 'order' THEN CAST(@InstanceId AS VARCHAR(36)) + ':' + ISNULL(CAST(@IdTurno AS VARCHAR), '0') + ':' + CAST(@Folio AS VARCHAR)
                WHEN 'orderitem' THEN CAST(@InstanceId AS VARCHAR(36)) + ':' + ISNULL(CAST(@IdTurno AS VARCHAR), '0') + ':' + CAST(@Folio AS VARCHAR) + ':' + CAST(@Movimiento AS VARCHAR)
                WHEN 'shift' THEN CAST(@IdTurno AS VARCHAR)
                WHEN 'payment' THEN CAST(@InstanceId AS VARCHAR(36)) + ':' + CAST(@Folio AS VARCHAR) + ':PAY'
                ELSE CAST(@InstanceId AS VARCHAR(36)) + ':' + CAST(@Folio AS VARCHAR)
            END
        END
    END
    ELSE
    BEGIN
        SET @EntityId = CASE @EntityType
            WHEN 'order' THEN CAST(@InstanceId AS VARCHAR(36)) + ':' + ISNULL(CAST(@IdTurno AS VARCHAR), '0') + ':' + CAST(@Folio AS VARCHAR)
            WHEN 'orderitem' THEN CAST(@InstanceId AS VARCHAR(36)) + ':' + ISNULL(CAST(@IdTurno AS VARCHAR), '0') + ':' + CAST(@Folio AS VARCHAR) + ':' + CAST(@Movimiento AS VARCHAR)
            WHEN 'shift' THEN CAST(@IdTurno AS VARCHAR)
            WHEN 'payment' THEN CAST(@InstanceId AS VARCHAR(36)) + ':' + CAST(@Folio AS VARCHAR) + ':PAY'
            ELSE CAST(@InstanceId AS VARCHAR(36)) + ':' + CAST(@Folio AS VARCHAR)
        END
    END

    RETURN @EntityId
END
GO
PRINT '  ✅ Created fn_GetAvoqadoEntityIdWithWorkspace'

PRINT ''

-- =====================================================
-- STEP 5: STORED PROCEDURES
-- =====================================================
PRINT '📌 STEP 5: Creating stored procedures...'

-- sp_GetPendingChanges
IF OBJECT_ID('sp_GetPendingChanges', 'P') IS NOT NULL DROP PROCEDURE sp_GetPendingChanges
GO
CREATE PROCEDURE sp_GetPendingChanges @MaxResults INT = 100
AS BEGIN
    SET NOCOUNT ON
    SELECT TOP (@MaxResults) Id, EntityType, EntityId, Operation, Timestamp, RetryCount
    FROM AvoqadoTracking
    WHERE ProcessedAt IS NULL AND RetryCount < 5
    ORDER BY Timestamp ASC
END
GO
PRINT '  ✅ Created sp_GetPendingChanges'

-- sp_MarkChangesProcessed (SQL 2014 compatible)
IF OBJECT_ID('sp_MarkChangesProcessed', 'P') IS NOT NULL DROP PROCEDURE sp_MarkChangesProcessed
GO
CREATE PROCEDURE sp_MarkChangesProcessed @Ids VARCHAR(MAX)
AS BEGIN
    SET NOCOUNT ON
    UPDATE AvoqadoTracking SET ProcessedAt = GETUTCDATE()
    WHERE Id IN (SELECT CAST(value AS BIGINT) FROM fn_SplitString(@Ids, ',') WHERE RTRIM(LTRIM(value)) <> '')
END
GO
PRINT '  ✅ Created sp_MarkChangesProcessed'

-- sp_ApplyPartialPayment (with payment logic that updates totals)
IF OBJECT_ID('sp_ApplyPartialPayment', 'P') IS NOT NULL DROP PROCEDURE sp_ApplyPartialPayment
GO
CREATE PROCEDURE sp_ApplyPartialPayment
    @Folio BIGINT, @PaymentAmount MONEY, @TipAmount MONEY = 0, @PaymentMethod VARCHAR(50),
    @Reference VARCHAR(255) = NULL, @Success BIT OUTPUT, @Message NVARCHAR(500) OUTPUT, @Remaining MONEY OUTPUT
AS BEGIN
    SET NOCOUNT ON

    -- 🔍 DEBUG: Log all parameters immediately
    INSERT INTO AvoqadoDebugLog (Folio, PaymentAmount, TipAmount, PaymentMethod, Reference, Message)
    VALUES (@Folio, @PaymentAmount, @TipAmount, @PaymentMethod, @Reference, 'Procedure called with these parameters')

    BEGIN TRY
        BEGIN TRANSACTION
        IF NOT EXISTS(SELECT 1 FROM tempcheques WHERE folio = @Folio)
        BEGIN
            SET @Success = 0
            SET @Message = 'Order not found'
            SET @Remaining = 0
            ROLLBACK
            RETURN
        END

        DECLARE @OrderTotal MONEY, @PaidSoFar MONEY, @CurrentObservaciones VARCHAR(250), @WorkspaceId UNIQUEIDENTIFIER, @CurrentIdTurno BIGINT
        DECLARE @OriginalSubtotal MONEY, @OriginalTax MONEY
        SELECT @OrderTotal = total, @CurrentObservaciones = ISNULL(observaciones, ''), @WorkspaceId = WorkspaceId, @CurrentIdTurno = idturno,
               @OriginalSubtotal = subtotal, @OriginalTax = totalimpuesto1
        FROM tempcheques WHERE folio = @Folio

        -- 🛡️ IDEMPOTENCY (H-7): RabbitMQ is at-least-once. A redelivered Payment.APPLY with the same
        -- reference must NOT insert a second payment nor re-scale items. Short-circuit if already applied.
        IF @Reference IS NOT NULL AND LTRIM(RTRIM(@Reference)) <> ''
           AND EXISTS (SELECT 1 FROM tempchequespagos WHERE folio = @Folio AND referencia = @Reference)
        BEGIN
            SET @Success = 1
            SET @Message = 'Pago ya aplicado previamente (idempotente)'
            SET @Remaining = @OrderTotal
            IF @@TRANCOUNT > 0 ROLLBACK
            INSERT INTO AvoqadoDebugLog (Folio, PaymentAmount, Reference, Message)
            VALUES (@Folio, @PaymentAmount, @Reference, 'IDEMPOTENT: reference already applied to this folio, skipped')
            RETURN
        END

        -- 🔧 CRITICAL FIX: If order has idturno=0, assign it to current open shift
        -- This ensures the order appears in shift reports (corte de caja X)
        IF @CurrentIdTurno = 0
        BEGIN
            DECLARE @OpenShiftId BIGINT
            SELECT @OpenShiftId = idturno FROM turnos WHERE cierre IS NULL

            IF @OpenShiftId IS NULL
            BEGIN
                SET @Success = 0
                SET @Message = 'ERROR: No open shift found. Cannot apply payment.'
                SET @Remaining = 0
                INSERT INTO AvoqadoDebugLog (Folio, PaymentAmount, Message)
                VALUES (@Folio, @PaymentAmount, 'ERROR: No open shift found')
                ROLLBACK
                RETURN
            END

            -- Update order to current open shift
            UPDATE tempcheques SET idturno = @OpenShiftId WHERE folio = @Folio

            INSERT INTO AvoqadoDebugLog (Folio, PaymentAmount, Message)
            VALUES (@Folio, @PaymentAmount, 'Order assigned to shift ' + CAST(@OpenShiftId AS VARCHAR))
        END

        SELECT @PaidSoFar = ISNULL(SUM(importe), 0) FROM tempchequespagos WHERE folio = @Folio
        -- 🔧 C-1 FIX: tempcheques.total is the OUTSTANDING balance — each partial already reduced it.
        -- Remaining = current balance - THIS payment. The previous formula also subtracted @PaidSoFar,
        -- double-counting prior payments (e.g. 2x$7 on $75 → showed $54 remaining instead of $61),
        -- causing balance drift and premature pagado=1 (under-collection). @PaidSoFar is kept for logging only.
        SET @Remaining = @OrderTotal - @PaymentAmount

        -- 🔍 DEBUG: Log calculation details
        INSERT INTO AvoqadoDebugLog (Folio, PaymentAmount, Message)
        VALUES (@Folio, @PaymentAmount,
                'OrderTotal=' + CAST(@OrderTotal AS VARCHAR) +
                ', PaidSoFar=' + CAST(@PaidSoFar AS VARCHAR) +
                ', Remaining=' + CAST(@Remaining AS VARCHAR))

        -- ALWAYS insert payment record (critical for shift reports)
        -- CRITICAL FIX: Use order's WorkspaceId (not NEWID) to ensure archiving works correctly
        -- CRITICAL FIX: Use @PaymentMethod parameter (not hardcoded 'ACASH')
        INSERT INTO tempchequespagos (folio, idformadepago, importe, propina, referencia, tipodecambio, WorkspaceId)
        VALUES (@Folio, @PaymentMethod, @PaymentAmount, @TipAmount, @Reference, 1, @WorkspaceId)

        -- 🔍 DEBUG: Confirm insert
        INSERT INTO AvoqadoDebugLog (Folio, PaymentAmount, Message)
        VALUES (@Folio, @PaymentAmount, 'Payment record inserted into tempchequespagos')

        -- Check if order is now fully paid. <= 0.01 (not ABS) also covers exact payment AND
        -- overpayment/change, preventing a negative @Remaining from producing a negative scaling ratio.
        IF @Remaining <= 0.01
        BEGIN
            -- 🔍 DEBUG: Full payment path
            INSERT INTO AvoqadoDebugLog (Folio, PaymentAmount, Message)
            VALUES (@Folio, @PaymentAmount, 'FULL PAYMENT PATH: Marking order as paid')

            -- FULL PAYMENT: Mark order as paid
            UPDATE tempcheques SET pagado = 1,
                observaciones = @CurrentObservaciones + CASE WHEN @CurrentObservaciones = '' THEN '' ELSE ' | ' END + 'PAGADO'
            WHERE folio = @Folio

            SET @Success = 1
            SET @Message = 'Order fully paid'
            SET @Remaining = 0

            -- 🔍 DEBUG: Confirm full payment
            INSERT INTO AvoqadoDebugLog (Folio, PaymentAmount, Message)
            VALUES (@Folio, @PaymentAmount, 'Full payment UPDATE executed')
        END
        ELSE
        BEGIN
            -- 🔍 DEBUG: Partial payment path
            INSERT INTO AvoqadoDebugLog (Folio, PaymentAmount, Message)
            VALUES (@Folio, @PaymentAmount, 'PARTIAL PAYMENT PATH: Remaining=' + CAST(@Remaining AS VARCHAR))

            -- PARTIAL PAYMENT: Adjust item quantities proportionally (SoftRestaurant native way)
            -- CRITICAL FIX: Use high precision DECIMAL to prevent rounding errors
            DECLARE @RemainingRatio DECIMAL(38,10) = CAST(@Remaining AS DECIMAL(38,10)) / CAST(@OrderTotal AS DECIMAL(38,10))

            -- 🔍 DEBUG: Show ratio calculation
            INSERT INTO AvoqadoDebugLog (Folio, PaymentAmount, Message)
            VALUES (@Folio, @PaymentAmount, 'Ratio calculation: ' + CAST(@Remaining AS VARCHAR) + ' / ' + CAST(@OrderTotal AS VARCHAR) + ' = ' + CAST(@RemainingRatio AS VARCHAR))

            -- Update item quantities to reflect remaining amount (like SoftRestaurant split bill)
            -- Use DECIMAL(38,10) for maximum precision
            UPDATE tempcheqdet
            SET cantidad = CAST(CAST(cantidad AS DECIMAL(38,10)) * @RemainingRatio AS DECIMAL(18,6))
            WHERE foliodet = @Folio

            -- 🔍 DEBUG: After quantity update
            INSERT INTO AvoqadoDebugLog (Folio, PaymentAmount, Message)
            VALUES (@Folio, @PaymentAmount, 'Item quantities updated, rows affected: ' + CAST(@@ROWCOUNT AS VARCHAR))

            -- CRITICAL FIX: Calculate new subtotal/tax proportionally from ORIGINAL values
            -- This ensures subtotal + tax = total EXACTLY (no division rounding errors)
            DECLARE @NewSubtotal MONEY = ROUND(CAST(@OriginalSubtotal AS DECIMAL(38,10)) * @RemainingRatio, 2)
            DECLARE @NewTax MONEY = @Remaining - @NewSubtotal
            DECLARE @PaymentNote VARCHAR(50) = 'Pago: $' + CAST(CAST(@PaymentAmount AS INT) AS VARCHAR) + ' (' + @PaymentMethod + ')'

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
                observaciones = CASE WHEN LEN(@CurrentObservaciones + ' | ' + @PaymentNote) <= 250
                    THEN @CurrentObservaciones + CASE WHEN @CurrentObservaciones = '' THEN '' ELSE ' | ' END + @PaymentNote
                    ELSE @PaymentNote END
            WHERE folio = @Folio

            -- 🔍 DEBUG: After order update
            INSERT INTO AvoqadoDebugLog (Folio, PaymentAmount, Message)
            VALUES (@Folio, @PaymentAmount, 'Order totals updated with new calculated values')

            SET @Success = 1
            SET @Message = 'Partial payment recorded - Remaining: $' + CAST(@Remaining AS VARCHAR)
        END

        -- Track changes
        INSERT INTO AvoqadoTracking (EntityType, EntityId, Operation, RetryCount)
        VALUES ('payment', dbo.fn_GetAvoqadoEntityIdWithWorkspace('payment', @Folio, NULL, NULL, NULL), 'CREATE', 0)

        INSERT INTO AvoqadoTracking (EntityType, EntityId, Operation, RetryCount)
        VALUES ('order', dbo.fn_GetAvoqadoEntityIdWithWorkspace('order', @Folio, NULL, NULL, NULL), 'UPDATE', 0)

        -- 🔍 DEBUG: Transaction about to commit
        INSERT INTO AvoqadoDebugLog (Folio, PaymentAmount, Message)
        VALUES (@Folio, @PaymentAmount, 'About to COMMIT transaction')

        COMMIT TRANSACTION

        -- 🔍 DEBUG: Transaction committed
        INSERT INTO AvoqadoDebugLog (Folio, PaymentAmount, Message)
        VALUES (@Folio, @PaymentAmount, 'Transaction COMMITTED successfully')
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK
        SET @Success = 0
        SET @Message = ERROR_MESSAGE()
        SET @Remaining = -1

        -- 🔍 DEBUG: Log error
        INSERT INTO AvoqadoDebugLog (Folio, PaymentAmount, Message)
        VALUES (@Folio, @PaymentAmount, 'ERROR: ' + ERROR_MESSAGE())
    END CATCH
END
GO
PRINT '  ✅ Created sp_ApplyPartialPayment'

-- sp_BeginShiftArchiving - Mark shift as being archived
IF OBJECT_ID('sp_BeginShiftArchiving', 'P') IS NOT NULL DROP PROCEDURE sp_BeginShiftArchiving
GO
CREATE PROCEDURE sp_BeginShiftArchiving @IdTurno BIGINT
AS BEGIN
    SET NOCOUNT ON
    -- Insert or update archiving record
    IF EXISTS(SELECT 1 FROM AvoqadoShiftArchiving WHERE IdTurno = @IdTurno)
        UPDATE AvoqadoShiftArchiving SET IsArchiving = 1, StartedAt = GETUTCDATE(), CompletedAt = NULL WHERE IdTurno = @IdTurno
    ELSE
        INSERT INTO AvoqadoShiftArchiving (IdTurno, IsArchiving) VALUES (@IdTurno, 1)
END
GO
PRINT '  ✅ Created sp_BeginShiftArchiving'

-- sp_EndShiftArchiving - Mark shift archiving as complete
IF OBJECT_ID('sp_EndShiftArchiving', 'P') IS NOT NULL DROP PROCEDURE sp_EndShiftArchiving
GO
CREATE PROCEDURE sp_EndShiftArchiving @IdTurno BIGINT
AS BEGIN
    SET NOCOUNT ON
    UPDATE AvoqadoShiftArchiving SET IsArchiving = 0, CompletedAt = GETUTCDATE() WHERE IdTurno = @IdTurno
    -- Clean up old archiving records (>7 days)
    DELETE FROM AvoqadoShiftArchiving WHERE CompletedAt < DATEADD(DAY, -7, GETUTCDATE())
END
GO
PRINT '  ✅ Created sp_EndShiftArchiving'

-- sp_CleanupOldTrackingRecords - Clean up old processed and error records
IF OBJECT_ID('sp_CleanupOldTrackingRecords', 'P') IS NOT NULL DROP PROCEDURE sp_CleanupOldTrackingRecords
GO
CREATE PROCEDURE sp_CleanupOldTrackingRecords @DaysToKeep INT = 7
AS BEGIN
    SET NOCOUNT ON
    DECLARE @CutoffDate DATETIME2 = DATEADD(DAY, -@DaysToKeep, GETUTCDATE())
    DECLARE @DeletedCount INT = 0

    -- Delete old processed records
    DELETE FROM AvoqadoTracking
    WHERE ProcessedAt IS NOT NULL
      AND ProcessedAt < @CutoffDate

    SET @DeletedCount = @@ROWCOUNT
    PRINT 'Deleted ' + CAST(@DeletedCount AS VARCHAR) + ' old processed records'

    -- Delete old trigger errors (RetryCount=99)
    DELETE FROM AvoqadoTracking
    WHERE RetryCount = 99
      AND Operation = 'ERROR'
      AND Timestamp < @CutoffDate

    SET @DeletedCount = @@ROWCOUNT
    PRINT 'Deleted ' + CAST(@DeletedCount AS VARCHAR) + ' old trigger error records'

    -- Delete old failed records (RetryCount >= 5, but not trigger errors)
    DELETE FROM AvoqadoTracking
    WHERE RetryCount >= 5
      AND RetryCount < 99
      AND Timestamp < @CutoffDate

    SET @DeletedCount = @@ROWCOUNT
    PRINT 'Deleted ' + CAST(@DeletedCount AS VARCHAR) + ' old failed records'
END
GO
PRINT '  ✅ Created sp_CleanupOldTrackingRecords'

PRINT ''

-- =====================================================
-- STEP 6: TRIGGERS (WITH NULL FIX)
-- =====================================================
PRINT '📌 STEP 6: Creating triggers...'

-- Orders Trigger
IF OBJECT_ID('Trg_Avoqado_Orders', 'TR') IS NOT NULL DROP TRIGGER Trg_Avoqado_Orders
GO
CREATE TRIGGER Trg_Avoqado_Orders ON tempcheques AFTER INSERT, UPDATE, DELETE AS
BEGIN
    SET NOCOUNT ON
    -- ✅ IMPROVED: Use flag instead of time window (more reliable for large shifts)
    IF EXISTS(
        SELECT 1 FROM AvoqadoShiftArchiving a
        WHERE a.IsArchiving = 1
        AND a.IdTurno IN (SELECT idturno FROM inserted UNION SELECT idturno FROM deleted)
    ) RETURN

    -- Fallback: Also check recent shift closes (for backwards compatibility)
    IF EXISTS(
        SELECT 1 FROM turnos t
        WHERE t.cierre IS NOT NULL
        AND t.idturno IN (SELECT idturno FROM inserted UNION SELECT idturno FROM deleted)
        AND DATEDIFF(SECOND, t.cierre, GETDATE()) < 30
    ) RETURN

    BEGIN TRY
        INSERT INTO AvoqadoTracking (EntityType, EntityId, Operation, RetryCount)
        SELECT DISTINCT 'order',
            CASE WHEN i.folio IS NULL AND d.folio IS NOT NULL
                THEN dbo.fn_GetAvoqadoEntityIdWithWorkspace('order', d.folio, d.idturno, NULL, d.WorkspaceId)
                ELSE dbo.fn_GetAvoqadoEntityIdWithWorkspace('order', COALESCE(i.folio, d.folio), COALESCE(i.idturno, d.idturno), NULL, NULL)
            END,
            CASE WHEN i.folio IS NOT NULL AND d.folio IS NOT NULL THEN 'UPDATE'
                 WHEN i.folio IS NOT NULL THEN 'CREATE' ELSE 'DELETE' END,
            0
        FROM inserted i FULL OUTER JOIN deleted d ON i.folio = d.folio
        WHERE COALESCE(i.folio, d.folio) IS NOT NULL
    END TRY
    BEGIN CATCH
        -- Log error but don't block POS - record with error message for manual review
        INSERT INTO AvoqadoTracking (EntityType, EntityId, Operation, RetryCount, ErrorMsg)
        SELECT 'order',
            'ERROR:' + CAST(COALESCE(i.folio, d.folio) AS VARCHAR),
            'ERROR',
            99,  -- Mark as failed
            'Trigger error: ' + ERROR_MESSAGE() + ' (Line ' + CAST(ERROR_LINE() AS VARCHAR) + ')'
        FROM inserted i FULL OUTER JOIN deleted d ON i.folio = d.folio
        WHERE COALESCE(i.folio, d.folio) IS NOT NULL
    END CATCH
END
GO
PRINT '  ✅ Created Trg_Avoqado_Orders'

-- OrderItems Trigger
IF OBJECT_ID('Trg_Avoqado_OrderItems', 'TR') IS NOT NULL DROP TRIGGER Trg_Avoqado_OrderItems
GO
CREATE TRIGGER Trg_Avoqado_OrderItems ON tempcheqdet AFTER INSERT, UPDATE, DELETE AS
BEGIN
    SET NOCOUNT ON

    -- ✅ CRITICAL: Shift close protection - prevent spurious DELETE events during shift archiving
    IF EXISTS(
        SELECT 1 FROM AvoqadoShiftArchiving a
        INNER JOIN tempcheques t ON a.IdTurno = t.idturno
        WHERE a.IsArchiving = 1
        AND t.folio IN (SELECT foliodet FROM inserted UNION SELECT foliodet FROM deleted)
    ) RETURN

    -- Fallback: Also check recent shift closes (for backwards compatibility)
    IF EXISTS(
        SELECT 1 FROM turnos tur
        INNER JOIN tempcheques t ON tur.idturno = t.idturno
        WHERE tur.cierre IS NOT NULL
        AND t.folio IN (SELECT foliodet FROM inserted UNION SELECT foliodet FROM deleted)
        AND DATEDIFF(SECOND, tur.cierre, GETDATE()) < 30
    ) RETURN

    BEGIN TRY
        INSERT INTO AvoqadoTracking (EntityType, EntityId, Operation, RetryCount)
        SELECT DISTINCT 'orderitem',
            CASE WHEN i.movimiento IS NULL AND d.movimiento IS NOT NULL
                -- 🔧 H-1 FIX: on DELETE the orderitem entity-id must be the LINE's own WorkspaceId
                -- (d.WorkspaceId from the deleted row), NOT the order's. Passing tempcheques.WorkspaceId
                -- made the DELETE id mismatch the CREATE/UPDATE id, so the backend could not locate the
                -- deleted line (or removed the wrong one) on every v11/v12 venue.
                THEN dbo.fn_GetAvoqadoEntityIdWithWorkspace('orderitem', d.foliodet, (SELECT idturno FROM tempcheques WHERE folio = d.foliodet), d.movimiento, d.WorkspaceId)
                ELSE dbo.fn_GetAvoqadoEntityIdWithWorkspace('orderitem', COALESCE(i.foliodet, d.foliodet), (SELECT idturno FROM tempcheques WHERE folio = COALESCE(i.foliodet, d.foliodet)), COALESCE(i.movimiento, d.movimiento), NULL)
            END,
            CASE WHEN i.movimiento IS NOT NULL AND d.movimiento IS NOT NULL THEN 'UPDATE'
                 WHEN i.movimiento IS NOT NULL THEN 'CREATE' ELSE 'DELETE' END,
            0
        FROM inserted i FULL OUTER JOIN deleted d ON i.foliodet = d.foliodet AND i.movimiento = d.movimiento

        INSERT INTO AvoqadoTracking (EntityType, EntityId, Operation, RetryCount)
        SELECT DISTINCT 'order',
            dbo.fn_GetAvoqadoEntityIdWithWorkspace('order', foliodet, (SELECT idturno FROM tempcheques WHERE folio = foliodet), NULL, NULL), 'UPDATE', 0
        FROM (SELECT foliodet FROM inserted UNION SELECT foliodet FROM deleted) changes
        WHERE EXISTS(SELECT 1 FROM tempcheques WHERE folio = changes.foliodet)
    END TRY
    BEGIN CATCH
        -- Log error but don't block POS - record with error message for manual review
        INSERT INTO AvoqadoTracking (EntityType, EntityId, Operation, RetryCount, ErrorMsg)
        SELECT 'orderitem',
            'ERROR:' + CAST(COALESCE(i.foliodet, d.foliodet) AS VARCHAR) + ':' + CAST(COALESCE(i.movimiento, d.movimiento) AS VARCHAR),
            'ERROR',
            99,  -- Mark as failed
            'Trigger error: ' + ERROR_MESSAGE() + ' (Line ' + CAST(ERROR_LINE() AS VARCHAR) + ')'
        FROM inserted i FULL OUTER JOIN deleted d ON i.foliodet = d.foliodet AND i.movimiento = d.movimiento
        WHERE COALESCE(i.foliodet, d.foliodet) IS NOT NULL
    END CATCH
END
GO
PRINT '  ✅ Created Trg_Avoqado_OrderItems'

-- Payments Trigger
IF OBJECT_ID('Trg_Avoqado_Payments', 'TR') IS NOT NULL DROP TRIGGER Trg_Avoqado_Payments
GO
CREATE TRIGGER Trg_Avoqado_Payments ON tempchequespagos AFTER INSERT, UPDATE, DELETE AS
BEGIN
    SET NOCOUNT ON

    -- ✅ CRITICAL: Shift close protection - prevent spurious DELETE events during shift archiving
    IF EXISTS(
        SELECT 1 FROM AvoqadoShiftArchiving a
        INNER JOIN tempcheques t ON a.IdTurno = t.idturno
        WHERE a.IsArchiving = 1
        AND t.folio IN (SELECT folio FROM inserted UNION SELECT folio FROM deleted)
    ) RETURN

    -- Fallback: Also check recent shift closes (for backwards compatibility)
    IF EXISTS(
        SELECT 1 FROM turnos tur
        INNER JOIN tempcheques t ON tur.idturno = t.idturno
        WHERE tur.cierre IS NOT NULL
        AND t.folio IN (SELECT folio FROM inserted UNION SELECT folio FROM deleted)
        AND DATEDIFF(SECOND, tur.cierre, GETDATE()) < 30
    ) RETURN

    BEGIN TRY
        INSERT INTO AvoqadoTracking (EntityType, EntityId, Operation, RetryCount)
        SELECT DISTINCT 'payment',
            dbo.fn_GetAvoqadoEntityIdWithWorkspace('payment', COALESCE(i.folio, d.folio), NULL, NULL, NULL),
            CASE WHEN i.folio IS NOT NULL AND d.folio IS NOT NULL THEN 'UPDATE'
                 WHEN i.folio IS NOT NULL THEN 'CREATE' ELSE 'DELETE' END,
            0
        FROM inserted i FULL OUTER JOIN deleted d ON i.folio = d.folio
        WHERE COALESCE(i.folio, d.folio) IS NOT NULL
    END TRY
    BEGIN CATCH
        -- Log error but don't block POS - record with error message for manual review
        INSERT INTO AvoqadoTracking (EntityType, EntityId, Operation, RetryCount, ErrorMsg)
        SELECT 'payment',
            'ERROR:' + CAST(COALESCE(i.folio, d.folio) AS VARCHAR),
            'ERROR',
            99,  -- Mark as failed
            'Trigger error: ' + ERROR_MESSAGE() + ' (Line ' + CAST(ERROR_LINE() AS VARCHAR) + ')'
        FROM inserted i FULL OUTER JOIN deleted d ON i.folio = d.folio
        WHERE COALESCE(i.folio, d.folio) IS NOT NULL
    END CATCH
END
GO
PRINT '  ✅ Created Trg_Avoqado_Payments'

-- Shifts Trigger (Simplified - matches working version)
IF OBJECT_ID('Trg_Avoqado_Shifts', 'TR') IS NOT NULL DROP TRIGGER Trg_Avoqado_Shifts
GO
CREATE TRIGGER Trg_Avoqado_Shifts ON turnos AFTER INSERT, UPDATE AS
BEGIN
    SET NOCOUNT ON

    BEGIN TRY
        -- Track shift open
        IF EXISTS(SELECT 1 FROM inserted WHERE cierre IS NULL)
        BEGIN
            INSERT INTO AvoqadoTracking (EntityType, EntityId, Operation, RetryCount)
            SELECT 'shift',
                dbo.fn_GetAvoqadoEntityIdWithWorkspace('shift', NULL, i.idturno, NULL, NULL),
                'OPENED',
                0
            FROM inserted i
            WHERE i.cierre IS NULL
        END

        -- Track shift close
        IF UPDATE(cierre)
        BEGIN
            INSERT INTO AvoqadoTracking (EntityType, EntityId, Operation, RetryCount)
            SELECT 'shift',
                dbo.fn_GetAvoqadoEntityIdWithWorkspace('shift', NULL, i.idturno, NULL, NULL),
                'CLOSED',
                0
            FROM inserted i
            INNER JOIN deleted d ON i.idturno = d.idturno
            WHERE d.cierre IS NULL AND i.cierre IS NOT NULL
        END
    END TRY
    BEGIN CATCH
        -- Log error but don't block POS
        INSERT INTO AvoqadoTracking (EntityType, EntityId, Operation, RetryCount, ErrorMsg)
        SELECT 'shift',
            'ERROR:' + CAST(idturno AS VARCHAR),
            'ERROR',
            99,
            'Trigger error: ' + ERROR_MESSAGE()
        FROM inserted
    END CATCH
END
GO
PRINT '  ✅ Created Trg_Avoqado_Shifts'

PRINT ''
PRINT '======================================================================'
PRINT ' ✅ INSTALLATION COMPLETE!'
PRINT '======================================================================'
PRINT ''
PRINT 'Installed:'
PRINT '  ✅ Payment methods (ACASH, ACARD)'
PRINT '  ✅ Test product (AVOTEST - hidden from POS)'
PRINT '  ✅ SQL Server 2014 compatibility (fn_SplitString)'
PRINT '  ✅ Core tables (Config, Tracking, Commands, InstanceInfo, DebugLog, PartialPayments, ShiftArchiving)'
PRINT '  ✅ Entity ID function (with NULL fix)'
PRINT '  ✅ Stored procedures (with partial payment logic and shift archiving)'
PRINT '  ✅ Triggers (with improved shift close protection)'
PRINT ''
PRINT 'Completed at: ' + CONVERT(VARCHAR, GETDATE(), 120)
PRINT ''
PRINT '======================================================================'
PRINT ' 📋 MAINTENANCE RECOMMENDATIONS'
PRINT '======================================================================'
PRINT ''
PRINT '1. Regular Cleanup (Run weekly):'
PRINT '   EXEC sp_CleanupOldTrackingRecords @DaysToKeep = 7'
PRINT ''
PRINT '2. Shift Close Process (from POS application):'
PRINT '   -- Before closing shift:'
PRINT '   EXEC sp_BeginShiftArchiving @IdTurno = {shift_id}'
PRINT '   -- ... do normal shift close archiving ...'
PRINT '   -- After closing shift:'
PRINT '   EXEC sp_EndShiftArchiving @IdTurno = {shift_id}'
PRINT ''
PRINT '3. Monitor Health:'
PRINT '   Run: 03-DIAGNOSTICS.sql'
PRINT ''
PRINT '======================================================================'