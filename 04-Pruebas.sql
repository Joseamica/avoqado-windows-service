-- ====================================================================
-- 04 - SCRIPT DE PRUEBAS PARA SISTEMA AVOQADO
-- Pruebas básicas que no interfieren con otros triggers del sistema
-- ====================================================================

PRINT N'🧪 =====================================================';
PRINT N'🧪 PRUEBAS DEL SISTEMA AVOQADO';
PRINT N'🧪 =====================================================';
PRINT N'';
PRINT N'📅 Fecha de pruebas: ' + CONVERT(VARCHAR, GETDATE(), 120);
PRINT N'';

-- Variables para resultados
DECLARE @TestsPassed INT = 0;
DECLARE @TestsFailed INT = 0;

-- =====================================================
-- PRUEBA 1: VERIFICAR OBJETOS INSTALADOS
-- =====================================================

PRINT N'📌 PRUEBA 1: VERIFICANDO OBJETOS INSTALADOS...';
PRINT N'----------------------------------------------';

-- Verificar columnas
IF COL_LENGTH('tempcheques', 'AvoqadoLastModifiedAt') IS NOT NULL
BEGIN
    PRINT N'  ✅ Columna tempcheques.AvoqadoLastModifiedAt existe';
    SET @TestsPassed = @TestsPassed + 1;
END
ELSE
BEGIN
    PRINT N'  ❌ Columna tempcheques.AvoqadoLastModifiedAt NO existe';
    SET @TestsFailed = @TestsFailed + 1;
END

IF COL_LENGTH('tempcheqdet', 'AvoqadoLastModifiedAt') IS NOT NULL
BEGIN
    PRINT N'  ✅ Columna tempcheqdet.AvoqadoLastModifiedAt existe';
    SET @TestsPassed = @TestsPassed + 1;
END
ELSE
BEGIN
    PRINT N'  ❌ Columna tempcheqdet.AvoqadoLastModifiedAt NO existe';
    SET @TestsFailed = @TestsFailed + 1;
END

-- Verificar tablas
IF OBJECT_ID('dbo.AvoqadoEntitySnapshots', 'U') IS NOT NULL
BEGIN
    PRINT N'  ✅ Tabla AvoqadoEntitySnapshots existe';
    SET @TestsPassed = @TestsPassed + 1;
END
ELSE
BEGIN
    PRINT N'  ❌ Tabla AvoqadoEntitySnapshots NO existe';
    SET @TestsFailed = @TestsFailed + 1;
END

IF OBJECT_ID('dbo.AvoqadoEntityTracking', 'U') IS NOT NULL
BEGIN
    PRINT N'  ✅ Tabla AvoqadoEntityTracking existe';
    SET @TestsPassed = @TestsPassed + 1;
END
ELSE
BEGIN
    PRINT N'  ❌ Tabla AvoqadoEntityTracking NO existe';
    SET @TestsFailed = @TestsFailed + 1;
END

-- Verificar procedimientos
IF OBJECT_ID('dbo.sp_TrackEntityChange', 'P') IS NOT NULL
BEGIN
    PRINT N'  ✅ Procedimiento sp_TrackEntityChange existe';
    SET @TestsPassed = @TestsPassed + 1;
END
ELSE
BEGIN
    PRINT N'  ❌ Procedimiento sp_TrackEntityChange NO existe';
    SET @TestsFailed = @TestsFailed + 1;
END

-- Verificar triggers
IF EXISTS (SELECT * FROM sys.triggers WHERE name = 'Trg_Avoqado_Orders')
BEGIN
    PRINT N'  ✅ Trigger Trg_Avoqado_Orders existe';
    SET @TestsPassed = @TestsPassed + 1;
END
ELSE
BEGIN
    PRINT N'  ❌ Trigger Trg_Avoqado_Orders NO existe';
    SET @TestsFailed = @TestsFailed + 1;
END

IF EXISTS (SELECT * FROM sys.triggers WHERE name = 'Trg_Avoqado_OrderItems')
BEGIN
    PRINT N'  ✅ Trigger Trg_Avoqado_OrderItems existe';
    SET @TestsPassed = @TestsPassed + 1;
END
ELSE
BEGIN
    PRINT N'  ❌ Trigger Trg_Avoqado_OrderItems NO existe';
    SET @TestsFailed = @TestsFailed + 1;
END

-- =====================================================
-- PRUEBA 2: PROBAR FUNCIONES DE HASH
-- =====================================================

PRINT N'';
PRINT N'📌 PRUEBA 2: PROBANDO FUNCIONES DE HASH...';
PRINT N'------------------------------------------';

-- Buscar una orden existente para probar
DECLARE @TestOrderId INT;
SELECT TOP 1 @TestOrderId = folio FROM tempcheques ORDER BY folio DESC;

IF @TestOrderId IS NOT NULL
BEGIN
    DECLARE @TestHash VARBINARY(32) = dbo.fn_GetOrderHash(@TestOrderId);
    IF @TestHash IS NOT NULL
    BEGIN
        PRINT N'  ✅ fn_GetOrderHash funciona correctamente (Orden ' + CAST(@TestOrderId AS VARCHAR) + ')';
        PRINT N'     Hash: 0x' + CONVERT(VARCHAR(64), @TestHash, 2);
        SET @TestsPassed = @TestsPassed + 1;
    END
    ELSE
    BEGIN
        PRINT N'  ❌ fn_GetOrderHash devolvió NULL';
        SET @TestsFailed = @TestsFailed + 1;
    END
END
ELSE
BEGIN
    PRINT N'  ⚠️  No hay órdenes en tempcheques para probar hash';
END

-- =====================================================
-- PRUEBA 3: PROBAR PROCEDIMIENTO DE TRACKING
-- =====================================================

PRINT N'';
PRINT N'📌 PRUEBA 3: PROBANDO PROCEDIMIENTO DE TRACKING...';
PRINT N'--------------------------------------------------';

-- Limpiar cualquier registro de prueba anterior
DELETE FROM AvoqadoEntityTracking WHERE EntityId = '999999';
DELETE FROM AvoqadoEntitySnapshots WHERE EntityId = '999999';

-- Probar inserción de tracking
EXEC sp_TrackEntityChange 'order', '999999', 'test_create';

IF EXISTS (SELECT 1 FROM AvoqadoEntityTracking WHERE EntityType = 'order' AND EntityId = '999999')
BEGIN
    PRINT N'  ✅ sp_TrackEntityChange funciona correctamente';
    SET @TestsPassed = @TestsPassed + 1;
    
    -- Limpiar registro de prueba
    DELETE FROM AvoqadoEntityTracking WHERE EntityId = '999999';
END
ELSE
BEGIN
    PRINT N'  ❌ sp_TrackEntityChange no creó el registro';
    SET @TestsFailed = @TestsFailed + 1;
END

-- =====================================================
-- PRUEBA 4: VERIFICAR sp_GetEntityChanges
-- =====================================================

PRINT N'';
PRINT N'📌 PRUEBA 4: PROBANDO sp_GetEntityChanges...';
PRINT N'--------------------------------------------';

BEGIN TRY
    -- Crear tabla temporal para resultados
    CREATE TABLE #TestResults (
        EntityType VARCHAR(50),
        EntityId VARCHAR(100),
        LastModifiedAt DATETIME2,
        ChangeReason VARCHAR(100),
        CurrentHash VARBINARY(32),
        LastSentHash VARBINARY(32),
        EventType VARCHAR(20)
    );
    
    -- Ejecutar procedimiento
    INSERT INTO #TestResults
    EXEC sp_GetEntityChanges @lastSyncTimestamp = '2020-01-01', @maxResults = 5;
    
    DECLARE @ResultCount INT = (SELECT COUNT(*) FROM #TestResults);
    PRINT N'  ✅ sp_GetEntityChanges ejecutado correctamente';
    PRINT N'     Cambios encontrados: ' + CAST(@ResultCount AS VARCHAR);
    SET @TestsPassed = @TestsPassed + 1;
    
    -- Mostrar algunos resultados si existen
    IF @ResultCount > 0
    BEGIN
        SELECT TOP 3 
            EntityType,
            EntityId,
            ChangeReason,
            EventType,
            LastModifiedAt
        FROM #TestResults
        ORDER BY LastModifiedAt DESC;
    END
    
    DROP TABLE #TestResults;
END TRY
BEGIN CATCH
    PRINT N'  ❌ Error al ejecutar sp_GetEntityChanges: ' + ERROR_MESSAGE();
    SET @TestsFailed = @TestsFailed + 1;
END CATCH

-- =====================================================
-- PRUEBA 5: VERIFICAR OTROS TRIGGERS NO AFECTADOS
-- =====================================================

PRINT N'';
PRINT N'📌 PRUEBA 5: VERIFICANDO OTROS TRIGGERS DEL SISTEMA...';
PRINT N'------------------------------------------------------';

-- Listar triggers NO relacionados con Avoqado en las mismas tablas
SELECT 
    t.name AS OtherTriggers,
    OBJECT_NAME(t.parent_id) AS TableName,
    t.is_disabled AS IsDisabled
FROM sys.triggers t
WHERE OBJECT_NAME(t.parent_id) IN ('tempcheques', 'tempcheqdet')
  AND t.name NOT LIKE '%Avoqado%'
  AND t.name NOT LIKE '%avocado%'
ORDER BY OBJECT_NAME(t.parent_id), t.name;

PRINT N'  ℹ️ Los triggers listados arriba NO son parte de Avoqado';
PRINT N'     y NO deben ser modificados por el sistema';

-- =====================================================
-- RESUMEN DE PRUEBAS
-- =====================================================

PRINT N'';
PRINT N'📊 =====================================================';
PRINT N'📊 RESUMEN DE PRUEBAS:';
PRINT N'📊 =====================================================';
PRINT N'  ✅ Pruebas exitosas: ' + CAST(@TestsPassed AS NVARCHAR(10));
PRINT N'  ❌ Pruebas fallidas: ' + CAST(@TestsFailed AS NVARCHAR(10));
PRINT N'';

IF @TestsFailed = 0
BEGIN
    PRINT N'🎉 TODAS LAS PRUEBAS PASARON EXITOSAMENTE';
    PRINT N'   El sistema Avoqado está funcionando correctamente';
END
ELSE
BEGIN
    PRINT N'⚠️  ALGUNAS PRUEBAS FALLARON';
    PRINT N'   Revise los errores anteriores y ejecute el script de instalación nuevamente';
END

PRINT N'';
PRINT N'📝 NOTA SOBRE OTROS TRIGGERS:';
PRINT N'   Si el trigger "trgChequeActualizado" u otros causan errores,';
PRINT N'   esos NO son parte del sistema Avoqado y deben ser revisados';
PRINT N'   por el administrador de la base de datos por separado.';
PRINT N'';
PRINT N'🏁 PRUEBAS COMPLETADAS';
PRINT N'=====================================================';