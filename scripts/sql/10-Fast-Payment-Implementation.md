# Fast Payment Implementation Documentation
Date: 2025-09-23
Author: Claude

## Overview
Fast payments (pagos rápidos) are standalone transactions that bypass the normal order workflow. They're used for quick cash register entries like tips, donations, or other quick sales that don't require the full order->print->pay cycle.

## Implementation Details

### 1. Architecture
Fast payments are implemented as a special type of order with these characteristics:
- `tipodeservicio = 3` (fast service type)
- `tipoventarapida = 1` (fast sale flag)
- `mesa = 'FAST'` (identifies as fast payment)
- Single product entry with dynamic pricing
- Immediate payment and closure

### 2. Components Modified

#### IPosAdapter Interface (`src/adapters/IPosAdapter.ts`)
- Added `FastPaymentData` interface for request data
- Added `FastPaymentResult` interface for response
- Added `createFastPayment()` method to interface

#### Commander (`src/components/commander.ts`)
- Added `FastPayment.CREATE` command handler
- Validates required fields: amount, paymentMethod, cashierId
- Routes to adapter's createFastPayment method

#### SoftRestaurant11Adapter (`src/adapters/SoftRestaurant11Adapter.ts`)
- Implemented `createFastPayment()` method
- Creates order with fast payment characteristics
- Adds FASTPAY product with dynamic pricing
- Applies payment and closes order in single transaction

### 3. Database Setup

#### Fast Payment Product
Created special product with ID 'FASTPAY':
- Description: 'Pago Rápido / Fast Payment'
- Group: '03' (generic group)
- `usarrapido = 1` (enabled for fast sales)
- Price: $0.00 (set dynamically per transaction)

#### SQL Script
`09-Fast-Payment-Product-Setup.sql` creates the required product and configuration.

### 4. Transaction Flow

1. **Command Reception**: Backend sends `FastPayment.CREATE` command
2. **Validation**: Commander validates required fields
3. **Order Creation**:
   - Create order with `tipoventarapida = 1`
   - Set `mesa = 'FAST'` for identification
   - Add FASTPAY product with payment amount as price
4. **Payment Processing**:
   - Mark order as printed (required for payment)
   - Insert payment record
   - Update order payment fields
   - Mark order as paid
5. **Response**: Return folio, check number, and transaction details

### 5. Payment Method Mapping

The system supports these payment method codes:
- `AEF` - Efectivo (Cash)
- `CRE` - Tarjeta de Crédito
- `DEB` - Tarjeta de Débito
- `ACASH` - Avoqado Cash
- Others map to `otros` field

### 6. Testing

#### Manual Database Test
```sql
DECLARE @newFolio BIGINT;
DECLARE @newWorkspaceId UNIQUEIDENTIFIER = NEWID();
BEGIN TRANSACTION;

-- Create fast payment order
INSERT INTO tempcheques (
    mesa, tipodeservicio, tipoventarapida, idturno,
    total, observaciones, WorkspaceId
) VALUES (
    'FAST', 3, 1, [SHIFT_ID],
    100.00, 'Test Fast Payment', @newWorkspaceId
);
SELECT @newFolio = SCOPE_IDENTITY();

-- Add product
INSERT INTO tempcheqdet (
    foliodet, movimiento, idproducto, cantidad, precio
) VALUES (
    @newFolio, 1, 'FASTPAY', 1, 100.00
);

-- Mark as printed and pay
UPDATE tempcheques SET impreso = 1 WHERE folio = @newFolio;
INSERT INTO tempchequespagos (folio, idformadepago, importe)
VALUES (@newFolio, 'AEF', 100.00);
UPDATE tempcheques SET pagado = 1, efectivo = 100.00 WHERE folio = @newFolio;

COMMIT;
SELECT @newFolio as Folio;
```

#### Backend Command Test
```json
{
  "entity": "FastPayment",
  "action": "CREATE",
  "payload": {
    "amount": 100.00,
    "posPaymentMethodId": "AEF",
    "cashierPosId": "1",
    "reference": "Test payment",
    "notes": "Testing fast payment"
  }
}
```

### 7. Tracking & Synchronization

Fast payments are tracked in `AvoqadoTracking` table and synchronized like regular orders:
- CREATE event on order creation
- UPDATE events for print and payment
- Events published with `pos.softrestaurant.order.*` routing keys
- Distinguishable by `tipoventarapida = 1` flag

### 8. Shift Integration

Fast payments:
- Require an open shift to process
- Are included in shift totals
- Are archived during shift close like regular orders
- Appear in shift reports

### 9. Known Limitations

1. **Product Requirement**: SoftRestaurant requires a product to create any sale
2. **Fixed Product ID**: Currently uses 'FASTPAY' by default (configurable via payload)
3. **No Modifications**: Fast payments don't support item modifications or discounts
4. **Single Payment**: Only supports single payment method per transaction

### 10. Future Enhancements

- Support for multiple products in fast payment
- Configurable fast payment product per venue
- Support for tips in fast payments
- Batch fast payment processing
- Fast payment reversal/cancellation

## Verification Queries

### Check Fast Payments
```sql
-- View all fast payments
SELECT folio, mesa, total, observaciones, fecha
FROM tempcheques
WHERE tipoventarapida = 1 AND mesa = 'FAST'
ORDER BY fecha DESC;

-- Check tracking
SELECT EntityId, Operation, Timestamp
FROM AvoqadoTracking
WHERE EntityType = 'order'
  AND EntityId IN (
    SELECT WorkspaceId FROM tempcheques
    WHERE tipoventarapida = 1
  );
```

### Shift Totals Including Fast Payments
```sql
SELECT
    COUNT(*) as TotalOrders,
    SUM(CASE WHEN tipoventarapida = 1 THEN 1 ELSE 0 END) as FastPayments,
    SUM(total) as TotalSales,
    SUM(CASE WHEN tipoventarapida = 1 THEN total ELSE 0 END) as FastPaymentTotal
FROM tempcheques
WHERE idturno = [SHIFT_ID];
```

## Rollback Instructions

If you need to remove fast payment support:

1. **Remove Product**:
```sql
DELETE FROM productosdetalle WHERE idproducto = 'FASTPAY';
DELETE FROM productos WHERE idproducto = 'FASTPAY';
```

2. **Revert Code Changes**:
- Restore original `IPosAdapter.ts`
- Restore original `commander.ts`
- Restore original `SoftRestaurant11Adapter.ts`

3. **Archive Existing Fast Payments**:
Fast payments in open shifts will be archived normally during shift close.