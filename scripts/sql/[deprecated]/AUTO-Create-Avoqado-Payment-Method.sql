-- =====================================================
-- AUTO-CREATE AVOQADO PAYMENT METHOD
-- Ensures Avoqado payment method exists in formasdepago
-- Creates it automatically if not present
-- =====================================================

USE avov2;
GO

PRINT '🔍 Checking for Avoqado payment method...';
PRINT '';

-- Check if ACASH or any Avoqado payment method exists
IF NOT EXISTS (SELECT 1 FROM formasdepago WHERE idformadepago IN ('ACASH', 'AVOQADO', 'AVO'))
BEGIN
    PRINT '⚠️  No Avoqado payment method found. Creating one...';

    -- Get the configuration from an existing cash payment method
    DECLARE @ReferencePaymentId VARCHAR(10);
    DECLARE @Description VARCHAR(30) = 'AVOQADO CASH';
    DECLARE @RequiresAuth BIT = 0;
    DECLARE @OpensCashDrawer BIT = 1;
    DECLARE @AllowsChange BIT = 1;
    DECLARE @IsCard BIT = 0;

    -- Find a cash payment method to copy settings from
    SELECT TOP 1
        @ReferencePaymentId = idformadepago
    FROM formasdepago
    WHERE
        (UPPER(descripcion) LIKE '%EFECTIVO%'
        OR UPPER(descripcion) LIKE '%CASH%'
        OR UPPER(descripcion) LIKE '%EFEC%'
        OR idformadepago IN ('01', '1', 'EF', 'AEF', 'EFEC'))
    ORDER BY
        CASE
            WHEN UPPER(descripcion) LIKE '%EFECTIVO%' THEN 1
            WHEN idformadepago = 'AEF' THEN 2
            WHEN idformadepago = '01' THEN 3
            ELSE 4
        END;

    IF @ReferencePaymentId IS NOT NULL
    BEGIN
        PRINT '✅ Found reference cash payment method: ' + @ReferencePaymentId;

        -- Create AVOQADO payment method with same settings as cash
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
        WHERE idformadepago = @ReferencePaymentId;

        PRINT '✅ Created AVOQADO payment method successfully!';
    END
    ELSE
    BEGIN
        PRINT '⚠️  No cash payment method found to copy settings from.';
        PRINT '   Creating AVOQADO with default settings...';

        -- Create with minimal defaults
        INSERT INTO formasdepago (
            idformadepago,
            descripcion
        )
        VALUES (
            'AVOQADO',
            'AVOQADO CASH'
        );

        PRINT '✅ Created AVOQADO payment method with defaults.';
    END
END
ELSE
BEGIN
    PRINT '✅ Avoqado payment method already exists:';

    SELECT
        idformadepago AS 'Payment ID',
        descripcion AS 'Description'
    FROM formasdepago
    WHERE idformadepago IN ('ACASH', 'AVOQADO', 'AVO');
END

PRINT '';
PRINT '=====================================================';
PRINT '✅ AVOQADO PAYMENT METHOD CHECK COMPLETE!';
PRINT '=====================================================';
PRINT '';

-- Show all payment methods for verification
PRINT 'Current payment methods in system:';
SELECT
    idformadepago AS 'ID',
    descripcion AS 'Description'
FROM formasdepago
ORDER BY idformadepago;