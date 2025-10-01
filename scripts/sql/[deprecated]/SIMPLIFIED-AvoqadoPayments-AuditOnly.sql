-- =====================================================
-- SIMPLIFIED: Avoqado Payments Audit Trail Only
-- Just tracks Avoqado payments for audit purposes
-- Payments still go directly to tempchequespagos
-- =====================================================

USE avov2;
GO

-- Simple audit table - no complex logic
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'AvoqadoPaymentAudit')
BEGIN
    CREATE TABLE AvoqadoPaymentAudit (
        Id INT IDENTITY(1,1) PRIMARY KEY,
        OrderFolio BIGINT NOT NULL,
        PaymentAmount MONEY NOT NULL,
        PaymentReference VARCHAR(100) NULL,
        CreatedAt DATETIME2 DEFAULT GETDATE(),

        INDEX IX_AvoqadoPaymentAudit_Folio (OrderFolio),
        INDEX IX_AvoqadoPaymentAudit_Date (CreatedAt)
    );

    PRINT '✅ Created simple AvoqadoPaymentAudit table for tracking only';
END

PRINT '';
PRINT 'This is ONLY for audit trail.';
PRINT 'Actual payments still go directly to tempchequespagos with ACASH!';