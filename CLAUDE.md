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

### Core Philosophy: Transactional Lifecycle
The POS operates on a fundamental principle: a transactional lifecycle based on temporary tables for active operations and permanent tables for historical data. The main entity (an order or "cheque") doesn't exist in a single state but transitions through well-defined phases, leaving a clear trace in the database.

### Key Tables in the Lifecycle:
- **`tempcheques`**: Contains active orders from the current shift. High-transactional table, constantly read and updated.
- **`cheques`**: Historical archive. Contains exact copies of orders once they've been closed (paid or cancelled) and the shift ends.
- **`turnos`**: Manages temporal context of operations. An order always belongs to a shift.

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

### Avoqado Integration Role:
- **Triggers**: Act as "microphones" on temp* tables, reporting changes to `AvoqadoEntityTracking`
- **Producer**: Intelligent debouncing, understands DELETE during shift close ≠ cancellation
- **Context-Aware**: Distinguishes between business cancellations and normal archiving

## Database Integration & SQL Scripts

The service integrates deeply with SoftRestaurant POS database through a sophisticated change tracking system that respects the POS transactional lifecycle.

### SQL Script Workflow (Execute in Order)
1. **`00-Verificacion.sql`** - Quick system status check (can run anytime)
2. **`01-Diagnostico.sql`** - Comprehensive diagnostic before any changes
3. **`02-Limpieza.sql`** - Complete cleanup of all Avoqado objects (if needed)
4. **`03-Instalacion.sql`** - Main installation script (creates all required objects)
5. **`04-Pruebas.sql`** - Testing script to verify installation

### Database Architecture

#### Core Tracking Tables
- **`AvoqadoInstanceInfo`** - Stores unique instance GUID for multi-location support
- **`AvoqadoEntityTracking`** - Universal change tracking table for orders, items, shifts
- **`AvoqadoEntitySnapshots`** - Content hash snapshots to detect actual changes (v1 only)

#### Enhanced POS Tables
The service adds `AvoqadoLastModifiedAt` timestamp columns to:
- **`tempcheques`** - Order headers (folio, total, customer, etc.)
- **`tempcheqdet`** - Order line items (products, quantities, prices)
- **`turnos`** - Shift information (open/close times, cashier)

#### Stored Procedures
- **`sp_TrackEntityChange`** - Records entity changes with timestamps and reasons
- **`sp_GetEntityChanges`** - Retrieves pending changes since last sync
- **`sp_UpdateEntitySnapshot`** - Updates content hash snapshots (v1 only)
- **`sp_CleanupStuckTracking`** - Maintenance procedure for stuck records

#### Database Triggers
- **`Trg_Avoqado_Orders`** - Tracks order creation, updates, and deletions
- **`Trg_Avoqado_OrderItems`** - Tracks individual item changes within orders
- **`Trg_Avoqado_Shifts`** - Tracks shift opening and closing events

### Entity ID Format
The service uses a hierarchical entity ID system:
- **Orders**: `{InstanceId}:{IdTurno}:{Folio}` (e.g., `abc123:45:1001`)
- **Order Items**: `{InstanceId}:{IdTurno}:{Folio}:{Movimiento}` (e.g., `abc123:45:1001:3`)
- **Shifts**: `{IdTurno}` (e.g., `45`)

## Architecture Overview

### Core Components
- **Producer** (`src/components/producer.ts`) - Polls database every 2 seconds, implements 2.5s debouncing for order updates, sends heartbeats every 60 seconds
- **Commander** (`src/components/commander.ts`) - Consumes commands from `pos_commands_exchange`, executes POS operations through adapters
- **Configuration Error Consumer** (`src/components/configurationErrorConsumer.ts`) - Handles venue ID validation errors with automatic recovery

### Core Infrastructure
- **Database** (`src/core/db.ts`) - SQL Server connection pool management
- **RabbitMQ** (`src/core/rabbitmq.ts`) - Message broker with exchange binding
- **Logger** (`src/core/logger.ts`) - Winston with daily rotation and structured logging
- **Service State Manager** (`src/core/serviceState.ts`) - State machine for service health
- **Configuration Manager** (`src/core/configurationManager.ts`) - Config validation and backup
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
- **Validation**: Automatic venue ID validation with fallback mechanisms
- **Backup System**: Maintains configuration history with rollback capability

## Key Technical Details

### Producer Architecture
- **Polling**: Executes `sp_GetEntityChanges` every 2 seconds with batching (max 100 results)
- **Debouncing**: Order updates batched for 2.5 seconds to reduce message volume
- **Event Types**: `created`, `updated`, `deleted` for orders; `created`, `updated`, `deleted` for items
- **Context-Aware**: Detects shift closures to prevent spurious order deletions

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

## Logging & Monitoring
- **Daily Rotation**: Separate files for info and error levels
- **Structured Logging**: Component-specific prefixes and context
- **Heartbeat Monitoring**: Regular status reports to central system
- **Windows Event Log**: Critical errors logged to system event log
- **Performance Metrics**: Database query times and message processing rates