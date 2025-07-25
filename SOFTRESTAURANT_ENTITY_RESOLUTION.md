# SoftRestaurant Entity Resolution System

## Problem Overview

SoftRestaurant POS has a unique behavior that creates duplicate orders in our backend system due to how it handles order creation and payment processing.

### The Root Cause

When SoftRestaurant creates an order, it follows this sequence:

1. **Order Creation**: `INSERT INTO tempcheques` with `idturno=0` (temporary shift ID)
2. **Order Payment**: `UPDATE tempcheques SET idturno=894, pagado=1` (real shift ID)

This creates different Entity IDs at each stage:
- Creation: `{InstanceId}:0:{folio}` (e.g., `abc123:0:1001`)
- Payment: `{InstanceId}:894:{folio}` (e.g., `abc123:894:1001`)

Our backend treats these as completely separate orders, causing:
- Duplicate order records
- Payment processing issues
- Inconsistent data synchronization

## Solution Architecture

We implemented a two-part solution maintaining clean, readable code:

### Part 1: Context-Aware Delete in Producer (Windows Service)

**File**: `src/components/producer.ts`
**Lines**: 152-162

The producer now detects shift closures and ignores order deletion events during normal shift archiving operations. This prevents valid orders from being incorrectly marked as DELETED when `tempcheques` records are purged during shift close.

```typescript
// Context-aware deletion logic
if (eventType === 'deleted') {
  const orderIdParts = change.EntityId.split(':')
  const shiftIdForOrder = orderIdParts[1]

  if (closedShiftIdsInBatch.has(shiftIdForOrder)) {
    // Skip deletion - this is normal shift archiving, not cancellation
    continue
  }
}
```

### Part 2: Smart Entity Resolution in Backend

**File**: `backend/src/services/pos-sync/posSyncOrder.service.ts`

Added intelligent order resolution that handles the idturno=0 → real idturno transition:

```typescript
async function findExistingOrderWithSmartResolution(
  externalId: string,
  venueId: string,
  folio: string
): Promise<Order | null>
```

**How it works**:
1. **Exact Match**: First tries to find order by exact Entity ID
2. **Smart Resolution**: If no exact match and current idturno ≠ 0:
   - Searches for orphaned order with idturno=0
   - If found, updates its externalId to the real Entity ID
   - Returns the updated order for processing

This ensures:
- Order creation with idturno=0 creates the initial record
- Order payment with real idturno finds and updates the same record
- No duplicate orders are created

## Implementation Benefits

### Code Clarity
- Each function has a single, clear responsibility
- Comprehensive comments explain the SoftRestaurant-specific behavior
- Easy for new developers to understand the edge case handling

### Data Integrity
- Prevents duplicate orders in the backend
- Maintains correct payment associations
- Preserves order history and audit trails

### Performance
- Minimal database queries (only when needed)
- Efficient Entity ID resolution
- No impact on normal order processing

## Technical Details

### Entity ID Format
- **Orders**: `{InstanceId}:{IdTurno}:{Folio}`
- **Order Items**: `{InstanceId}:{IdTurno}:{Folio}:{Movimiento}`
- **Shifts**: `{IdTurno}`

### Database Compatibility
- SQL Server 2014 Express Edition compatible
- Uses existing SoftRestaurant table structure
- No schema modifications required

### Error Handling
- Graceful fallback to exact matching if smart resolution fails
- Comprehensive logging for debugging
- Transaction safety maintained

## Monitoring and Debugging

### Log Messages to Watch
- `🔍 SmartResolution] Buscando orden huérfana con idturno=0`
- `🎯 SmartResolution] ¡Orden huérfana encontrada!`
- `Producer-Context] Ignorando eliminación... turno cerrado`

### Key Metrics
- Reduced duplicate order creation
- Successful payment processing on existing orders
- Decreased order deletion events during shift close

## Future Considerations

This solution is specifically designed for SoftRestaurant's dual-key architecture pattern. If other POS systems are integrated, they may require different entity resolution strategies.

The code is structured to be easily extensible for additional POS system behaviors while maintaining the clean, readable approach requested.