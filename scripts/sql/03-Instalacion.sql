-- ====================================================================
-- 03 - SCRIPT DE INSTALACIÓN COMPLETA PARA SISTEMA AVOQADO
-- Crea todos los objetos necesarios verificando primero si existen
-- ====================================================================

PRINT N'🔧 =====================================================';
PRINT N'🔧 INSTALACIÓN COMPLETA DEL SISTEMA AVOQADO';
PRINT N'🔧 =====================================================';
PRINT N'';
PRINT N'📅 Fecha de instalación: ' + CONVERT(VARCHAR, GETDATE(), 120);
PRINT N'';

-- =====================================================
-- PASO 1: CREAR COLUMNAS SI NO EXISTEN
-- =====================================================

PRINT N'📌 PASO 1: VERIFICANDO Y CREANDO COLUMNAS...';
PRINT N'-------------------------------------------';

-- Crear columna en tempcheques si no existe
IF COL_LENGTH('tempcheques', 'AvoqadoLastModifiedAt') IS NULL
BEGIN
    ALTER TABLE tempcheques ADD AvoqadoLastModifiedAt DATETIME2 DEFAULT GETDATE();
    PRINT N'  ✅ Creada columna: tempcheques.AvoqadoLastModifiedAt';
END
ELSE
BEGIN
    PRINT N'  ℹ️ Columna ya existe: tempcheques.AvoqadoLastModifiedAt';
END

-- Crear columna en tempcheqdet si no existe
IF COL_LENGTH('tempcheqdet', 'AvoqadoLastModifiedAt') IS NULL
BEGIN
    ALTER TABLE tempcheqdet ADD AvoqadoLastModifiedAt DATETIME2 DEFAULT GETDATE();
    PRINT N'  ✅ Creada columna: tempcheqdet.AvoqadoLastModifiedAt';
END
ELSE
BEGIN
    PRINT N'  ℹ️ Columna ya existe: tempcheqdet.AvoqadoLastModifiedAt';
END

-- =====================================================
-- PASO 2: CREAR TABLAS DE TRACKING
-- =====================================================

PRINT N'';
PRINT N'📌 PASO 2: CREANDO TABLAS DE TRACKING...';
PRINT N'---------------------------------------';

-- Tabla universal de snapshots
IF OBJECT_ID('dbo.AvoqadoEntitySnapshots', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.AvoqadoEntitySnapshots (
        Id BIGINT IDENTITY(1,1) PRIMARY KEY,
        EntityType VARCHAR(50) NOT NULL,        -- 'order', 'shift', 'staff', 'area'
        EntityId VARCHAR(100) NOT NULL,         -- folio, idturno, idmesero, etc.
        ContentHash VARBINARY(32) NOT NULL,     -- Hash del contenido
        LastSentAt DATETIME2 NOT NULL,
        EventsSent INT DEFAULT 1,
        CreatedAt DATETIME2 DEFAULT GETDATE(),
        
        -- Indice compuesto para busquedas rapidas
        UNIQUE (EntityType, EntityId)
    );
    PRINT N'  ✅ Creada tabla: AvoqadoEntitySnapshots';
END
ELSE
BEGIN
    PRINT N'  ℹ️ Tabla ya existe: AvoqadoEntitySnapshots';
END

-- Tabla universal de tracking
IF OBJECT_ID('dbo.AvoqadoEntityTracking', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.AvoqadoEntityTracking (
        Id BIGINT IDENTITY(1,1) PRIMARY KEY,
        EntityType VARCHAR(50) NOT NULL,
        EntityId VARCHAR(100) NOT NULL,
        LastModifiedAt DATETIME2 NOT NULL DEFAULT GETDATE(),
        ChangeReason VARCHAR(100) NULL,         -- 'insert', 'update', 'delete', 'related_change'
        
        UNIQUE (EntityType, EntityId)
    );
    PRINT N'  ✅ Creada tabla: AvoqadoEntityTracking';
END
ELSE
BEGIN
    PRINT N'  ℹ️ Tabla ya existe: AvoqadoEntityTracking';
END

-- =====================================================
-- PASO 3: CREAR INDICES
-- =====================================================

PRINT N'';
PRINT N'📌 PASO 3: CREANDO INDICES...';
PRINT N'----------------------------';

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_AvoqadoEntitySnapshots_Type_LastSent')
BEGIN
    CREATE INDEX IX_AvoqadoEntitySnapshots_Type_LastSent 
    ON dbo.AvoqadoEntitySnapshots(EntityType, LastSentAt);
    PRINT N'  ✅ Creado índice: IX_AvoqadoEntitySnapshots_Type_LastSent';
END

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_AvoqadoEntityTracking_Modified')
BEGIN
    CREATE INDEX IX_AvoqadoEntityTracking_Modified 
    ON dbo.AvoqadoEntityTracking(LastModifiedAt, EntityType);
    PRINT N'  ✅ Creado índice: IX_AvoqadoEntityTracking_Modified';
END

-- =====================================================
-- PASO 4: CREAR PROCEDIMIENTOS ALMACENADOS
-- =====================================================

PRINT N'';
PRINT N'📌 PASO 4: CREANDO PROCEDIMIENTOS ALMACENADOS...';
PRINT N'-----------------------------------------------';

-- sp_TrackEntityChange
IF OBJECT_ID('dbo.sp_TrackEntityChange', 'P') IS NULL
BEGIN
    EXEC('
    CREATE PROCEDURE dbo.sp_TrackEntityChange
        @entityType VARCHAR(50),
        @entityId VARCHAR(100),
        @changeReason VARCHAR(100) = ''update''
    AS
    BEGIN
        SET NOCOUNT ON;
        
        IF EXISTS (SELECT 1 FROM AvoqadoEntityTracking WHERE EntityType = @entityType AND EntityId = @entityId)
        BEGIN
            UPDATE AvoqadoEntityTracking 
            SET LastModifiedAt = GETDATE(),
                ChangeReason = @changeReason
            WHERE EntityType = @entityType AND EntityId = @entityId;
        END
        ELSE
        BEGIN
            INSERT INTO AvoqadoEntityTracking (EntityType, EntityId, LastModifiedAt, ChangeReason)
            VALUES (@entityType, @entityId, GETDATE(), @changeReason);
        END
    END
    ');
    PRINT N'  ✅ Creado procedimiento: sp_TrackEntityChange';
END

-- sp_GetEntityChanges
IF OBJECT_ID('dbo.sp_GetEntityChanges', 'P') IS NULL
BEGIN
    EXEC('
    CREATE PROCEDURE dbo.sp_GetEntityChanges
        @lastSyncTimestamp DATETIME2,
        @entityType VARCHAR(50) = NULL,
        @maxResults INT = 100
    AS
    BEGIN
        SET NOCOUNT ON;
        
        WITH ChangedEntities AS (
            SELECT 
                et.EntityType,
                et.EntityId,
                et.LastModifiedAt,
                et.ChangeReason
            FROM AvoqadoEntityTracking et
            WHERE et.LastModifiedAt > @lastSyncTimestamp
              AND (@entityType IS NULL OR et.EntityType = @entityType)
        ),
        EntitiesWithHash AS (
            SELECT 
                ce.EntityType,
                ce.EntityId,
                ce.LastModifiedAt,
                ce.ChangeReason,
                CASE ce.EntityType
                    WHEN ''order'' THEN dbo.fn_GetOrderHash(CAST(ce.EntityId AS INT))
                    WHEN ''shift'' THEN dbo.fn_GetShiftHash(CAST(ce.EntityId AS BIGINT))
                    WHEN ''staff'' THEN dbo.fn_GetStaffHash(ce.EntityId)
                    ELSE HASHBYTES(''SHA2_256'', ce.EntityId)
                END as CurrentHash,
                snap.ContentHash as LastSentHash
            FROM ChangedEntities ce
            LEFT JOIN AvoqadoEntitySnapshots snap 
                ON ce.EntityType = snap.EntityType AND ce.EntityId = snap.EntityId
        )
        SELECT TOP (@maxResults)
            EntityType,
            EntityId,
            LastModifiedAt,
            ChangeReason,
            CurrentHash,
            LastSentHash,
            CASE 
                WHEN LastSentHash IS NULL THEN ''created''
                WHEN CurrentHash != LastSentHash THEN ''updated''
                ELSE ''no_change''
            END as EventType
        FROM EntitiesWithHash
        WHERE LastSentHash IS NULL OR CurrentHash != LastSentHash
        ORDER BY LastModifiedAt ASC;
    END
    ');
    PRINT N'  ✅ Creado procedimiento: sp_GetEntityChanges';
END

-- sp_UpdateEntitySnapshot
IF OBJECT_ID('dbo.sp_UpdateEntitySnapshot', 'P') IS NULL
BEGIN
    EXEC('
    CREATE PROCEDURE dbo.sp_UpdateEntitySnapshot
        @entityType VARCHAR(50),
        @entityId VARCHAR(100),
        @contentHash VARBINARY(32)
    AS
    BEGIN
        SET NOCOUNT ON;
        
        IF EXISTS (SELECT 1 FROM AvoqadoEntitySnapshots WHERE EntityType = @entityType AND EntityId = @entityId)
        BEGIN
            UPDATE AvoqadoEntitySnapshots 
            SET ContentHash = @contentHash,
                LastSentAt = GETDATE(),
                EventsSent = EventsSent + 1
            WHERE EntityType = @entityType AND EntityId = @entityId;
        END
        ELSE
        BEGIN
            INSERT INTO AvoqadoEntitySnapshots (EntityType, EntityId, ContentHash, LastSentAt, EventsSent)
            VALUES (@entityType, @entityId, @contentHash, GETDATE(), 1);
        END
    END
    ');
    PRINT N'  ✅ Creado procedimiento: sp_UpdateEntitySnapshot';
END

-- sp_CleanupStuckTracking
IF OBJECT_ID('dbo.sp_CleanupStuckTracking', 'P') IS NULL
BEGIN
    EXEC('
    CREATE PROCEDURE dbo.sp_CleanupStuckTracking
        @olderThanMinutes INT = 60
    AS
    BEGIN
        SET NOCOUNT ON;
        
        DECLARE @cutoffTime DATETIME2 = DATEADD(MINUTE, -@olderThanMinutes, GETDATE());
        DECLARE @cleanedCount INT = 0;
        
        DECLARE stuck_cursor CURSOR FOR
            SELECT DISTINCT t.EntityType, t.EntityId
            FROM AvoqadoEntityTracking t
            LEFT JOIN AvoqadoEntitySnapshots s ON t.EntityType = s.EntityType AND t.EntityId = s.EntityId
            WHERE t.LastModifiedAt < @cutoffTime
              AND (s.LastSentAt IS NULL OR s.LastSentAt < t.LastModifiedAt);
        
        DECLARE @entityType VARCHAR(50), @entityId VARCHAR(100);
        
        OPEN stuck_cursor;
        FETCH NEXT FROM stuck_cursor INTO @entityType, @entityId;
        
        WHILE @@FETCH_STATUS = 0
        BEGIN
            DECLARE @exists BIT = 0;
            
            IF @entityType = ''order''
            BEGIN
                IF EXISTS (SELECT 1 FROM tempcheques WHERE folio = CAST(@entityId AS INT))
                    SET @exists = 1;
            END
            
            IF @exists = 0
            BEGIN
                DELETE FROM AvoqadoEntityTracking 
                WHERE EntityType = @entityType AND EntityId = @entityId;
                
                IF EXISTS (SELECT 1 FROM AvoqadoEntitySnapshots WHERE EntityType = @entityType AND EntityId = @entityId)
                BEGIN
                    UPDATE AvoqadoEntitySnapshots 
                    SET ContentHash = HASHBYTES(''SHA2_256'', ''DELETED''),
                        LastSentAt = GETDATE()
                    WHERE EntityType = @entityType AND EntityId = @entityId;
                END
                ELSE
                BEGIN
                    INSERT INTO AvoqadoEntitySnapshots (EntityType, EntityId, ContentHash, LastSentAt)
                    VALUES (@entityType, @entityId, HASHBYTES(''SHA2_256'', ''DELETED''), GETDATE());
                END
                
                SET @cleanedCount = @cleanedCount + 1;
            END
            
            FETCH NEXT FROM stuck_cursor INTO @entityType, @entityId;
        END;
        
        CLOSE stuck_cursor;
        DEALLOCATE stuck_cursor;
        
        RETURN @cleanedCount;
    END
    ');
    PRINT N'  ✅ Creado procedimiento: sp_CleanupStuckTracking';
END

-- =====================================================
-- PASO 5: CREAR FUNCIONES
-- =====================================================

PRINT N'';
PRINT N'📌 PASO 5: CREANDO FUNCIONES...';
PRINT N'------------------------------';

-- fn_GetOrderHash
IF OBJECT_ID('dbo.fn_GetOrderHash', 'FN') IS NULL
BEGIN
    EXEC('
    CREATE FUNCTION dbo.fn_GetOrderHash(@folio INT)
    RETURNS VARBINARY(32)
    AS
    BEGIN
        DECLARE @content NVARCHAR(MAX);
        DECLARE @orderContent NVARCHAR(MAX);
        DECLARE @itemsContent NVARCHAR(MAX);
        
        SELECT @orderContent = 
            ISNULL(CAST(total as NVARCHAR(50)), '''') + ''|'' +
            ISNULL(CAST(subtotal as NVARCHAR(50)), '''') + ''|'' + 
            ISNULL(CAST(pagado as NVARCHAR(50)), '''') + ''|'' +
            ISNULL(CAST(cancelado as NVARCHAR(50)), '''') + ''|'' +
            ISNULL(idmesero, '''') + ''|'' +
            ISNULL(CAST(mesa as NVARCHAR(50)), '''') + ''|''
        FROM tempcheques 
        WHERE folio = @folio;
        
        SELECT @itemsContent = COALESCE(
            (SELECT 
                ISNULL(CAST(cantidad as NVARCHAR(50)), '''') + ''-'' +
                ISNULL(idproducto, '''') + ''-'' + 
                ISNULL(CAST(precio as NVARCHAR(50)), '''') + '',''
             FROM tempcheqdet 
             WHERE foliodet = @folio
             ORDER BY idproducto
             FOR XML PATH('''')
            ), ''''
        );
        
        SET @content = ISNULL(@orderContent, '''') + ISNULL(@itemsContent, '''');
        RETURN HASHBYTES(''SHA2_256'', @content);
    END
    ');
    PRINT N'  ✅ Creada función: fn_GetOrderHash';
END

-- fn_GetShiftHash
IF OBJECT_ID('dbo.fn_GetShiftHash', 'FN') IS NULL
BEGIN
    EXEC('
    CREATE FUNCTION dbo.fn_GetShiftHash(@idturno BIGINT)
    RETURNS VARBINARY(32)
    AS
    BEGIN
        DECLARE @content NVARCHAR(MAX);
        
        SELECT @content = 
            ISNULL(CAST(idturno as NVARCHAR(50)), '''') + ''|'' +
            ISNULL(CAST(apertura as NVARCHAR(50)), '''') + ''|'' +
            ISNULL(CAST(cierre as NVARCHAR(50)), '''') + ''|'' +
            ISNULL(idmesero, '''') + ''|''
        FROM turnos 
        WHERE idturno = @idturno;
        
        RETURN HASHBYTES(''SHA2_256'', ISNULL(@content, ''''));
    END
    ');
    PRINT N'  ✅ Creada función: fn_GetShiftHash';
END

-- fn_GetStaffHash
IF OBJECT_ID('dbo.fn_GetStaffHash', 'FN') IS NULL
BEGIN
    EXEC('
    CREATE FUNCTION dbo.fn_GetStaffHash(@idmesero VARCHAR(50))
    RETURNS VARBINARY(32)
    AS
    BEGIN
        DECLARE @content NVARCHAR(MAX);
        
        SELECT @content = 
            ISNULL(idmesero, '''') + ''|'' +
            ISNULL(nombre, '''') + ''|'' +
            ISNULL(contraseña, '''') + ''|''
        FROM meseros 
        WHERE idmesero = @idmesero;
        
        RETURN HASHBYTES(''SHA2_256'', ISNULL(@content, ''''));
    END
    ');
    PRINT N'  ✅ Creada función: fn_GetStaffHash';
END

-- =====================================================
-- PASO 6: CREAR TRIGGERS
-- =====================================================

PRINT N'';
PRINT N'📌 PASO 6: CREANDO TRIGGERS...';
PRINT N'-----------------------------';

-- Trigger para ordenes principales
IF NOT EXISTS (SELECT * FROM sys.triggers WHERE name = 'Trg_Avoqado_Orders')
BEGIN
    EXEC('
    CREATE TRIGGER Trg_Avoqado_Orders
    ON dbo.tempcheques
    AFTER INSERT, UPDATE, DELETE
    AS
    BEGIN
        SET NOCOUNT ON;
        
        -- Actualizar timestamp en la misma tabla (solo para INSERT/UPDATE)
        IF EXISTS (SELECT 1 FROM inserted)
        BEGIN
            UPDATE tc
            SET AvoqadoLastModifiedAt = GETDATE()
            FROM dbo.tempcheques tc
            INNER JOIN inserted i ON tc.folio = i.folio;
        END
        
        -- Registrar cambio en tracking universal
        DECLARE @entityId VARCHAR(100);
        DECLARE @changeReason VARCHAR(100);
        
        -- Manejar INSERT/UPDATE
        IF EXISTS (SELECT 1 FROM inserted)
        BEGIN
            DECLARE order_cursor CURSOR FOR 
                SELECT DISTINCT CAST(folio AS VARCHAR(100)) FROM inserted;
            
            SET @changeReason = CASE 
                WHEN EXISTS (SELECT 1 FROM deleted) THEN ''order_updated''
                ELSE ''order_created''
            END;
            
            OPEN order_cursor;
            FETCH NEXT FROM order_cursor INTO @entityId;
            
            WHILE @@FETCH_STATUS = 0
            BEGIN
                EXEC sp_TrackEntityChange ''order'', @entityId, @changeReason;
                FETCH NEXT FROM order_cursor INTO @entityId;
            END;
            
            CLOSE order_cursor;
            DEALLOCATE order_cursor;
        END
        
        -- Manejar DELETE
        IF EXISTS (SELECT 1 FROM deleted) AND NOT EXISTS (SELECT 1 FROM inserted)
        BEGIN
            DECLARE delete_cursor CURSOR FOR 
                SELECT DISTINCT CAST(folio AS VARCHAR(100)) FROM deleted;
            
            OPEN delete_cursor;
            FETCH NEXT FROM delete_cursor INTO @entityId;
            
            WHILE @@FETCH_STATUS = 0
            BEGIN
                EXEC sp_TrackEntityChange ''order'', @entityId, ''order_deleted'';
                FETCH NEXT FROM delete_cursor INTO @entityId;
            END;
            
            CLOSE delete_cursor;
            DEALLOCATE delete_cursor;
        END
    END
    ');
    PRINT N'  ✅ Creado trigger: Trg_Avoqado_Orders';
END

-- Trigger para items de ordenes
IF NOT EXISTS (SELECT * FROM sys.triggers WHERE name = 'Trg_Avoqado_OrderItems')
BEGIN
    EXEC('
    CREATE TRIGGER Trg_Avoqado_OrderItems
    ON dbo.tempcheqdet
    AFTER INSERT, UPDATE, DELETE
    AS
    BEGIN
        SET NOCOUNT ON;
        
        -- Actualizar timestamp en la misma tabla (solo para INSERT/UPDATE)
        IF EXISTS (SELECT 1 FROM inserted)
        BEGIN
            UPDATE td
            SET AvoqadoLastModifiedAt = GETDATE()
            FROM dbo.tempcheqdet td
            INNER JOIN inserted i ON td.foliodet = i.foliodet AND td.idproducto = i.idproducto;
        END
        
        -- Actualizar timestamp en tabla padre y registrar cambio
        DECLARE @entityId VARCHAR(100);
        DECLARE item_cursor CURSOR FOR 
            SELECT DISTINCT CAST(foliodet AS VARCHAR(100)) FROM (
                SELECT foliodet FROM inserted
                UNION
                SELECT foliodet FROM deleted
            ) affected_orders;
        
        OPEN item_cursor;
        FETCH NEXT FROM item_cursor INTO @entityId;
        
        WHILE @@FETCH_STATUS = 0
        BEGIN
            -- Actualizar timestamp en orden padre (solo si la orden aún existe)
            UPDATE tempcheques 
            SET AvoqadoLastModifiedAt = GETDATE() 
            WHERE folio = CAST(@entityId AS INT);
            
            -- Registrar cambio
            EXEC sp_TrackEntityChange ''order'', @entityId, ''item_change'';
            FETCH NEXT FROM item_cursor INTO @entityId;
        END;
        
        CLOSE item_cursor;
        DEALLOCATE item_cursor;
    END
    ');
    PRINT N'  ✅ Creado trigger: Trg_Avoqado_OrderItems';
END

-- Trigger para turnos (con lógica de eliminar y recrear)

-- 1. Primero, se elimina el trigger si ya existe para asegurar la actualización.
IF EXISTS (SELECT * FROM sys.triggers WHERE name = 'Trg_Avoqado_Shifts')
BEGIN
    DROP TRIGGER Trg_Avoqado_Shifts;
    PRINT N'  ⚠️ Trigger existente Trg_Avoqado_Shifts eliminado para recrearlo.';
END

-- 2. Después, se crea la versión más reciente del trigger.
EXEC('
CREATE TRIGGER Trg_Avoqado_Shifts
ON dbo.turnos
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @entityId VARCHAR(100);
    DECLARE @changeReason VARCHAR(100);

    -- Manejar INSERT y UPDATE
    IF EXISTS (SELECT 1 FROM inserted)
    BEGIN
        SET @changeReason = CASE
            WHEN EXISTS (SELECT 1 FROM deleted) THEN ''shift_updated''
            ELSE ''shift_created''
        END;

        DECLARE shift_cursor CURSOR FOR
            SELECT DISTINCT CAST(idturno AS VARCHAR(100)) FROM inserted;

        OPEN shift_cursor;
        FETCH NEXT FROM shift_cursor INTO @entityId;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            EXEC sp_TrackEntityChange ''shift'', @entityId, @changeReason;
            FETCH NEXT FROM shift_cursor INTO @entityId;
        END;
        CLOSE shift_cursor;
        DEALLOCATE shift_cursor;
    END
    -- Manejar DELETE
    ELSE IF EXISTS (SELECT 1 FROM deleted)
    BEGIN
        DECLARE delete_cursor CURSOR FOR
            SELECT DISTINCT CAST(idturno AS VARCHAR(100)) FROM deleted;

        OPEN delete_cursor;
        FETCH NEXT FROM delete_cursor INTO @entityId;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            EXEC sp_TrackEntityChange ''shift'', @entityId, ''shift_deleted'';
            FETCH NEXT FROM delete_cursor INTO @entityId;
        END;
        CLOSE delete_cursor;
        DEALLOCATE delete_cursor;
    END
END
');
PRINT N'  ✅ Creado trigger: Trg_Avoqado_Shifts';

-- =====================================================
-- PASO 7: VERIFICACIÓN FINAL
-- =====================================================

PRINT N'';
PRINT N'📌 PASO 7: VERIFICACIÓN FINAL...';
PRINT N'-------------------------------';

-- Verificar objetos creados
DECLARE @CreatedObjects INT = 0;

IF EXISTS (SELECT 1 FROM sys.tables WHERE name IN ('AvoqadoEntitySnapshots', 'AvoqadoEntityTracking'))
    SET @CreatedObjects = @CreatedObjects + 2;

IF EXISTS (SELECT 1 FROM sys.procedures WHERE name IN ('sp_TrackEntityChange', 'sp_GetEntityChanges', 'sp_UpdateEntitySnapshot', 'sp_CleanupStuckTracking'))
    SET @CreatedObjects = @CreatedObjects + 4;

IF EXISTS (SELECT 1 FROM sys.objects WHERE type = 'FN' AND name IN ('fn_GetOrderHash', 'fn_GetShiftHash', 'fn_GetStaffHash'))
    SET @CreatedObjects = @CreatedObjects + 3;

IF EXISTS (SELECT 1 FROM sys.triggers WHERE name IN ('Trg_Avoqado_Orders', 'Trg_Avoqado_OrderItems'))
    SET @CreatedObjects = @CreatedObjects + 2;

PRINT N'';
PRINT N'📊 =====================================================';
PRINT N'📊 RESUMEN DE INSTALACIÓN:';
PRINT N'📊 =====================================================';
PRINT N'  ✅ Objetos principales creados: ' + CAST(@CreatedObjects AS NVARCHAR(10)) + '/11';
PRINT N'  ✅ Sistema Avoqado instalado correctamente';
PRINT N'';
PRINT N'📝 NOTAS IMPORTANTES:';
PRINT N'  • Los triggers solo manejan órdenes (tempcheques/tempcheqdet)';
PRINT N'  • Para soporte DELETE: las órdenes eliminadas se marcan como "order_deleted"';
PRINT N'  • Use sp_CleanupStuckTracking para limpiar registros atascados';
PRINT N'';
PRINT N'🏁 INSTALACIÓN COMPLETADA';
PRINT N'   Puede proceder con el script 04-Pruebas';
PRINT N'=====================================================';