-- ====================================================================
-- SOFTRESTAURANT v11 WORKSPACEID SUPPORT - AVOQADO SYNC SERVICE
--
-- VERSIÓN: 2.3.0
-- FECHA: 2025-09-20
--
-- PROPÓSITO:
-- Actualiza los triggers para SoftRestaurant v11 para usar WorkspaceId
-- como Entity ID en lugar del formato tradicional InstanceId:IdTurno:Folio
--
-- COMPATIBLE CON: SoftRestaurant v11+ (con WorkspaceId)
-- REQUIERE: Script 03-Instalacion-v2-sin-syncstate.sql ejecutado previamente
-- ====================================================================

PRINT N'🔧 =============================================================';
PRINT N'🔧 ACTUALIZANDO TRIGGERS PARA SOFTRESTAURANT v11 (WorkspaceId)';
PRINT N'🔧 =============================================================';
PRINT N'';

-- Verificar que tenemos WorkspaceId en las tablas
IF COL_LENGTH('tempcheques', 'WorkspaceId') IS NULL
BEGIN
    PRINT N'❌ ERROR: Esta base de datos no tiene WorkspaceId. Este script es solo para SoftRestaurant v11+';
    RETURN;
END

PRINT N'✅ WorkspaceId detectado. Continuando con la actualización...';

-- =====================================================
-- PASO 1: ACTUALIZAR VERSIÓN
-- =====================================================
PRINT N'📌 PASO 1: Actualizando versión a 2.3.0...';
UPDATE dbo.AvoqadoInstanceInfo SET Version = '2.3.0';
PRINT N'  ✅ Versión actualizada a 2.3.0 (SoftRestaurant v11 Support)';

-- =====================================================
-- PASO 2: TRIGGER DE ÓRDENES PARA v11 (WorkspaceId)
-- =====================================================
PRINT N'📌 PASO 2: Recreando trigger de órdenes para v11...';

IF OBJECT_ID('Trg_Avoqado_Orders', 'TR') IS NOT NULL DROP TRIGGER Trg_Avoqado_Orders;

EXEC('
CREATE TRIGGER Trg_Avoqado_Orders ON dbo.tempcheques AFTER INSERT, UPDATE, DELETE AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @changeReason VARCHAR(100);
    DECLARE @entityId VARCHAR(200);
    DECLARE @workspaceId UNIQUEIDENTIFIER;

    -- Procesar INSERT/UPDATE
    IF EXISTS(SELECT 1 FROM inserted)
    BEGIN
        SET @changeReason = CASE WHEN EXISTS(SELECT 1 FROM deleted) THEN ''order_updated'' ELSE ''order_created'' END;

        DECLARE order_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT DISTINCT WorkspaceId FROM inserted;

        OPEN order_cursor;
        FETCH NEXT FROM order_cursor INTO @workspaceId;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            -- Use WorkspaceId as Entity ID for v11
            SET @entityId = CAST(@workspaceId AS VARCHAR(36));
            EXEC sp_TrackEntityChange ''order'', @entityId, @changeReason;
            FETCH NEXT FROM order_cursor INTO @workspaceId;
        END;

        CLOSE order_cursor;
        DEALLOCATE order_cursor;
    END

    -- Procesar DELETE
    ELSE IF EXISTS(SELECT 1 FROM deleted)
    BEGIN
        DECLARE delete_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT DISTINCT WorkspaceId FROM deleted;

        OPEN delete_cursor;
        FETCH NEXT FROM delete_cursor INTO @workspaceId;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @entityId = CAST(@workspaceId AS VARCHAR(36));
            EXEC sp_TrackEntityChange ''order'', @entityId, ''order_deleted'';
            FETCH NEXT FROM delete_cursor INTO @workspaceId;
        END;

        CLOSE delete_cursor;
        DEALLOCATE delete_cursor;
    END
END');

PRINT N'  ✅ Trigger `Trg_Avoqado_Orders` actualizado para v11';

-- =====================================================
-- PASO 3: TRIGGER DE ITEMS PARA v11 (WorkspaceId + Sequence)
-- =====================================================
PRINT N'📌 PASO 3: Recreando trigger de items para v11...';

IF OBJECT_ID('Trg_Avoqado_OrderItems', 'TR') IS NOT NULL DROP TRIGGER Trg_Avoqado_OrderItems;

EXEC('
CREATE TRIGGER Trg_Avoqado_OrderItems ON dbo.tempcheqdet AFTER INSERT, UPDATE, DELETE AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @itemEntityId VARCHAR(200);
    DECLARE @changeReason VARCHAR(100);
    DECLARE @workspaceId UNIQUEIDENTIFIER;
    DECLARE @movimiento NUMERIC(3,0);

    -- Tabla temporal para cambios
    DECLARE @changes TABLE (
        WorkspaceId UNIQUEIDENTIFIER,
        movimiento NUMERIC(3,0),
        ChangeType VARCHAR(20)
    );

    -- Detectar todos los cambios
    WITH AllChanges AS (
        SELECT
            COALESCE(i.WorkspaceId, d.WorkspaceId) as WorkspaceId,
            COALESCE(i.movimiento, d.movimiento) as movimiento,
            CASE
                WHEN i.movimiento IS NOT NULL AND d.movimiento IS NOT NULL THEN ''item_updated''
                WHEN i.movimiento IS NOT NULL AND d.movimiento IS NULL THEN ''item_created''
                WHEN i.movimiento IS NULL AND d.movimiento IS NOT NULL THEN ''item_deleted''
            END as ChangeType
        FROM inserted i
        FULL OUTER JOIN deleted d ON i.foliodet = d.foliodet AND i.movimiento = d.movimiento
    )
    INSERT INTO @changes (WorkspaceId, movimiento, ChangeType)
    SELECT WorkspaceId, movimiento, ChangeType FROM AllChanges WHERE ChangeType IS NOT NULL;

    -- Procesar cada cambio
    DECLARE item_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT WorkspaceId, movimiento, ChangeType FROM @changes;

    OPEN item_cursor;
    FETCH NEXT FROM item_cursor INTO @workspaceId, @movimiento, @changeReason;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- For v11: Use WorkspaceId:Sequence as Entity ID for items
        SET @itemEntityId = CAST(@workspaceId AS VARCHAR(36)) + '':'' + CAST(@movimiento AS VARCHAR(10));
        EXEC sp_TrackEntityChange ''orderitem'', @itemEntityId, @changeReason;
        FETCH NEXT FROM item_cursor INTO @workspaceId, @movimiento, @changeReason;
    END;

    CLOSE item_cursor;
    DEALLOCATE item_cursor;
END');

PRINT N'  ✅ Trigger `Trg_Avoqado_OrderItems` actualizado para v11';

-- =====================================================
-- PASO 4: ACTUALIZAR TRIGGER DE TURNOS PARA v11
-- =====================================================
PRINT N'📌 PASO 4: Actualizando trigger de turnos para v11...';

IF OBJECT_ID('Trg_Avoqado_Shifts', 'TR') IS NOT NULL DROP TRIGGER Trg_Avoqado_Shifts;

EXEC('
CREATE TRIGGER Trg_Avoqado_Shifts ON dbo.turnos AFTER INSERT, UPDATE, DELETE AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @changeReason VARCHAR(100);
    DECLARE @entityId VARCHAR(200);
    DECLARE @workspaceId UNIQUEIDENTIFIER;

    -- Procesar INSERT/UPDATE
    IF EXISTS(SELECT 1 FROM inserted)
    BEGIN
        SET @changeReason = CASE WHEN EXISTS(SELECT 1 FROM deleted) THEN ''shift_updated'' ELSE ''shift_created'' END;

        DECLARE shift_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT DISTINCT WorkspaceId FROM inserted;

        OPEN shift_cursor;
        FETCH NEXT FROM shift_cursor INTO @workspaceId;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            -- Use WorkspaceId as Entity ID for shifts in v11
            SET @entityId = CAST(@workspaceId AS VARCHAR(36));
            EXEC sp_TrackEntityChange ''shift'', @entityId, @changeReason;
            FETCH NEXT FROM shift_cursor INTO @workspaceId;
        END;

        CLOSE shift_cursor;
        DEALLOCATE shift_cursor;
    END

    -- Procesar DELETE
    ELSE IF EXISTS(SELECT 1 FROM deleted)
    BEGIN
        DECLARE delete_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT DISTINCT WorkspaceId FROM deleted;

        OPEN delete_cursor;
        FETCH NEXT FROM delete_cursor INTO @workspaceId;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @entityId = CAST(@workspaceId AS VARCHAR(36));
            EXEC sp_TrackEntityChange ''shift'', @entityId, ''shift_deleted'';
            FETCH NEXT FROM delete_cursor INTO @workspaceId;
        END;

        CLOSE delete_cursor;
        DEALLOCATE delete_cursor;
    END
END');

PRINT N'  ✅ Trigger `Trg_Avoqado_Shifts` actualizado para v11';

-- =====================================================
-- PASO 5: LIMPIEZA DE DATOS ANTIGUOS (OPCIONAL)
-- =====================================================
PRINT N'📌 PASO 5: Limpieza de tracking anterior...';
PRINT N'⚠️  Esto eliminará todos los registros de tracking con formato InstanceId:IdTurno:Folio';
PRINT N'   Si quiere conservar el historial, detenga aquí y haga backup.';

-- Uncomment the next line to clean old tracking data
-- DELETE FROM AvoqadoEntityTracking WHERE EntityId LIKE '%:%:%';

PRINT N'  ℹ️  Limpieza omitida. Para limpiar datos antiguos, descomente la línea DELETE.';

-- =====================================================
-- FINALIZACIÓN
-- =====================================================
PRINT N'';
PRINT N'✅ =============================================================';
PRINT N'✅ ACTUALIZACIÓN COMPLETADA PARA SOFTRESTAURANT v11';
PRINT N'✅ =============================================================';
PRINT N'';
PRINT N'📋 CAMBIOS APLICADOS:';
PRINT N'   • Triggers actualizados para usar WorkspaceId como Entity ID';
PRINT N'   • Formato de Entity ID para órdenes: [WorkspaceId]';
PRINT N'   • Formato de Entity ID para items: [WorkspaceId]:[Sequence]';
PRINT N'   • Formato de Entity ID para turnos: [WorkspaceId]';
PRINT N'   • Versión actualizada a 2.3.0';
PRINT N'';
PRINT N'⚠️  IMPORTANTE: El backend debe ser actualizado para manejar este nuevo formato.';
PRINT N'   Ver documentación en CLAUDE.md para los cambios necesarios en el backend.';