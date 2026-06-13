-- ====================================================================
-- SCRIPT 05: OPTIMIZACIÓN DE TRACKING - AVOQADO SYNC SERVICE V2.3
--
-- VERSIÓN: 2.3.0
-- REQUISITO: haber ejecutado 03-Instalacion-v2-sin-syncstate.sql
-- ORDEN DE DEPLOY: ejecutar este script ANTES de actualizar el servicio
--                  a la versión 2.3.x (el Producer nuevo pasa @lastSyncId).
--
-- PROPÓSITO:
-- 1. ÍNDICE para el polling: sp_GetEntityChanges corre cada 2 segundos;
--    sin índice en LastModifiedAt hacía table scan + sort en cada poll,
--    cada vez más caro porque la tabla nunca se purgaba.
-- 2. CURSOR COMPUESTO (LastModifiedAt, Id): los triggers set-based marcan
--    lotes enteros con el MISMO timestamp; con cursor solo-timestamp los
--    empates en la frontera del lote (TOP @maxResults) se perdían.
-- 3. UPSERTS SET-BASED SIN CURSORES en los 3 triggers: los cursores fila
--    por fila + EXEC por fila penalizaban CADA operación del POS dentro de
--    su propia transacción (SQL 2014 Express 32-bit, 1GB de buffer pool).
-- 4. sp_TrackEntityChange RACE-SAFE: el patrón IF EXISTS→UPDATE/INSERT
--    podía violar el UNIQUE(EntityType, EntityId) bajo concurrencia y
--    ABORTAR la transacción del POS (error visible para el mesero).
-- 5. sp_PurgeAvoqadoTracking: SQL Express no tiene SQL Agent; el servicio
--    invoca esta purga una vez al día (entidades sin cambios en 30 días).
--
-- COMPATIBILIDAD: SQL Server 2014 (12.0.4100.1) — sin CREATE OR ALTER.
-- IDEMPOTENTE: se puede ejecutar múltiples veces sin efectos secundarios.
-- ====================================================================

PRINT N'🔧 =============================================================';
PRINT N'🔧 SCRIPT 05: OPTIMIZACIÓN DE TRACKING (V2.3)';
PRINT N'🔧 =============================================================';
PRINT N'';

-- =====================================================
-- PASO 0: VALIDACIONES PREVIAS
-- =====================================================
PRINT N'📌 PASO 0: Validando prerequisitos...';
IF OBJECT_ID('dbo.AvoqadoEntityTracking', 'U') IS NULL
BEGIN
    RAISERROR(N'❌ La tabla AvoqadoEntityTracking no existe. Ejecuta primero 03-Instalacion-v2-sin-syncstate.sql.', 16, 1);
    SET NOEXEC ON; -- Aborta el resto del script
END
GO

IF COL_LENGTH('dbo.AvoqadoEntityTracking', 'Id') IS NULL
BEGIN
    -- Instalaciones v1 muy viejas no tenían la columna Id.
    ALTER TABLE dbo.AvoqadoEntityTracking ADD Id BIGINT IDENTITY(1,1) NOT NULL;
    PRINT N'  ✅ Columna Id (IDENTITY) agregada a AvoqadoEntityTracking.';
END
ELSE
    PRINT N'  ℹ️ Prerequisitos OK.';
GO

-- =====================================================
-- PASO 1: ÍNDICE DE POLLING
-- =====================================================
PRINT N'';
PRINT N'📌 PASO 1: Creando índice IX_AvoqadoEntityTracking_Modified...';
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_AvoqadoEntityTracking_Modified' AND object_id = OBJECT_ID('dbo.AvoqadoEntityTracking'))
BEGIN
    DROP INDEX IX_AvoqadoEntityTracking_Modified ON dbo.AvoqadoEntityTracking;
    PRINT N'  ℹ️ Índice previo eliminado (se recrea con la definición nueva).';
END

-- Cubriente para: WHERE LastModifiedAt > @ts OR (= @ts AND Id > @id) ORDER BY LastModifiedAt, Id
CREATE NONCLUSTERED INDEX IX_AvoqadoEntityTracking_Modified
    ON dbo.AvoqadoEntityTracking (LastModifiedAt ASC, Id ASC)
    INCLUDE (EntityType, EntityId, ChangeReason);
PRINT N'  ✅ Índice creado: el poll de cada 2s pasa de table scan a index seek.';
GO

-- =====================================================
-- PASO 2: sp_TrackEntityChange (RACE-SAFE)
-- =====================================================
PRINT N'';
PRINT N'📌 PASO 2: Recreando sp_TrackEntityChange (race-safe)...';
IF OBJECT_ID('dbo.sp_TrackEntityChange', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_TrackEntityChange;
EXEC('CREATE PROCEDURE dbo.sp_TrackEntityChange @entityType VARCHAR(50), @entityId VARCHAR(200), @changeReason VARCHAR(100) AS
BEGIN
    SET NOCOUNT ON;

    -- UPDATE primero (caso más común). UPDLOCK+HOLDLOCK serializa el rango
    -- para que dos sesiones no inserten el mismo (EntityType, EntityId).
    UPDATE dbo.AvoqadoEntityTracking WITH (UPDLOCK, HOLDLOCK)
       SET LastModifiedAt = GETUTCDATE(), ChangeReason = @changeReason
     WHERE EntityType = @entityType AND EntityId = @entityId;

    IF @@ROWCOUNT = 0
    BEGIN
        BEGIN TRY
            INSERT INTO dbo.AvoqadoEntityTracking (EntityType, EntityId, ChangeReason)
            VALUES (@entityType, @entityId, @changeReason);
        END TRY
        BEGIN CATCH
            -- 2601/2627 = duplicado por carrera: otro proceso insertó primero.
            -- Convertimos a UPDATE en lugar de abortar la transacción del POS.
            IF ERROR_NUMBER() NOT IN (2601, 2627) THROW;
            UPDATE dbo.AvoqadoEntityTracking
               SET LastModifiedAt = GETUTCDATE(), ChangeReason = @changeReason
             WHERE EntityType = @entityType AND EntityId = @entityId;
        END CATCH
    END
END');
PRINT N'  ✅ sp_TrackEntityChange recreado.';
GO

-- =====================================================
-- PASO 3: sp_GetEntityChanges (CURSOR COMPUESTO)
-- =====================================================
PRINT N'';
PRINT N'📌 PASO 3: Recreando sp_GetEntityChanges (cursor compuesto ts+id)...';
IF OBJECT_ID('dbo.sp_GetEntityChanges', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_GetEntityChanges;
EXEC('CREATE PROCEDURE dbo.sp_GetEntityChanges @lastSyncTimestamp DATETIME2, @maxResults INT = 100, @lastSyncId BIGINT = 9223372036854775807 AS
BEGIN
    SET NOCOUNT ON;
    -- DEFAULT de @lastSyncId = BIGINT MAX a propósito: un servicio VIEJO que
    -- no pasa el parámetro conserva su semántica exacta (solo ts estrictamente
    -- mayor; con default 0 re-enviaría en bucle las filas empatadas con el
    -- cursor). El servicio v2.3+ siempre lo pasa explícito. El cursor
    -- compuesto evita perder filas con timestamp empatado en la frontera del
    -- lote (los triggers set-based marcan lotes enteros con el mismo GETUTCDATE()).
    SELECT TOP (@maxResults) Id, EntityType, EntityId, LastModifiedAt, ChangeReason
    FROM dbo.AvoqadoEntityTracking
    WHERE LastModifiedAt > @lastSyncTimestamp
       OR (LastModifiedAt = @lastSyncTimestamp AND Id > @lastSyncId)
    ORDER BY LastModifiedAt ASC, Id ASC;
END');
PRINT N'  ✅ sp_GetEntityChanges recreado.';
GO

-- =====================================================
-- PASO 4: sp_PurgeAvoqadoTracking
-- =====================================================
PRINT N'';
PRINT N'📌 PASO 4: Creando sp_PurgeAvoqadoTracking...';
IF OBJECT_ID('dbo.sp_PurgeAvoqadoTracking', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_PurgeAvoqadoTracking;
EXEC('CREATE PROCEDURE dbo.sp_PurgeAvoqadoTracking @daysToKeep INT = 30 AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @cutoff DATETIME2 = DATEADD(DAY, -@daysToKeep, GETUTCDATE());

    -- Borrado por lotes para no inflar el log de transacciones del Express.
    WHILE 1 = 1
    BEGIN
        DELETE TOP (5000) FROM dbo.AvoqadoEntityTracking WHERE LastModifiedAt < @cutoff;
        IF @@ROWCOUNT = 0 BREAK;
    END
END');
PRINT N'  ✅ sp_PurgeAvoqadoTracking creado (el servicio lo invoca a diario).';
GO

-- =====================================================
-- PASO 5: TRIGGERS SET-BASED (SIN CURSORES)
-- =====================================================
PRINT N'';
PRINT N'📌 PASO 5: Recreando triggers set-based...';

-- ---------------------------------------------------------------
-- Trigger de Órdenes: mismos EntityIds (instance:idturno:folio) y
-- ChangeReasons (order_created/updated/deleted) que la v2.2.
-- ---------------------------------------------------------------
IF OBJECT_ID('Trg_Avoqado_Orders', 'TR') IS NOT NULL DROP TRIGGER Trg_Avoqado_Orders;
EXEC('
CREATE TRIGGER Trg_Avoqado_Orders ON dbo.tempcheques AFTER INSERT, UPDATE, DELETE AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @InstanceId VARCHAR(36);
    SELECT TOP 1 @InstanceId = CAST(InstanceId AS VARCHAR(36)) FROM dbo.AvoqadoInstanceInfo;
    IF @InstanceId IS NULL RETURN;

    DECLARE @changes TABLE (EntityId VARCHAR(200) PRIMARY KEY, ChangeReason VARCHAR(100));

    IF EXISTS (SELECT 1 FROM inserted)
    BEGIN
        DECLARE @reason VARCHAR(100) = CASE WHEN EXISTS (SELECT 1 FROM deleted) THEN ''order_updated'' ELSE ''order_created'' END;
        INSERT INTO @changes (EntityId, ChangeReason)
        SELECT DISTINCT @InstanceId + '':'' + ISNULL(CAST(idturno AS VARCHAR(30)), '''') + '':'' + CAST(folio AS VARCHAR(30)), @reason
        FROM inserted
        WHERE folio IS NOT NULL;
    END
    ELSE
    BEGIN
        INSERT INTO @changes (EntityId, ChangeReason)
        SELECT DISTINCT @InstanceId + '':'' + ISNULL(CAST(idturno AS VARCHAR(30)), '''') + '':'' + CAST(folio AS VARCHAR(30)), ''order_deleted''
        FROM deleted
        WHERE folio IS NOT NULL;
    END

    -- Upsert set-based: una pasada por lote en lugar de cursor + EXEC por fila.
    UPDATE t SET LastModifiedAt = GETUTCDATE(), ChangeReason = c.ChangeReason
    FROM dbo.AvoqadoEntityTracking t WITH (UPDLOCK, HOLDLOCK)
    INNER JOIN @changes c ON t.EntityType = ''order'' AND t.EntityId = c.EntityId;

    INSERT INTO dbo.AvoqadoEntityTracking (EntityType, EntityId, ChangeReason)
    SELECT ''order'', c.EntityId, c.ChangeReason
    FROM @changes c
    WHERE NOT EXISTS (
        SELECT 1 FROM dbo.AvoqadoEntityTracking t WITH (UPDLOCK, HOLDLOCK)
        WHERE t.EntityType = ''order'' AND t.EntityId = c.EntityId
    );
END
');
PRINT N'  ✅ Trigger Trg_Avoqado_Orders (set-based) creado.';
GO

-- ---------------------------------------------------------------
-- Trigger de Items: misma detección FULL OUTER JOIN de la v2.2
-- (item_created/updated/deleted + ''item_change'' en la orden padre),
-- pero sin cursor: el idturno del padre se resuelve con CROSS APPLY
-- (mismo criterio MAX(idturno) por folio) y los upserts son por lote.
-- ---------------------------------------------------------------
IF OBJECT_ID('Trg_Avoqado_OrderItems', 'TR') IS NOT NULL DROP TRIGGER Trg_Avoqado_OrderItems;
EXEC('
CREATE TRIGGER Trg_Avoqado_OrderItems ON dbo.tempcheqdet AFTER INSERT, UPDATE, DELETE AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @InstanceId VARCHAR(36);
    SELECT TOP 1 @InstanceId = CAST(InstanceId AS VARCHAR(36)) FROM dbo.AvoqadoInstanceInfo;
    IF @InstanceId IS NULL RETURN;

    -- 1) Detectar todos los cambios del lote en una sola pasada.
    DECLARE @raw TABLE (foliodet INT, movimiento NUMERIC(3,0), ChangeReason VARCHAR(100), PRIMARY KEY (foliodet, movimiento));
    INSERT INTO @raw (foliodet, movimiento, ChangeReason)
    SELECT
        COALESCE(i.foliodet, d.foliodet),
        COALESCE(i.movimiento, d.movimiento),
        CASE
            WHEN i.movimiento IS NOT NULL AND d.movimiento IS NOT NULL THEN ''item_updated''
            WHEN i.movimiento IS NOT NULL THEN ''item_created''
            ELSE ''item_deleted''
        END
    FROM inserted i
    FULL OUTER JOIN deleted d ON i.foliodet = d.foliodet AND i.movimiento = d.movimiento
    WHERE COALESCE(i.foliodet, d.foliodet) IS NOT NULL;

    -- 2) Resolver idturno del padre (seek por PK folio vía CROSS APPLY).
    DECLARE @items TABLE (ItemEntityId VARCHAR(200) PRIMARY KEY, OrderEntityId VARCHAR(200), ChangeReason VARCHAR(100));
    INSERT INTO @items (ItemEntityId, OrderEntityId, ChangeReason)
    SELECT
        @InstanceId + '':'' + CAST(tc.idturno AS VARCHAR(30)) + '':'' + CAST(r.foliodet AS VARCHAR(30)) + '':'' + CAST(r.movimiento AS VARCHAR(10)),
        @InstanceId + '':'' + CAST(tc.idturno AS VARCHAR(30)) + '':'' + CAST(r.foliodet AS VARCHAR(30)),
        r.ChangeReason
    FROM @raw r
    CROSS APPLY (SELECT MAX(x.idturno) AS idturno FROM dbo.tempcheques x WHERE x.folio = r.foliodet) tc
    WHERE tc.idturno IS NOT NULL;

    IF NOT EXISTS (SELECT 1 FROM @items) RETURN;

    -- 3) Upsert de items.
    UPDATE t SET LastModifiedAt = GETUTCDATE(), ChangeReason = c.ChangeReason
    FROM dbo.AvoqadoEntityTracking t WITH (UPDLOCK, HOLDLOCK)
    INNER JOIN @items c ON t.EntityType = ''orderitem'' AND t.EntityId = c.ItemEntityId;

    INSERT INTO dbo.AvoqadoEntityTracking (EntityType, EntityId, ChangeReason)
    SELECT ''orderitem'', c.ItemEntityId, c.ChangeReason
    FROM @items c
    WHERE NOT EXISTS (
        SELECT 1 FROM dbo.AvoqadoEntityTracking t WITH (UPDLOCK, HOLDLOCK)
        WHERE t.EntityType = ''orderitem'' AND t.EntityId = c.ItemEntityId
    );

    -- 4) Upsert de la orden padre con motivo genérico (el Producer lo debouncea).
    DECLARE @orders TABLE (OrderEntityId VARCHAR(200) PRIMARY KEY);
    INSERT INTO @orders (OrderEntityId)
    SELECT DISTINCT OrderEntityId FROM @items;

    UPDATE t SET LastModifiedAt = GETUTCDATE(), ChangeReason = ''item_change''
    FROM dbo.AvoqadoEntityTracking t WITH (UPDLOCK, HOLDLOCK)
    INNER JOIN @orders o ON t.EntityType = ''order'' AND t.EntityId = o.OrderEntityId;

    INSERT INTO dbo.AvoqadoEntityTracking (EntityType, EntityId, ChangeReason)
    SELECT ''order'', o.OrderEntityId, ''item_change''
    FROM @orders o
    WHERE NOT EXISTS (
        SELECT 1 FROM dbo.AvoqadoEntityTracking t WITH (UPDLOCK, HOLDLOCK)
        WHERE t.EntityType = ''order'' AND t.EntityId = o.OrderEntityId
    );
END
');
PRINT N'  ✅ Trigger Trg_Avoqado_OrderItems (set-based) creado.';
GO

-- ---------------------------------------------------------------
-- Trigger de Turnos: mismos EntityIds (idturno) y ChangeReasons
-- (shift_created/updated/deleted) que la v2.2.
-- ---------------------------------------------------------------
IF OBJECT_ID('Trg_Avoqado_Shifts', 'TR') IS NOT NULL DROP TRIGGER Trg_Avoqado_Shifts;
EXEC('
CREATE TRIGGER Trg_Avoqado_Shifts ON dbo.turnos AFTER INSERT, UPDATE, DELETE AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @changes TABLE (EntityId VARCHAR(200) PRIMARY KEY, ChangeReason VARCHAR(100));

    IF EXISTS (SELECT 1 FROM inserted)
    BEGIN
        DECLARE @reason VARCHAR(100) = CASE WHEN EXISTS (SELECT 1 FROM deleted) THEN ''shift_updated'' ELSE ''shift_created'' END;
        INSERT INTO @changes (EntityId, ChangeReason)
        SELECT DISTINCT CAST(idturno AS VARCHAR(200)), @reason
        FROM inserted
        WHERE idturno IS NOT NULL;
    END
    ELSE
    BEGIN
        INSERT INTO @changes (EntityId, ChangeReason)
        SELECT DISTINCT CAST(idturno AS VARCHAR(200)), ''shift_deleted''
        FROM deleted
        WHERE idturno IS NOT NULL;
    END

    UPDATE t SET LastModifiedAt = GETUTCDATE(), ChangeReason = c.ChangeReason
    FROM dbo.AvoqadoEntityTracking t WITH (UPDLOCK, HOLDLOCK)
    INNER JOIN @changes c ON t.EntityType = ''shift'' AND t.EntityId = c.EntityId;

    INSERT INTO dbo.AvoqadoEntityTracking (EntityType, EntityId, ChangeReason)
    SELECT ''shift'', c.EntityId, c.ChangeReason
    FROM @changes c
    WHERE NOT EXISTS (
        SELECT 1 FROM dbo.AvoqadoEntityTracking t WITH (UPDLOCK, HOLDLOCK)
        WHERE t.EntityType = ''shift'' AND t.EntityId = c.EntityId
    );
END
');
PRINT N'  ✅ Trigger Trg_Avoqado_Shifts (set-based) creado.';
GO

SET NOEXEC OFF;
GO

PRINT N'';
PRINT N'🎉 =============================================================';
PRINT N'🎉 OPTIMIZACIÓN COMPLETADA (V2.3).';
PRINT N'🎉 Recuerda: actualizar el servicio a v2.3.x DESPUÉS de este script.';
PRINT N'🎉 =============================================================';
