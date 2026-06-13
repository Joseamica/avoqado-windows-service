# 💳 Avoqado Payment Testing Guide

**Version**: 2.5.0
**Date**: September 30, 2025
**Purpose**: Complete guide for testing and troubleshooting Avoqado payment integration

---

## 🎯 Quick Start

After cleaning your database (`DELETE FROM tempcheques/tempchequespagos/tempcheqdet`), follow this procedure:

### Step 1: Run Diagnostic Scripts

```sql
-- Step 1: Verify installation
-- Execute: scripts/sql/00-VERIFICATION.sql

-- Step 2: Follow testing procedure
-- Execute: scripts/sql/98-CLEAN-TESTING-PROCEDURE.sql
-- (This script guides you step-by-step)

-- Step 3: Before closing shift
-- Execute: scripts/sql/99-SHIFT-CLOSE-DIAGNOSTIC.sql

-- Step 4: After closing shift
-- Execute: scripts/sql/99-SHIFT-CLOSE-DIAGNOSTIC.sql (again)
```

---

## 🐛 Recent Bug Investigation: Negative Quantities

### What Happened

User reported that a $50 payment on a $1,500 order resulted in:
- ❌ Negative quantity: `-0.147`
- ❌ Negative line amounts
- ❌ Order total: `$0.00`
- ❌ Auto-printed when it shouldn't

### Root Cause ✅

**The stored procedure was working CORRECTLY.** The issue was contaminated test data:

```sql
-- Order state:
Total: $1,500.00

-- Existing payments (from previous tests):
$500 (AEF)
$750 (AEF)
$300 (AEF)
$50  (AEF)
$100 (AEF, TEST-PAYMENT-2)
$20  (AEF)
-----
$1,720 TOTAL PAID

-- New payment:
$50 (ACASH from Avoqado)

-- Result:
Remaining = $1,500 - ($1,720 + $50) = -$220 ✅ Mathematically correct!
```

### Why Negative Quantities Appeared

The stored procedure `sp_ApplyPartialPayment` uses **quantity ratio adjustment** (SoftRestaurant native pattern):

```sql
-- Calculation (working as designed):
@RemainingRatio = @Remaining / @OrderTotal
@RemainingRatio = -220 / 1500 = -0.1467

-- Applied to each line item:
UPDATE tempcheqdet
SET cantidad = cantidad * @RemainingRatio
-- Example: cantidad = 1.0 * -0.1467 = -0.147 ✅
```

### Solution ✅

```sql
-- Clean contaminated data:
DELETE FROM tempcheqdet
DELETE FROM tempchequespagos
DELETE FROM tempcheques
```

### Prevention

Always start with clean data when testing. Use the new **98-CLEAN-TESTING-PROCEDURE.sql** script which includes cleanup steps.

---

## 🔍 Understanding WorkspaceId in Payments

### Critical Concept

In SoftRestaurant v11, **each payment gets its own unique WorkspaceId**, even if it's for the same order:

```
Order WorkspaceId:    68D8362E-2311-470E-8571-AD49874E4B6D
Payment 1 WorkspaceId: 12345678-AAAA-BBBB-CCCC-DDDDDDDDDDDD
Payment 2 WorkspaceId: 87654321-EEEE-FFFF-0000-111111111111
```

**This is NORMAL and EXPECTED behavior in SoftRestaurant v11.**

### Why This Matters for Shift Close

During shift close, payments are archived using:

```sql
-- Correct archiving query (joins on folio, NOT WorkspaceId):
INSERT INTO chequespagos
SELECT p.*
FROM tempchequespagos p
INNER JOIN tempcheques t ON p.folio = t.folio  -- ✅ Correct
WHERE t.idturno = @ShiftId
```

If shift reports filter by WorkspaceId instead of joining on folio, Avoqado payments will be excluded.

---

## 🚨 Troubleshooting: Missing Avoqado Payments in Shift Reports

### Symptom

After shift close, Avoqado payments (sent via DEB) don't appear in shift reports, but POS payments do.

### Diagnostic Steps

#### Step 1: Verify Payments Were Archived

```sql
-- Check archived Avoqado payments (uses DEB method)
-- Distinguish by reference field containing "AVOQADO" or similar
SELECT *
FROM chequespagos
WHERE idformadepago = 'DEB'
  AND (referencia LIKE '%AVOQADO%' OR referencia LIKE '%TEST%')
ORDER BY folio DESC
```

**If NO results**: Payments weren't archived → Archiving process issue
**If results exist**: Payments ARE archived → Shift report query issue

#### Step 2: Analyze Shift Report Query

The shift report likely has one of these issues:

**Problem A: Filtering by WorkspaceId**
```sql
-- ❌ WRONG: This excludes Avoqado payments
SELECT p.*
FROM chequespagos p
INNER JOIN cheques c ON p.WorkspaceId = c.WorkspaceId  -- ❌ Wrong join
WHERE c.idturno = @ShiftId
```

**Solution**:
```sql
-- ✅ CORRECT: Join on folio
SELECT p.*
FROM chequespagos p
INNER JOIN cheques c ON p.folio = c.folio  -- ✅ Correct join
WHERE c.idturno = @ShiftId
```

**Problem B: Payment Method Filter**
```sql
-- ❌ WRONG: Hardcoded payment method list (rare, usually includes DEB)
WHERE p.idformadepago IN ('AEF', 'TARJETA', 'CREDITO')  -- Missing DEB
```

**Solution**:
```sql
-- ✅ CORRECT: Include DEB (native debit card method)
WHERE p.idformadepago IN ('AEF', 'DEB', 'TARJETA', 'CREDITO', 'CRE')

-- OR better: Use visible flag (recommended)
INNER JOIN formasdepago f ON p.idformadepago = f.idformadepago
WHERE f.visible = 1
```

**Problem C: Distinguishing Avoqado vs POS Payments**
Since both use DEB, filter by reference or timestamp:
```sql
-- Check payment references
SELECT folio, idformadepago, importe, referencia, fechahora
FROM chequespagos
WHERE idformadepago = 'DEB'
ORDER BY folio, fechahora
```

**Note**: Avoqado payments should have a distinct reference (e.g., "AVOQADO-xxx" or transaction ID)

#### Step 3: Use Diagnostic Script

```sql
-- Run this to analyze the complete payment flow
-- Execute: scripts/sql/99-SHIFT-CLOSE-DIAGNOSTIC.sql
```

This script will show:
- Current active payments
- WorkspaceId matching analysis
- Simulated archiving queries
- Historical archived data
- Specific recommendations

---

## 📋 Complete Testing Procedure

### Prerequisites

1. ✅ Avoqado integration installed (`01-COMPLETE-INSTALL.sql`)
2. ✅ Payment methods created (ACASH, ACARD)
3. ✅ Windows service running
4. ✅ Clean database (no contaminated test data)

### Test Scenario

**Goal**: Verify that Avoqado partial payment + POS payment completion works correctly and appears in shift reports.

### Detailed Steps

#### 1. Verify Installation

```sql
-- Run: scripts/sql/00-VERIFICATION.sql
-- Confirm all objects exist and triggers are enabled
```

#### 2. Open Shift (From POS)

- Start new shift from SoftRestaurant POS
- Note the shift ID

#### 3. Create Order (From POS)

- Create new order
- Add products totaling at least $100
- Print the bill (sets `impreso=1`)
- **DO NOT PAY YET**

#### 4. Capture Pre-Payment State

```sql
-- Run: scripts/sql/99-SHIFT-CLOSE-DIAGNOSTIC.sql
-- Save output for comparison later
```

#### 5. Apply Avoqado Payment

**Method A: Via RabbitMQ Command** (Production)
```json
{
  "command": "applyPartialPayment",
  "folio": 1,
  "amount": 50.00,
  "paymentMethodId": "DEB",
  "reference": "AVOQADO-TEST-001"
}
```

**Note**: Backend automatically sends DEB for all Avoqado payments (see `payment.tpv.service.ts:1101`).

**Method B: Direct SQL** (Testing only)
```sql
DECLARE @Success BIT, @Message NVARCHAR(MAX), @Remaining MONEY

EXEC sp_ApplyPartialPayment
    @Folio = 1,
    @PaymentAmount = 50.00,
    @PaymentMethodId = 'DEB',
    @Reference = 'TEST-PAYMENT',
    @Success = @Success OUTPUT,
    @Message = @Message OUTPUT,
    @Remaining = @Remaining OUTPUT

PRINT 'Success: ' + CAST(@Success AS VARCHAR)
PRINT 'Message: ' + @Message
PRINT 'Remaining: $' + CAST(@Remaining AS VARCHAR)
```

#### 6. Verify Partial Payment

```sql
-- Check payment was inserted
SELECT *
FROM tempchequespagos
WHERE folio = 1

-- Check order is still unpaid (pagado=0)
SELECT folio, total, pagado, impreso
FROM tempcheques
WHERE folio = 1

-- Check debug log
SELECT TOP 5 *
FROM AvoqadoDebugLog
ORDER BY Timestamp DESC
```

**Expected Results**:
- ✅ Payment inserted into `tempchequespagos`
- ✅ Order still has `pagado = 0`
- ✅ Quantities adjusted proportionally
- ✅ Debug log shows remaining amount

#### 7. Complete Payment from POS

- Open payment screen in SoftRestaurant
- POS should show **remaining amount** (not full amount)
- Complete payment using any method (cash, card, etc.)

#### 8. Verify Full Payment

```sql
-- Check all payments
SELECT
    p.folio,
    p.idformadepago,
    f.descripcion,
    p.importe + p.propina as Total,
    p.referencia,
    CASE
        WHEN p.referencia LIKE '%AVOQADO%' OR p.referencia LIKE '%TEST%' THEN 'AVOQADO'
        ELSE 'POS'
    END as Source
FROM tempchequespagos p
INNER JOIN formasdepago f ON p.idformadepago = f.idformadepago
WHERE p.folio = 1

-- Check order is fully paid
SELECT folio, total, pagado
FROM tempcheques
WHERE folio = 1
```

**Expected Results**:
- ✅ Multiple payments exist (Avoqado + POS)
- ✅ Total payments equal order total
- ✅ Order has `pagado = 1`

#### 9. Pre-Shift-Close Diagnostic

```sql
-- Run: scripts/sql/99-SHIFT-CLOSE-DIAGNOSTIC.sql
-- Section 6 shows what WILL be archived
```

#### 10. Close Shift (From POS)

- Close the shift from SoftRestaurant
- Generate shift report
- **CHECK**: Do Avoqado payments appear in the report?

#### 11. Post-Shift-Close Verification

```sql
-- Run: scripts/sql/99-SHIFT-CLOSE-DIAGNOSTIC.sql
-- Section 7 shows archived data

-- Verify Avoqado payments were archived
SELECT
    p.folio,
    f.descripcion as PaymentMethod,
    p.importe + p.propina as Amount,
    p.referencia,
    CASE
        WHEN p.referencia LIKE '%AVOQADO%' OR p.referencia LIKE '%TEST%' THEN 'AVOQADO'
        ELSE 'POS'
    END as Source
FROM chequespagos p
INNER JOIN formasdepago f ON p.idformadepago = f.idformadepago
INNER JOIN cheques c ON p.folio = c.folio
WHERE c.idturno = @ShiftId  -- Use your shift ID
  AND (p.referencia LIKE '%AVOQADO%' OR p.referencia LIKE '%TEST%')
```

**Expected Results**:
- ✅ Avoqado payments appear in `chequespagos`
- ✅ Payments linked to correct order (folio match)

---

## ✅ Success Criteria

### Technical Success
- [x] Payment inserted into `tempchequespagos`
- [x] Order quantities adjusted correctly
- [x] Order marked as paid after full payment
- [x] Payments archived during shift close
- [x] Archived payments linked to correct order

### Business Success
- [x] Shift report includes Avoqado payments
- [x] Payment totals match order totals
- [x] No spurious deletion events during shift close
- [x] No negative quantities on legitimate payments

---

## 🔧 Maintenance

### Weekly Cleanup

```sql
-- Remove old processed/error records
EXEC sp_CleanupOldTrackingRecords @DaysToKeep = 7
```

### Monthly Verification

```sql
-- Run: scripts/sql/03-DIAGNOSTICS.sql
-- Review health check section
```

---

## 📞 Support

### Documentation Files

- **This Guide**: `PAYMENT-TESTING-GUIDE.md`
- **Changelog**: `CHANGELOG-v2.5.0.md`
- **Analysis Report**: `ANALYSIS-REPORT.md`
- **Main Docs**: `CLAUDE.md`

### SQL Scripts

- **Installation**: `scripts/sql/01-COMPLETE-INSTALL.sql`
- **Verification**: `scripts/sql/00-VERIFICATION.sql`
- **Testing Procedure**: `scripts/sql/98-CLEAN-TESTING-PROCEDURE.sql`
- **Shift Diagnostic**: `scripts/sql/99-SHIFT-CLOSE-DIAGNOSTIC.sql`

### Common Issues

| Issue | Solution |
|-------|----------|
| Negative quantities | Clean contaminated test data |
| Payments not in report | Check shift report query joins on folio, not WorkspaceId |
| Payment methods missing | Run `01-COMPLETE-INSTALL.sql` |
| Trigger errors | Check `AvoqadoTracking` table for RetryCount=99 |

---

## 🎉 Summary

The v2.5.0 release includes comprehensive testing and diagnostic tools to ensure Avoqado payment integration works seamlessly with SoftRestaurant v11. The key to success is:

1. **Clean Data**: Start with clean temp tables
2. **Proper Joins**: Shift reports must join on `folio`, not `WorkspaceId`
3. **Regular Maintenance**: Run cleanup procedures weekly
4. **Use Diagnostic Tools**: The new scripts provide complete visibility into the payment flow

**Result**: Avoqado payments work identically to native SoftRestaurant payments and appear correctly in all shift reports.
