# Avoqado Client Onboarding - SQL Installation Checklist

## Prerequisites
- SQL Server 2014 or higher
- SA or equivalent permissions
- SoftRestaurant v10, v11, or v12 installed
- Database backup completed

## Installation Sequence

### Step 1: Initial Verification (Optional)
```sql
-- Run 00-Verificacion.sql
-- Quick check to see current state
```
**Purpose**: Verify if any Avoqado objects already exist

### Step 2: Diagnostic (Optional)
```sql
-- Run 01-Diagnostico.sql
-- Comprehensive system analysis
```
**Purpose**: Document current system state before changes

### Step 3: Main Installation (REQUIRED)
```sql
-- Run 02-Unified-Installation.sql
-- This is the main installation script
```
**Creates**:
- ✅ AvoqadoConfig table (configuration)
- ✅ AvoqadoTracking table (change tracking)
- ✅ AvoqadoCommands table (command queue)
- ✅ Entity ID functions
- ✅ Database triggers (Orders, OrderItems, Payments, Shifts)
- ✅ Stored procedures (sp_GetPendingChanges, sp_MarkChangesProcessed, sp_ApplyPartialPayment)

### Step 4: Fix DELETE Operations (REQUIRED)
```sql
-- Run 03-Fix-NULL-EntityId-DELETE.sql
-- Critical fix for DELETE operations
```
**Purpose**: Prevents "NULL EntityId" errors when deleting orders from POS
**Note**: This MUST be run after 02-Unified-Installation.sql

### Step 5: Native Payment Flow (REQUIRED)
```sql
-- Run 04-Native-Payment-Flow.sql
-- Enhanced payment processing
```
**Purpose**: Implements native SoftRestaurant payment behavior for full payments
**Features**:
- Auto-printing of unpaid orders
- Proper payment type mapping
- Native field updates (efectivo, tarjeta, etc.)

### Step 6: Verification (Optional)
```sql
-- Run 05-Pruebas.sql
-- Test the installation
```
**Purpose**: Verify all components are working correctly

## Connection Examples

### For Production (localhost)
```bash
sqlcmd -S "localhost\NATIONALSOFT" -U sa -P "PASSWORD" -d DATABASE_NAME -i "SCRIPT.sql"
```

### For Testing (external database)
```bash
sqlcmd -S "100.80.118.68,49759" -U sa -P "National09" -d avov2 -i "SCRIPT.sql"
```

## Post-Installation Checklist

- [ ] Verify AvoqadoConfig has correct InstanceId
- [ ] Check triggers are active on tempcheques, tempcheqdet, turnos
- [ ] Test order creation generates tracking records
- [ ] Test payment processing works correctly
- [ ] Configure Windows service with correct database connection
- [ ] Start Windows service and verify heartbeats

## Script Descriptions

| Script | Required | Purpose |
|--------|----------|---------|
| 00-Verificacion.sql | No | Quick status check |
| 01-Diagnostico.sql | No | Detailed diagnostic |
| **02-Unified-Installation.sql** | **YES** | **Main installation** |
| **03-Fix-NULL-EntityId-DELETE.sql** | **YES** | **Critical DELETE fix** |
| **04-Native-Payment-Flow.sql** | **YES** | **Native payment flow** |
| 05-Pruebas.sql | No | Testing verification |

## Important Notes

1. **Always backup the database before installation**
2. **Run scripts in order: 02 → 03 → 04**
3. **Never skip script 03 - it fixes a critical issue**
4. **Script 04 replaces the sp_ApplyPartialPayment from script 02**
5. **For production, use localhost\NATIONALSOFT**
6. **For testing, use external database with port**

## Support

If you encounter issues:
1. Run 01-Diagnostico.sql and save output
2. Check Windows Event Log for service errors
3. Verify SQL Server version compatibility
4. Ensure proper permissions on database