# Complete Deployment & Testing Guide

## ✅ All Fixes Applied

### 1. **WorkspaceId Fix** ✅
- **Changed**: `NEWID()` → `@WorkspaceId` (uses order's WorkspaceId)
- **Impact**: Payments now correctly linked to orders
- **File**: `scripts/sql/01-COMPLETE-INSTALL.sql` Line 407

### 2. **Payment Method Parameter Fix** ✅
- **Changed**: Hardcoded `'ACASH'` → `@PaymentMethod` parameter
- **Impact**: Stored procedure now uses actual payment method passed
- **File**: `scripts/sql/01-COMPLETE-INSTALL.sql` Line 407

### 3. **Ratio Precision Fix** ✅
- **Changed**: `DECIMAL(10,6)` → `DECIMAL(18,10)` + `ROUND()`
- **Impact**: No more $89.98 instead of $90.00 errors
- **File**: `scripts/sql/01-COMPLETE-INSTALL.sql` Lines 441, 450

### 4. **Tax Calculation Precision Fix** ✅
- **Changed**: Direct division → `ROUND(@Remaining / 1.16, 2)`
- **Impact**: Exact tax calculations
- **File**: `scripts/sql/01-COMPLETE-INSTALL.sql` Lines 459-460

### 5. **Payment Method Note Fix** ✅
- **Changed**: Hardcoded `'(ACASH)'` → `'(' + @PaymentMethod + ')'`
- **Impact**: Correct payment method shown in order notes
- **File**: `scripts/sql/01-COMPLETE-INSTALL.sql` Line 461

## 🚨 CRITICAL: Use DEB Instead of ACASH/AEF

**Root Cause**: ACASH/AEF (tipo=1 CASH) gets recalculated to $0.00 by SoftRestaurant's consolidation logic before shift close archiving.

**Solution**: Use DEB (tipo=2 CARD) - card payments are NOT recalculated.

### Why This Happens:

SoftRestaurant runs this consolidation query before archiving:
```sql
UPDATE tempcp set tempcp.importe=viewcal.nuevoefectivopagos
from tempchequespagos as tempcp
inner join vwcalculatempcheques as viewcal on tempcp.folio=viewcal.folio
WHERE tempcp.idformadepago in (
    select top(1) ffp.idformadepago from formasdepago
    where ffp.tipo=1  -- ONLY CASH TYPE!
)
```

Result: Cash payments get zeroed out, card payments stay intact.

### Backend Configuration Required:

**✅ UPDATED**: The backend now automatically uses DEB for all Avoqado payments.

```json
{
  "action": "Payment.APPLY",
  "payload": {
    "folio": 12345,
    "amount": 15.00,
    "posPaymentMethodId": "DEB",  ← Backend automatically uses DEB (tipo=2 CARD)
    "tip": 0,
    "reference": null
  }
}
```

## 📋 Deployment Steps

### Step 1: Deploy Updated Stored Procedure

```bash
# Set password
export SQLCMDPASSWORD='National09'

# Deploy to test database
sqlcmd -S "tcp:100.80.118.68,49759" -d avov2 -U sa -i "scripts/sql/01-COMPLETE-INSTALL.sql"
```

### Step 2: Verify Deployment

```sql
-- Check stored procedure updated
SELECT
    OBJECT_NAME(object_id) AS ProcedureName,
    modify_date
FROM sys.procedures
WHERE name = 'sp_ApplyPartialPayment'

-- Should show today's date
```

### Step 3: Verify Payment Methods

```sql
SELECT idformadepago, descripcion, tipo, visible, sumatotal
FROM formasdepago
WHERE idformadepago IN ('ACASH', 'ACARD', 'AEF', 'DEB')

-- Expected:
-- ACASH | AVOQADO CASH | tipo=1 | visible=1 | sumatotal=0 (deprecated)
-- ACARD | AVOQADO CARD | tipo=2 | visible=1 | sumatotal=0 (deprecated)
-- AEF   | EFECTIVO     | tipo=1 | visible=1 | sumatotal=0
-- DEB   | TAR. DEBITO  | tipo=2 | visible=1 | sumatotal=0 ← Used by Avoqado
```

### Step 4: Backend Already Updated

✅ The backend (`payment.tpv.service.ts`) now automatically uses `DEB` for all Avoqado payments (CASH, BANK_TRANSFER, OTHER).

## 🧪 Complete Test Scenario

### Test Case: $15 Payment on $861.92 Bill

1. **Create Order** ($861.92 total)

2. **Send Avoqado Payment** via RabbitMQ:
   ```json
   {
     "action": "Payment.APPLY",
     "payload": {
       "folio": [FOLIO],
       "amount": 15.00,
       "posPaymentMethodId": "DEB",
       "tip": 0
     }
   }
   ```

3. **Verify Payment & Order State**:
   ```sql
   -- Check payment inserted correctly
   SELECT
       t.folio,
       t.total AS OrderTotal,
       t.WorkspaceId AS OrderWID,
       t.observaciones,
       p.idformadepago,
       p.importe AS PaymentAmount,
       p.WorkspaceId AS PaymentWID,
       CASE WHEN t.WorkspaceId = p.WorkspaceId THEN '✅ MATCH' ELSE '❌ MISMATCH' END AS Status
   FROM tempcheques t
   JOIN tempchequespagos p ON t.folio = p.folio
   WHERE t.folio = [FOLIO]

   -- Expected:
   -- OrderTotal:     $846.92 (reduced by $15)
   -- PaymentAmount:  $15.00
   -- Status:         ✅ MATCH
   -- observaciones:  "Pago: $15 (DEB)"
   ```

4. **Verify Item Quantities Adjusted**:
   ```sql
   SELECT
       foliodet,
       idproducto,
       cantidad,
       precio,
       ROUND(cantidad * precio, 2) AS itemTotal
   FROM tempcheqdet
   WHERE foliodet = [FOLIO]

   -- Sum of itemTotal should equal $846.92 (NOT $846.90 or $846.94!)
   ```

5. **Complete Payment from POS** ($846.92 with DEB card)

6. **Verify Before Shift Close**:
   ```sql
   SELECT folio, idformadepago, importe
   FROM tempchequespagos
   WHERE folio = [FOLIO]
   ORDER BY idformadepago

   -- Expected:
   -- DEB (Avoqado): $15.00   ✅
   -- DEB (POS):     $846.92  ✅
   -- Note: Both payments use DEB method
   ```

7. **Close Shift** from POS

8. **Verify Archived Correctly**:
   ```sql
   SELECT
       c.folio,
       c.total AS OriginalTotal,
       c.efectivo,
       c.tarjeta,
       c.observaciones,
       cp.idformadepago,
       cp.importe AS ArchivedAmount
   FROM cheques c
   LEFT JOIN chequespagos cp ON c.folio = cp.folio
   WHERE c.folio = [FOLIO]
   ORDER BY cp.importe

   -- Expected:
   -- DEB: $15.00    ✅ (Avoqado payment - NOT $0.00!)
   -- DEB: $846.92   ✅ (POS payment)
   -- Total payments: $861.92
   -- Note: Both use DEB, distinguish by reference/timestamp
   ```

9. **Check Shift Report** in POS - should show both payments

## 🔍 Debugging Queries

### Check Current Payment State:
```sql
SELECT
    t.folio,
    t.total,
    t.WorkspaceId AS OrderWID,
    p.idformadepago,
    p.importe,
    p.WorkspaceId AS PaymentWID,
    CASE WHEN t.WorkspaceId = p.WorkspaceId THEN '✅' ELSE '❌' END AS Match
FROM tempcheques t
LEFT JOIN tempchequespagos p ON t.folio = p.folio
WHERE t.idturno = (SELECT TOP 1 idturno FROM turnos WHERE cierre IS NULL)
```

### Check Debug Logs:
```sql
SELECT TOP 30
    Timestamp,
    Folio,
    PaymentAmount,
    PaymentMethod,
    Message
FROM AvoqadoDebugLog
ORDER BY Timestamp DESC
```

### Check Last Archived Shift:
```sql
DECLARE @LastShift BIGINT = (SELECT TOP 1 idturno FROM turnos WHERE cierre IS NOT NULL ORDER BY cierre DESC)

PRINT 'Shift: ' + CAST(@LastShift AS VARCHAR)

SELECT
    c.folio,
    c.total,
    c.observaciones,
    STRING_AGG(cp.idformadepago + ':$' + CAST(cp.importe AS VARCHAR), ', ') AS Payments
FROM cheques c
LEFT JOIN chequespagos cp ON c.folio = cp.folio
WHERE c.idturno = @LastShift
GROUP BY c.folio, c.total, c.observaciones
```

## ⚠️ Common Issues & Solutions

### Issue 1: Payment Shows $0.00 in Shift Report
**Symptom**: Payment archived but amount is $0.00
**Cause**: Using ACASH/AEF (tipo=1) instead of DEB (tipo=2)
**Solution**: ✅ Backend already updated to use DEB automatically

### Issue 2: WorkspaceId Mismatch
**Symptom**: Payment has different WorkspaceId than order
**Cause**: Old stored procedure using `NEWID()`
**Solution**: Redeploy updated stored procedure (Step 1)

### Issue 3: $89.98 instead of $90.00
**Symptom**: Precision errors in remaining amount
**Cause**: Insufficient precision in ratio calculation
**Solution**: Already fixed with `DECIMAL(18,10)` + `ROUND()`

### Issue 4: Payment Method Shows Incorrect Method in Notes
**Symptom**: Order notes show wrong payment method
**Cause**: Old stored procedure hardcoded note
**Solution**: ✅ Already fixed - now uses `@PaymentMethod` parameter (shows "DEB")

## 📊 Success Criteria

✅ Payment inserted with WorkspaceId matching order
✅ Payment amount preserved (not zeroed to $0.00)
✅ Order total reduced by exact payment amount
✅ No precision errors (exact $90.00, not $89.98)
✅ Payment archived correctly with correct amount
✅ Shift report shows both Avoqado and POS payments
✅ Payment method displayed correctly in notes

## 🎯 Summary

**All fixes are in `scripts/sql/01-COMPLETE-INSTALL.sql`**:
- ✅ WorkspaceId: Use order's WorkspaceId
- ✅ Payment Method: Use parameter not hardcoded
- ✅ Precision: DECIMAL(18,10) + ROUND()
- ✅ Tax: ROUND calculations

**Backend Change Applied**:
- ✅ Backend now uses: `"posPaymentMethodId": "DEB"`
- Change made in: `payment.tpv.service.ts:1101`

**Why DEB**:
- ACASH/AEF = tipo=1 (CASH) → Gets recalculated to $0.00 ❌
- DEB = tipo=2 (CARD) → NOT recalculated ✅
- Native payment method, no custom ACARD needed

**Deploy & Test**:
1. Deploy SQL script
2. ✅ Backend already uses DEB
3. Test complete payment flow
4. Verify shift report

See `PAYMENT-METHOD-FIX.md` for detailed root cause analysis.
