-- ====================================================================
-- 02 - SCRIPT DE LIMPIEZA DEFINITIVO PARA SISTEMA AVOQADO
-- Elimina TODOS los objetos de la instalación nueva y de versiones antiguas.
-- Creado para ser el inverso exacto del script 03-Instalación.
-- ====================================================================

PRINT N'🧹 =====================================================';
PRINT N'🧹 LIMPIEZA DEFINITIVA DEL SISTEMA AVOQADO';
PRINT N'🧹 =====================================================';
PRINT N'';
PRINT N'📅 Fecha de limpieza: ' + CONVERT(VARCHAR, GETDATE(), 120);
PRINT N'';

-- Variables para contar objetos eliminados
DECLARE @TriggerCount INT = 0;
DECLARE @ProcCount INT = 0;
DECLARE @FuncCount INT = 0;
DECLARE @TableCount INT = 0;
DECLARE @ColumnCount INT = 0;
DECLARE @IndexCount INT = 0;
DECLARE @sql NVARCHAR(MAX);
DECLARE @triggerName NVARCHAR(128), @procName NVARCHAR(128), @funcName NVARCHAR(128), @indexName NVARCHAR(128), @constraintName NVARCHAR(128);


-- 1. ELIMINAR TRIGGERS
PRINT N'📌 1. ELIMINANDO TRIGGERS...';
PRINT N'-----------------------------';

DECLARE @AvoqadoTriggers TABLE (TriggerName NVARCHAR(128));
INSERT INTO @AvoqadoTriggers VALUES
    ('Trg_Avoqado_Orders'),
    ('Trg_Avoqado_OrderItems'),
    ('Trg_Avoqado_UpdateTimestamp'),
    ('Trg_Avoqado_ItemsUpdateParent'),
    ('trg_AvoqadoOrderTracking'),
    ('Trg_Avoqado_Shifts'),
    ('Trg_Avoqado_Areas'),
    ('Trg_Avoqado_Staff');

DECLARE trigger_cursor CURSOR FOR
    SELECT t.name
    FROM sys.triggers t
    WHERE t.name IN (SELECT TriggerName FROM @AvoqadoTriggers)
       OR LOWER(t.name) LIKE '%avoqado%'
       OR LOWER(t.name) LIKE '%avocado%';

OPEN trigger_cursor;
FETCH NEXT FROM trigger_cursor INTO @triggerName;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'DROP TRIGGER ' + QUOTENAME(@triggerName);
    EXEC sp_executesql @sql;
    PRINT N'  ✅ Eliminado trigger: ' + @triggerName;
    SET @TriggerCount = @TriggerCount + 1;
    FETCH NEXT FROM trigger_cursor INTO @triggerName;
END;
CLOSE trigger_cursor;
DEALLOCATE trigger_cursor;

IF @TriggerCount = 0
    PRINT N'  ℹ️ No se encontraron triggers de Avoqado';


-- 2. ELIMINAR PROCEDIMIENTOS ALMACENADOS
PRINT N'';
PRINT N'📌 2. ELIMINANDO PROCEDIMIENTOS...';
PRINT N'-----------------------------------';

DECLARE proc_cursor CURSOR FOR
    SELECT name
    FROM sys.procedures
    WHERE name IN (
        'sp_TrackEntityChange',
        'sp_GetEntityChanges',
        'sp_UpdateEntitySnapshot',
        'sp_CleanupStuckTracking'
    )
    OR LOWER(name) LIKE '%avoqado%';

OPEN proc_cursor;
FETCH NEXT FROM proc_cursor INTO @procName;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'DROP PROCEDURE ' + QUOTENAME(@procName);
    EXEC sp_executesql @sql;
    PRINT N'  ✅ Eliminado procedimiento: ' + @procName;
    SET @ProcCount = @ProcCount + 1;
    FETCH NEXT FROM proc_cursor INTO @procName;
END;
CLOSE proc_cursor;
DEALLOCATE proc_cursor;

IF @ProcCount = 0
    PRINT N'  ℹ️ No se encontraron procedimientos de Avoqado';


-- 3. ELIMINAR FUNCIONES
PRINT N'';
PRINT N'📌 3. ELIMINANDO FUNCIONES...';
PRINT N'----------------------------';

DECLARE func_cursor CURSOR FOR
    SELECT name
    FROM sys.objects
    WHERE type IN ('FN', 'IF', 'TF')
      AND (name IN ('fn_GetOrderHash', 'fn_GetShiftHash', 'fn_GetStaffHash')
      OR LOWER(name) LIKE '%avoqado%');

OPEN func_cursor;
FETCH NEXT FROM func_cursor INTO @funcName;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'DROP FUNCTION ' + QUOTENAME(@funcName);
    EXEC sp_executesql @sql;
    PRINT N'  ✅ Eliminada función: ' + @funcName;
    SET @FuncCount = @FuncCount + 1;
    FETCH NEXT FROM func_cursor INTO @funcName;
END;
CLOSE func_cursor;
DEALLOCATE func_cursor;

IF @FuncCount = 0
    PRINT N'  ℹ️ No se encontraron funciones de Avoqado';


-- 4. ELIMINAR ÍNDICES
PRINT N'';
PRINT N'📌 4. ELIMINANDO ÍNDICES...';
PRINT N'--------------------------';

-- Eliminar índices de la nueva instalación (sobre tablas Avoqado)
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_AvoqadoEntitySnapshots_Type_LastSent')
BEGIN
    DROP INDEX IX_AvoqadoEntitySnapshots_Type_LastSent ON dbo.AvoqadoEntitySnapshots;
    PRINT N'  ✅ Eliminado índice: IX_AvoqadoEntitySnapshots_Type_LastSent';
    SET @IndexCount = @IndexCount + 1;
END

IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_AvoqadoEntityTracking_Modified')
BEGIN
    DROP INDEX IX_AvoqadoEntityTracking_Modified ON dbo.AvoqadoEntityTracking;
    PRINT N'  ✅ Eliminado índice: IX_AvoqadoEntityTracking_Modified';
    SET @IndexCount = @IndexCount + 1;
END

-- Eliminar índice de versión antigua en tempcheques (el que causó el error original)
SET @indexName = NULL;
SELECT @indexName = i.name
FROM sys.indexes i
INNER JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
INNER JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
WHERE i.object_id = OBJECT_ID('tempcheques') AND c.name = 'AvoqadoLastModifiedAt';

IF @indexName IS NOT NULL
BEGIN
    SET @sql = N'DROP INDEX ' + QUOTENAME(@indexName) + N' ON dbo.tempcheques';
    EXEC sp_executesql @sql;
    PRINT N'  ✅ Eliminado índice de versión antigua: ' + @indexName;
    SET @IndexCount = @IndexCount + 1;
END

IF @IndexCount = 0
    PRINT N'  ℹ️ No se encontraron índices específicos de Avoqado para eliminar.';


-- 5. ELIMINAR TABLAS
PRINT N'';
PRINT N'📌 5. ELIMINANDO TABLAS...';
PRINT N'-------------------------';

IF OBJECT_ID('dbo.AvoqadoEntitySnapshots', 'U') IS NOT NULL
BEGIN
    DROP TABLE dbo.AvoqadoEntitySnapshots;
    PRINT N'  ✅ Eliminada tabla: AvoqadoEntitySnapshots';
    SET @TableCount = @TableCount + 1;
END

IF OBJECT_ID('dbo.AvoqadoEntityTracking', 'U') IS NOT NULL
BEGIN
    DROP TABLE dbo.AvoqadoEntityTracking;
    PRINT N'  ✅ Eliminada tabla: AvoqadoEntityTracking';
    SET @TableCount = @TableCount + 1;
END

IF @TableCount = 0
    PRINT N'  ℹ️ No se encontraron tablas de Avoqado';


-- 6. ELIMINAR COLUMNAS
PRINT N'';
PRINT N'📌 6. ELIMINANDO COLUMNAS...';
PRINT N'---------------------------';

-- Eliminar columna de tempcheques
IF COL_LENGTH('tempcheques', 'AvoqadoLastModifiedAt') IS NOT NULL
BEGIN
    -- Eliminar constraint default si existe
    SELECT @constraintName = dc.name
    FROM sys.default_constraints dc
    JOIN sys.columns c ON dc.parent_column_id = c.column_id AND dc.parent_object_id = c.object_id
    WHERE c.name = 'AvoqadoLastModifiedAt' AND OBJECT_NAME(c.object_id) = 'tempcheques';

    IF @constraintName IS NOT NULL
    BEGIN
        SET @sql = N'ALTER TABLE tempcheques DROP CONSTRAINT ' + QUOTENAME(@constraintName);
        EXEC sp_executesql @sql;
    END

    -- Eliminar la columna
    ALTER TABLE tempcheques DROP COLUMN AvoqadoLastModifiedAt;
    PRINT N'  ✅ Eliminada columna: tempcheques.AvoqadoLastModifiedAt';
    SET @ColumnCount = @ColumnCount + 1;
END

-- Eliminar columna de tempcheqdet
IF COL_LENGTH('tempcheqdet', 'AvoqadoLastModifiedAt') IS NOT NULL
BEGIN
    SET @constraintName = NULL;
    SELECT @constraintName = dc.name
    FROM sys.default_constraints dc
    JOIN sys.columns c ON dc.parent_column_id = c.column_id AND dc.parent_object_id = c.object_id
    WHERE c.name = 'AvoqadoLastModifiedAt' AND OBJECT_NAME(c.object_id) = 'tempcheqdet';

    IF @constraintName IS NOT NULL
    BEGIN
        SET @sql = N'ALTER TABLE tempcheqdet DROP CONSTRAINT ' + QUOTENAME(@constraintName);
        EXEC sp_executesql @sql;
    END

    -- Eliminar la columna
    ALTER TABLE tempcheqdet DROP COLUMN AvoqadoLastModifiedAt;
    PRINT N'  ✅ Eliminada columna: tempcheqdet.AvoqadoLastModifiedAt';
    SET @ColumnCount = @ColumnCount + 1;
END

IF @ColumnCount = 0
    PRINT N'  ℹ️ No se encontraron columnas de Avoqado';


-- 7. RESUMEN DE LIMPIEZA
PRINT N'';
PRINT N'📊 =====================================================';
PRINT N'📊 RESUMEN DE LIMPIEZA:';
PRINT N'📊 =====================================================';
PRINT N'  🗑️ Triggers eliminados: ' + CAST(@TriggerCount AS NVARCHAR(10));
PRINT N'  🗑️ Procedimientos eliminados: ' + CAST(@ProcCount AS NVARCHAR(10));
PRINT N'  🗑️ Funciones eliminadas: ' + CAST(@FuncCount AS NVARCHAR(10));
PRINT N'  🗑️ Índices eliminados: ' + CAST(@IndexCount AS NVARCHAR(10));
PRINT N'  🗑️ Tablas eliminadas: ' + CAST(@TableCount AS NVARCHAR(10));
PRINT N'  🗑️ Columnas eliminadas: ' + CAST(@ColumnCount AS NVARCHAR(10));
PRINT N'';
PRINT N'✅ LIMPIEZA COMPLETADA';
PRINT N'=====================================================';