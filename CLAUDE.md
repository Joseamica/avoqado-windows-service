# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Windows service that acts as a real-time synchronization bridge between a local Point-of-Sale (POS) system and the central Avoqado platform. It continuously monitors the POS database for changes to orders, items, and shifts, publishing these events to a RabbitMQ message broker. It also listens for commands from the Avoqado platform and executes them on the local POS system, ensuring seamless bidirectional data consistency.

**Key Features:**
- Real-time event publishing with debounced order updates
- Bidirectional sync (Producer polling + Commander execution)
- POS adapter architecture for different POS systems (currently SoftRestaurant v11)
- Windows service integration with health monitoring
- Resilient configuration management with automatic error recovery

## Common Commands

### Development & Build
- `npm run dev` - Run with hot-reload using nodemon
- `npm run build` - Compile TypeScript to JavaScript
- `npm start` - Run the compiled application

### Code Quality
- `npm run format` - Format code with Prettier
- `npm run check-format` - Check code formatting

### Windows Service Management (requires admin privileges)
- `npm run svc:install` - Install as Windows service
- `npm run svc:uninstall` - Uninstall Windows service

### Packaging
- `npm run package` - Build and create AvoqadoSyncService.exe

## SoftRestaurant POS System Architecture

### SQL Server Version
**CRITICAL:** This POS system runs on **Microsoft SQL Server 2014 Express Edition (32-bit)** - Version 12.0.4100.1 Intel X86. All database operations, triggers, and stored procedures must be compatible with SQL Server 2014 syntax and features.

### Database Schema Overview
The SoftRestaurant v11 database contains **366 tables** with a sophisticated multi-tenant architecture:
- **366 total tables** including core business logic, configuration, and integration tables
- **189 foreign key relationships** ensuring referential integrity
- **Multi-tenant support** through `WorkspaceId` (uniqueidentifier) columns
- **Avoqado integration tables** already installed for real-time sync

### Core Philosophy: Transactional Lifecycle
The POS operates on a fundamental principle: a transactional lifecycle based on temporary tables for active operations and permanent tables for historical data. The main entity (an order or "cheque") doesn't exist in a single state but transitions through well-defined phases, leaving a clear trace in the database.

### Key Tables in the Lifecycle:
- **`tempcheques`**: Contains active orders from the current shift. High-transactional table with **194 columns** including totals, payments, customer info, and Avoqado integration
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
- **Tables**: All (temp* to permanent counterparts)
- **Process**: Copies data to historical tables, closes shift in `turnos`, purges temp* tables
- **Logic**: DELETE from temp* tables at shift end is normal lifecycle, NOT cancellation

### Database Relationships & Integrity
The system maintains data integrity through **189 foreign key relationships**:
- **Product relationships**: `productos` ← `tempcheqdet`, `cheqdet` (order items reference products)
- **Customer relationships**: `clientes` ← `tempcheques` (orders reference customers)
- **Payment relationships**: `formasdepago` ← `tempchequespagos` (payments reference payment methods)
- **Area relationships**: `areasrestaurant` ← `tempcheques` (orders reference restaurant areas)
- **Enterprise relationships**: `empresas` ← multiple tables (multi-company support)

### Avoqado Integration Role:
- **Triggers**: Act as "microphones" on temp* tables, reporting changes to `AvoqadoEntityTracking`
- **Producer**: Intelligent debouncing, understands DELETE during shift close ≠ cancellation
- **Context-Aware**: Distinguishes between business cancellations and normal archiving
- **Multi-tenant**: Uses `WorkspaceId` for proper data isolation

## Database Integration & SQL Scripts

The service integrates deeply with SoftRestaurant POS database through a sophisticated change tracking system that respects the POS transactional lifecycle.

### SQL Script Workflow (Execute in Order)
1. **`00-Verificacion.sql`** - Quick system status check (can run anytime)
2. **`01-Diagnostico.sql`** - Comprehensive diagnostic before any changes
3. **`02-Limpieza.sql`** - Complete cleanup of all Avoqado objects (if needed)
4. **`03-Instalacion.sql`** - Main installation script (creates all required objects)
5. **`04-Pruebas.sql`** - Testing script to verify installation

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

#### Avoqado Integration Tables
- **`AvoqadoInstanceInfo`** - Stores unique instance GUID for multi-location support
- **`AvoqadoEntityTracking`** - Universal change tracking table for orders, items, shifts
  - Primary key with unique constraint on EntityType + EntityId
  - Indexed on LastModifiedAt + EntityType for performance
- **`AvoqadoEntitySnapshots`** - Content hash snapshots to detect actual changes (v1 only)
  - Unique constraint on EntityType + EntityId
  - Indexed on EntityType + LastSentAt

#### Enhanced POS Tables
The service adds `AvoqadoLastModifiedAt` timestamp columns to:
- **`tempcheques`** - Order headers (194 columns including totals, customer, payments)
- **`tempcheqdet`** - Order line items (products, quantities, prices, modifications)
- **`turnos`** - Shift information (open/close times, cashier, station)

#### Stored Procedures
- **`sp_TrackEntityChange`** - Records entity changes with timestamps and reasons
- **`sp_GetEntityChanges`** - Retrieves pending changes since last sync (batched, max 100)
- **`sp_UpdateEntitySnapshot`** - Updates content hash snapshots (v1 only)
- **`sp_CleanupStuckTracking`** - Maintenance procedure for stuck records

#### Database Triggers (SQL Server 2014 Compatible)
- **`Trg_Avoqado_Orders`** - Tracks order creation, updates, and deletions on `tempcheques`
- **`Trg_Avoqado_OrderItems`** - Tracks individual item changes within orders on `tempcheqdet`
- **`Trg_Avoqado_Shifts`** - Tracks shift opening and closing events on `turnos`

#### Index Strategy
**Primary Keys:** All 366 tables have defined primary keys for data integrity
**Performance Indexes:**
- `IX_AvoqadoEntityTracking_Modified` - On LastModifiedAt + EntityType
- `IX_cheques_workspaceid` - Multi-column index for workspace queries
- `IX_cheques_fecha` - Date-based queries for reporting
- `FYI_chequespagos_folio` - Foreign key index for payment lookups

### Entity ID Format
The service uses a hierarchical entity ID system:
- **Orders**: `{InstanceId}:{IdTurno}:{Folio}` (e.g., `abc123:894:1001`)
- **Order Items**: `{InstanceId}:{IdTurno}:{Folio}:{Movimiento}` (e.g., `abc123:894:1001:3`)
- **Shifts**: `{IdTurno}` (e.g., `894`)

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

**Code Implementation**: All database queries in this codebase correctly use `idturno` for business operations, maintaining compatibility with SoftRestaurant's application layer.

## Architecture Overview

### Core Components
- **Producer** (`src/components/producer.ts`) - Polls database every 2 seconds, implements 2.5s debouncing for order updates, sends heartbeats every 60 seconds
- **Commander** (`src/components/commander.ts`) - Consumes commands from `pos_commands_exchange`, executes POS operations through adapters
- **Configuration Error Consumer** (`src/components/configurationErrorConsumer.ts`) - Handles venue ID validation errors with automatic recovery

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

## Key Technical Details

### Producer Architecture
- **Polling**: Executes `sp_GetEntityChanges` every 2 seconds with batching (max 100 results)
- **SQL Server 2014 Compatibility**: Uses T-SQL syntax compatible with version 12.0.4100.1
- **Debouncing**: Order updates batched for 2.5 seconds to reduce message volume
- **Event Types**: `created`, `updated`, `deleted` for orders; `created`, `updated`, `deleted` for items
- **Context-Aware**: Detects shift closures to prevent spurious order deletions
- **Dual-Key Aware**: Uses `idturno` (business key) for all shift operations, not `idturnointerno` (PK)
- **Multi-tenant Aware**: Respects WorkspaceId boundaries in all queries

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
1. Add entity type to `AvoqadoEntityTracking` enum
2. Create corresponding database triggers
3. Add processing logic in `producer.ts`
4. Update message routing keys

### Debugging Database Issues
1. Run `00-Verificacion.sql` for quick status
2. Use `01-Diagnostico.sql` for detailed analysis
3. Check logs for trigger execution and SQL errors
4. Use `04-Pruebas.sql` to validate functionality

## Database Performance & Monitoring
- **SQL Server 2014 Optimization**: Queries optimized for version 12.0.4100.1 performance characteristics
- **Index Usage**: Leverages 366-table schema indexes for optimal query performance
- **Connection Pooling**: Manages SQL Server 2014 connection limits efficiently
- **Query Batching**: Limits result sets to prevent memory issues with large datasets
- **Multi-tenant Isolation**: Ensures WorkspaceId filtering in all database operations

## Logging & Monitoring
- **Daily Rotation**: Separate files for info and error levels
- **Structured Logging**: Component-specific prefixes and context
- **Heartbeat Monitoring**: Regular status reports to central system
- **Windows Event Log**: Critical errors logged to system event log
- **Performance Metrics**: Database query times and message processing rates
- **SQL Server Metrics**: Connection pool status, query execution times, deadlock detection