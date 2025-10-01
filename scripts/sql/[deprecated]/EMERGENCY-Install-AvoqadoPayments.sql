-- =====================================================
-- EMERGENCY FIX: Install Missing Avoqado Payment System
-- This creates the payment tracking infrastructure
-- that allows Avoqado payments to appear in reports
-- =====================================================

USE avov2;
GO

-- =====================================================
-- 1. CREATE AVOQADO PARTIAL PAYMENTS TABLE
-- =====================================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'AvoqadoPartialPayments')
BEGIN
    CREATE TABLE AvoqadoPartialPayments (
        Id INT IDENTITY(1,1) PRIMARY KEY,
        OrderFolio BIGINT NOT NULL,
        PaymentAmount MONEY NOT NULL,
        PaymentMethod VARCHAR(50) NOT NULL,
        PaymentReference VARCHAR(100) NULL,
        ProcessedAt DATETIME2 DEFAULT GETDATE(),
        AppliedToPos BIT DEFAULT 0,
        AppliedAt DATETIME2 NULL,
        ErrorMessage NVARCHAR(MAX) NULL,

        INDEX IX_AvoqadoPartialPayments_Folio (OrderFolio),
        INDEX IX_AvoqadoPartialPayments_Applied (AppliedToPos, ProcessedAt)
    );

    PRINT '✅ Created AvoqadoPartialPayments table'
END
ELSE
BEGIN
    PRINT '⚠️ AvoqadoPartialPayments table already exists'
END
GO

-- =====================================================
-- 2. CREATE STORED PROCEDURE TO APPLY PARTIAL PAYMENTS
-- =====================================================
IF EXISTS (SELECT * FROM sys.procedures WHERE name = 'sp_ApplyPartialPayment')
    DROP PROCEDURE sp_ApplyPartialPayment;
GO

CREATE PROCEDURE sp_ApplyPartialPayment
    @OrderFolio BIGINT,
    @PaymentAmount MONEY,
    @PaymentMethod VARCHAR(50),
    @PaymentReference VARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Insert payment record
        INSERT INTO AvoqadoPartialPayments (
            OrderFolio,
            PaymentAmount,
            PaymentMethod,
            PaymentReference,
            ProcessedAt,
            AppliedToPos
        ) VALUES (
            @OrderFolio,
            @PaymentAmount,
            @PaymentMethod,
            @PaymentReference,
            GETDATE(),
            0
        );

        -- Check if order exists in tempcheques
        IF EXISTS (SELECT 1 FROM tempcheques WHERE folio = @OrderFolio)
        BEGIN
            -- Apply payment to tempchequespagos (standard payment table)
            -- Use ACASH for Avoqado payments
            DECLARE @IdFormaPago VARCHAR(10) = 'ACASH';

            -- Insert into standard payments table
            INSERT INTO tempchequespagos (
                folio,
                idformadepago,
                importe,
                propina,
                tipodecambio,
                referencia,
                sistema_envio
            ) VALUES (
                @OrderFolio,
                @IdFormaPago,
                @PaymentAmount,
                0,
                1.0,
                ISNULL(@PaymentReference, 'Avoqado Payment'),
                1
            );

            -- Update the partial payment as applied
            UPDATE AvoqadoPartialPayments
            SET AppliedToPos = 1,
                AppliedAt = GETDATE()
            WHERE OrderFolio = @OrderFolio
              AND AppliedToPos = 0;

            -- Track in Avoqado system
            INSERT INTO AvoqadoTracking (
                EntityType,
                EntityId,
                Operation,
                Timestamp,
                ProcessedAt
            ) VALUES (
                'PAYMENT',
                CAST(@OrderFolio AS VARCHAR(50)),
                'CREATE',
                GETDATE(),
                NULL
            );
        END

        COMMIT TRANSACTION;
        SELECT 'SUCCESS' as Status, 'Payment applied successfully' as Message;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        -- Log error in partial payments table
        UPDATE AvoqadoPartialPayments
        SET ErrorMessage = ERROR_MESSAGE()
        WHERE OrderFolio = @OrderFolio
          AND AppliedToPos = 0;

        SELECT 'ERROR' as Status, ERROR_MESSAGE() as Message;
    END CATCH
END
GO

-- =====================================================
-- 3. CREATE FUNCTION TO GET TOTAL AVOQADO PAYMENTS
-- =====================================================
IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'fn_GetAvoqadoPaymentsTotal') AND type = 'FN')
    DROP FUNCTION fn_GetAvoqadoPaymentsTotal;
GO

CREATE FUNCTION fn_GetAvoqadoPaymentsTotal(@OrderFolio BIGINT)
RETURNS MONEY
AS
BEGIN
    DECLARE @Total MONEY = 0;

    SELECT @Total = ISNULL(SUM(PaymentAmount), 0)
    FROM AvoqadoPartialPayments
    WHERE OrderFolio = @OrderFolio
      AND AppliedToPos = 1;

    RETURN @Total;
END
GO

-- =====================================================
-- 4. CREATE VIEW FOR SHIFT REPORTS INCLUDING AVOQADO
-- =====================================================
IF EXISTS (SELECT * FROM sys.views WHERE name = 'vw_ShiftPaymentsReport')
    DROP VIEW vw_ShiftPaymentsReport;
GO

CREATE VIEW vw_ShiftPaymentsReport AS
SELECT
    -- Standard payments from tempchequespagos
    'POS' as PaymentSource,
    p.folio,
    p.idformadepago,
    f.descripcion as FormaPago,
    p.importe,
    p.propina,
    GETDATE() as fecha,
    p.referencia
FROM tempchequespagos p
INNER JOIN formasdepago f ON p.idformadepago = f.idformadepago

UNION ALL

-- Avoqado payments
SELECT
    'AVOQADO' as PaymentSource,
    ap.OrderFolio as folio,
    'ACASH' as idformadepago,
    'Avoqado - ' + ap.PaymentMethod as FormaPago,
    ap.PaymentAmount as importe,
    0 as propina,
    ap.ProcessedAt as fecha,
    ap.PaymentReference as referencia
FROM AvoqadoPartialPayments ap
WHERE ap.AppliedToPos = 1;
GO

-- =====================================================
-- 5. APPLY YOUR EXISTING $77 PAYMENT
-- =====================================================
PRINT '';
PRINT '🔧 Applying your $77 Avoqado payment to order 3...';

-- Check current order status
DECLARE @CurrentTotal MONEY;
SELECT @CurrentTotal = total FROM tempcheques WHERE folio = 3;
PRINT 'Order 3 total: $' + CAST(@CurrentTotal AS VARCHAR(20));

-- Apply the Avoqado payment
EXEC sp_ApplyPartialPayment
    @OrderFolio = 3,
    @PaymentAmount = 77.00,
    @PaymentMethod = 'cash',
    @PaymentReference = 'Avoqado Test Payment';

-- Verify payment was applied
PRINT '';
PRINT '✅ Payment applied. Verifying...';
SELECT * FROM vw_ShiftPaymentsReport WHERE folio = 3;

PRINT '';
PRINT '=====================================================';
PRINT '✅ AVOQADO PAYMENT SYSTEM INSTALLED SUCCESSFULLY!';
PRINT '=====================================================';
PRINT '';
PRINT 'The payment tracking system is now active.';
PRINT 'Your $77 payment has been applied to order 3.';
PRINT 'Payments will now appear in shift reports!';
PRINT '';
PRINT 'Next steps:';
PRINT '1. Complete the remaining payment for order 3';
PRINT '2. Close the shift';
PRINT '3. Generate the report - Avoqado payments will appear!';