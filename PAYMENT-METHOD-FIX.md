# Critical Fix: Payment Method Selection

> **📌 HISTORICAL NOTE (Updated Oct 1, 2024):**
> This document describes the investigation that led to discovering why ACASH payments were zeroed.
> **FINAL SOLUTION**: Backend now uses **DEB** (not ACARD) for all Avoqado payments.
> See `payment.tpv.service.ts:1101` for implementation.

## 🚨 ROOT CAUSE: ACASH (Cash Type) Gets Recalculated to $0.00

### The Problem

**ACASH (tipo=1 = CASH)** payments get **recalculated by SoftRestaurant's native consolidation logic** during shift close preparation, causing Avoqado payments to be archived with **$0.00** instead of the actual amount paid.

### What Happens:

1. **Avoqado pays $15.00** via ACASH (tipo=1 CASH)
   - Payment inserted into `tempchequespagos` with `importe=15.00`
   - Order total reduced from $861.92 to $846.92

2. **Waiter pays remaining $846.92** with DEB card (tipo=2)
   - But POS somehow records $861.92 payment (original total?)

3. **SoftRestaurant's consolidation logic** (before shift close):
   ```sql
   -- Line 1909 in logs - THIS ZEROS OUT CASH PAYMENTS!
   UPDATE tempcp set tempcp.importe=viewcal.nuevoefectivopagos
   from tempchequespagos as tempcp
   inner join vwcalculatempcheques as viewcal on tempcp.folio=viewcal.folio
   WHERE tempcp.idformadepago in (
       select top(1) ffp.idformadepago from formasdepago
       where ffp.tipo=1  -- CASH TYPE ONLY!
   )
   ```

4. **SoftRestaurant recalculates**:
   - "Order total = $861.92"
   - "Card payments = $861.92"
   - "Therefore, Cash = $0.00"
   - **Updates ACASH payment to $0.00**

5. **Shift close archives** the zeroed-out payment:
   ```
   ACASH: $0.00  ❌ (should be $15.00)
   DEB:   $861.92 ✅
   ```

### Database Evidence:

```sql
-- Archived order (folio=24539, shift 959)
total:              $861.92
efectivo:           $0.00    ❌ (ACASH zeroed)
tarjeta:            $861.92
observaciones:      "Pago: $15 (ACASH)"  ✅ (note preserved)

-- Archived payments
ACASH:  $0.00    ❌
DEB:    $861.92  ✅
```

## ✅ SOLUTION: Use ACARD (Card Type) Instead

**ACARD (tipo=2 = CARD)** payments are **NOT recalculated** by SoftRestaurant's consolidation logic!

### Payment Method Types:

| Payment Method | Type | Description | Recalculated? | Status |
|---------------|------|-------------|---------------|--------|
| **ACASH** | tipo=1 (CASH) | Avoqado Cash | ❌ YES - Gets zeroed! | Deprecated |
| **AEF** | tipo=1 (CASH) | Efectivo | ❌ YES - Gets zeroed! | Native |
| **ACARD** | tipo=2 (CARD) | Avoqado Card | ✅ NO - Safe | Deprecated |
| **DEB** | tipo=2 (CARD) | Debit Card | ✅ NO - Safe | ✅ **USED** |
| **CRE** | tipo=2 (CARD) | Credit Card | ✅ NO - Safe | Native |

### Why Card Type Works:

SoftRestaurant's consolidation **only recalculates tipo=1 (CASH)**:
```sql
WHERE tempcp.idformadepago in (
    select top(1) ffp.idformadepago from formasdepago
    where ffp.tipo=1  -- ONLY CASH TYPES!
)
```

**Card payments (tipo=2) are left untouched** and archived with their original amounts.

## 🔧 Implementation Changes

### 1. Backend Service
**✅ IMPLEMENTED**: Updated payment method mapping in `avoqado-server/src/services/tpv/payment.tpv.service.ts`:

```typescript
// ❌ OLD: Used 'AEF' (Cash - tipo=1)
CASH: 'AEF',
BANK_TRANSFER: 'AEF',
OTHER: 'AEF',

// ✅ NEW: Use 'DEB' (Card - tipo=2) - Line 1101
CASH: 'DEB',
BANK_TRANSFER: 'DEB',
OTHER: 'DEB',
// Default fallback: 'DEB'
```

**Note**: Initially considered ACARD, but DEB is preferred as it's a native SoftRestaurant payment method.

### 2. Stored Procedure (Already Fixed)
The stored procedure now:
- ✅ Uses `@PaymentMethod` parameter (not hardcoded)
- ✅ Uses order's `@WorkspaceId` (not `NEWID()`)
- ✅ Uses `ROUND()` for precision

### 3. Payment Method Configuration
**✅ NO ACTION NEEDED**: DEB is a native SoftRestaurant payment method.

```sql
-- Verify DEB exists (should already exist)
SELECT idformadepago, descripcion, tipo, visible, sumatotal
FROM formasdepago
WHERE idformadepago = 'DEB'

-- Expected:
-- DEB | TAR. DEBITO | tipo=2 | visible=1 | sumatotal=0
```

**Note**: ACARD/ACASH were custom payment methods created during testing but are no longer needed.

## 🧪 Testing Checklist

### Before Testing:
1. ✅ Deploy updated stored procedure (with WorkspaceId + precision fixes)
2. ✅ Backend updated to use 'DEB' instead of 'AEF' (payment.tpv.service.ts:1101)
3. ✅ Verify DEB payment method exists (should be native)

### Test Scenario:
1. **Create order**: $100.00
2. **Avoqado payment**: $10.00 (backend sends DEB automatically)
3. **Verify**:
   - Order total reduced to $90.00
   - Payment in tempchequespagos: DEB = $10.00
4. **Complete with POS**: Pay remaining $90.00 with DEB
5. **Close shift**
6. **Verify archived data**:
   ```sql
   SELECT c.folio, c.total, c.efectivo, c.tarjeta, c.observaciones,
          cp.idformadepago, cp.importe
   FROM cheques c
   LEFT JOIN chequespagos cp ON c.folio = cp.folio
   WHERE c.idturno = [SHIFT_ID]
   ```

### Expected Result:
```
Order total:  $100.00 (original)
Payments archived:
  DEB (Avoqado): $10.00  ✅ (preserved!)
  DEB (POS):     $90.00  ✅
Total payments: $100.00 ✅

Note: Both payments use DEB, distinguish by reference/timestamp
```

## 📋 Additional Fixes Applied

### 1. Ratio Precision (Fixed)
```sql
-- ❌ OLD: DECIMAL(10,6) - Caused $89.98 instead of $90.00
DECLARE @RemainingRatio DECIMAL(10,6) = @Remaining / @OrderTotal

-- ✅ NEW: DECIMAL(18,10) + ROUND for exact precision
DECLARE @RemainingRatio DECIMAL(18,10) = CAST(@Remaining AS DECIMAL(18,10)) / CAST(@OrderTotal AS DECIMAL(18,10))
UPDATE tempcheqdet SET cantidad = ROUND(cantidad * @RemainingRatio, 4)
```

### 2. Tax Calculation Precision (Fixed)
```sql
-- ❌ OLD: Could cause rounding errors
DECLARE @NewSubtotal MONEY = @Remaining / 1.16

-- ✅ NEW: ROUND to 2 decimals
DECLARE @NewSubtotal MONEY = ROUND(@Remaining / 1.16, 2)
DECLARE @NewTax MONEY = ROUND(@Remaining - (@Remaining / 1.16), 2)
```

### 3. WorkspaceId Matching (Fixed)
```sql
-- ❌ OLD: Random WorkspaceId caused archiving issues
VALUES (@Folio, @PaymentMethod, @PaymentAmount, ..., NEWID())

-- ✅ NEW: Uses order's WorkspaceId
VALUES (@Folio, @PaymentMethod, @PaymentAmount, ..., @WorkspaceId)
```

## ⚠️ CRITICAL: Why We MUST Update Order Totals

**The user is absolutely correct** - we MUST update order totals:

> "if we pay from avoqado and the amount paid is not subtracted from the total order,
> then when the waiter pays the bill won't discount the already paid amount"

**If we DON'T reduce totals**:
1. Customer orders $100.00
2. Avoqado pays $10.00 (but total stays $100.00)
3. Waiter goes to collect payment
4. POS shows: "Total due: $100.00" ❌
5. Customer pays $100.00 AGAIN
6. **Customer charged $110.00 total!** ❌❌❌

**With our current logic** (reducing totals):
1. Customer orders $100.00
2. Avoqado pays $10.00 (total reduced to $90.00)
3. Waiter goes to collect payment
4. POS shows: "Total due: $90.00" ✅
5. Customer pays $90.00
6. **Customer charged $100.00 total** ✅

## 🎯 Final Solution Summary

1. ✅ **Use DEB (tipo=2)** instead of ACASH/AEF (tipo=1)
2. ✅ **Update order totals** (quantity adjustment + recalculation)
3. ✅ **Use order's WorkspaceId** for payment matching
4. ✅ **Use ROUND()** for 100% precision
5. ✅ **Keep current partial payment logic** (it's correct!)

**✅ IMPLEMENTED**: Backend now uses **DEB** (native payment method) instead of custom ACARD.
- File: `payment.tpv.service.ts:1101`
- All Avoqado payments (CASH, BANK_TRANSFER, OTHER) → DEB
