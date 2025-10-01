-- ====================================================================
-- AVOQADO INSTALLATION VERIFICATION
-- Checks all required objects exist and are configured correctly
-- ====================================================================

USE avov2;
GO

PRINT '======================================================================'
PRINT ' AVOQADO INSTALLATION VERIFICATION'
PRINT '======================================================================'
PRINT ''

-- Check SoftRestaurant version
DECLARE @Version VARCHAR(50)
SELECT @Version = versiondb FROM parametros2
PRINT '📌 SoftRestaurant Version: ' + ISNULL(@Version, 'NOT FOUND')

-- Check WorkspaceId support
IF COL_LENGTH('tempcheques', 'WorkspaceId') IS NOT NULL
    PRINT '📌 WorkspaceId Support: YES (v11+)'
ELSE
    PRINT '📌 WorkspaceId Support: NO (v10)'

PRINT ''
PRINT '======================================================================'
PRINT ' CHECKING REQUIRED OBJECTS'
PRINT '======================================================================'
PRINT ''

-- Check tables
PRINT '📋 TABLES:'
IF OBJECT_ID('AvoqadoInstanceInfo', 'U') IS NOT NULL
    PRINT '  ✅ AvoqadoInstanceInfo'
ELSE
    PRINT '  ❌ AvoqadoInstanceInfo - MISSING'

IF OBJECT_ID('AvoqadoConfig', 'U') IS NOT NULL
    PRINT '  ✅ AvoqadoConfig'
ELSE
    PRINT '  ❌ AvoqadoConfig - MISSING'

IF OBJECT_ID('AvoqadoTracking', 'U') IS NOT NULL
BEGIN
    PRINT '  ✅ AvoqadoTracking'

    -- Check structure
    IF COL_LENGTH('AvoqadoTracking', 'ProcessedAt') IS NOT NULL
        PRINT '      ✅ Has ProcessedAt column'
    ELSE
        PRINT '      ❌ Missing ProcessedAt column'

    IF COL_LENGTH('AvoqadoTracking', 'RetryCount') IS NOT NULL
        PRINT '      ✅ Has RetryCount column'
    ELSE
        PRINT '      ❌ Missing RetryCount column'
END
ELSE
    PRINT '  ❌ AvoqadoTracking - MISSING'

IF OBJECT_ID('AvoqadoCommands', 'U') IS NOT NULL
    PRINT '  ✅ AvoqadoCommands'
ELSE
    PRINT '  ❌ AvoqadoCommands - MISSING'

PRINT ''
PRINT '📦 STORED PROCEDURES:'
IF OBJECT_ID('sp_GetPendingChanges', 'P') IS NOT NULL
    PRINT '  ✅ sp_GetPendingChanges'
ELSE
    PRINT '  ❌ sp_GetPendingChanges - MISSING'

IF OBJECT_ID('sp_MarkChangesProcessed', 'P') IS NOT NULL
    PRINT '  ✅ sp_MarkChangesProcessed'
ELSE
    PRINT '  ❌ sp_MarkChangesProcessed - MISSING'

IF OBJECT_ID('sp_ApplyPartialPayment', 'P') IS NOT NULL
    PRINT '  ✅ sp_ApplyPartialPayment'
ELSE
    PRINT '  ❌ sp_ApplyPartialPayment - MISSING'

PRINT ''
PRINT '⚙️ FUNCTIONS:'
IF OBJECT_ID('fn_GetAvoqadoEntityId', 'FN') IS NOT NULL
    PRINT '  ✅ fn_GetAvoqadoEntityId'
ELSE IF OBJECT_ID('fn_GetAvoqadoEntityIdWithWorkspace', 'FN') IS NOT NULL
    PRINT '  ✅ fn_GetAvoqadoEntityIdWithWorkspace'
ELSE
    PRINT '  ❌ Entity ID function - MISSING'

IF OBJECT_ID('fn_SplitString', 'FN') IS NOT NULL
    PRINT '  ✅ fn_SplitString (SQL 2014 compatible)'
ELSE
    PRINT '  ⚠️ fn_SplitString - MISSING (needed for SQL 2014)'

PRINT ''
PRINT '🔔 TRIGGERS:'
IF OBJECT_ID('Trg_Avoqado_Orders', 'TR') IS NOT NULL
    PRINT '  ✅ Trg_Avoqado_Orders'
ELSE
    PRINT '  ❌ Trg_Avoqado_Orders - MISSING'

IF OBJECT_ID('Trg_Avoqado_OrderItems', 'TR') IS NOT NULL
    PRINT '  ✅ Trg_Avoqado_OrderItems'
ELSE
    PRINT '  ❌ Trg_Avoqado_OrderItems - MISSING'

IF OBJECT_ID('Trg_Avoqado_Payments', 'TR') IS NOT NULL
    PRINT '  ✅ Trg_Avoqado_Payments'
ELSE
    PRINT '  ❌ Trg_Avoqado_Payments - MISSING'

IF OBJECT_ID('Trg_Avoqado_Shifts', 'TR') IS NOT NULL
    PRINT '  ✅ Trg_Avoqado_Shifts'
ELSE
    PRINT '  ❌ Trg_Avoqado_Shifts - MISSING'

PRINT ''
PRINT '💳 PAYMENT METHODS:'
IF EXISTS (SELECT 1 FROM formasdepago WHERE idformadepago = 'ACASH')
    PRINT '  ✅ ACASH payment method configured'
ELSE
    PRINT '  ⚠️ ACASH payment method - NOT CONFIGURED'

IF EXISTS (SELECT 1 FROM formasdepago WHERE idformadepago = 'ACARD')
    PRINT '  ✅ ACARD payment method configured'
ELSE
    PRINT '  ⚠️ ACARD payment method - NOT CONFIGURED'

PRINT ''
PRINT '🧪 TEST PRODUCT:'
IF EXISTS (SELECT 1 FROM productos WHERE idproducto = 'AVOTEST')
    PRINT '  ✅ AVOTEST product exists (for testing)'
ELSE
    PRINT '  ⚠️ AVOTEST product - NOT FOUND'

PRINT ''
PRINT '======================================================================'
PRINT ' DATA STATUS'
PRINT '======================================================================'
PRINT ''

IF OBJECT_ID('AvoqadoTracking', 'U') IS NOT NULL
BEGIN
    DECLARE @TotalRecords INT, @Pending INT, @Processed INT

    SELECT
        @TotalRecords = COUNT(*),
        @Pending = COUNT(CASE WHEN ProcessedAt IS NULL THEN 1 END),
        @Processed = COUNT(CASE WHEN ProcessedAt IS NOT NULL THEN 1 END)
    FROM AvoqadoTracking

    PRINT '📊 Tracking Records:'
    PRINT '   Total: ' + CAST(@TotalRecords AS VARCHAR)
    PRINT '   Pending: ' + CAST(@Pending AS VARCHAR)
    PRINT '   Processed: ' + CAST(@Processed AS VARCHAR)
END

PRINT ''
PRINT '======================================================================'
PRINT ' VERIFICATION COMPLETE'
PRINT '======================================================================'