-- =====================================================
-- STORED PROCEDURE: sp_EnsureAvoqadoPaymentMethod
-- Ensures Avoqado payment method exists before processing payments
-- Returns the payment method ID to use
-- =====================================================

USE avov2;
GO

IF EXISTS (SELECT * FROM sys.procedures WHERE name = 'sp_EnsureAvoqadoPaymentMethod')
    DROP PROCEDURE sp_EnsureAvoqadoPaymentMethod;
GO

CREATE PROCEDURE sp_EnsureAvoqadoPaymentMethod
    @PaymentMethodId VARCHAR(10) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    -- Check if any Avoqado payment method exists
    SELECT TOP 1 @PaymentMethodId = idformadepago
    FROM formasdepago
    WHERE idformadepago IN ('ACASH', 'AVOQADO', 'AVO')
    ORDER BY
        CASE idformadepago
            WHEN 'AVOQADO' THEN 1  -- Prefer AVOQADO
            WHEN 'ACASH' THEN 2    -- Then ACASH
            WHEN 'AVO' THEN 3      -- Then AVO
        END;

    -- If not found, create it
    IF @PaymentMethodId IS NULL
    BEGIN
        -- Find a reference cash payment method to copy settings
        DECLARE @ReferenceId VARCHAR(10);

        SELECT TOP 1 @ReferenceId = idformadepago
        FROM formasdepago
        WHERE
            UPPER(descripcion) LIKE '%EFECTIVO%'
            OR UPPER(descripcion) LIKE '%CASH%'
            OR idformadepago IN ('01', '1', 'EF', 'AEF');

        IF @ReferenceId IS NOT NULL
        BEGIN
            -- Copy settings from reference cash payment method
            INSERT INTO formasdepago (
                idformadepago,
                descripcion,
                tipo,
                tipodecambio,
                solicitareferencia,
                prioridadboton,
                visible,
                aceptapropina,
                pagoenlinea,
                tipotarjeta,
                nofacturable,
                tipoTarjetaBancaria,
                leerbrazalete,
                cargohabitacion_eg,
                visible_kiosco,
                autocapturar,
                sumatotal,
                equivalencia,
                WorkspaceId
            )
            SELECT
                'AVOQADO',
                'AVOQADO CASH',
                tipo,
                tipodecambio,
                0, -- Don't require reference
                prioridadboton,
                1, -- Visible
                aceptapropina,
                0, -- Not online payment
                0, -- Not a card
                nofacturable,
                tipoTarjetaBancaria,
                0, -- Don't read bracelet
                0, -- No room charge
                visible_kiosco,
                autocapturar,
                sumatotal,
                'AVOQADO CASH',
                WorkspaceId
            FROM formasdepago
            WHERE idformadepago = @ReferenceId;
        END
        ELSE
        BEGIN
            -- No reference found, create with defaults
            INSERT INTO formasdepago (idformadepago, descripcion)
            VALUES ('AVOQADO', 'AVOQADO CASH');
        END

        SET @PaymentMethodId = 'AVOQADO';
    END

    -- Return the payment method ID to use
    SELECT @PaymentMethodId as PaymentMethodId;
END
GO

PRINT '✅ Created sp_EnsureAvoqadoPaymentMethod stored procedure';
PRINT '';
PRINT 'Usage from application:';
PRINT '  DECLARE @MethodId VARCHAR(10);';
PRINT '  EXEC sp_EnsureAvoqadoPaymentMethod @PaymentMethodId = @MethodId OUTPUT;';
PRINT '  -- Then use @MethodId for the payment';