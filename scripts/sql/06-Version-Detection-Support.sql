-- ====================================================================
-- SOFTRESTAURANT VERSION DETECTION SUPPORT - AVOQADO SYNC SERVICE
--
-- VERSIÓN: 2.4.0
-- FECHA: 2025-09-20
--
-- PROPÓSITO:
-- Implementa detección automática de versión de SoftRestaurant para
-- usar el formato correcto de Entity ID independientemente de si
-- existe la columna WorkspaceId o no.
--
-- COMPATIBLE CON: SoftRestaurant v10+ y v11+
-- REQUIERE: Script 03-Instalacion-v2-sin-syncstate.sql ejecutado previamente
-- ====================================================================

PRINT N'🔧 ============================================================='
PRINT N'🔧 INSTALANDO DETECCIÓN DE VERSIÓN SOFTRESTAURANT'
PRINT N'🔧 ============================================================='
PRINT N''

-- Verificar que tenemos las tablas necesarias
IF OBJECT_ID('parametros2', 'U') IS NULL
BEGIN
    PRINT N'❌ ERROR: Esta base de datos no tiene la tabla parametros2 requerida.'
    RETURN
END

-- Obtener la versión actual
DECLARE @currentVersion DECIMAL(10,6)
SELECT @currentVersion = versiondb FROM parametros2

PRINT N'📋 Versión de SoftRestaurant detectada: ' + CAST(@currentVersion AS VARCHAR(20))

-- =====================================================
-- PASO 1: CREAR FUNCIÓN DE DETECCIÓN DE VERSIÓN
-- =====================================================
PRINT N'📌 PASO 1: Creando función de detección de versión...'

IF OBJECT_ID('dbo.fn_GetSoftRestaurantVersion', 'FN') IS NOT NULL
    DROP FUNCTION dbo.fn_GetSoftRestaurantVersion

EXEC('
CREATE FUNCTION dbo.fn_GetSoftRestaurantVersion()
RETURNS DECIMAL(10,6)
AS
BEGIN
    DECLARE @version DECIMAL(10,6)
    SELECT @version = ISNULL(versiondb, 10.0) FROM parametros2
    RETURN @version
END')

PRINT N'  ✅ Función `fn_GetSoftRestaurantVersion` creada'

-- =====================================================
-- PASO 2: CREAR STORED PROCEDURE PARA ENTITY ID
-- =====================================================
PRINT N'📌 PASO 2: Creando stored procedure para Entity ID...'

IF OBJECT_ID('dbo.sp_GenerateEntityId', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_GenerateEntityId

EXEC('
CREATE PROCEDURE dbo.sp_GenerateEntityId
    @EntityType VARCHAR(50),
    @WorkspaceId UNIQUEIDENTIFIER = NULL,
    @IdTurno BIGINT = NULL,
    @Folio BIGINT = NULL,
    @Movimiento INT = NULL,
    @EntityId VARCHAR(200) OUTPUT
AS
BEGIN
    DECLARE @version DECIMAL(10,6)
    DECLARE @instanceId VARCHAR(50)

    -- Obtener versión y instance ID
    SET @version = dbo.fn_GetSoftRestaurantVersion()
    SELECT @instanceId = InstanceId FROM AvoqadoInstanceInfo

    -- Generar Entity ID según la versión
    IF @version >= 11.0
    BEGIN
        -- Formato v11: Usar WorkspaceId
        IF @EntityType = ''order''
            SET @EntityId = CAST(@WorkspaceId AS VARCHAR(36))
        ELSE IF @EntityType = ''orderitem''
            SET @EntityId = CAST(@WorkspaceId AS VARCHAR(36)) + '':'' + CAST(@Movimiento AS VARCHAR(10))
        ELSE IF @EntityType = ''shift''
            SET @EntityId = CAST(@WorkspaceId AS VARCHAR(36))
    END
    ELSE
    BEGIN
        -- Formato v10: Usar formato tradicional
        IF @EntityType = ''order''
            SET @EntityId = @instanceId + '':'' + CAST(@IdTurno AS VARCHAR(20)) + '':'' + CAST(@Folio AS VARCHAR(20))
        ELSE IF @EntityType = ''orderitem''
            SET @EntityId = @instanceId + '':'' + CAST(@IdTurno AS VARCHAR(20)) + '':'' + CAST(@Folio AS VARCHAR(20)) + '':'' + CAST(@Movimiento AS VARCHAR(10))
        ELSE IF @EntityType = ''shift''
            SET @EntityId = CAST(@IdTurno AS VARCHAR(20))
    END
END')

PRINT N'  ✅ Stored Procedure `sp_GenerateEntityId` creado'

-- =====================================================
-- PASO 3: ACTUALIZAR VERSIÓN
-- =====================================================
PRINT N'📌 PASO 3: Actualizando versión a 2.4.0...'
UPDATE dbo.AvoqadoInstanceInfo SET Version = '2.4.0'
PRINT N'  ✅ Versión actualizada a 2.4.0 (Version Detection Support)'

-- =====================================================
-- PASO 4: RECREAR TRIGGERS CON DETECCIÓN DE VERSIÓN
-- =====================================================
PRINT N'📌 PASO 4: Recreando triggers con detección de versión...'

-- TRIGGER DE ÓRDENES
IF OBJECT_ID('Trg_Avoqado_Orders', 'TR') IS NOT NULL DROP TRIGGER Trg_Avoqado_Orders

EXEC('
CREATE TRIGGER Trg_Avoqado_Orders ON dbo.tempcheques AFTER INSERT, UPDATE, DELETE AS
BEGIN
    SET NOCOUNT ON

    DECLARE @changeReason VARCHAR(100)
    DECLARE @entityId VARCHAR(200)
    DECLARE @workspaceId UNIQUEIDENTIFIER
    DECLARE @idturno BIGINT
    DECLARE @folio BIGINT

    -- Procesar INSERT/UPDATE
    IF EXISTS(SELECT 1 FROM inserted)
    BEGIN
        SET @changeReason = CASE WHEN EXISTS(SELECT 1 FROM deleted) THEN ''order_updated'' ELSE ''order_created'' END

        DECLARE order_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT folio, idturno,
                   CASE WHEN COL_LENGTH(''tempcheques'', ''WorkspaceId'') IS NOT NULL
                        THEN WorkspaceId
                        ELSE NULL
                   END as WorkspaceId
            FROM inserted

        OPEN order_cursor
        FETCH NEXT FROM order_cursor INTO @folio, @idturno, @workspaceId

        WHILE @@FETCH_STATUS = 0
        BEGIN
            -- Generar Entity ID usando el stored procedure
            EXEC sp_GenerateEntityId ''order'', @workspaceId, @idturno, @folio, NULL, @entityId OUTPUT
            EXEC sp_TrackEntityChange ''order'', @entityId, @changeReason
            FETCH NEXT FROM order_cursor INTO @folio, @idturno, @workspaceId
        END

        CLOSE order_cursor
        DEALLOCATE order_cursor
    END

    -- Procesar DELETE
    ELSE IF EXISTS(SELECT 1 FROM deleted)
    BEGIN
        DECLARE delete_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT folio, idturno,
                   CASE WHEN COL_LENGTH(''tempcheques'', ''WorkspaceId'') IS NOT NULL
                        THEN WorkspaceId
                        ELSE NULL
                   END as WorkspaceId
            FROM deleted

        OPEN delete_cursor
        FETCH NEXT FROM delete_cursor INTO @folio, @idturno, @workspaceId

        WHILE @@FETCH_STATUS = 0
        BEGIN
            EXEC sp_GenerateEntityId ''order'', @workspaceId, @idturno, @folio, NULL, @entityId OUTPUT
            EXEC sp_TrackEntityChange ''order'', @entityId, ''order_deleted''
            FETCH NEXT FROM delete_cursor INTO @folio, @idturno, @workspaceId
        END

        CLOSE delete_cursor
        DEALLOCATE delete_cursor
    END
END')

PRINT N'  ✅ Trigger `Trg_Avoqado_Orders` actualizado con detección de versión'

-- TRIGGER DE ITEMS
IF OBJECT_ID('Trg_Avoqado_OrderItems', 'TR') IS NOT NULL DROP TRIGGER Trg_Avoqado_OrderItems

EXEC('
CREATE TRIGGER Trg_Avoqado_OrderItems ON dbo.tempcheqdet AFTER INSERT, UPDATE, DELETE AS
BEGIN
    SET NOCOUNT ON

    DECLARE @itemEntityId VARCHAR(200)
    DECLARE @changeReason VARCHAR(100)
    DECLARE @workspaceId UNIQUEIDENTIFIER
    DECLARE @movimiento NUMERIC(3,0)
    DECLARE @folio BIGINT
    DECLARE @idturno BIGINT

    -- Tabla temporal para cambios
    DECLARE @changes TABLE (
        folio BIGINT,
        WorkspaceId UNIQUEIDENTIFIER,
        movimiento NUMERIC(3,0),
        ChangeType VARCHAR(20)
    )

    -- Detectar todos los cambios
    ;WITH AllChanges AS (
        SELECT
            COALESCE(i.foliodet, d.foliodet) as folio,
            CASE WHEN COL_LENGTH(''tempcheqdet'', ''WorkspaceId'') IS NOT NULL
                 THEN COALESCE(i.WorkspaceId, d.WorkspaceId)
                 ELSE NULL
            END as WorkspaceId,
            COALESCE(i.movimiento, d.movimiento) as movimiento,
            CASE
                WHEN i.movimiento IS NOT NULL AND d.movimiento IS NOT NULL THEN ''item_updated''
                WHEN i.movimiento IS NOT NULL AND d.movimiento IS NULL THEN ''item_created''
                WHEN i.movimiento IS NULL AND d.movimiento IS NOT NULL THEN ''item_deleted''
            END as ChangeType
        FROM inserted i
        FULL OUTER JOIN deleted d ON i.foliodet = d.foliodet AND i.movimiento = d.movimiento
    )
    INSERT INTO @changes (folio, WorkspaceId, movimiento, ChangeType)
    SELECT folio, WorkspaceId, movimiento, ChangeType FROM AllChanges WHERE ChangeType IS NOT NULL

    -- Procesar cada cambio
    DECLARE item_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT folio, WorkspaceId, movimiento, ChangeType FROM @changes

    OPEN item_cursor
    FETCH NEXT FROM item_cursor INTO @folio, @workspaceId, @movimiento, @changeReason

    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- Obtener idturno de la orden padre
        SELECT @idturno = idturno FROM tempcheques WHERE folio = @folio

        -- Generar Entity ID usando el stored procedure
        EXEC sp_GenerateEntityId ''orderitem'', @workspaceId, @idturno, @folio, @movimiento, @itemEntityId OUTPUT
        EXEC sp_TrackEntityChange ''orderitem'', @itemEntityId, @changeReason
        FETCH NEXT FROM item_cursor INTO @folio, @workspaceId, @movimiento, @changeReason
    END

    CLOSE item_cursor
    DEALLOCATE item_cursor
END')

PRINT N'  ✅ Trigger `Trg_Avoqado_OrderItems` actualizado con detección de versión'

-- TRIGGER DE TURNOS
IF OBJECT_ID('Trg_Avoqado_Shifts', 'TR') IS NOT NULL DROP TRIGGER Trg_Avoqado_Shifts

EXEC('
CREATE TRIGGER Trg_Avoqado_Shifts ON dbo.turnos AFTER INSERT, UPDATE, DELETE AS
BEGIN
    SET NOCOUNT ON

    DECLARE @changeReason VARCHAR(100)
    DECLARE @entityId VARCHAR(200)
    DECLARE @workspaceId UNIQUEIDENTIFIER
    DECLARE @idturno BIGINT

    -- Procesar INSERT/UPDATE
    IF EXISTS(SELECT 1 FROM inserted)
    BEGIN
        SET @changeReason = CASE WHEN EXISTS(SELECT 1 FROM deleted) THEN ''shift_updated'' ELSE ''shift_created'' END

        DECLARE shift_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT idturno,
                   CASE WHEN COL_LENGTH(''turnos'', ''WorkspaceId'') IS NOT NULL
                        THEN WorkspaceId
                        ELSE NULL
                   END as WorkspaceId
            FROM inserted

        OPEN shift_cursor
        FETCH NEXT FROM shift_cursor INTO @idturno, @workspaceId

        WHILE @@FETCH_STATUS = 0
        BEGIN
            EXEC sp_GenerateEntityId ''shift'', @workspaceId, @idturno, NULL, NULL, @entityId OUTPUT
            EXEC sp_TrackEntityChange ''shift'', @entityId, @changeReason
            FETCH NEXT FROM shift_cursor INTO @idturno, @workspaceId
        END

        CLOSE shift_cursor
        DEALLOCATE shift_cursor
    END

    -- Procesar DELETE
    ELSE IF EXISTS(SELECT 1 FROM deleted)
    BEGIN
        DECLARE delete_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT idturno,
                   CASE WHEN COL_LENGTH(''turnos'', ''WorkspaceId'') IS NOT NULL
                        THEN WorkspaceId
                        ELSE NULL
                   END as WorkspaceId
            FROM deleted

        OPEN delete_cursor
        FETCH NEXT FROM delete_cursor INTO @idturno, @workspaceId

        WHILE @@FETCH_STATUS = 0
        BEGIN
            EXEC sp_GenerateEntityId ''shift'', @workspaceId, @idturno, NULL, NULL, @entityId OUTPUT
            EXEC sp_TrackEntityChange ''shift'', @entityId, ''shift_deleted''
            FETCH NEXT FROM delete_cursor INTO @idturno, @workspaceId
        END

        CLOSE delete_cursor
        DEALLOCATE delete_cursor
    END
END')

PRINT N'  ✅ Trigger `Trg_Avoqado_Shifts` actualizado con detección de versión'

-- =====================================================
-- FINALIZACIÓN
-- =====================================================
PRINT N''
PRINT N'✅ ============================================================='
PRINT N'✅ DETECCIÓN DE VERSIÓN INSTALADA EXITOSAMENTE'
PRINT N'✅ ============================================================='
PRINT N''
PRINT N'📋 CAMBIOS APLICADOS:'
PRINT N'   • Función fn_GetSoftRestaurantVersion() creada'
PRINT N'   • Stored Procedure sp_GenerateEntityId() creado'
PRINT N'   • Triggers actualizados con detección automática de versión'
PRINT N'   • Formato de Entity ID determinado por versión real, no por columnas'
PRINT N'   • Versión actualizada a 2.4.0'
PRINT N''
PRINT N'🔍 VERSIÓN DETECTADA: ' + CAST(@currentVersion AS VARCHAR(20))
IF @currentVersion >= 11.0
    PRINT N'   → Usará formato v11: WorkspaceId'
ELSE
    PRINT N'   → Usará formato v10: InstanceId:IdTurno:Folio'
PRINT N''
PRINT N'⚠️  IMPORTANTE: El producer debe ser actualizado para usar detección de versión.'
PRINT N'   Los Entity IDs ahora se generan según la versión real de SoftRestaurant.'