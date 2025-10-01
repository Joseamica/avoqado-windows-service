-- ====================================================================
-- 10 - NATIVE SOFTRESTAURANT PAYMENT FLOW FOR FULL PAYMENTS
-- SQL Server 2014 Compatible
--
-- PURPOSE:
-- Implements native SoftRestaurant payment behavior when payment
-- from Avoqado is for the full amount or more. Ensures proper
-- order printing, payment recording, and status updates.
-- ====================================================================

PRINT N'🔧 =============================================================';
PRINT N'🔧 IMPLEMENTING NATIVE PAYMENT FLOW FOR FULL PAYMENTS';
PRINT N'🔧 =============================================================';
PRINT N'';
PRINT N'Started at: ' + CONVERT(VARCHAR, GETDATE(), 120);
PRINT N'';

-- =====================================================
-- DROP OLD VERSION IF EXISTS
-- =====================================================
IF OBJECT_ID('sp_ApplyPartialPayment', 'P') IS NOT NULL
BEGIN
    PRINT N'📌 Dropping existing sp_ApplyPartialPayment...';
    DROP PROCEDURE sp_ApplyPartialPayment;
END
GO

-- =====================================================
-- CREATE ENHANCED PAYMENT PROCEDURE
-- =====================================================
PRINT N'📌 Creating enhanced payment procedure with native flow...';
GO

CREATE PROCEDURE sp_ApplyPartialPayment
    @Folio BIGINT,
    @PaymentAmount MONEY,
    @TipAmount MONEY = 0,
    @PaymentMethod VARCHAR(50),
    @Reference VARCHAR(255) = NULL,
    @Success BIT OUTPUT,
    @Message NVARCHAR(500) OUTPUT,
    @Remaining MONEY OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- =====================================================
        -- VALIDATE ORDER EXISTS
        -- =====================================================
        IF NOT EXISTS(SELECT 1 FROM tempcheques WHERE folio = @Folio)
        BEGIN
            SET @Success = 0;
            SET @Message = 'Order not found: ' + CAST(@Folio AS VARCHAR);
            SET @Remaining = 0;
            ROLLBACK;
            RETURN;
        END

        -- =====================================================
        -- GET CURRENT ORDER STATE
        -- =====================================================
        DECLARE @OrderTotal MONEY, @PaidSoFar MONEY, @Impreso BIT, @Pagado BIT;
        DECLARE @CurrentObservaciones VARCHAR(250), @NumCheque INT;
        DECLARE @IdTurno BIGINT, @Estacion VARCHAR(50);

        SELECT
            @OrderTotal = total,
            @Impreso = impreso,
            @Pagado = pagado,
            @NumCheque = numcheque,
            @CurrentObservaciones = ISNULL(observaciones, ''),
            @IdTurno = idturno,
            @Estacion = ISNULL(estacion, 'POS01')
        FROM tempcheques
        WHERE folio = @Folio;

        -- Check if already paid
        IF @Pagado = 1
        BEGIN
            SET @Success = 0;
            SET @Message = 'Order already paid';
            SET @Remaining = 0;
            ROLLBACK;
            RETURN;
        END

        -- Get total paid so far
        SELECT @PaidSoFar = ISNULL(SUM(importe), 0)
        FROM tempchequespagos
        WHERE folio = @Folio;

        -- Calculate remaining after this payment
        SET @Remaining = @OrderTotal - (@PaidSoFar + @PaymentAmount);

        -- =====================================================
        -- DETERMINE PAYMENT TYPE (1=Cash, 2=Card, 3=Voucher, 4=Other)
        -- =====================================================
        DECLARE @PaymentType INT = 1; -- Default to cash
        DECLARE @IdFormaDePago VARCHAR(2);

        -- Map payment method to SoftRestaurant format
        IF @PaymentMethod LIKE '%card%' OR @PaymentMethod LIKE '%tarj%'
            SET @PaymentType = 2;
        ELSE IF @PaymentMethod LIKE '%vale%' OR @PaymentMethod LIKE '%voucher%'
            SET @PaymentType = 3;
        ELSE IF @PaymentMethod NOT LIKE '%efec%' AND @PaymentMethod NOT LIKE '%cash%'
            SET @PaymentType = 4;

        -- Get the correct payment form ID
        SELECT TOP 1 @IdFormaDePago = idformadepago
        FROM formasdepago
        WHERE tipo = @PaymentType
        ORDER BY idformadepago;

        -- Default if not found
        IF @IdFormaDePago IS NULL
            SET @IdFormaDePago = '01'; -- Default to cash

        -- =====================================================
        -- PROCESS PAYMENT BASED ON AMOUNT
        -- =====================================================
        IF @Remaining > 0.01  -- PARTIAL PAYMENT
        BEGIN
            -- =====================================================
            -- PARTIAL PAYMENT LOGIC (Keep existing)
            -- =====================================================
            DECLARE @RemainingRatio DECIMAL(10,6) = @Remaining / @OrderTotal;

            -- Update item quantities to reflect remaining amount
            UPDATE tempcheqdet
            SET cantidad = CAST(cantidad * @RemainingRatio AS DECIMAL(10,4))
            WHERE foliodet = @Folio;

            -- Update order totals
            DECLARE @NewSubtotal MONEY = @Remaining / 1.16;  -- Assuming 16% tax
            DECLARE @NewTax MONEY = @Remaining - @NewSubtotal;

            -- Build payment note
            DECLARE @PaymentNote VARCHAR(50);
            SET @PaymentNote = 'Pago: $' + CAST(@PaymentAmount AS VARCHAR) +
                              ' (' + LEFT(@PaymentMethod, 3) + ') ' +
                              CONVERT(VARCHAR(5), GETDATE(), 108);

            -- Update order with new totals
            UPDATE tempcheques
            SET total = @Remaining,
                subtotal = @NewSubtotal,
                totalimpuesto1 = @NewTax,
                totalconpropina = @Remaining,
                totalsindescuento = @Remaining,
                totalsindescuentoimp = @Remaining,
                totalconpropinacargo = @Remaining,
                totalconcargo = @Remaining,
                subtotalcondescuento = @NewSubtotal,
                subtotalsinimpuestos = @NewSubtotal,
                observaciones = CASE
                    WHEN LEN(@CurrentObservaciones + ' | ' + @PaymentNote) <= 250
                    THEN @CurrentObservaciones + CASE WHEN @CurrentObservaciones = '' THEN '' ELSE ' | ' END + @PaymentNote
                    ELSE @PaymentNote
                END
            WHERE folio = @Folio;

            SET @Success = 1;
            SET @Message = 'Partial payment applied. Remaining: $' + CAST(@Remaining AS VARCHAR);
        END
        ELSE  -- FULL PAYMENT (Native Flow)
        BEGIN
            -- =====================================================
            -- NATIVE FULL PAYMENT FLOW
            -- =====================================================

            -- Step 1: Ensure order is printed (required before payment)
            IF @Impreso = 0
            BEGIN
                DECLARE @NextNumCheque INT;
                DECLARE @Serie VARCHAR(15) = ''; -- Default serie

                -- Get next sequential number
                SELECT @NextNumCheque = ultimofolio + 1
                FROM folios WITH (TABLOCKX)
                WHERE serie = @Serie;

                -- Print the order (assign numcheque)
                UPDATE tempcheques WITH(TABLOCK)
                SET impreso = 1,
                    numcheque = @NextNumCheque,
                    cierre = GETDATE(),
                    impresiones = impresiones + 1,
                    seriefolio = @Serie
                WHERE folio = @Folio;

                -- Update folio counter
                UPDATE folios WITH(TABLOCK)
                SET ultimofolio = @NextNumCheque
                WHERE serie = @Serie;

                -- Update cuentas table if exists
                IF EXISTS(SELECT 1 FROM cuentas WHERE foliocuenta = @Folio)
                BEGIN
                    UPDATE cuentas
                    SET imprimir = 1, procesado = 1
                    WHERE foliocuenta = @Folio;
                END

                SET @NumCheque = @NextNumCheque;
            END

            -- Step 2: Insert payment record
            INSERT INTO tempchequespagos (
                folio,
                idformadepago,
                importe,
                propina,
                referencia,
                tipodecambio
            )
            VALUES (
                @Folio,
                @IdFormaDePago,
                @PaymentAmount - @TipAmount,  -- Separate amount from tip
                @TipAmount,
                @Reference,
                1  -- Exchange rate
            );

            -- Step 3: Update payment totals in tempcheques
            DECLARE @Efectivo MONEY = 0, @Tarjeta MONEY = 0, @Vales MONEY = 0, @Otros MONEY = 0;
            DECLARE @PropinaTarjeta MONEY = 0;

            -- Calculate totals by payment type
            SELECT
                @Efectivo = SUM(CASE WHEN f.tipo = 1 THEN p.importe + p.propina ELSE 0 END),
                @Tarjeta = SUM(CASE WHEN f.tipo = 2 THEN p.importe + p.propina ELSE 0 END),
                @Vales = SUM(CASE WHEN f.tipo = 3 THEN p.importe + p.propina ELSE 0 END),
                @Otros = SUM(CASE WHEN f.tipo = 4 THEN p.importe + p.propina ELSE 0 END),
                @PropinaTarjeta = SUM(CASE WHEN f.tipo = 2 THEN p.propina ELSE 0 END)
            FROM tempchequespagos p
            INNER JOIN formasdepago f ON p.idformadepago = f.idformadepago
            WHERE p.folio = @Folio;

            -- Step 4: Mark order as paid and update totals
            UPDATE tempcheques
            SET pagado = 1,
                efectivo = ISNULL(@Efectivo, 0),
                tarjeta = ISNULL(@Tarjeta, 0),
                vales = ISNULL(@Vales, 0),
                otros = ISNULL(@Otros, 0),
                propina = ISNULL(@Efectivo + @Tarjeta + @Vales + @Otros - @OrderTotal, 0),
                propinatarjeta = ISNULL(@PropinaTarjeta, 0),
                usuariopago = SYSTEM_USER,
                observaciones = CASE
                    WHEN LEN(@CurrentObservaciones) < 200
                    THEN @CurrentObservaciones + CASE WHEN @CurrentObservaciones = '' THEN '' ELSE ' | ' END + 'PAGADO COMPLETO'
                    ELSE 'PAGADO COMPLETO'
                END
            WHERE folio = @Folio;

            -- Step 5: Handle change if overpaid
            IF @Remaining < 0
            BEGIN
                SET @Success = 1;
                SET @Message = 'Order fully paid. Change: $' + CAST(ABS(@Remaining) AS VARCHAR);
            END
            ELSE
            BEGIN
                SET @Success = 1;
                SET @Message = 'Order fully paid';
            END

            SET @Remaining = 0;
        END

        -- =====================================================
        -- TRACK IN AVOQADO SYSTEM
        -- =====================================================
        INSERT INTO AvoqadoTracking (EntityType, EntityId, Operation)
        VALUES ('payment', dbo.fn_GetAvoqadoEntityId('payment', @Folio, NULL, NULL), 'APPLIED');

        COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK;

        SET @Success = 0;
        SET @Message = ERROR_MESSAGE();
        SET @Remaining = -1;

        PRINT N'❌ Error in payment procedure: ' + ERROR_MESSAGE();
    END CATCH
END
GO

PRINT N'  ✅ Enhanced payment procedure created';
PRINT N'';

-- =====================================================
-- VERIFY INSTALLATION
-- =====================================================
PRINT N'📌 Verifying installation...';

IF OBJECT_ID('sp_ApplyPartialPayment', 'P') IS NOT NULL
    PRINT N'  ✅ Payment procedure installed successfully';
ELSE
    PRINT N'  ❌ Payment procedure installation failed';

PRINT N'';
PRINT N'✅ =============================================================';
PRINT N'✅ NATIVE PAYMENT FLOW IMPLEMENTATION COMPLETE!';
PRINT N'✅ =============================================================';
PRINT N'';
PRINT N'Key Features:';
PRINT N'  🔧 Automatic order printing if not printed';
PRINT N'  🔧 Proper numcheque assignment from folios table';
PRINT N'  🔧 Payment type mapping (Cash, Card, Voucher, Other)';
PRINT N'  🔧 Correct payment totals update (efectivo, tarjeta, etc.)';
PRINT N'  🔧 Native SoftRestaurant payment flow for full payments';
PRINT N'  🔧 Change calculation for overpayments';
PRINT N'';
PRINT N'Completed at: ' + CONVERT(VARCHAR, GETDATE(), 120);
PRINT N'=============================================================';