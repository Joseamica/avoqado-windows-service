-- ====================================================================
-- 01 - SCRIPT DE DIAGNÓSTICO PARA SISTEMA AVOQADO
-- Ejecutar SIEMPRE primero para ver qué existe antes de cualquier cambio
-- ====================================================================

PRINT N'🔍 =====================================================';
PRINT N'🔍 DIAGNÓSTICO COMPLETO DEL SISTEMA AVOQADO';
PRINT N'🔍 =====================================================';
PRINT N'';
PRINT N'📅 Fecha de diagnóstico: ' + CONVERT(VARCHAR, GETDATE(), 120);
PRINT N'';

-- 1. TRIGGERS ESPECÍFICOS DE AVOQADO
PRINT N'📌 1. TRIGGERS ESPECÍFICOS DE AVOQADO:';
PRINT N'-------------------------------------';
-- Solo buscamos los triggers que son parte del sistema Avoqado
SELECT 
    t.name AS TriggerName,
    OBJECT_NAME(t.parent_id) AS TableName,
    t.is_disabled AS IsDisabled,
    t.create_date AS CreatedDate,
    CASE 
        WHEN t.name IN ('Trg_Avoqado_Orders', 'Trg_Avoqado_OrderItems') THEN N'✅ Trigger Avoqado Actual'
        WHEN t.name IN ('Trg_Avoqado_UpdateTimestamp', 'Trg_Avoqado_ItemsUpdateParent') THEN N'⚠️ Trigger Avoqado Antiguo'
        WHEN t.name = 'trg_AvoqadoOrderTracking' THEN N'❌ Trigger Legacy Problemático'
        ELSE N'❓ Verificar si es de Avoqado'
    END AS Status
FROM sys.triggers t
WHERE t.name IN (
    -- Triggers actuales
    'Trg_Avoqado_Orders', 
    'Trg_Avoqado_OrderItems',
    -- Triggers antiguos
    'Trg_Avoqado_UpdateTimestamp', 
    'Trg_Avoqado_ItemsUpdateParent',
    'trg_AvoqadoOrderTracking',
    -- Otros posibles
    'Trg_Avoqado_Shifts', 
    'Trg_Avoqado_Areas', 
    'Trg_Avoqado_Staff'
)
OR LOWER(t.name) LIKE '%avoqado%'
OR LOWER(t.name) LIKE '%avocado%'
ORDER BY t.name;

-- 2. COLUMNAS AVOQADO
PRINT N'';
PRINT N'📌 2. COLUMNAS AVOQADO EN TABLAS:';
PRINT N'---------------------------------';
SELECT 
    t.name AS TableName,
    c.name AS ColumnName,
    ty.name AS DataType,
    c.is_nullable,
    ISNULL(dc.definition, 'Sin default') AS DefaultValue
FROM sys.columns c
INNER JOIN sys.tables t ON c.object_id = t.object_id
INNER JOIN sys.types ty ON c.user_type_id = ty.user_type_id
LEFT JOIN sys.default_constraints dc ON c.default_object_id = dc.object_id
WHERE c.name = 'AvoqadoLastModifiedAt'
   AND t.name IN ('tempcheques', 'tempcheqdet')
ORDER BY t.name;

-- 3. PROCEDIMIENTOS ALMACENADOS
PRINT N'';
PRINT N'📌 3. PROCEDIMIENTOS ALMACENADOS DE AVOQADO:';
PRINT N'-------------------------------------------';
SELECT 
    name AS ProcedureName,
    create_date AS CreatedDate,
    CASE 
        WHEN name IN ('sp_TrackEntityChange', 'sp_GetEntityChanges', 'sp_UpdateEntitySnapshot') THEN N'✅ Core Avoqado'
        WHEN name = 'sp_CleanupStuckTracking' THEN N'✅ Utilidad Avoqado'
        ELSE N'❓ Verificar'
    END AS Status
FROM sys.procedures
WHERE name IN (
    'sp_TrackEntityChange', 
    'sp_GetEntityChanges', 
    'sp_UpdateEntitySnapshot', 
    'sp_CleanupStuckTracking'
)
OR LOWER(name) LIKE '%avoqado%'
ORDER BY name;

-- 4. FUNCIONES
PRINT N'';
PRINT N'📌 4. FUNCIONES DE AVOQADO:';
PRINT N'---------------------------';
SELECT 
    name AS FunctionName,
    type_desc AS FunctionType,
    create_date AS CreatedDate
FROM sys.objects
WHERE type IN ('FN', 'IF', 'TF')
  AND name IN ('fn_GetOrderHash', 'fn_GetShiftHash', 'fn_GetStaffHash')
ORDER BY name;

-- 5. TABLAS
PRINT N'';
PRINT N'📌 5. TABLAS DE AVOQADO:';
PRINT N'-----------------------';
SELECT 
    t.name AS TableName,
    t.create_date AS CreatedDate,
    p.rows AS [RowCount]
FROM sys.tables t
INNER JOIN sys.partitions p ON t.object_id = p.object_id AND p.index_id IN (0, 1)
WHERE t.name IN ('AvoqadoEntitySnapshots', 'AvoqadoEntityTracking')
ORDER BY t.name;

-- 6. VERIFICAR OTROS TRIGGERS EN LAS MISMAS TABLAS
PRINT N'';
PRINT N'📌 6. OTROS TRIGGERS EN TABLAS tempcheques/tempcheqdet:';
PRINT N'-------------------------------------------------------';
PRINT N'⚠️  IMPORTANTE: Estos triggers NO son parte de Avoqado';
SELECT 
    t.name AS TriggerName,
    OBJECT_NAME(t.parent_id) AS TableName,
    t.create_date AS CreatedDate,
    N'⚠️ NO ES DE AVOQADO - No tocar' AS Warning
FROM sys.triggers t
WHERE OBJECT_NAME(t.parent_id) IN ('tempcheques', 'tempcheqdet')
  AND t.name NOT IN (
    'Trg_Avoqado_Orders', 
    'Trg_Avoqado_OrderItems',
    'Trg_Avoqado_UpdateTimestamp', 
    'Trg_Avoqado_ItemsUpdateParent',
    'trg_AvoqadoOrderTracking'
  )
  AND LOWER(t.name) NOT LIKE '%avoqado%'
  AND LOWER(t.name) NOT LIKE '%avocado%'
ORDER BY t.name;

-- 7. RESUMEN
PRINT N'';
PRINT N'📊 =====================================================';
PRINT N'📊 RESUMEN DEL DIAGNÓSTICO:';
PRINT N'📊 =====================================================';

DECLARE @HasColumns BIT = 0;
DECLARE @HasTriggers BIT = 0;
DECLARE @HasTables BIT = 0;
DECLARE @HasProcs BIT = 0;

IF EXISTS (SELECT 1 FROM sys.columns c INNER JOIN sys.tables t ON c.object_id = t.object_id 
           WHERE c.name = 'AvoqadoLastModifiedAt' AND t.name IN ('tempcheques', 'tempcheqdet'))
    SET @HasColumns = 1;

IF EXISTS (SELECT 1 FROM sys.triggers WHERE name IN ('Trg_Avoqado_Orders', 'Trg_Avoqado_OrderItems') 
           OR LOWER(name) LIKE '%avoqado%')
    SET @HasTriggers = 1;

IF EXISTS (SELECT 1 FROM sys.tables WHERE name IN ('AvoqadoEntitySnapshots', 'AvoqadoEntityTracking'))
    SET @HasTables = 1;

IF EXISTS (SELECT 1 FROM sys.procedures WHERE name IN ('sp_TrackEntityChange', 'sp_GetEntityChanges'))
    SET @HasProcs = 1;

PRINT N'  🔸 Columnas AvoqadoLastModifiedAt: ' + CASE WHEN @HasColumns = 1 THEN N'✅ Existen' ELSE N'❌ No existen' END;
PRINT N'  🔸 Triggers de Avoqado: ' + CASE WHEN @HasTriggers = 1 THEN N'✅ Existen' ELSE N'❌ No existen' END;
PRINT N'  🔸 Tablas de tracking: ' + CASE WHEN @HasTables = 1 THEN N'✅ Existen' ELSE N'❌ No existen' END;
PRINT N'  🔸 Procedimientos: ' + CASE WHEN @HasProcs = 1 THEN N'✅ Existen' ELSE N'❌ No existen' END;

PRINT N'';
IF @HasColumns = 1 OR @HasTriggers = 1 OR @HasTables = 1 OR @HasProcs = 1
BEGIN
    PRINT N'⚠️  ACCIÓN REQUERIDA: Ejecutar script 02-Limpieza antes de instalar';
END
ELSE
BEGIN
    PRINT N'✅ Sistema limpio, puede proceder con script 03-Instalación';
END

PRINT N'';
PRINT N'🏁 DIAGNÓSTICO COMPLETADO';
PRINT N'=====================================================';