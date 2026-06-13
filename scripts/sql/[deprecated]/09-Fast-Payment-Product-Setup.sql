-- =============================================
-- Fast Payment Product Setup for SoftRestaurant
-- Date: 2025-09-23
-- Author: Claude
-- =============================================

/*
PURPOSE:
--------
This script creates a special product in SoftRestaurant for handling fast payments.
Fast payments are standalone transactions that don't require a full order workflow.
They're used for quick cash register entries like tips, donations, or other quick sales.

REQUIREMENTS:
-------------
- SoftRestaurant v10 or v11 database
- Execute with appropriate permissions to insert into productos and productosdetalle tables
- Should be run AFTER the Avoqado integration is installed

PRODUCT CONFIGURATION:
----------------------
- Product ID: 'FASTPAY' (can be customized)
- Description: 'Pago Rápido / Fast Payment'
- Group: 'OTROS' (miscellaneous group)
- Enabled for: Fast sales (usarrapido = 1)
- Price: Variable (will be set dynamically based on payment amount)
*/

-- =========================================
-- 1. CHECK IF FAST PAYMENT PRODUCT EXISTS
-- =========================================
IF NOT EXISTS (SELECT 1 FROM productos WHERE idproducto = 'FASTPAY')
BEGIN
    PRINT 'Creating fast payment product...'

    -- Check if OTROS group exists, if not create it
    IF NOT EXISTS (SELECT 1 FROM grupos WHERE idgrupo = 'OTROS')
    BEGIN
        INSERT INTO grupos (
            idgrupo, descripcion, clasificacion, prioridad,
            color, colorletra, prioridadimpresion, cambiacolorcuenta,
            colorcuenta, colorletracuenta, solicitaautorizacion,
            imagenmenuelectronico, extmenu, porcentajepropina, alcohol, servicecode
        ) VALUES (
            'OTROS', 'Otros / Miscellaneous', 1, 99,
            16777215, 0, 99, 0,
            16777215, 0, 0,
            '', '', 0, 0, ''
        )
        PRINT 'Created OTROS product group'
    END

    -- =========================================
    -- 2. INSERT FAST PAYMENT PRODUCT
    -- =========================================
    INSERT INTO productos (
        idproducto, descripcion, idgrupo, nombrecorto, plu,
        imagen, nofacturable, comentario, usarcomedor, usardomicilio,
        usarrapido, usarcedis, idinsumospresentaciones, imagenmenuelectronico,
        descripcionmenuelectronico, usarmenuelectronico, extmenu
    ) VALUES (
        'FASTPAY',                          -- idproducto
        'Pago Rápido / Fast Payment',      -- descripcion
        'OTROS',                            -- idgrupo
        'PAGO RAPIDO',                      -- nombrecorto
        'FASTPAY',                          -- plu
        '',                                 -- imagen
        0,                                  -- nofacturable (facturable)
        'Producto especial para pagos rápidos', -- comentario
        0,                                  -- usarcomedor (no)
        0,                                  -- usardomicilio (no)
        1,                                  -- usarrapido (SI - importante!)
        0,                                  -- usarcedis (no)
        '',                                 -- idinsumospresentaciones
        '',                                 -- imagenmenuelectronico
        'Fast Payment',                     -- descripcionmenuelectronico
        0,                                  -- usarmenuelectronico
        ''                                  -- extmenu
    )

    -- =========================================
    -- 3. INSERT PRODUCT DETAILS
    -- =========================================
    INSERT INTO productosdetalle (
        idproducto, precio, bloqueado, idimpuesto1, idimpuesto2, idimpuesto3,
        preciosinimpuestos, sugerido, impuesto1, impuesto2, impuesto3
    ) VALUES (
        'FASTPAY',      -- idproducto
        0.00,          -- precio (será dinámico)
        0,             -- bloqueado (no bloqueado)
        '',            -- idimpuesto1
        '',            -- idimpuesto2
        '',            -- idimpuesto3
        0.00,          -- preciosinimpuestos
        0,             -- sugerido
        0,             -- impuesto1
        0,             -- impuesto2
        0              -- impuesto3
    )

    PRINT 'Fast payment product created successfully!'
END
ELSE
BEGIN
    PRINT 'Fast payment product already exists (FASTPAY)'

    -- Ensure it's enabled for fast sales
    UPDATE productos
    SET usarrapido = 1
    WHERE idproducto = 'FASTPAY'

    PRINT 'Updated fast payment product configuration'
END

-- =========================================
-- 4. VERIFICATION QUERIES
-- =========================================
PRINT ''
PRINT 'Verification:'
PRINT '============='

-- Check product exists
SELECT
    p.idproducto,
    p.descripcion,
    p.idgrupo,
    p.usarrapido,
    pd.precio,
    CASE WHEN p.usarrapido = 1 THEN 'YES' ELSE 'NO' END AS 'Enabled for Fast Sales'
FROM productos p
INNER JOIN productosdetalle pd ON p.idproducto = pd.idproducto
WHERE p.idproducto = 'FASTPAY'

-- =========================================
-- 5. USAGE NOTES
-- =========================================
/*
HOW TO USE THIS PRODUCT:
-------------------------
1. The Windows service will use product ID 'FASTPAY' by default for fast payments
2. The product price will be set dynamically to match the payment amount
3. Fast payments will create orders with:
   - tipodeservicio = 3 (fast service)
   - tipoventarapida = 1 (fast sale)
   - mesa = 'FAST' (identifies as fast payment)

CUSTOMIZATION:
--------------
If you want to use a different product ID:
1. Create your custom product with usarrapido = 1
2. Pass the productId in the FastPaymentData when calling createFastPayment()

TESTING:
--------
To test a fast payment from the backend:
{
  "entity": "FastPayment",
  "action": "CREATE",
  "payload": {
    "amount": 100.00,
    "posPaymentMethodId": "EF",
    "cashierPosId": "1",
    "reference": "Test fast payment",
    "notes": "Testing fast payment integration"
  }
}

CLEANUP:
--------
If you need to remove the fast payment product:
DELETE FROM productosdetalle WHERE idproducto = 'FASTPAY'
DELETE FROM productos WHERE idproducto = 'FASTPAY'
*/