# Avoqado SQL Scripts - ESSENTIAL ONLY

## ✅ Your System is ALREADY CONFIGURED and WORKING!

These scripts are organized for different scenarios:

## 🚨 00-FIX-PARTIAL-PAYMENT-LOGIC.sql
**Purpose**: CRITICAL FIX - Ensures ALL payments are recorded in shift reports
**When to use**: If Avoqado payments are missing from shift reports
**What it does**: Fixes sp_ApplyPartialPayment to insert payment records for both partial AND full payments
**Impact**: Without this fix, partial payments only update totals but don't create payment records

## 🔧 00-FIX-ACARD-SUBTIPO.sql
**Purpose**: Fix ACARD payment method missing subtipo field
**When to use**: If you get "El campo SUBTIPO no acepta valores NULL" error when closing shifts
**What it does**: Sets subtipo=0 and tipoTarjetaBancaria=1 for ACARD payment method

## 📊 00-DIAGNOSTICS.sql (formerly 03-DIAGNOSTICS.sql)
**Purpose**: Check system health WITHOUT making changes
**When to use**: Anytime you want to verify the system status
**Safe**: YES - Read-only, makes NO changes

## 🔧 01-COMPLETE-INSTALLATION.sql
**Purpose**: Safe installation that PRESERVES your current working structure
**When to use**: ONLY if tables/procedures are missing
**What it does**:
- Creates AvoqadoTracking with ProcessedAt/RetryCount (as your Producer requires)
- Creates sp_GetPendingChanges that returns RetryCount
- Preserves existing triggers if they're working

## 🔨 02-FIX-TRIGGERS.sql
**Purpose**: Fix ONLY the triggers to include RetryCount
**When to use**: If triggers are missing RetryCount field
**What it does**: Updates all 4 triggers to include RetryCount = 0

## 💳 03-FIX-PAYMENT-PROCEDURE.sql
**Purpose**: Creates sp_ApplyPartialPayment that adapter expects
**When to use**: If you get "sp_ApplyPartialPayment not found" error
**What it does**: Creates the stored procedure for Avoqado payments

## 🆕 04-ONBOARD-NEW-CLIENT.sql
**Purpose**: Complete installation for NEW clients
**When to use**: Setting up Avoqado on a fresh SoftRestaurant database
**What it does**: Everything needed for a new installation

## ⚠️ IMPORTANT NOTES

1. **Your current system uses**:
   - ProcessedAt (datetime2) NOT Processed (bit)
   - RetryCount (int) - REQUIRED by Producer.ts
   - ACASH payment method already exists

2. **DO NOT RUN installation scripts unless something is broken!**
   Your system is already working correctly.

3. **For debugging**, always run 00-DIAGNOSTICS.sql first

4. **Connection for testing**:
   ```
   sqlcmd -S "tcp:100.80.118.68,49759" -d avov2 -U sa -P National09
   ```