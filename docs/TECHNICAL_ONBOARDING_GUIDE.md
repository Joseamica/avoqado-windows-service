# Avoqado Technical Onboarding Guide for SoftRestaurant Clients

## Table of Contents
1. [Pre-Onboarding Checklist](#pre-onboarding-checklist)
2. [Phase 1: Environment Assessment](#phase-1-environment-assessment)
3. [Phase 2: Database Preparation](#phase-2-database-preparation)
4. [Phase 3: Avoqado Integration Installation](#phase-3-avoqado-integration-installation)
5. [Phase 4: Windows Service Setup](#phase-4-windows-service-setup)
6. [Phase 5: Configuration & Testing](#phase-5-configuration--testing)
7. [Phase 6: Go-Live](#phase-6-go-live)
8. [Troubleshooting Common Issues](#troubleshooting-common-issues)

---

## Pre-Onboarding Checklist

### Required Information from Client
- [ ] Restaurant/Venue Name
- [ ] Number of POS terminals
- [ ] SoftRestaurant Version (10, 11, or 12)
- [ ] SQL Server details (version, instance name)
- [ ] Network topology (single location vs multi-location)
- [ ] Current shift patterns (24hr, split shifts, etc.)
- [ ] Payment methods used
- [ ] Existing integrations (if any)

### Technical Requirements Verification
```powershell
# Run on client's server
sqlcmd -S localhost\NATIONALSOFT -Q "SELECT @@VERSION"
sqlcmd -S localhost\NATIONALSOFT -Q "SELECT DB_NAME() as CurrentDB"
```

---

## Phase 1: Environment Assessment

### 1.1 Connect to Client Database
```bash
# For remote support
sqlcmd -S "tcp:CLIENT_IP,PORT" -U sa -P PASSWORD -d DATABASE_NAME

# Verify SQL Server version (MUST be 2014 or higher)
sqlcmd -Q "SELECT @@VERSION, SERVERPROPERTY('ProductVersion') as Version"
```

### 1.2 Detect SoftRestaurant Version
```sql
-- Check version in database
SELECT versiondb FROM parametros2

-- Check for WorkspaceId support (v11+ indicator)
SELECT COL_LENGTH('tempcheques', 'WorkspaceId') as HasWorkspaceId
-- Returns: 16 for v11+, NULL for v10
```

### 1.3 Assess Database Health
```sql
-- Check active orders
SELECT COUNT(*) as ActiveOrders FROM tempcheques WHERE pagado = 0

-- Check current shift
SELECT idturno, apertura, cierre,
       CASE WHEN cierre IS NULL THEN 'OPEN' ELSE 'CLOSED' END as Status
FROM turnos
ORDER BY idturno DESC

-- Check database size
EXEC sp_spaceused

-- Check for existing Avoqado objects
SELECT type_desc, name
FROM sys.objects
WHERE name LIKE '%Avoqado%'
```

### 1.4 Document Current Configuration
```sql
-- Payment methods
SELECT * FROM formasdepago

-- Invoice series (if using electronic invoicing)
SELECT DISTINCT serie FROM cheques WHERE serie IS NOT NULL

-- Multi-tenant check (v11+)
SELECT COUNT(DISTINCT WorkspaceId) as TenantCount
FROM tempcheques
WHERE WorkspaceId IS NOT NULL
```

---

## Phase 2: Database Preparation

### 2.1 Create Database Backup
```sql
-- CRITICAL: Always backup before changes
BACKUP DATABASE [DATABASE_NAME]
TO DISK = 'C:\Backups\DATABASE_NAME_PRE_AVOQADO.bak'
WITH FORMAT, INIT, COMPRESSION
```

### 2.2 Clean Previous Installations (if any)
```bash
# Run cleanup script
sqlcmd -S localhost\NATIONALSOFT -d DATABASE_NAME -i "scripts\sql\02-Complete-Cleanup.sql"
```

### 2.3 Fix Common Issues

#### OLE DB Provider Error (as shown in screenshot)
```sql
-- Fix OLE DB Provider for SQL Server issues
-- This error typically occurs with NULL value handling

-- Enable advanced options
EXEC sp_configure 'show advanced options', 1
RECONFIGURE

-- Configure OLE DB
EXEC sp_configure 'Ad Hoc Distributed Queries', 1
RECONFIGURE

-- If using 32-bit SQL Server with 64-bit provider
-- Check provider installation
SELECT * FROM sys.dm_exec_sessions WHERE is_user_process = 1
```

---

## Phase 3: Avoqado Integration Installation

### 3.1 Run Installation Script
```bash
# Install Avoqado integration
sqlcmd -S localhost\NATIONALSOFT -d DATABASE_NAME -U sa -P PASSWORD -i "scripts\sql\03-Unified-Installation.sql"
```

### 3.2 Verify Installation
```sql
-- Check all components installed
SELECT
    (SELECT COUNT(*) FROM sys.tables WHERE name LIKE 'Avoqado%') as Tables,
    (SELECT COUNT(*) FROM sys.triggers WHERE name LIKE 'Trg_Avoqado%') as Triggers,
    (SELECT COUNT(*) FROM sys.procedures WHERE name LIKE 'sp_%Avoqado%' OR name = 'sp_ApplyPartialPayment') as Procedures,
    (SELECT COUNT(*) FROM sys.objects WHERE type IN ('FN','IF','TF') AND name LIKE 'fn_%Avoqado%') as Functions
```

### 3.3 Configure Venue ID
```sql
-- CRITICAL: Set unique venue ID for this location
UPDATE AvoqadoConfig
SET VenueId = 'VENUE_GUID_HERE',
    IsEnabled = 1

-- Verify configuration
SELECT * FROM AvoqadoConfig
```

---

## Phase 4: Windows Service Setup

### 4.1 Install Windows Service
```powershell
# Run as Administrator
cd C:\AvoqadoSync

# Install service
npm run svc:install

# Verify installation
Get-Service -Name "AvoqadoSyncService"
```

### 4.2 Configure Service
```json
// C:\ProgramData\AvoqadoSync\config.json
{
  "venueId": "VENUE_GUID_HERE",
  "posType": "softrestaurant",
  "posVersion": "11",
  "rabbitMqUrl": "amqp://user:pass@rabbitmq.avoqado.com:5672",
  "sqlConfig": {
    "server": "localhost\\NATIONALSOFT",
    "database": "DATABASE_NAME",
    "user": "sa",
    "password": "PASSWORD",
    "options": {
      "encrypt": false,
      "trustServerCertificate": true,
      "enableArithAbort": true
    }
  }
}
```

### 4.3 Start Service
```powershell
# Start the service
Start-Service -Name "AvoqadoSyncService"

# Check logs
Get-Content "C:\ProgramData\AvoqadoSync\logs\combined.log" -Tail 50
```

---

## Phase 5: Configuration & Testing

### 5.1 Test Order Creation
```sql
-- Create test order
EXEC sp_CreateEmptyOrder @Mesa = 'TEST01', @IdMesero = '01'

-- Verify tracking
SELECT TOP 5 * FROM AvoqadoTracking ORDER BY Timestamp DESC
```

### 5.2 Test Partial Payments
```sql
-- Test partial payment procedure
DECLARE @Success BIT, @Message NVARCHAR(500), @Remaining MONEY

EXEC sp_ApplyPartialPayment
    @Folio = 1,
    @PaymentAmount = 50,
    @PaymentMethod = '01',
    @Success = @Success OUTPUT,
    @Message = @Message OUTPUT,
    @Remaining = @Remaining OUTPUT

SELECT @Success as Success, @Message as Message, @Remaining as Remaining
```

### 5.3 Verify Real-time Sync
```powershell
# Monitor Windows Service
Get-Content "C:\ProgramData\AvoqadoSync\logs\combined.log" -Wait

# Check RabbitMQ messages being sent
# Look for: "Published event: pos.softrestaurant.order.created"
```

### 5.4 Test Shift Close
```sql
-- Simulate shift close (TEST ENVIRONMENT ONLY)
UPDATE turnos SET cierre = GETDATE()
WHERE idturno = (SELECT MAX(idturno) FROM turnos WHERE cierre IS NULL)

-- Verify no false deletions in tracking
SELECT * FROM AvoqadoTracking
WHERE Operation = 'DELETE'
AND Timestamp > DATEADD(MINUTE, -5, GETUTCDATE())
```

---

## Phase 6: Go-Live

### 6.1 Final Checklist
- [ ] All test cases passed
- [ ] Windows Service running without errors
- [ ] RabbitMQ connection stable
- [ ] Heartbeat messages being sent (every 60 seconds)
- [ ] No performance degradation on POS
- [ ] Backup restoration procedure tested

### 6.2 Production Cutover
```sql
-- Enable production mode
UPDATE AvoqadoConfig
SET IsProduction = 1,
    DebugMode = 0

-- Clear test data
DELETE FROM AvoqadoTracking WHERE ProcessedAt IS NULL
```

### 6.3 Monitor First Shift
```sql
-- Real-time monitoring query
SELECT
    EntityType,
    Operation,
    COUNT(*) as Count,
    MAX(Timestamp) as LastEvent
FROM AvoqadoTracking
WHERE Timestamp > DATEADD(HOUR, -1, GETUTCDATE())
GROUP BY EntityType, Operation
ORDER BY MAX(Timestamp) DESC
```

---

## Troubleshooting Common Issues

### Issue 1: OLE DB Provider Error (As in Screenshot)
```sql
-- The error "Cannot insert NULL value" indicates missing required fields

-- Check for NULL values in critical fields
SELECT * FROM tempcheques
WHERE folio IS NULL
   OR idturno IS NULL
   OR total IS NULL

-- Fix orphaned records
DELETE FROM tempcheques WHERE folio IS NULL

-- Ensure triggers handle NULLs properly
-- Already handled in our v3.0 triggers
```

### Issue 2: Windows Service Not Starting
```powershell
# Check Event Viewer
Get-EventLog -LogName Application -Source "AvoqadoSyncService" -Newest 10

# Test database connection
sqlcmd -S localhost\NATIONALSOFT -U sa -P PASSWORD -Q "SELECT 1"

# Verify config file
Test-Path "C:\ProgramData\AvoqadoSync\config.json"
```

### Issue 3: Messages Not Reaching RabbitMQ
```powershell
# Test RabbitMQ connection
telnet rabbitmq.avoqado.com 5672

# Check firewall
netsh advfirewall firewall show rule name=all | findstr 5672

# Add firewall rule if needed
netsh advfirewall firewall add rule name="RabbitMQ" dir=out action=allow protocol=TCP remoteport=5672
```

### Issue 4: Duplicate Orders
```sql
-- Check for duplicate Entity IDs
SELECT EntityId, COUNT(*) as DupeCount
FROM AvoqadoTracking
WHERE EntityType = 'order'
GROUP BY EntityId
HAVING COUNT(*) > 1

-- Fix by ensuring unique constraint
ALTER TABLE AvoqadoTracking
ADD CONSTRAINT UQ_EntityTracking UNIQUE(EntityType, EntityId, Operation)
```

### Issue 5: Performance Degradation
```sql
-- Check index fragmentation
SELECT
    OBJECT_NAME(object_id) as TableName,
    index_id,
    avg_fragmentation_in_percent
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'DETAILED')
WHERE avg_fragmentation_in_percent > 30

-- Rebuild indexes if needed
ALTER INDEX ALL ON AvoqadoTracking REBUILD
ALTER INDEX ALL ON tempcheques REBUILD
```

---

## Support Contacts

### During Onboarding
- Technical Issues: tech-support@avoqado.com
- Integration Questions: integrations@avoqado.com
- Emergency Hotline: +1-XXX-XXX-XXXX

### Post Go-Live
- Monitor dashboard: https://dashboard.avoqado.com
- Support ticket system: https://support.avoqado.com
- Documentation: https://docs.avoqado.com

---

## Appendix: Quick SQL Reference

### Most Used Queries During Onboarding
```sql
-- 1. Check current status
SELECT * FROM AvoqadoConfig

-- 2. Recent tracking activity
SELECT TOP 10 * FROM AvoqadoTracking ORDER BY Timestamp DESC

-- 3. Pending changes
SELECT COUNT(*) FROM AvoqadoTracking WHERE ProcessedAt IS NULL

-- 4. Service heartbeat check
SELECT MAX(Timestamp) as LastHeartbeat
FROM AvoqadoTracking
WHERE EntityType = 'heartbeat'

-- 5. Emergency disable
UPDATE AvoqadoConfig SET IsEnabled = 0
```

---

**Document Version**: 1.0.0
**Last Updated**: 2025-09-23
**Compatibility**: SoftRestaurant v10, v11, v12 with SQL Server 2014+