# 📚 Complete SQL Scripts Guide

## 🎯 For Your Specific Issue

You deleted `tempcheqdet` records and got:
```
[OrderItem Processor] EntityId v11 inválido: DA1F7C3E-93BA-4D2F-B1A4-6E02B7778FD2:0:1:1
```

**Fix:**
```bash
sqlcmd -S "tcp:100.80.118.68,49759" -d avov2 -U sa -P National09 -i "98-FIX-INVALID-ENTITY-IDS.sql"
```

This removes tracking records with invalid EntityId format.

---

## 📋 All Available Scripts

### 🔧 **Maintenance Scripts**

| Script | When to Use | What It Does |
|--------|-------------|--------------|
| `98-FIX-INVALID-ENTITY-IDS.sql` | EntityId validation errors | Removes v10 format IDs in v11 system |
| `99-RESET-TRACKING.sql` | Service stuck/not processing | Marks all pending as processed |
| `99-FIX-TRIGGER-ERRORS.sql` | 🚨 POS/Avoqado out of sync | Reviews and fixes trigger errors (RetryCount=99) |
| `00-CLEANUP-ALL.sql` | Start completely fresh | Removes ALL Avoqado objects |

### 📊 **Monitoring Scripts**

| Script | When to Use | What It Shows |
|--------|-------------|---------------|
| `00-VERIFICATION.sql` | After install/changes | All required objects exist |
| `02-TESTING.sql` | Test functionality | Procedures work correctly |
| `03-DIAGNOSTICS.sql` | Daily health check | Full system status |

### 🚀 **Installation Scripts**

| Script | When to Use | What It Does |
|--------|-------------|--------------|
| `[deprecated]-02-Unified-Installation.sql` | Fresh install | Complete base installation |
| `[deprecated]-03-Fix-NULL-EntityId-DELETE.sql` | After base install | Fixes NULL EntityId errors |
| `06-FIX-SQL2014-COMPATIBILITY.sql` | STRING_SPLIT errors | SQL Server 2014 compatibility |
| `01-COMPLETE-INSTALL.sql` | Fill in missing pieces | Adds any missing components |

---

## 🚨 Quick Solutions

### Problem 1: Invalid EntityId Errors
```bash
sqlcmd -S "tcp:100.80.118.68,49759" -d avov2 -U sa -P National09 -i "98-FIX-INVALID-ENTITY-IDS.sql"
```

### Problem 2: Service Stuck
```bash
sqlcmd -S "tcp:100.80.118.68,49759" -d avov2 -U sa -P National09 -i "99-RESET-TRACKING.sql"
```

### Problem 3: Verify Everything Works
```bash
sqlcmd -S "tcp:100.80.118.68,49759" -d avov2 -U sa -P National09 -i "03-DIAGNOSTICS.sql"
```

### Problem 4: Payments Not Showing
The `sp_ApplyPartialPayment` needs to UPDATE order totals. Check if installed correctly with `00-VERIFICATION.sql`.

---

## 💡 Prevention Tips

1. **Don't manually delete POS records** - Use POS interface
2. **If you must delete**, run `98-FIX-INVALID-ENTITY-IDS.sql` after
3. **Run diagnostics daily** with `03-DIAGNOSTICS.sql`
4. **Keep service stopped** during database changes

---

## 📖 More Information

See `README-MAINTENANCE.md` for detailed maintenance procedures.