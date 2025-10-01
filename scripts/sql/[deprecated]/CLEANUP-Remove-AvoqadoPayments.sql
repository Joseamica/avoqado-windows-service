-- =====================================================
-- CLEANUP: Remove AvoqadoPartialPayments Infrastructure
-- This removes the emergency fix and uses native POS payments
-- =====================================================

USE avov2;
GO

PRINT '🧹 Cleaning up AvoqadoPartialPayments infrastructure...';
PRINT '';

-- 1. Drop the view if it exists
IF EXISTS (SELECT * FROM sys.views WHERE name = 'vw_ShiftPaymentsReport')
BEGIN
    DROP VIEW vw_ShiftPaymentsReport;
    PRINT '✅ Removed vw_ShiftPaymentsReport view';
END

-- 2. Drop the stored procedure if it exists
IF EXISTS (SELECT * FROM sys.procedures WHERE name = 'sp_ApplyPartialPayment')
BEGIN
    DROP PROCEDURE sp_ApplyPartialPayment;
    PRINT '✅ Removed sp_ApplyPartialPayment procedure';
END

-- 3. Drop the function if it exists
IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'fn_GetAvoqadoPaymentsTotal') AND type = 'FN')
BEGIN
    DROP FUNCTION fn_GetAvoqadoPaymentsTotal;
    PRINT '✅ Removed fn_GetAvoqadoPaymentsTotal function';
END

-- 4. Drop the AvoqadoPartialPayments table
IF EXISTS (SELECT * FROM sys.tables WHERE name = 'AvoqadoPartialPayments')
BEGIN
    DROP TABLE AvoqadoPartialPayments;
    PRINT '✅ Removed AvoqadoPartialPayments table';
END

PRINT '';
PRINT '=====================================================';
PRINT '✅ CLEANUP COMPLETE!';
PRINT '=====================================================';
PRINT '';
PRINT 'The system now uses the native payment flow:';
PRINT '1. Avoqado payments go directly to tempchequespagos';
PRINT '2. Use payment method "ACASH" for all Avoqado payments';
PRINT '3. Payments appear automatically in all POS reports';
PRINT '';
PRINT 'No extra tables or stored procedures needed!';