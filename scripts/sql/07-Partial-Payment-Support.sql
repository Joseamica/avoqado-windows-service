-- ====================================================================
-- AVOQADO PARTIAL PAYMENT TRACKING - WINDOWS SERVICE
--
-- VERSIÓN: 2.5.0
-- FECHA: 2025-09-22
--
-- PROPÓSITO:
-- Crea la infraestructura necesaria para el manejo inteligente de pagos
-- parciales en SoftRestaurant, ya que el POS no soporta pagos parciales
-- nativamente. Permite rastrear pagos hasta completar el total de la orden.
--
-- COMPATIBLE CON: SoftRestaurant v10+ y v11+
-- REQUIERE: Script 06-Version-Detection-Support.sql ejecutado previamente
-- ====================================================================

PRINT N'💳 ============================================================='
PRINT N'💳 INSTALANDO SOPORTE PARA PAGOS PARCIALES'
PRINT N'💳 ============================================================='
PRINT N''

-- Verificar que tenemos las tablas base necesarias
IF OBJECT_ID('tempcheques', 'U') IS NULL OR OBJECT_ID('AvoqadoInstanceInfo', 'U') IS NULL
BEGIN
    PRINT N'❌ ERROR: Faltan tablas base requeridas (tempcheques, AvoqadoInstanceInfo).'
    RETURN
END

-- =====================================================
-- PASO 1: CREAR TABLA DE PAGOS PARCIALES
-- =====================================================
PRINT N'📌 PASO 1: Creando tabla de pagos parciales...'

IF OBJECT_ID('AvoqadoPartialPayments', 'U') IS NOT NULL
    DROP TABLE AvoqadoPartialPayments

CREATE TABLE AvoqadoPartialPayments (
    Id BIGINT IDENTITY(1,1) PRIMARY KEY,
    Folio BIGINT NOT NULL,
    Amount MONEY NOT NULL,
    TipAmount MONEY DEFAULT 0,
    PaymentMethodId VARCHAR(50) NOT NULL,
    Reference VARCHAR(255),
    CreatedAt DATETIME2 DEFAULT GETDATE(),
    ProcessedAt DATETIME2 NULL,
    IsProcessed BIT DEFAULT 0,

    -- Campos de auditoría
    ExternalPaymentId VARCHAR(255), -- ID del pago en Avoqado backend
    PaymentData NVARCHAR(MAX), -- JSON con datos adicionales del pago

    -- Índices
    INDEX IX_AvoqadoPartialPayments_Folio (Folio, IsProcessed),
    INDEX IX_AvoqadoPartialPayments_Created (CreatedAt),
    INDEX IX_AvoqadoPartialPayments_External (ExternalPaymentId)
)

PRINT N'  ✅ Tabla `AvoqadoPartialPayments` creada'

-- =====================================================
-- PASO 2: CREAR FUNCIONES DE AYUDA
-- =====================================================
PRINT N'📌 PASO 2: Creando funciones de ayuda para pagos...'

-- Función para obtener el total de pagos parciales de una orden
IF OBJECT_ID('dbo.fn_GetPartialPaymentsTotal', 'FN') IS NOT NULL
    DROP FUNCTION dbo.fn_GetPartialPaymentsTotal

EXEC('
CREATE FUNCTION dbo.fn_GetPartialPaymentsTotal(@Folio BIGINT)
RETURNS MONEY
AS
BEGIN
    DECLARE @total MONEY
    SELECT @total = ISNULL(SUM(Amount), 0)
    FROM AvoqadoPartialPayments
    WHERE Folio = @Folio AND IsProcessed = 0
    RETURN @total
END')

PRINT N'  ✅ Función `fn_GetPartialPaymentsTotal` creada'

-- Función para verificar si una orden puede ser pagada completamente
IF OBJECT_ID('dbo.fn_CanCompleteOrderPayment', 'FN') IS NOT NULL
    DROP FUNCTION dbo.fn_CanCompleteOrderPayment

EXEC('
CREATE FUNCTION dbo.fn_CanCompleteOrderPayment(@Folio BIGINT, @NewPaymentAmount MONEY)
RETURNS BIT
AS
BEGIN
    DECLARE @orderTotal MONEY
    DECLARE @partialTotal MONEY
    DECLARE @existingPayments MONEY

    -- Obtener total de la orden
    SELECT @orderTotal = ISNULL(total, 0) FROM tempcheques WHERE folio = @Folio

    -- Obtener pagos parciales pendientes
    SET @partialTotal = dbo.fn_GetPartialPaymentsTotal(@Folio)

    -- Obtener pagos ya aplicados en tempchequespagos
    SELECT @existingPayments = ISNULL(SUM(importe), 0) FROM tempchequespagos WHERE folio = @Folio

    -- Verificar si el total de pagos cubre la orden
    IF (@partialTotal + @existingPayments + @NewPaymentAmount) >= @orderTotal
        RETURN 1

    RETURN 0
END')

PRINT N'  ✅ Función `fn_CanCompleteOrderPayment` creada'

-- =====================================================
-- PASO 3: CREAR STORED PROCEDURES
-- =====================================================
PRINT N'📌 PASO 3: Creando stored procedures para manejo de pagos...'

-- Procedure para agregar un pago parcial
IF OBJECT_ID('dbo.sp_AddPartialPayment', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_AddPartialPayment

EXEC('
CREATE PROCEDURE dbo.sp_AddPartialPayment
    @Folio BIGINT,
    @Amount MONEY,
    @TipAmount MONEY = 0,
    @PaymentMethodId VARCHAR(50),
    @Reference VARCHAR(255) = NULL,
    @ExternalPaymentId VARCHAR(255) = NULL,
    @PaymentData NVARCHAR(MAX) = NULL,
    @PartialPaymentId BIGINT OUTPUT
AS
BEGIN
    INSERT INTO AvoqadoPartialPayments (
        Folio, Amount, TipAmount, PaymentMethodId, Reference,
        ExternalPaymentId, PaymentData
    )
    VALUES (
        @Folio, @Amount, @TipAmount, @PaymentMethodId, @Reference,
        @ExternalPaymentId, @PaymentData
    )

    SET @PartialPaymentId = SCOPE_IDENTITY()
END')

PRINT N'  ✅ Stored Procedure `sp_AddPartialPayment` creado'

-- Procedure para procesar todos los pagos parciales de una orden
IF OBJECT_ID('dbo.sp_ProcessPartialPayments', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_ProcessPartialPayments

EXEC('
CREATE PROCEDURE dbo.sp_ProcessPartialPayments
    @Folio BIGINT,
    @TotalProcessed MONEY OUTPUT,
    @PaymentsCount INT OUTPUT
AS
BEGIN
    DECLARE @paymentMethodId VARCHAR(50)
    DECLARE @amount MONEY
    DECLARE @tipAmount MONEY
    DECLARE @reference VARCHAR(255)

    SET @TotalProcessed = 0
    SET @PaymentsCount = 0

    -- Cursor para procesar todos los pagos parciales pendientes
    DECLARE payment_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT PaymentMethodId, Amount, TipAmount, Reference
        FROM AvoqadoPartialPayments
        WHERE Folio = @Folio AND IsProcessed = 0
        ORDER BY CreatedAt

    OPEN payment_cursor
    FETCH NEXT FROM payment_cursor INTO @paymentMethodId, @amount, @tipAmount, @reference

    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- Insertar en tempchequespagos
        INSERT INTO tempchequespagos (folio, idformadepago, importe, propina, referencia)
        VALUES (@Folio, @paymentMethodId, @amount, @tipAmount, @reference)

        SET @TotalProcessed = @TotalProcessed + @amount
        SET @PaymentsCount = @PaymentsCount + 1

        FETCH NEXT FROM payment_cursor INTO @paymentMethodId, @amount, @tipAmount, @reference
    END

    CLOSE payment_cursor
    DEALLOCATE payment_cursor

    -- Marcar todos los pagos parciales como procesados
    UPDATE AvoqadoPartialPayments
    SET IsProcessed = 1, ProcessedAt = GETDATE()
    WHERE Folio = @Folio AND IsProcessed = 0
END')

PRINT N'  ✅ Stored Procedure `sp_ProcessPartialPayments` creado'

-- =====================================================
-- PASO 4: ACTUALIZAR VERSIÓN
-- =====================================================
PRINT N'📌 PASO 4: Actualizando versión a 2.5.0...'
UPDATE dbo.AvoqadoInstanceInfo SET Version = '2.5.0'
PRINT N'  ✅ Versión actualizada a 2.5.0 (Partial Payment Support)'

-- =====================================================
-- PASO 5: PRUEBAS BÁSICAS
-- =====================================================
PRINT N'📌 PASO 5: Ejecutando pruebas básicas...'

-- Verificar que las funciones funcionan
DECLARE @testResult MONEY
DECLARE @testCanPay BIT

SET @testResult = dbo.fn_GetPartialPaymentsTotal(999999) -- Folio inexistente
IF @testResult = 0
    PRINT N'  ✅ Función fn_GetPartialPaymentsTotal funciona correctamente'
ELSE
    PRINT N'  ❌ Error en función fn_GetPartialPaymentsTotal'

SET @testCanPay = dbo.fn_CanCompleteOrderPayment(999999, 100.00) -- Folio inexistente
IF @testCanPay = 0
    PRINT N'  ✅ Función fn_CanCompleteOrderPayment funciona correctamente'
ELSE
    PRINT N'  ❌ Error en función fn_CanCompleteOrderPayment'

-- =====================================================
-- FINALIZACIÓN
-- =====================================================
PRINT N''
PRINT N'✅ ============================================================='
PRINT N'✅ SOPORTE PARA PAGOS PARCIALES INSTALADO EXITOSAMENTE'
PRINT N'✅ ============================================================='
PRINT N''
PRINT N'📋 CAMBIOS APLICADOS:'
PRINT N'   • Tabla AvoqadoPartialPayments creada para rastrear pagos parciales'
PRINT N'   • Función fn_GetPartialPaymentsTotal() para calcular totales'
PRINT N'   • Función fn_CanCompleteOrderPayment() para validar pagos completos'
PRINT N'   • Stored Procedure sp_AddPartialPayment() para registrar pagos'
PRINT N'   • Stored Procedure sp_ProcessPartialPayments() para procesar pagos'
PRINT N'   • Versión actualizada a 2.5.0'
PRINT N''
PRINT N'🔧 PRÓXIMOS PASOS:'
PRINT N'   1. Actualizar el adapter de SoftRestaurant11 para usar estas funciones'
PRINT N'   2. Implementar el manejo inteligente de pagos en el Windows Service'
PRINT N'   3. Configurar el backend para enviar comandos de pago via RabbitMQ'