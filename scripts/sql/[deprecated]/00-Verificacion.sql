-- ====================================================================
-- 00 - VERIFICACIÓN RÁPIDA DEL SISTEMA AVOQADO
-- Ejecutar en cualquier momento para ver el estado actual
-- ====================================================================

PRINT N'⚡ VERIFICACIÓN RÁPIDA AVOQADO';
PRINT N'==============================';
PRINT N'';

-- 1. ¿Está instalado?
IF EXISTS (SELECT 1 FROM sys.tables WHERE name = 'AvoqadoEntityTracking')
    PRINT N'✅ Sistema Avoqado: INSTALADO'
ELSE
    PRINT N'❌ Sistema Avoqado: NO INSTALADO';

-- 2. Cambios pendientes
IF EXISTS (SELECT 1 FROM sys.tables WHERE name = 'AvoqadoEntityTracking')
BEGIN
    DECLARE @PendingChanges INT = (
        SELECT COUNT(*) 
        FROM AvoqadoEntityTracking t
        LEFT JOIN AvoqadoEntitySnapshots s ON t.EntityType = s.EntityType AND t.EntityId = s.EntityId
        WHERE t.LastModifiedAt > ISNULL(s.LastSentAt, '1900-01-01')
    );
    PRINT N'📊 Cambios pendientes de envío: ' + CAST(@PendingChanges AS VARCHAR);
END

-- 3. Triggers activos
DECLARE @AvoqadoTriggers INT = (
    SELECT COUNT(*) 
    FROM sys.triggers 
    WHERE name IN ('Trg_Avoqado_Orders', 'Trg_Avoqado_OrderItems')
);
PRINT N'🔧 Triggers Avoqado activos: ' + CAST(@AvoqadoTriggers AS VARCHAR) + '/2';

-- 4. Último cambio registrado
IF EXISTS (SELECT 1 FROM sys.tables WHERE name = 'AvoqadoEntityTracking')
BEGIN
    DECLARE @LastChange DATETIME2 = (SELECT MAX(LastModifiedAt) FROM AvoqadoEntityTracking);
    IF @LastChange IS NOT NULL
        PRINT N'🕒 Último cambio registrado: ' + CONVERT(VARCHAR, @LastChange, 120);
END

PRINT N'';
PRINT N'Para más detalles ejecute: 01-Diagnóstico';