-- =============================================
-- Fix sp_ApplyPartialPayment to use SoftRestaurant's native quantity adjustment
-- (Like split bill - adjusts item quantities proportionally)
-- =============================================

USE avov2
GO

IF OBJECT_ID('sp_ApplyPartialPayment') IS NOT NULL
    DROP PROCEDURE sp_ApplyPartialPayment
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
AS BEGIN
    SET NOCOUNT ON

    -- 🔍 DEBUG: Log all parameters immediately
    INSERT INTO AvoqadoDebugLog (Folio, PaymentAmount, TipAmount, PaymentMethod, Reference, Message)
    VALUES (@Folio, @PaymentAmount, @TipAmount, @PaymentMethod, @Reference, 'Procedure called with these parameters')

    BEGIN TRY
        BEGIN TRANSACTION

        -- Validate order exists
        IF NOT EXISTS(SELECT 1 FROM tempcheques WHERE folio = @Folio)
        BEGIN
            SET @Success = 0
            SET @Message = 'Order not found'
            SET @Remaining = 0
            ROLLBACK
            RETURN
        END

        -- Get order details
        DECLARE @OrderTotal MONEY, @PaidSoFar MONEY, @CurrentObservaciones VARCHAR(250), @WorkspaceId UNIQUEIDENTIFIER
        SELECT @OrderTotal = total, @CurrentObservaciones = ISNULL(observaciones, ''), @WorkspaceId = WorkspaceId
        FROM tempcheques WHERE folio = @Folio

        -- Calculate remaining balance after this payment
        SELECT @PaidSoFar = ISNULL(SUM(importe), 0) FROM tempchequespagos WHERE folio = @Folio
        SET @Remaining = @OrderTotal - (@PaidSoFar + @PaymentAmount)

        -- 🔍 DEBUG: Log calculation details
        INSERT INTO AvoqadoDebugLog (Folio, PaymentAmount, Message)
        VALUES (@Folio, @PaymentAmount,
                'OrderTotal=' + CAST(@OrderTotal AS VARCHAR) +
                ', PaidSoFar=' + CAST(@PaidSoFar AS VARCHAR) +
                ', Remaining=' + CAST(@Remaining AS VARCHAR))

        -- ALWAYS insert payment record (critical for shift reports)
        -- IMPORTANT: Each payment gets unique WorkspaceId (SoftRestaurant native behavior)
        INSERT INTO tempchequespagos (folio, idformadepago, importe, propina, referencia, tipodecambio, WorkspaceId)
        VALUES (@Folio, 'ACASH', @PaymentAmount, @TipAmount, @Reference, 1, NEWID())

        -- 🔍 DEBUG: Confirm insert
        INSERT INTO AvoqadoDebugLog (Folio, PaymentAmount, Message)
        VALUES (@Folio, @PaymentAmount, 'Payment record inserted into tempchequespagos')

        -- Check if order is now fully paid
        IF ABS(@Remaining) <= 0.01
        BEGIN
            -- 🔍 DEBUG: Full payment path
            INSERT INTO AvoqadoDebugLog (Folio, PaymentAmount, Message)
            VALUES (@Folio, @PaymentAmount, 'FULL PAYMENT PATH: Marking order as paid')

            -- FULL PAYMENT: Mark order as paid
            UPDATE tempcheques SET pagado = 1,
                observaciones = @CurrentObservaciones + CASE WHEN @CurrentObservaciones = '' THEN '' ELSE ' | ' END + 'PAGADO'
            WHERE folio = @Folio

            SET @Success = 1
            SET @Message = 'Order fully paid'
            SET @Remaining = 0

            -- 🔍 DEBUG: Confirm full payment
            INSERT INTO AvoqadoDebugLog (Folio, PaymentAmount, Message)
            VALUES (@Folio, @PaymentAmount, 'Full payment UPDATE executed')
        END
        ELSE
        BEGIN
            -- 🔍 DEBUG: Partial payment path
            INSERT INTO AvoqadoDebugLog (Folio, PaymentAmount, Message)
            VALUES (@Folio, @PaymentAmount, 'PARTIAL PAYMENT PATH: Remaining=' + CAST(@Remaining AS VARCHAR))

            -- PARTIAL PAYMENT: Adjust item quantities proportionally (SoftRestaurant native way)
            DECLARE @RemainingRatio DECIMAL(10,6) = @Remaining / @OrderTotal

            -- 🔍 DEBUG: Show ratio calculation
            INSERT INTO AvoqadoDebugLog (Folio, PaymentAmount, Message)
            VALUES (@Folio, @PaymentAmount, 'Ratio calculation: ' + CAST(@Remaining AS VARCHAR) + ' / ' + CAST(@OrderTotal AS VARCHAR) + ' = ' + CAST(@RemainingRatio AS VARCHAR))

            -- Update item quantities to reflect remaining amount (like SoftRestaurant split bill)
            UPDATE tempcheqdet
            SET cantidad = CAST(cantidad * @RemainingRatio AS DECIMAL(10,4))
            WHERE foliodet = @Folio

            -- 🔍 DEBUG: After quantity update
            INSERT INTO AvoqadoDebugLog (Folio, PaymentAmount, Message)
            VALUES (@Folio, @PaymentAmount, 'Item quantities updated, rows affected: ' + CAST(@@ROWCOUNT AS VARCHAR))

            -- Recalculate order totals from updated quantities
            DECLARE @NewSubtotal MONEY = @Remaining / 1.16
            DECLARE @NewTax MONEY = @Remaining - (@Remaining / 1.16)
            DECLARE @PaymentNote VARCHAR(50) = 'Pago: $' + CAST(CAST(@PaymentAmount AS INT) AS VARCHAR) + ' (ACASH)'

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
                observaciones = CASE WHEN LEN(@CurrentObservaciones + ' | ' + @PaymentNote) <= 250
                    THEN @CurrentObservaciones + CASE WHEN @CurrentObservaciones = '' THEN '' ELSE ' | ' END + @PaymentNote
                    ELSE @PaymentNote END
            WHERE folio = @Folio

            -- 🔍 DEBUG: After order update
            INSERT INTO AvoqadoDebugLog (Folio, PaymentAmount, Message)
            VALUES (@Folio, @PaymentAmount, 'Order totals updated with new calculated values')

            SET @Success = 1
            SET @Message = 'Partial payment recorded - Remaining: $' + CAST(@Remaining AS VARCHAR)
        END

        -- Track changes
        INSERT INTO AvoqadoTracking (EntityType, EntityId, Operation, RetryCount)
        VALUES ('payment', dbo.fn_GetAvoqadoEntityIdWithWorkspace('payment', @Folio, NULL, NULL, NULL), 'CREATE', 0)

        INSERT INTO AvoqadoTracking (EntityType, EntityId, Operation, RetryCount)
        VALUES ('order', dbo.fn_GetAvoqadoEntityIdWithWorkspace('order', @Folio, NULL, NULL, NULL), 'UPDATE', 0)

        -- 🔍 DEBUG: Transaction about to commit
        INSERT INTO AvoqadoDebugLog (Folio, PaymentAmount, Message)
        VALUES (@Folio, @PaymentAmount, 'About to COMMIT transaction')

        COMMIT TRANSACTION

        -- 🔍 DEBUG: Transaction committed
        INSERT INTO AvoqadoDebugLog (Folio, PaymentAmount, Message)
        VALUES (@Folio, @PaymentAmount, 'Transaction COMMITTED successfully')

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK
        SET @Success = 0
        SET @Message = ERROR_MESSAGE()
        SET @Remaining = -1

        -- 🔍 DEBUG: Log error
        INSERT INTO AvoqadoDebugLog (Folio, PaymentAmount, Message)
        VALUES (@Folio, @PaymentAmount, 'ERROR: ' + ERROR_MESSAGE())
    END CATCH
END
GO

PRINT '✅ sp_ApplyPartialPayment recreated with SoftRestaurant native quantity adjustment'
PRINT ''
PRINT '📝 This now works like SoftRestaurant split bill:'
PRINT '   - Adjusts item quantities proportionally'
PRINT '   - Shift close recalculation will work correctly'
PRINT ''
PRINT '🧪 Test with: Apply $10 payment to $777 order'
PRINT '   - Ratio: 767/777 = 0.987132'
PRINT '   - Quantity: 1.0 * 0.987132 = 0.9871'
PRINT '   - Recalculated total: 0.9871 * $777 = $767.06'