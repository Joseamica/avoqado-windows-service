-- ====================================================================
-- COMPLETE CLEANUP - Remove ALL Avoqado objects
-- Run this to start fresh
-- ====================================================================

USE avov2;
GO

PRINT '======================================================================'
PRINT ' CLEANING UP ALL AVOQADO OBJECTS'
PRINT '======================================================================'
PRINT ''

-- Drop triggers
IF OBJECT_ID('Trg_Avoqado_Orders', 'TR') IS NOT NULL
BEGIN
    DROP TRIGGER Trg_Avoqado_Orders
    PRINT '✅ Dropped Trg_Avoqado_Orders'
END

IF OBJECT_ID('Trg_Avoqado_OrderItems', 'TR') IS NOT NULL
BEGIN
    DROP TRIGGER Trg_Avoqado_OrderItems
    PRINT '✅ Dropped Trg_Avoqado_OrderItems'
END

IF OBJECT_ID('Trg_Avoqado_Payments', 'TR') IS NOT NULL
BEGIN
    DROP TRIGGER Trg_Avoqado_Payments
    PRINT '✅ Dropped Trg_Avoqado_Payments'
END

IF OBJECT_ID('Trg_Avoqado_Shifts', 'TR') IS NOT NULL
BEGIN
    DROP TRIGGER Trg_Avoqado_Shifts
    PRINT '✅ Dropped Trg_Avoqado_Shifts'
END

-- Drop stored procedures
IF OBJECT_ID('sp_ApplyPartialPayment', 'P') IS NOT NULL
BEGIN
    DROP PROCEDURE sp_ApplyPartialPayment
    PRINT '✅ Dropped sp_ApplyPartialPayment'
END

IF OBJECT_ID('sp_GetPendingChanges', 'P') IS NOT NULL
BEGIN
    DROP PROCEDURE sp_GetPendingChanges
    PRINT '✅ Dropped sp_GetPendingChanges'
END

IF OBJECT_ID('sp_MarkChangesProcessed', 'P') IS NOT NULL
BEGIN
    DROP PROCEDURE sp_MarkChangesProcessed
    PRINT '✅ Dropped sp_MarkChangesProcessed'
END

IF OBJECT_ID('sp_EnsureAvoqadoPaymentMethod', 'P') IS NOT NULL
BEGIN
    DROP PROCEDURE sp_EnsureAvoqadoPaymentMethod
    PRINT '✅ Dropped sp_EnsureAvoqadoPaymentMethod'
END

-- Drop functions
IF OBJECT_ID('fn_GetAvoqadoEntityId', 'FN') IS NOT NULL
BEGIN
    DROP FUNCTION fn_GetAvoqadoEntityId
    PRINT '✅ Dropped fn_GetAvoqadoEntityId'
END

IF OBJECT_ID('fn_GetAvoqadoEntityIdWithWorkspace', 'FN') IS NOT NULL
BEGIN
    DROP FUNCTION fn_GetAvoqadoEntityIdWithWorkspace
    PRINT '✅ Dropped fn_GetAvoqadoEntityIdWithWorkspace'
END

IF OBJECT_ID('fn_SplitString', 'TF') IS NOT NULL
BEGIN
    DROP FUNCTION fn_SplitString
    PRINT '✅ Dropped fn_SplitString'
END

-- Drop views
IF OBJECT_ID('vw_OrderPayments', 'V') IS NOT NULL
BEGIN
    DROP VIEW vw_OrderPayments
    PRINT '✅ Dropped vw_OrderPayments'
END

-- Drop tables (in order to handle dependencies)
IF OBJECT_ID('AvoqadoPartialPayments', 'U') IS NOT NULL
BEGIN
    DROP TABLE AvoqadoPartialPayments
    PRINT '✅ Dropped AvoqadoPartialPayments'
END

IF OBJECT_ID('AvoqadoCommands', 'U') IS NOT NULL
BEGIN
    DROP TABLE AvoqadoCommands
    PRINT '✅ Dropped AvoqadoCommands'
END

IF OBJECT_ID('AvoqadoTracking', 'U') IS NOT NULL
BEGIN
    DROP TABLE AvoqadoTracking
    PRINT '✅ Dropped AvoqadoTracking'
END

IF OBJECT_ID('AvoqadoConfig', 'U') IS NOT NULL
BEGIN
    DROP TABLE AvoqadoConfig
    PRINT '✅ Dropped AvoqadoConfig'
END

IF OBJECT_ID('AvoqadoInstanceInfo', 'U') IS NOT NULL
BEGIN
    DROP TABLE AvoqadoInstanceInfo
    PRINT '✅ Dropped AvoqadoInstanceInfo'
END

-- Remove payment methods (optional - commented out by default)
/*
IF EXISTS (SELECT 1 FROM formasdepago WHERE idformadepago = 'ACASH')
BEGIN
    DELETE FROM formasdepago WHERE idformadepago = 'ACASH'
    PRINT '✅ Removed ACASH payment method'
END

IF EXISTS (SELECT 1 FROM formasdepago WHERE idformadepago = 'ACARD')
BEGIN
    DELETE FROM formasdepago WHERE idformadepago = 'ACARD'
    PRINT '✅ Removed ACARD payment method'
END
*/

-- Remove test product (optional - commented out by default)
/*
IF EXISTS (SELECT 1 FROM productos WHERE idproducto = 'AVOTEST')
BEGIN
    DELETE FROM productos WHERE idproducto = 'AVOTEST'
    PRINT '✅ Removed AVOTEST test product'
END
*/

PRINT ''
PRINT '======================================================================'
PRINT ' ✅ CLEANUP COMPLETE - Database is clean'
PRINT '======================================================================'
PRINT ''
PRINT 'NOTE: The following were NOT removed (preserved by default):'
PRINT '  - Payment methods (ACASH, ACARD)'
PRINT '  - Test product (AVOTEST)'
PRINT ''
PRINT 'To remove them, uncomment the sections above and re-run.'