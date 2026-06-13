# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 🔴 CRITICAL — Ask which payment tier BEFORE building or changing anything

Avoqado is a tier-gated SaaS (**FREE · PRO · PREMIUM · ENTERPRISE**). This service is a sync bridge
(SoftRestaurant ↔ Avoqado) and rarely surfaces paid features directly — but if you add a sync
capability, command, or data flow that corresponds to a paid platform feature, **STOP and ask the
founder which tier it falls under** so the bridge doesn't quietly hand a higher-tier capability to a
lower-tier venue. A change shipped without a tier decision is unfinished.

- **Backend (authoritative):** `avoqado-server/src/services/access/basePlan.service.ts` +
  `avoqado-server/src/middlewares/checkFeatureAccess.middleware.ts`. Obligatory gating questions:
  `avoqado-server/.claude/rules/feature-gating.md`. PREMIUM-only codes today: `CFDI`, `INVENTORY_TRACKING`.
- **Enforcement status:** ✅ only **avoqado-web-dashboard** enforces tiers today; **avoqado-ios** and
  **avoqado-android** have NO tier gating yet. Treat tier codes like permissions: a name mismatch fails silently.

## Project Overview

This is a Windows service that acts as a real-time synchronization bridge between a local Point-of-Sale (POS) system and the central Avoqado
platform. It continuously monitors the POS database for changes to orders, items, and shifts, publishing these events to a RabbitMQ message
broker. It also listens for commands from the Avoqado platform and executes them on the local POS system, ensuring seamless bidirectional
data consistency.

**Key Features:**

- Real-time event publishing with debounced order updates
- Bidirectional sync (Producer polling + Commander execution)
- POS adapter architecture for different POS systems (currently SoftRestaurant v11)
- Windows service integration with health monitoring
- Resilient configuration management with automatic error recovery

## ⚠️ CRITICAL COMPATIBILITY REQUIREMENT

**🚨 HIGHLY IMPORTANT: ALL modifications, fixes, features, and changes MUST work with BOTH SoftRestaurant v10 AND v11 systems.**

This includes but is not limited to:

- **Database schema changes**: Must handle presence/absence of WorkspaceId columns
- **Entity ID generation**: Must support both v10 format (`{InstanceId}:{IdTurno}:{Folio}`) and v11 format (`{WorkspaceId}`)
- **Stored procedures and triggers**: Must be compatible with both versions' table structures
- **Producer logic**: Must detect version and handle appropriate Entity ID formats
- **Order processing**: Must handle both idturno-based (v10) and WorkspaceId-based (v11) operations
- **Shift management**: Must work with both version's shift identification systems
- **Payment processing**: Must accommodate both versions' payment table structures

**Version Detection**: Use `dbo.fn_GetSoftRestaurantVersion()` to detect version and implement version-specific logic when needed.

**Testing Requirement**: Every change must be verified against both v10 and v11 test databases before deployment.

## 🚨 CRITICAL SQL SCRIPT SYNCHRONIZATION RULE

**MANDATORY: When making ANY changes to SQL scripts, you MUST update ALL related scripts:**

1. **Main Installation**: `scripts/sql/01-COMPLETE-INSTALL.sql`
2. **Cleanup**: `scripts/sql/00-CLEANUP-ALL.sql` (add removal logic)
3. **Verification**: `scripts/sql/00-VERIFICATION.sql` (add existence checks)
4. **Testing**: `scripts/sql/02-TESTING.sql` (add functional tests)
5. **Diagnostics**: `scripts/sql/03-DIAGNOSTICS.sql` (add monitoring checks)

**Examples of changes requiring updates across all scripts:**

- Adding/removing payment methods (ACASH, ACARD)
- Adding/removing test products (AVOTEST)
- Adding/removing stored procedures
- Adding/removing triggers
- Adding/removing tables
- Changing table structures (ProcessedAt vs Processed)
- Adding/removing functions

**Process:**

1. Make change in installation script (`01-COMPLETE-INSTALL.sql`)
2. Add cleanup logic in `00-CLEANUP-ALL.sql`
3. Add verification check in `00-VERIFICATION.sql`
4. Add test in `02-TESTING.sql`
5. Add diagnostic monitoring in `03-DIAGNOSTICS.sql`

**Why this is critical:**

- Installation scripts create objects → other scripts must verify/test them
- Cleanup scripts must remove what installation creates
- Verification ensures installation worked correctly
- Testing validates functionality
- Diagnostics monitors health in production

**NO EXCEPTIONS**: This synchronization is NOT optional. All 5 scripts must stay in sync.

## Common Commands

### Development & Build

- `npm run dev` - Run with hot-reload using nodemon
- `npm run build` - Compile TypeScript to JavaScript
- `npm start` - Run the compiled application

### Code Quality

- `npm run format` - Format code with Prettier
- `npm run check-format` - Check code formatting

### SQL Monitoring & Profiling (IMPORTANT FOR CLAUDE)

- `npm run monitor` - Start real-time SQL Server query monitoring for the POS database

### Windows Service Management (requires admin privileges)

- `npm run svc:install` - Install as Windows service
- `npm run svc:uninstall` - Uninstall Windows service

### Packaging

- `npm run package` - Build and create AvoqadoSyncService.exe

### 🔍 SQL Server Real-Time Monitoring (CRITICAL FOR CLAUDE)

**IMPORTANT: Whenever analyzing POS behavior or debugging database issues, ALWAYS run the SQL monitor first to see what queries the POS is
executing.**

#### Starting the Monitor

```bash
# Start monitoring (run this FIRST before any POS testing)
npm run monitor
```

This connects to the remote SQL Server and shows:

- **Real-time queries** as they execute
- **Query statistics** (execution count, CPU time, duration)
- **Active connections** and their operations
- **Recent query history** with performance metrics

#### Monitor Configuration

The monitor automatically connects to:

- **Server**: `100.80.118.68:49759`
- **Database**: `avov2`
- **Credentials**: Already configured in the tool

#### What Claude Can See

When the monitor is running, Claude can observe:

1. **Order Creation**: `INSERT INTO tempcheques` with all fields
2. **Adding Items**: `INSERT INTO tempcheqdet` for each product
3. **Order Updates**: `UPDATE tempcheques` for modifications
4. **Printing Bills**: `UPDATE tempcheques SET impreso=1`
5. **Payments**: `INSERT INTO tempchequespagos` and `UPDATE tempcheques SET pagado=1`
6. **Shift Operations**: `INSERT/UPDATE turnos` for shift open/close
7. **Trigger Executions**: `Trg_Avoqado_*` triggers firing
8. **Stored Procedures**: `sp_GetPendingChanges` polling
9. **Transaction Patterns**: BEGIN TRAN, COMMIT, ROLLBACK sequences

#### Usage Workflow for Claude

1. **Before any POS testing**:

   ```bash
   npm run monitor  # Start this FIRST
   ```

2. **In another terminal**:

   ```bash
   npm run dev     # Start the Windows service
   ```

3. **Observe the monitor output** to see:
   - What queries the POS executes
   - How triggers respond
   - Performance bottlenecks
   - Transaction patterns

#### Monitor Output Format

```
🔍 SQL SERVER QUERY MONITOR
⏰ 1:47:25 p.m.
=====================================
✨ Active queries show here in real-time

📈 Recent Query Statistics:
=====================================
1. [Time] Exec:391 CPU:179ms
   SELECT TOP (@MaxResults) Id, EntityType...
```

#### Critical Use Cases

- **Debugging Integration**: See exactly what SQL the POS runs
- **Performance Analysis**: Identify slow queries and bottlenecks
- **Trigger Validation**: Verify Avoqado triggers are firing correctly
- **Transaction Monitoring**: Watch shift close sequences
- **Error Investigation**: Catch failed queries and deadlocks

**NOTE**: The monitor updates every 2 seconds. Press `Ctrl+C` to stop.

### Database Access & Debugging

**IMPORTANT Database Connection Strategy:**

- **PRODUCTION**: Always uses `localhost\NATIONALSOFT` (instance name, no port)
  - Configuration: `DB_SERVER=localhost`, `DB_INSTANCE=NATIONALSOFT`
- **DEVELOPMENT/TESTING**: Uses external database with port for active license testing
  - Configuration: `DB_SERVER=100.80.118.68,49759` (port overrides instance name)
- **The db.ts automatically handles both**: Detects if port is present and configures accordingly

**🔐 Recommended Method: Using sql.ps1 (Secure Credential Storage)**

The project includes `sql.ps1` - a PowerShell script that uses encrypted credentials stored locally. This is the **preferred method** for all SQL queries:

```bash
# Quick queries
powershell -File sql.ps1 "SELECT TOP 5 * FROM sys.tables"

# Run SQL script files
powershell -File sql.ps1 -f scripts/sql/00-VERIFICATION.sql

# Interactive SQL session
powershell -File sql.ps1
```

**Benefits:**
- ✅ No password in command line or history
- ✅ No permission prompts for repeated queries
- ✅ Credentials encrypted in `.sqlcred` file
- ✅ Works seamlessly from Git Bash and PowerShell
- ✅ Ideal for automation and Claude Code usage

**Setup (one-time):**
```powershell
powershell -Command '$pw = ConvertTo-SecureString "National09" -AsPlainText -Force; ConvertFrom-SecureString $pw | Out-File .sqlcred'
```

**Alternative Method: Direct sqlcmd (Not Recommended)**

For manual one-off queries, you can use sqlcmd directly, but this requires entering the password each time:

- `sqlcmd -S 'localhost\NATIONALSOFT' -U sa -P 'PASSWORD' -Q "QUERY"` - Production (instance name)
- `sqlcmd -S "tcp:100.80.118.68,49759" -U sa -P 'PASSWORD' -Q "QUERY"` - Testing (with port)

**CRITICAL SQL Server Connection Notes:**

- **Always quote the server name** with single quotes when using instance: `'localhost\NATIONALSOFT'`
- **Alternative approaches if connection fails:**
  - Escape backslash: `localhost\\NATIONALSOFT`
  - Force TCP: `"tcp:localhost\NATIONALSOFT"`
  - Use IP and port: `127.0.0.1,1433`
- **Available databases:** `softrestaurant10`, `softrestaurant11`
- **Version differences:**
  - v10: No WorkspaceId, No Avoqado integration
  - v11: Has WorkspaceId per entity, Has Avoqado integration tables

## SoftRestaurant POS System Architecture

### SQL Server Version

**CRITICAL:** This POS system runs on **Microsoft SQL Server 2014 Express Edition (32-bit)** - Version 12.0.4100.1 Intel X86. All database
operations, triggers, and stored procedures must be compatible with SQL Server 2014 syntax and features.

### Database Schema Overview

The SoftRestaurant v11 database contains **366 tables** with a sophisticated multi-tenant architecture:

- **366 total tables** including core business logic, configuration, and integration tables
- **189 foreign key relationships** ensuring referential integrity
- **Multi-tenant support** through `WorkspaceId` (uniqueidentifier) columns
- **Avoqado integration tables** already installed for real-time sync

### 🔑 CRITICAL: WorkspaceId Architecture (v11)

**IMPORTANT**: Each entity has its **OWN unique WorkspaceId** - they do NOT share WorkspaceIds!

```sql
-- Example: Order folio 3 with 2 items and 1 payment
tempcheques:        folio=3,     WorkspaceId=3E4D9070-D76D-4387-8A49-12143F84AA2D  (order)
tempcheqdet:        foliodet=3,  WorkspaceId=309FF1B2-BE05-4CB5-9BB7-B09B510BF4DC  (item 1)
tempcheqdet:        foliodet=3,  WorkspaceId=2FDB2D3F-1F79-47F7-BE65-63547F137347  (item 2)
tempchequespagos:   folio=3,     WorkspaceId=A1B2C3D4-E5F6-G7H8-I9J0-K1L2M3N4O5P6  (payment)
turnos:             idturno=962, WorkspaceId=F1E2D3C4-B5A6-9788-6655-443322110099  (shift)

-- ✅ All belong to same order because folio/foliodet = 3
-- ✅ Each has its own UNIQUE WorkspaceId
-- ✅ Entity IDs for v11 are just the WorkspaceId (no concatenation, no suffixes)
```

**Key Points:**
- WorkspaceId is a **GUID per entity** (not a tenant identifier)
- Entities relate through **folio/foliodet numbers**, NOT through WorkspaceId
- In v11, Entity ID = WorkspaceId (e.g., `309FF1B2-BE05-4CB5-9BB7-B09B510BF4DC`)
- In v10, Entity ID = `{InstanceId}:{IdTurno}:{Folio}` or `{InstanceId}:{IdTurno}:{Folio}:{Movimiento}`

### Core Philosophy: Transactional Lifecycle

The POS operates on a fundamental principle: a transactional lifecycle based on temporary tables for active operations and permanent tables
for historical data. The main entity (an order or "cheque") doesn't exist in a single state but transitions through well-defined phases,
leaving a clear trace in the database.

### Key Tables in the Lifecycle:

- **`tempcheques`**: Contains active orders from the current shift. High-transactional table with **194 columns** including totals,
  payments, customer info, and Avoqado integration
- **`cheques`**: Historical archive. Contains exact copies of orders once they've been closed (paid or cancelled) and the shift ends
- **`turnos`**: Manages temporal context of operations. An order always belongs to a shift
  - **CRITICAL**: Uses Dual-Key Architecture - `idturnointerno` (PK) + `idturno` (Business Key)
  - **Applications use**: `idturno` for all business operations and queries
  - **Database uses**: `idturnointerno` as technical primary key (auto-increment)
- **`tempcheqdet`**: Order line items (products, quantities, prices, modifications)
- **`tempchequespagos`**: Payment records for active orders

### Critical Fields in tempcheques Table (194 columns total):

- **Primary Key**: `folio` (bigint) - Unique order identifier
- **Status Fields**: `pagado` (bit), `cancelado` (bit), `impreso` (bit) - Order lifecycle gates
- **Business Fields**: `total` (money), `subtotal` (money), `idturno` (bigint), `mesa` (varchar)
  - **IMPORTANT**: `idturno` references business key in `turnos`, not the PK `idturnointerno`
- **Multi-tenant**: `WorkspaceId` (uniqueidentifier) - For multi-location support
- **Avoqado Integration**: `AvoqadoLastModifiedAt` (datetime2) - Change tracking timestamp

### 4 Phases of Order Lifecycle:

#### Phase 1: Open Order in Modification 📝

- **Tables**: `tempcheques` + `tempcheqdet` (item details)
- **Process**: When a waiter opens a new table/account, creates record with `pagado=0`, `cancelado=0`, `impreso=0`
- **Logic**: Order is "volatile". Totals constantly recalculated after each item modification

#### Phase 2: Consolidation & Presentation (Print Bill) 🖨️

- **Tables**: `tempcheques`
- **Process**: Before printing, system recalculates totals, obtains sequential `numcheque`, sets `impreso=1`
- **Logic**: `impreso=1` acts as gatekeeper - order cannot be paid without this flag

#### Phase 3: Settlement (Pay Bill) 💳

- **Tables**: `tempchequespagos`, `tempcheques`
- **Process**: Verifies `impreso=1`, inserts payment record, sets `pagado=1`
- **Logic**: Payment insertion and `pagado=1` finalize active order life

#### Phase 4: Archive & Purge (Shift Close) 🗄️

- **Tables**: All (temp\* to permanent counterparts)
- **Process**: Complete transactional archiving process within a single transaction
- **Logic**: DELETE from temp\* tables at shift end is normal lifecycle, NOT cancellation

**Technical Implementation (SQL Server 2014 Compatible):**

1. **Pre-Archive Validation**: Verify shift has no open orders and check constraints
2. **Master Archive Operations** (within transaction):
   - `INSERT INTO cheques SELECT * FROM tempcheques WHERE idturno=X`
   - `INSERT INTO cheqdet SELECT * FROM tempcheqdet d INNER JOIN tempcheques t...`
   - `INSERT INTO chequespagos SELECT * FROM tempchequespagos p INNER JOIN tempcheques t...`
3. **Auxiliary Archive Operations**:
   - `INSERT INTO cancela` - Canceled item records
   - `INSERT INTO cheqpedidos` - Order-to-delivery mapping
   - `INSERT INTO bitacoratarjetacredito` - Credit card transaction logs
   - `INSERT INTO numerostarjetas` - Loyalty card transactions
   - `INSERT INTO foliosfacturados` - Invoice relationships
4. **Table Management & Cleanup**:
   - Free table assignments: `UPDATE mesas SET estatus_ocupacion=0`
   - Clear production queue: `DELETE FROM PRODUCTOSENPRODUCCION WHERE folio IN...`
   - Reset counter sequences: `UPDATE folios SET ultimaorden=0, ultimofolioproduccion=0`
5. **Shift Finalization**:
   - `UPDATE turnos SET cierre=GETDATE() WHERE idturno=X` (CRITICAL: This triggers shift close detection)
   - **NOTE**: Actual DELETE from temp\* tables happens AFTER shift close timestamp is set

### Database Relationships & Integrity

The system maintains data integrity through **189 foreign key relationships**:

- **Product relationships**: `productos` ← `tempcheqdet`, `cheqdet` (order items reference products)
- **Customer relationships**: `clientes` ← `tempcheques` (orders reference customers)
- **Payment relationships**: `formasdepago` ← `tempchequespagos` (payments reference payment methods)
- **Area relationships**: `areasrestaurant` ← `tempcheques` (orders reference restaurant areas)
- **Enterprise relationships**: `empresas` ← multiple tables (multi-company support)

### Shift Close Process Technical Details

**Critical Database Operations Sequence:**

1. **Archive Phase** (Lines 79-88 in trace):
   - Data migration from temp\* to permanent tables within single transaction
   - All `INSERT INTO [permanent] SELECT * FROM [temp*] WHERE idturno=X` operations
   - **Time Duration**: ~6 seconds for full archive process
2. **Cleanup Phase** (Lines 89-94):
   - Table status reset and production queue cleanup
   - Mesa assignments freed and occupancy status cleared
3. **Finalization Phase** (Line 95):
   - **CRITICAL**: `UPDATE turnos SET cierre='timestamp' WHERE idturno=X`
   - This UPDATE is the definitive marker for shift closure
   - **Performance Note**: Line 95 shows 203ms execution time with 3697 logical reads
4. **Post-Close Operations** (Lines 96-98):
   - Sequence counter resets
   - Transaction commit

**Key Timing Patterns from Real Trace:**

- **Transaction Start**: `set implicit_transactions on` (Line 74)
- **Archive Duration**: ~6 seconds (Lines 79-94)
- **Shift Close**: `UPDATE turnos SET cierre=...` (Line 95) - **THIS IS THE DETECTION POINT**
- **Transaction Complete**: `COMMIT TRAN` (Line 98)

### Avoqado Integration Role:

- **Triggers**: Act as "microphones" on temp\* tables, reporting changes to `AvoqadoTracking`
- **Producer**: Intelligent debouncing, understands DELETE during shift close ≠ cancellation
- **Context-Aware**: Detects `turnos.cierre` updates to identify legitimate shift closures
- **Timing Intelligence**: Uses shift close timestamp detection to prevent spurious deletion events
- **Multi-tenant**: Uses `WorkspaceId` for proper data isolation

## Database Integration & SQL Scripts

The service integrates deeply with SoftRestaurant POS database through a sophisticated change tracking system that respects the POS
transactional lifecycle.

### SQL Script Workflow (Execute in Order)

**IMPORTANT**: All scripts now use `DB_NAME()` for database detection. Run them against your target database context.

#### Core Installation & Verification

1. **`00-VERIFICATION.sql`** - Quick system status check (can run anytime)
   - ✅ Enhanced with trigger enabled/disabled status
   - ✅ Validates new tables (AvoqadoDebugLog, AvoqadoPartialPayments, AvoqadoShiftArchiving)
2. **`00-CLEANUP-ALL.sql`** - Complete cleanup of all Avoqado objects (for fresh install)
   - ✅ Synchronized with all new v2.5.0 objects
3. **`01-COMPLETE-INSTALL.sql`** - Main installation script (creates all required objects)
   - ✅ Includes AvoqadoDebugLog table for sp_ApplyPartialPayment debugging
   - ✅ Includes AvoqadoPartialPayments table for payment tracking
   - ✅ Includes AvoqadoShiftArchiving table for improved shift close protection
   - ✅ Added sp_BeginShiftArchiving and sp_EndShiftArchiving procedures
   - ✅ Added sp_CleanupOldTrackingRecords for automatic maintenance
   - ✅ Improved triggers with flag-based shift close detection
4. **`02-TESTING.sql`** - Testing script to verify installation
5. **`03-DIAGNOSTICS.sql`** - Comprehensive diagnostic and monitoring
   - ✅ Includes cleanup recommendations based on AvoqadoTracking age

#### Advanced Diagnostic & Testing Tools (v2.5.0)

6. **`98-CLEAN-TESTING-PROCEDURE.sql`** - 🆕 Step-by-step testing guide

   - Complete walkthrough for testing Avoqado payment integration
   - Includes pre/post shift-close verification steps
   - Troubleshooting guide for missing payments in shift reports
   - **Usage**: Run after fresh installation to validate complete payment flow

7. **`99-SHIFT-CLOSE-DIAGNOSTIC.sql`** - 🆕 Shift close payment archiving analysis
   - Analyzes payment WorkspaceId matching between orders and payments
   - Simulates archiving queries to predict what will be archived
   - Compares temp\* table data with archived data
   - **Usage**: Run BEFORE and AFTER shift close to diagnose archiving issues

#### Maintenance & Tracking Cleanup

- **Tracking maintenance** is handled by `sp_CleanupOldTrackingRecords` (see Stored Procedures below),
  which prunes old processed/error rows from `AvoqadoTracking`. There is no separate optimization
  script to apply: `scripts/sql/05-Optimizacion-Tracking.sql` is **deprecated** (moved to
  `scripts/sql/[deprecated]/`) and is NOT part of the canonical model. All required objects are
  consolidated into `01-COMPLETE-INSTALL.sql`.

### Database Architecture

#### SQL Server 2014 Specific Features

- **Compatibility Level**: SQL Server 2014 (version 12.0.4100.1)
- **Data Types**: Uses `money` for currency, `datetime2` for timestamps, `uniqueidentifier` for GUIDs
- **Indexing**: Includes clustered and non-clustered indexes for performance
- **Constraints**: Extensive use of foreign keys (189 relationships) and check constraints

#### Complete Table Structure (366 Tables)

**Core Business Tables:**

- **`tempcheques`** (194 columns) - Active orders with comprehensive business logic
- **`tempcheqdet`** - Order line items with product details
- **`tempchequespagos`** - Payment records for active orders
- **`productos`** - Product catalog with pricing and classifications
- **`clientes`** - Customer master data with contact information
- **`turnos`** - Shift management with opening/closing controls
- **`areasrestaurant`** - Restaurant areas and table management
- **`formasdepago`** - Payment methods configuration

**Historical Tables:**

- **`cheques`** - Archived orders (mirrors tempcheques structure)
- **`cheqdet`** - Archived order items
- **`chequespagos`** - Archived payment records

**Configuration & Control:**

- **`empresas`** - Company/enterprise configuration
- **`estaciones`** - POS terminal/station setup
- **`usuarios`** - User accounts and permissions
- **`workspace_*`** tables - Multi-tenant workspace management
- **`parametros`**, **`parametros2`**, **`parametros3`** - System parameters and configuration flags
- **`configuracion`** - **CRITICAL: Contains fiscal day configuration (see below)**

#### 🕐 Fiscal Day Configuration (IMPORTANT)

**Table**: `configuracion`

SoftRestaurant uses a fiscal day cycle that differs from calendar days. The fiscal day defines when reports and business operations consider a "new day" to begin:

```sql
SELECT cortezinicio, cortezfin, cortezfindiasiguiente FROM configuracion
-- Results:
-- cortezinicio: 06:00:00 AM        (fiscal day starts)
-- cortezfin: 05:59:59 AM           (fiscal day ends)
-- cortezfindiasiguiente: 1         (end time is next calendar day)
```

**What This Means**:
- **Fiscal day window**: 6:00 AM to 5:59:59 AM (next day)
- **Purpose**: Groups sales and reports into logical business days rather than calendar days
- **Related setting**: `parametros2.cierrediarioaperturarturno = 1` enables automatic daily shift management
- **Counter behavior**:
  - `idturno` in `turnos` table: **Never resets** - increments indefinitely (965, 964, 963...)
  - `ultimofolio` in `folios` table: **Never resets** - continues forever
  - `ultimaorden` in `folios` table: **Resets to 0** on shift close
  - `ultimofolioproduccion` in `folios` table: **Resets to 0** on shift close

**IMPORTANT**: This configuration determines when shift reports consider a new business day. All sales between 6:00 AM and 5:59:59 AM (next day) are grouped together for reporting purposes.

#### Avoqado Integration Tables

**Core Tables:**

- **`AvoqadoInstanceInfo`** - Stores unique instance GUID for multi-location support
- **`AvoqadoConfig`** - Configuration and version detection (PosVersion, HasWorkspaceId)
- **`AvoqadoTracking`** - Universal change tracking table for orders, items, shifts, payments
  - Primary key with unique constraint on EntityType + EntityId
  - Indexed on Timestamp + EntityType for performance
  - Tracks Operation (CREATE, UPDATE, DELETE) and ProcessedAt timestamp
- **`AvoqadoCommands`** - Command queue for Avoqado → POS operations

**New Tables (v2.5.0):**

- **`AvoqadoDebugLog`** ✅ - Debug logging for sp_ApplyPartialPayment operations
  - Indexed on Timestamp for performance
  - Tracks payment processing flow with detailed messages
- **`AvoqadoPartialPayments`** ✅ - Partial payment tracking table
  - Indexed on Folio + IsProcessed for quick lookups
  - Tracks payment amount, method, and processing status
- **`AvoqadoShiftArchiving`** ✅ - Shift archiving state management
  - Prevents spurious deletion events during shift close
  - Uses flag-based approach instead of time window (more reliable for large shifts)
  - Auto-cleans old records after 7 days

#### Enhanced POS Tables

The service integrates with existing POS tables through trigger-based change tracking:

- **`tempcheques`** - Order headers (194 columns including totals, customer, payments)
- **`tempcheqdet`** - Order line items (products, quantities, prices, modifications)
- **`turnos`** - Shift information (open/close times, cashier, station)

#### Stored Procedures

**Sync Operations:**

- **`sp_GetPendingChanges`** - Retrieves pending changes since last sync (reads `WHERE ProcessedAt IS NULL`, batched, max 100)
- **`sp_MarkChangesProcessed`** - Marks changes as processed (sets `ProcessedAt`) after successful sync

**Payment Operations:**

- **`sp_ApplyPartialPayment`** - Handles partial payment processing and validation
  - Includes comprehensive debug logging to AvoqadoDebugLog
  - Implements SoftRestaurant-style quantity adjustment for partial payments

**Shift Management (v2.5.0):**

- **`sp_BeginShiftArchiving`** ✅ - Marks shift as being archived (prevents spurious deletion events)
- **`sp_EndShiftArchiving`** ✅ - Marks shift archiving as complete

**Maintenance (v2.5.0):**

- **`sp_CleanupOldTrackingRecords`** ✅ - Automated cleanup of old processed/error records (`@DaysToKeep INT = 7`)
  - Deletes processed records older than @DaysToKeep days (default: 7)
  - Deletes trigger errors (RetryCount=99) older than @DaysToKeep days
  - Deletes failed records (RetryCount>=5) older than @DaysToKeep days

#### Database Triggers (SQL Server 2014 Compatible)

- **`Trg_Avoqado_Orders`** - Tracks order creation, updates, and deletions on `tempcheques`
  - ✅ Improved (v2.5.0): Uses AvoqadoShiftArchiving flag + 30s fallback for shift close protection
  - ✅ More reliable for large shifts with >30 second archiving time
- **`Trg_Avoqado_OrderItems`** - Tracks individual item changes within orders on `tempcheqdet`
- **`Trg_Avoqado_Payments`** - Tracks payment insertions on `tempchequespagos`
- **`Trg_Avoqado_Shifts`** - Tracks shift opening and closing events on `turnos`

#### Index Strategy

**Primary Keys:** All 366 tables have defined primary keys for data integrity **Performance Indexes:**

- `IX_Pending` - On `AvoqadoTracking(ProcessedAt, Timestamp)` for fast pending-change polling
- `IX_cheques_workspaceid` - Multi-column index for workspace queries
- `IX_cheques_fecha` - Date-based queries for reporting
- `FYI_chequespagos_folio` - Foreign key index for payment lookups

### Entity ID Format & Version Detection

The service automatically detects SoftRestaurant version using `parametros2.versiondb` and generates Entity IDs accordingly:

**v10 Format (version < 11.0):**

- **Orders**: `{InstanceId}:{IdTurno}:{Folio}` (e.g., `abc123:894:1001`)
- **Order Items**: `{InstanceId}:{IdTurno}:{Folio}:{Movimiento}` (e.g., `abc123:894:1001:3`)
- **Shifts**: `{IdTurno}` (e.g., `894`)

**v11 Format (version >= 11.0):**

- **Orders**: `{WorkspaceId}` (e.g., `68D8362E-2311-470E-8571-AD49874E4B6D`)
- **Order Items**: `{WorkspaceId}:{Movimiento}` (e.g., `68D8362E-2311-470E-8571-AD49874E4B6D:3`)
- **Shifts**: `{WorkspaceId}` (e.g., `A1B2C3D4-E5F6-G7H8-I9J0-K1L2M3N4O5P6`)

**Version Detection Implementation:**

- **Database Function**: `dbo.fn_GetSoftRestaurantVersion()` queries `parametros2.versiondb`
- **Stored Procedure**: `dbo.sp_GenerateEntityId` generates appropriate Entity IDs based on version
- **Producer Logic**: Detects version on startup and uses proper format throughout execution
- **SQL Triggers**: Use version detection instead of checking WorkspaceId column presence

**CRITICAL NOTE**: All Entity IDs use `idturno` (business key), NOT `idturnointerno` (technical PK)

### SoftRestaurant Dual-Key Architecture

The `turnos` table implements a sophisticated dual-key pattern:

- **Technical Primary Key**: `idturnointerno` (bigint, auto-increment)

  - Used for database optimization and referential integrity
  - Sequential values: 80885, 80884, 80883, etc.
  - Never used in application logic or queries

- **Business Key**: `idturno` (bigint, manually assigned)
  - Used by all POS applications and business logic
  - Values like: 894, 893, 892, etc.
  - Referenced by `tempcheques.idturno` and all related tables
  - Used in all Entity IDs and synchronization

**Code Implementation**: All database queries in this codebase correctly use `idturno` for business operations, maintaining compatibility
with SoftRestaurant's application layer.

## SoftRestaurant Documentation Reference

This repository contains comprehensive documentation of SoftRestaurant v11 POS system for development and integration purposes. The
documentation is organized into several interconnected files and directories that provide complete technical coverage.

### 📁 Master Documentation

**Primary Reference**: `docs/SoftRestaurant_Master_Documentation.md`

- Central hub for all SoftRestaurant knowledge
- Complete overview of documentation structure
- Integration architecture and business flows
- Quick reference links to all specialized documents

### 📁 Configuration & Client Onboarding

**File**: `SoftRestaurant_Configuration_Guide.md`

- **Purpose**: Complete guide for onboarding new Avoqado clients
- **Key Topics**:
  - Multi-tenant WorkspaceId management (1000+ active tenants)
  - Invoice series configuration (Serie A, B, C, etc.)
  - Payment methods setup (formasdepago table)
  - Parameter tables analysis (parametros, parametros2, parametros3)
  - Database connection and access procedures
- **Usage**: Reference this for every new client integration
- **Critical Rules**: Contains essential "NEVER DO" and "ALWAYS DO" guidelines

### 📁 Technical Solutions

**File**: `SOFTRESTAURANT_ENTITY_RESOLUTION.md`

- **Purpose**: Documents the solution for SoftRestaurant's unique order processing behavior
- **Key Topics**:
  - Order creation with idturno=0 → real idturno transition
  - Smart entity resolution to prevent duplicate orders
  - Context-aware deletion during shift closures
  - Implementation details in producer and backend services
- **Usage**: Reference when debugging order duplication or entity ID issues

### 📁 Database Schema Reference (info-softrest11/)

**Directory Overview**: `info-softrest11/README.md` (Spanish)

- Complete structure explanation of database reference files

**Schema Information** (`info-softrest11/database-schema/`):

- `table-definitions.csv` - All 366 tables in the system
- `table-relationships.csv` - Complete column definitions and data types
- `core-relationships.csv` - Critical table relationships
- `table-create-statements.sql` - Full schema recreation scripts
- `constraints/` - Foreign keys (189 relationships), indexes, primary keys

**Business Flow Traces** (`info-softrest11/sql-traces/`):

- `shift-close-flow.sql` - Real SQL Server Profiler trace of shift closure (203ms timing)
- `order-lifecycle-flow.sql` - Complete order creation to payment process
- **Source**: Actual production SQL Server 2014 traces

**Table Analysis** (`info-softrest11/table-analysis/`):

- `turnos-table-details.sql` - Critical shifts table structure analysis
- Documents dual-key architecture (idturnointerno vs idturno)

### 📁 Integration Database Objects (analysis/db/)

**Avoqado-Specific Components**:

**Stored Procedures**:

- `sp_GetPendingChanges.sql` - Retrieves unprocessed entity changes for sync
- `sp_MarkChangesProcessed.sql` - Marks changes as processed after sync
- `sp_ApplyPartialPayment.sql` - Partial payment processing and validation

**Functions**:

- `fn_CanCompleteOrderPayment.sql` - Payment validation logic
- `fn_GetPartialPaymentsTotal.sql` - Payment total calculations
- `fn_GetSoftRestaurantVersion.sql` - Version detection

**Database Triggers**:

- `Trg_Avoqado_Orders.sql` - Order change tracking
- `Trg_Avoqado_OrderItems.sql` - Order item change tracking
- `Trg_Avoqado_Shifts.sql` - Shift change tracking

**Table Schemas**:

- `tempcheques_columns.txt` - Complete order table structure (194 columns)
- `AvoqadoTracking_*` - Change tracking table analysis
- `AvoqadoPartialPayments_*` - Partial payment table analysis

### 📋 Quick Reference Commands

**Find Table Information**:

```bash
# Search for specific table
grep -i "tempcheques" info-softrest11/database-schema/table-definitions.csv

# Check table relationships
grep -i "turnos" info-softrest11/database-schema/constraints/foreign-keys.csv

# Find business flow details
grep -i "UPDATE turnos" info-softrest11/sql-traces/shift-close-flow.sql
```

**Database Analysis**:

```bash
# List all integration stored procedures
ls analysis/db/sp_*.sql

# Check table structures
ls analysis/db/*_columns.txt

# Find trigger definitions
ls analysis/db/Trg_*.sql
```

### 🔍 Documentation Usage Patterns

**For New Developers**:

1. Start with `docs/SoftRestaurant_Master_Documentation.md` - complete overview
2. Read `SoftRestaurant_Configuration_Guide.md` - understand configuration
3. Review `SOFTRESTAURANT_ENTITY_RESOLUTION.md` - understand unique challenges

**For Client Onboarding**:

1. Use `SoftRestaurant_Configuration_Guide.md` as primary checklist
2. Reference `info-softrest11/database-schema/` for schema validation
3. Check WorkspaceId isolation requirements

**For Debugging Issues**:

1. Check `SOFTRESTAURANT_ENTITY_RESOLUTION.md` for entity ID problems
2. Use `info-softrest11/sql-traces/` to understand expected business flows
3. Reference `analysis/db/` for integration-specific database objects

**For Database Changes**:

1. Review `info-softrest11/database-schema/constraints/` for relationships
2. Check `table-create-statements.sql` for recreation procedures
3. Validate against `analysis/db/` integration objects

### ⚠️ Critical Notes

- **File Status**: All documentation files are current and active (no deprecated files)
- **Maintenance**: Configuration guides updated regularly based on client onboarding experience
- **Multi-tenant**: All procedures must respect WorkspaceId isolation (1000+ active tenants)
- **Version Compatibility**: All SQL must be SQL Server 2014 Express compatible
- **Reference Only**: Schema files are read-only historical reference, not for modification

### 🔗 Cross-References

- **Database Connection Info**: See "External Database Access" section below
- **SQL Server Compatibility**: See "SQL Server Version" section above
- **Entity ID Formats**: See "Entity ID Format & Version Detection" section above
- **Performance Metrics**: See "Database Performance & Monitoring" section below

## Architecture Overview

### Core Components

- **Producer** (`src/components/producer.ts`) - Polls database every 2 seconds, implements 2.5s debouncing for order updates, sends
  heartbeats every 60 seconds
- **Commander** (`src/components/commander.ts`) - Consumes commands from `pos_commands_exchange`, executes POS operations through adapters
- **Configuration Error Consumer** (`src/components/configurationErrorConsumer.ts`) - Handles venue ID validation errors with automatic
  recovery

### Core Infrastructure

- **Database** (`src/core/db.ts`) - SQL Server 2014 connection pool management with compatibility settings
- **RabbitMQ** (`src/core/rabbitmq.ts`) - Message broker with exchange binding
- **Logger** (`src/core/logger.ts`) - Winston with daily rotation and structured logging
- **Service State Manager** (`src/core/serviceState.ts`) - State machine for service health
- **Configuration Manager** (`src/core/configurationManager.ts`) - Config validation and backup
- **Connection Resilience** (`src/core/connectionResilience.ts`) - SQL Server 2014 specific connection handling
- **Windows Notification** (`src/core/windowsNotification.ts`) - PowerShell-based system notifications

### POS Adapter Pattern

- **IPosAdapter** (`src/adapters/IPosAdapter.ts`) - Interface for POS operations
- **SoftRestaurant11Adapter** (`src/adapters/SoftRestaurant11Adapter.ts`) - Implementation for SoftRestaurant v11
  - Order creation and item management
  - Payment processing and order closure
  - Shift management (open/close with cash reconciliation)
  - Transaction-based operations with rollback support

### Configuration Management

- **Development**: Uses `.env` file when `NODE_ENV=development`
- **Production**: Uses `%ProgramData%\AvoqadoSync\config.json`
- **Required Fields**: venueId, posType, posVersion, rabbitMqUrl, sqlConfig
- **SQL Server 2014 Config**: Connection strings must specify compatibility settings for SQL Server 2014
- **Validation**: Automatic venue ID validation with fallback mechanisms
- **Backup System**: Maintains configuration history with rollback capability
- **Multi-tenant**: WorkspaceId configuration for proper data isolation

## SoftRestaurant Entity Resolution System

The service includes intelligent handling for SoftRestaurant's unique order lifecycle where orders are created with `idturno=0` and later
updated to the real shift ID during payment. This prevents duplicate orders in the backend.

**Key Implementation**:

- **Producer**: Context-aware deletion logic prevents spurious order deletions during shift close
- **Backend**: Smart entity resolution automatically links orders with different Entity IDs but same folio
- **Documentation**: See `SOFTRESTAURANT_ENTITY_RESOLUTION.md` for complete technical details

## Key Technical Details

### Producer Architecture

- **Version Detection**: Automatically detects SoftRestaurant version using `parametros2.versiondb` on startup (v2.4.0+)
- **Polling**: Executes `sp_GetPendingChanges` every 2 seconds with batching (max 100 results),
  guarded against overlapping cycles (a slow batch never runs concurrently with the next tick)
- **Durable sync cursor (resilience layer)**: At-least-once delivery is guaranteed by the `ProcessedAt`
  mechanism on `AvoqadoTracking` (`sp_GetPendingChanges` only returns rows where `ProcessedAt IS NULL`).
  On top of that, `src/core/syncCursor.ts` persists a cursor `(Timestamp, Id)` over `AvoqadoTracking` to
  `sync-cursor.json` (dev: project root; prod: `%ProgramData%\AvoqadoSync`). This disk cursor is an extra
  resilience layer — NOT the primary delivery guarantee — that lets the Producer resume near where it left
  off and avoid a blind re-scan window after a long restart
- **SQL Server 2014 Compatibility**: Uses T-SQL syntax compatible with version 12.0.4100.1
- **Debouncing**: Order updates batched for 2.5 seconds to reduce message volume
- **Event Types**: `created`, `updated`, `deleted` for orders; `created`, `updated`, `deleted` for items
- **Context-Aware**: Detects shift closures to prevent spurious order deletions
- **Version-Aware Processing**: Uses detected version to determine Entity ID format (v10 vs v11)
- **Dual-Key Aware**: Uses `idturno` (business key) for all shift operations, not `idturnointerno` (PK)
- **Multi-tenant Aware**: Respects WorkspaceId boundaries in v11 databases

### Message Routing

- **Events Published To**: `pos_events_exchange`
  - `pos.softrestaurant.order.{created|updated|deleted}`
  - `pos.softrestaurant.orderitem.{created|updated|deleted}`
  - `pos.softrestaurant.shift.{created|closed}`
  - `pos.softrestaurant.system.heartbeat`
- **Commands Consumed From**: `pos_commands_exchange`
  - `command.softrestaurant.{venueId}` - Regular POS commands
  - `command.softrestaurant.configuration.error` - Configuration error notifications

### Service State Machine

- **RUNNING** - Normal operation with heartbeats and polling
- **CONFIGURATION_ERROR** - Invalid venue ID, heartbeats stopped
- **RECONFIGURING** - Applying new configuration
- **STOPPED** - Service shutdown or critical error

### Error Handling & Recovery

- **Configuration Errors**: Automatic venue switching with Windows notifications
- **Database Errors**: Connection pooling with retry logic
- **RabbitMQ Errors**: Automatic reconnection with exponential backoff
- **Loop Prevention**: Cooldown periods and maximum retry limits

## Entry Points & Service Management

- **`src/main.ts`** - Windows service installer/uninstaller using node-windows
- **`src/service.ts`** - Main orchestrator that starts all components
- **Management Console**: Interactive CLI (development mode only) for real-time monitoring

## Development Patterns

### Adding New POS Adapters

1. Implement `IPosAdapter` interface
2. Add adapter selection logic in `commander.ts`
3. Create corresponding SQL triggers and procedures
4. Update entity ID formats if needed

### Adding New Entity Types

1. Add entity type to `AvoqadoTracking` enum
2. Create corresponding database triggers
3. Add processing logic in `producer.ts`
4. Update message routing keys

### Debugging Database Issues

1. Run `00-Verificacion.sql` for quick status
2. Use `01-Diagnostico.sql` for detailed analysis
3. Check logs for trigger execution and SQL errors
4. Use `04-Pruebas.sql` to validate functionality
5. Reference `info-soft-rest/` for database schema and SQL traces:
   - `database-schema/table-definitions.csv` - Complete table list
   - `database-schema/constraints/foreign-keys.csv` - Relationship mappings
   - `sql-traces/shift-close-flow.sql` - Real shift close process trace

## Database Performance & Monitoring

- **SQL Server 2014 Optimization**: Queries optimized for version 12.0.4100.1 performance characteristics
- **Index Usage**: Leverages 366-table schema indexes for optimal query performance
- **Connection Pooling**: Manages SQL Server 2014 connection limits efficiently
- **Query Batching**: Limits result sets to prevent memory issues with large datasets
- **Multi-tenant Isolation**: Ensures WorkspaceId filtering in all database operations

All the important information about the database is on analysis\db\

## External Database Access

### Testing & Development Databases

For testing and development, you can access external database instances with different SoftRestaurant versions:

**SoftRestaurant v11 Database (with WorkspaceId)**:

- Server: `100.80.118.68:49759`
- Instance: `NATIONALSOFT`
- Database: `avov2`
- User: `sa`
- Password: `National09`

**SoftRestaurant v11 Database (without Avoqado integration)**:

- Server: `100.114.70.80:1433`
- Instance: `NATIONALSOFT`
- Database: `avo`
- User: `sa`
- Password: `National09`
- Note: Has WorkspaceId support but no Avoqado tracking tables installed

### Connection Methods

**Using sqlcmd for External Databases**:

```bash
# Set password (Windows PowerShell)
$env:SQLCMDPASSWORD = 'National09'

# Set password (Linux/macOS/Git Bash)
export SQLCMDPASSWORD='National09'

# Connect to v11 database (includes port)
sqlcmd -S "tcp:100.80.118.68,49759" -d avov2 -U sa -Q "SELECT @@SERVERNAME, DB_NAME();"

# Connect to v11 database without Avoqado integration (includes port)
sqlcmd -S "tcp:100.114.70.80,1433" -d avo -U sa -Q "SELECT @@SERVERNAME, DB_NAME();"
```

**Note**: Ports are only needed for external database connections via sqlcmd. Local connections use instance names.

### Database Version Detection

To check if a database supports WorkspaceId (v11):

```sql
SELECT COL_LENGTH('tempcheques', 'WorkspaceId') as HasWorkspaceId;
-- Returns 16 for v11, NULL for v10
```

### Entity ID Format Analysis

Check Entity ID formats in tracking table:

```sql
SELECT
  CASE
    WHEN EntityId LIKE '%:%:%' THEN 'v10 (InstanceId:IdTurno:Folio)'
    WHEN EntityId LIKE '%:%' AND EntityId NOT LIKE '%:%:%' THEN 'v11 (WorkspaceId:Sequence)'
    WHEN EntityId NOT LIKE '%:%' THEN 'v11 (WorkspaceId)'
    ELSE 'Unknown'
  END as EntityIDFormat,
  COUNT(*) as Count
FROM AvoqadoTracking
GROUP BY
  CASE
    WHEN EntityId LIKE '%:%:%' THEN 'v10 (InstanceId:IdTurno:Folio)'
    WHEN EntityId LIKE '%:%' AND EntityId NOT LIKE '%:%:%' THEN 'v11 (WorkspaceId:Sequence)'
    WHEN EntityId NOT LIKE '%:%' THEN 'v11 (WorkspaceId)'
    ELSE 'Unknown'
  END;
```

## Logging & Monitoring

- **Daily Rotation**: Separate files for info and error levels
- **Structured Logging**: Component-specific prefixes and context
- **Heartbeat Monitoring**: Regular status reports to central system
- **Windows Event Log**: Critical errors logged to system event log
- **Performance Metrics**: Database query times and message processing rates
- **SQL Server Metrics**: Connection pool status, query execution times, deadlock detection

## 🚨 CRITICAL: Documentation Synchronization Rule

**MANDATORY REQUIREMENT**: Every time ANY change is made to:

- Database schema (tables, columns, procedures, triggers)
- Stored procedure signatures or functionality
- Integration architecture or data flow
- Entity ID formats or tracking mechanisms
- Core system behavior or implementation

**MUST IMMEDIATELY UPDATE ALL DOCUMENTATION FILES:**

- `CLAUDE.md` (primary project documentation)
- `AGENTS.md` (agent-specific documentation)
- `docs/SoftRestaurant_Master_Documentation.md` (master reference)
- Any relevant SQL diagnostic/test scripts

**WHY THIS IS CRITICAL:**

- Documentation drift leads to confusion and incorrect assumptions
- Outdated docs can cause developers to implement deprecated patterns
- Inconsistent documentation wastes debugging time
- New team members will follow outdated guidance

**PROCESS:**

1. Make the technical change
2. IMMEDIATELY update all related documentation
3. Verify documentation consistency across all files
4. Test that examples in documentation actually work

**NO EXCEPTIONS**: Documentation updates are NOT optional - they are part of the change implementation.

## 🔴 CRITICAL — Keep the Avoqado MCP in sync

The Avoqado MCP (`avoqado-server/scripts/mcp/`) is a **first-class interface**: it exposes
the platform's data and actions to AI agents (internal ops today, customer-facing tomorrow).
It must never fall behind the platform.

**Whenever you add or change a feature, Prisma model, service, endpoint, permission, or any
capability the MCP should expose, you MUST add or update the matching MCP tool in
`avoqado-server/scripts/mcp/` as part of the SAME change — never "later".** A capability that
exists but isn't reachable through the MCP is unfinished. Treat the MCP like permissions: kept
in lockstep, never an afterthought.

## 🔴 CRITICAL — Keep the sales presentation in sync

The partner sales presentation (`~/Documents/Programming/Avoqado-HQ/operations/marketing/platform-presentation/`)
is the canonical "what Avoqado does" document — third parties sell from it. It must never fall
behind the platform.

**Whenever you add, change, or remove a customer-visible capability (feature, module, product,
payment method, supported sector, tier packaging), you MUST update BOTH deliverables as part of
the SAME change — never "later":** the full deck (`avoqado-presentacion.html`) AND the one-pager
(`avoqado-one-pager.html`), then regenerate both PDFs following that folder's `README.md`.
Updating only one of the two is an incomplete change. Internal refactors and bugfixes with no
customer-visible impact are exempt.

## Health Stack

- typecheck: npx tsc --noEmit
- lint: npx prettier --check "src/**/*.ts"
