-- ====================================================================
-- 03-UNIFICADO - SCRIPT DE INSTALACIÓN Y ACTUALIZACIÓN COMPLETA
-- Crea y actualiza todos los objetos necesarios para el sistema AVOQADO.
-- Incluye el tracking a nivel de item de orden.
-- ====================================================================

PRINT N'🔧 =============================================================';
PRINT N'🔧 INSTALACIÓN/ACTUALIZACIÓN COMPLETA DEL SISTEMA AVOQADO';
PRINT N'🔧 =============================================================';
PRINT N'';
PRINT N'📅 Fecha de ejecución: ' + CONVERT(VARCHAR, GETDATE(), 120);
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
        EntityType VARCHAR(50) NOT NULL,      -- 'order', 'shift', 'staff', 'orderitem', etc.
        EntityId VARCHAR(100) NOT NULL,      -- folio, idturno, folio:idproducto, etc.
        ContentHash VARBINARY(32) NOT NULL,  -- Hash del contenido
        LastSentAt DATETIME2 NOT NULL,
        EventsSent INT DEFAULT 1,
        CreatedAt DATETIME2 DEFAULT GETDATE(),
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
        ChangeReason VARCHAR(100) NULL,      -- 'insert', 'update', 'delete', 'item_change'
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
ELSE
    PRINT N'  ℹ️ Índice ya existe: IX_AvoqadoEntitySnapshots_Type_LastSent';


IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_AvoqadoEntityTracking_Modified')
BEGIN
    CREATE INDEX IX_AvoqadoEntityTracking_Modified  
    ON dbo.AvoqadoEntityTracking(LastModifiedAt, EntityType);
    PRINT N'  ✅ Creado índice: IX_AvoqadoEntityTracking_Modified';
END
ELSE
    PRINT N'  ℹ️ Índice ya existe: IX_AvoqadoEntityTracking_Modified';

-- =====================================================
-- PASO 4: CREAR/ACTUALIZAR FUNCIONES
-- =====================================================
PRINT N'';
PRINT N'📌 PASO 4: CREANDO/ACTUALIZANDO FUNCIONES...';
PRINT N'-------------------------------------------';

-- fn_GetOrderHash
IF OBJECT_ID('dbo.fn_GetOrderHash', 'FN') IS NOT NULL DROP FUNCTION dbo.fn_GetOrderHash;
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
PRINT N'  ✅ Creada/Actualizada función: fn_GetOrderHash';

-- fn_GetOrderItemHash (VERSIÓN CORREGIDA)
IF OBJECT_ID('dbo.fn_GetOrderItemHash', 'FN') IS NOT NULL DROP FUNCTION dbo.fn_GetOrderItemHash;
EXEC('
CREATE FUNCTION dbo.fn_GetOrderItemHash(@foliodet INT, @idproducto VARCHAR(50))
RETURNS VARBINARY(32)
AS
BEGIN
    DECLARE @content NVARCHAR(MAX);
    
    -- NOTA: Se usan las columnas existentes en la tabla tempcheqdet.
    -- Se ha sustituido "observaciones" por "comentario".
    -- Se han omitido "importe" y "cancelado" por no existir y se ha añadido "descuento".
    SELECT @content = 
        ISNULL(CAST(foliodet as NVARCHAR(50)), '''') + ''|'' +
        ISNULL(idproducto, '''') + ''|'' +
        ISNULL(CAST(cantidad as NVARCHAR(50)), '''') + ''|'' +
        ISNULL(CAST(precio as NVARCHAR(50)), '''') + ''|'' +
        ISNULL(CAST(descuento as NVARCHAR(50)), '''') + ''|'' +
        ISNULL(comentario, '''') + ''|''
    FROM tempcheqdet 
    WHERE foliodet = @foliodet AND idproducto = @idproducto;
    
    RETURN HASHBYTES(''SHA2_256'', ISNULL(@content, ''''));
END
');
PRINT N'  ✅ Creada/Actualizada función: fn_GetOrderItemHash (Corregida)';

-- fn_GetShiftHash
IF OBJECT_ID('dbo.fn_GetShiftHash', 'FN') IS NOT NULL DROP FUNCTION dbo.fn_GetShiftHash;
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
PRINT N'  ✅ Creada/Actualizada función: fn_GetShiftHash';

-- fn_GetStaffHash
IF OBJECT_ID('dbo.fn_GetStaffHash', 'FN') IS NOT NULL DROP FUNCTION dbo.fn_GetStaffHash;
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
PRINT N'  ✅ Creada/Actualizada función: fn_GetStaffHash';


-- =====================================================
-- PASO 5: CREAR/ACTUALIZAR PROCEDIMIENTOS ALMACENADOS
-- =====================================================

PRINT N'';
PRINT N'📌 PASO 5: CREANDO/ACTUALIZANDO PROCEDIMIENTOS ALMACENADOS...';
PRINT N'-----------------------------------------------------------';

-- sp_TrackEntityChange
IF OBJECT_ID('dbo.sp_TrackEntityChange', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_TrackEntityChange;
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
PRINT N'  ✅ Creado/Actualizado procedimiento: sp_TrackEntityChange';

-- sp_GetEntityChanges (VERSIÓN ACTUALIZADA)
IF OBJECT_ID('dbo.sp_GetEntityChanges', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_GetEntityChanges;
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
                WHEN ''orderitem'' THEN 
                    CASE 
                        WHEN CHARINDEX('':'', ce.EntityId) > 0 THEN
                            dbo.fn_GetOrderItemHash(
                                CAST(SUBSTRING(ce.EntityId, 1, CHARINDEX('':'', ce.EntityId) - 1) AS INT),
                                SUBSTRING(ce.EntityId, CHARINDEX('':'', ce.EntityId) + 1, LEN(ce.EntityId))
                            )
                        ELSE NULL
                    END
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
            WHEN ChangeReason LIKE ''%_deleted'' AND LastSentHash IS NULL THEN ''deleted''
            WHEN LastSentHash IS NULL THEN ''created''
            WHEN CurrentHash != LastSentHash THEN ''updated''
            ELSE ''no_change''
        END as EventType
    FROM EntitiesWithHash
    WHERE (LastSentHash IS NULL OR CurrentHash != LastSentHash) OR ChangeReason LIKE ''%_deleted''
    ORDER BY LastModifiedAt ASC;
END
');
PRINT N'  ✅ Creado/Actualizado procedimiento: sp_GetEntityChanges';

-- sp_UpdateEntitySnapshot
IF OBJECT_ID('dbo.sp_UpdateEntitySnapshot', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_UpdateEntitySnapshot;
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
PRINT N'  ✅ Creado/Actualizado procedimiento: sp_UpdateEntitySnapshot';

-- sp_CleanupStuckTracking
IF OBJECT_ID('dbo.sp_CleanupStuckTracking', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_CleanupStuckTracking;
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
        DECLARE @exists BIT = 1; -- Assume it exists unless proven otherwise
        
        -- Check if the entity still exists in the source table
        IF @entityType = ''order''
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM tempcheques WHERE folio = CAST(@entityId AS INT)) SET @exists = 0;
        END
        ELSE IF @entityType = ''orderitem'' AND CHARINDEX('':'', @entityId) > 0
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM tempcheqdet WHERE foliodet = CAST(SUBSTRING(@entityId, 1, CHARINDEX('':'', @entityId) - 1) AS INT) AND idproducto = SUBSTRING(@entityId, CHARINDEX('':'', @entityId) + 1, LEN(@entityId))) SET @exists = 0;
        END
        -- Add checks for other entities like ''shift'', ''staff'', etc.

        IF @exists = 0
        BEGIN
            -- The entity was deleted from the source system. Mark it for deletion.
            EXEC sp_TrackEntityChange @entityType, @entityId, ''deleted'';
            SET @cleanedCount = @cleanedCount + 1;
        END
        
        FETCH NEXT FROM stuck_cursor INTO @entityType, @entityId;
    END;
    
    CLOSE stuck_cursor;
    DEALLOCATE stuck_cursor;
    
    PRINT N''  ℹ️ Registros atascados procesados como eliminados: '' + CAST(@cleanedCount AS VARCHAR);
    RETURN @cleanedCount;
END
');
PRINT N'  ✅ Creado/Actualizado procedimiento: sp_CleanupStuckTracking';


-- =====================================================
-- PASO 6: CREAR/ACTUALIZAR TRIGGERS
-- =====================================================

PRINT N'';
PRINT N'📌 PASO 6: CREANDO/ACTUALIZANDO TRIGGERS...';
PRINT N'------------------------------------------';

-- Trigger para ordenes principales
IF OBJECT_ID('Trg_Avoqado_Orders', 'TR') IS NOT NULL DROP TRIGGER Trg_Avoqado_Orders;
EXEC('
CREATE TRIGGER Trg_Avoqado_Orders
ON dbo.tempcheques
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    
    IF EXISTS (SELECT 1 FROM inserted)
    BEGIN
        UPDATE tc
        SET AvoqadoLastModifiedAt = GETDATE()
        FROM dbo.tempcheques tc
        INNER JOIN inserted i ON tc.folio = i.folio;
    END
    
    DECLARE @entityId VARCHAR(100);
    DECLARE @changeReason VARCHAR(100);
    
    -- Manejar INSERT/UPDATE
    IF EXISTS (SELECT 1 FROM inserted)
    BEGIN
        SET @changeReason = CASE 
            WHEN EXISTS (SELECT 1 FROM deleted) THEN ''order_updated''
            ELSE ''order_created''
        END;
        
        DECLARE order_cursor CURSOR FOR 
            SELECT DISTINCT CAST(folio AS VARCHAR(100)) FROM inserted;
        
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
    ELSE IF EXISTS (SELECT 1 FROM deleted)
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
PRINT N'  ✅ Creado/Actualizado trigger: Trg_Avoqado_Orders';

-- Trigger para items de ordenes (VERSIÓN ACTUALIZADA)
IF OBJECT_ID('Trg_Avoqado_OrderItems', 'TR') IS NOT NULL DROP TRIGGER Trg_Avoqado_OrderItems;
EXEC('
CREATE TRIGGER Trg_Avoqado_OrderItems
ON dbo.tempcheqdet
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @orderEntityId VARCHAR(100);
    DECLARE @itemEntityId VARCHAR(100);
    DECLARE @changeReason VARCHAR(100);
    DECLARE @foliodet INT;
    DECLARE @idproducto VARCHAR(50);

    -- CASO 1: INSERT/UPDATE de items
    IF EXISTS (SELECT 1 FROM inserted)
    BEGIN
        UPDATE td
        SET AvoqadoLastModifiedAt = GETDATE()
        FROM dbo.tempcheqdet td
        INNER JOIN inserted i ON td.foliodet = i.foliodet AND td.idproducto = i.idproducto;
        
        DECLARE item_cursor CURSOR FOR 
            SELECT DISTINCT foliodet, idproducto FROM inserted;
        
        OPEN item_cursor;
        FETCH NEXT FROM item_cursor INTO @foliodet, @idproducto;
        
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @itemEntityId = CAST(@foliodet AS VARCHAR) + '':'' + @idproducto;
            SET @orderEntityId = CAST(@foliodet AS VARCHAR);
            
            SET @changeReason = CASE 
                WHEN EXISTS (SELECT 1 FROM deleted WHERE foliodet = @foliodet AND idproducto = @idproducto) 
                THEN ''item_updated''
                ELSE ''item_created''
            END;
            
            EXEC sp_TrackEntityChange ''orderitem'', @itemEntityId, @changeReason;
            EXEC sp_TrackEntityChange ''order'', @orderEntityId, ''item_change''; -- Actualiza la orden padre
            
            FETCH NEXT FROM item_cursor INTO @foliodet, @idproducto;
        END;
        
        CLOSE item_cursor;
        DEALLOCATE item_cursor;
    END
    -- CASO 2: DELETE de items
    ELSE IF EXISTS (SELECT 1 FROM deleted)
    BEGIN
        DECLARE delete_cursor CURSOR FOR 
            SELECT DISTINCT foliodet, idproducto FROM deleted;
        
        OPEN delete_cursor;
        FETCH NEXT FROM delete_cursor INTO @foliodet, @idproducto;
        
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @itemEntityId = CAST(@foliodet AS VARCHAR) + '':'' + @idproducto;
            SET @orderEntityId = CAST(@foliodet AS VARCHAR);
            
            EXEC sp_TrackEntityChange ''orderitem'', @itemEntityId, ''item_deleted'';
            EXEC sp_TrackEntityChange ''order'', @orderEntityId, ''item_removed''; -- Actualiza la orden padre
            
            FETCH NEXT FROM delete_cursor INTO @foliodet, @idproducto;
        END;
        
        CLOSE delete_cursor;
        DEALLOCATE delete_cursor;
    END
END
');
PRINT N'  ✅ Creado/Actualizado trigger: Trg_Avoqado_OrderItems';

-- Trigger para turnos
IF OBJECT_ID('Trg_Avoqado_Shifts', 'TR') IS NOT NULL DROP TRIGGER Trg_Avoqado_Shifts;
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
PRINT N'  ✅ Creado/Actualizado trigger: Trg_Avoqado_Shifts';


-- =====================================================
-- PASO 7: VERIFICACIÓN FINAL
-- =====================================================

PRINT N'';
PRINT N'📌 PASO 7: VERIFICACIÓN FINAL...';
PRINT N'-------------------------------';

DECLARE @ObjectCount INT = 0;
DECLARE @TotalObjects INT = 13; -- Actualizado el total de objetos (se añadió Trg_Avoqado_Shifts)

IF OBJECT_ID('dbo.AvoqadoEntitySnapshots', 'U') IS NOT NULL SET @ObjectCount = @ObjectCount + 1;
IF OBJECT_ID('dbo.AvoqadoEntityTracking', 'U') IS NOT NULL SET @ObjectCount = @ObjectCount + 1;
IF OBJECT_ID('dbo.sp_TrackEntityChange', 'P') IS NOT NULL SET @ObjectCount = @ObjectCount + 1;
IF OBJECT_ID('dbo.sp_GetEntityChanges', 'P') IS NOT NULL SET @ObjectCount = @ObjectCount + 1;
IF OBJECT_ID('dbo.sp_UpdateEntitySnapshot', 'P') IS NOT NULL SET @ObjectCount = @ObjectCount + 1;
IF OBJECT_ID('dbo.sp_CleanupStuckTracking', 'P') IS NOT NULL SET @ObjectCount = @ObjectCount + 1;
IF OBJECT_ID('dbo.fn_GetOrderHash', 'FN') IS NOT NULL SET @ObjectCount = @ObjectCount + 1;
IF OBJECT_ID('dbo.fn_GetOrderItemHash', 'FN') IS NOT NULL SET @ObjectCount = @ObjectCount + 1;
IF OBJECT_ID('dbo.fn_GetShiftHash', 'FN') IS NOT NULL SET @ObjectCount = @ObjectCount + 1;
IF OBJECT_ID('dbo.fn_GetStaffHash', 'FN') IS NOT NULL SET @ObjectCount = @ObjectCount + 1;
IF OBJECT_ID('Trg_Avoqado_Orders', 'TR') IS NOT NULL SET @ObjectCount = @ObjectCount + 1;
IF OBJECT_ID('Trg_Avoqado_OrderItems', 'TR') IS NOT NULL SET @ObjectCount = @ObjectCount + 1;
IF OBJECT_ID('Trg_Avoqado_Shifts', 'TR') IS NOT NULL SET @ObjectCount = @ObjectCount + 1;


PRINT N'';
PRINT N'📊 =====================================================';
PRINT N'📊 RESUMEN DE INSTALACIÓN:';
PRINT N'📊 =====================================================';
PRINT N'  ✅ Objetos creados/actualizados: ' + CAST(@ObjectCount AS NVARCHAR(10)) + '/' + CAST(@TotalObjects AS NVARCHAR(10));
IF @ObjectCount = @TotalObjects
    PRINT N'  ✅ ¡Sistema Avoqado instalado y actualizado correctamente!';
ELSE
    PRINT N'  ❌ ATENCIÓN: No todos los objetos se crearon correctamente. Revise los mensajes de error.';

PRINT N'';
PRINT N'📝 NOTAS IMPORTANTES:';
PRINT N'  • Este script es ahora unificado. Incluye la creación y actualización de todos los objetos.';
PRINT N'  • Se ha añadido tracking para "orderitem" con el formato de ID: "folio:idproducto".';
PRINT N'  • Los cambios en items (crear, actualizar, borrar) también marcan la orden padre como modificada.';
PRINT N'';
PRINT N'🏁 INSTALACIÓN COMPLETADA';
PRINT N'=====================================================';