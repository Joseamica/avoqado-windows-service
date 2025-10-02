# SoftRestaurant v11 Master Documentation
## Complete Reference for Avoqado Integration

---

## 📑 Table of Contents

1. [Overview](#overview)
2. [Documentation Structure](#documentation-structure)
3. [Core System Understanding](#core-system-understanding)
4. [Integration Architecture](#integration-architecture)
5. [Database Reference](#database-reference)
6. [Business Flow Documentation](#business-flow-documentation)
7. [Configuration Management](#configuration-management)
8. [Troubleshooting & Entity Resolution](#troubleshooting--entity-resolution)
9. [File Organization](#file-organization)

---

## Overview

This master documentation serves as the central reference for understanding SoftRestaurant v11 POS system integration with Avoqado. It consolidates all technical knowledge, database analysis, and implementation details necessary for development and maintenance.

### System Characteristics

- **Database**: SQL Server 2014 Express Edition (32-bit)
- **Architecture**: Multi-tenant with WorkspaceId isolation
- **Tenants**: 1000+ active restaurants
- **Tables**: 366 tables with 189 foreign key relationships
- **Version**: SoftRestaurant v11

---

## Documentation Structure

### 📁 Primary Documentation Files

#### 1. Configuration & Onboarding
- **`SoftRestaurant_Configuration_Guide.md`** - Complete guide for client onboarding
  - Invoice series management (foliosfacturas)
  - Payment methods configuration (formasdepago)
  - Multi-tenant WorkspaceId management
  - Parameter tables analysis (parametros, parametros2, parametros3)
  - Onboarding checklist and validation queries

#### 2. Technical Solutions
- **`SOFTRESTAURANT_ENTITY_RESOLUTION.md`** - Entity resolution system documentation
  - Handles SoftRestaurant's unique idturno=0 → real idturno transition
  - Smart order resolution to prevent duplicates
  - Context-aware deletion during shift closures
  - Implementation in producer and backend services

### 📁 Database Reference (info-softrest11/)

#### 3. Database Schema Information
- **`info-softrest11/README.md`** - Complete overview of database reference structure
- **`info-softrest11/database-schema/`**:
  - `table-definitions.csv` - All 366 tables
  - `table-relationships.csv` - Complete column definitions
  - `core-relationships.csv` - Critical table relationships
  - `table-create-statements.sql` - Full schema recreation scripts
  - `constraints/` - Foreign keys, indexes, primary keys

#### 4. Business Flow Analysis
- **`info-softrest11/sql-traces/`**:
  - `shift-close-flow.sql` - Complete shift closure process (203ms timing)
  - `order-lifecycle-flow.sql` - Full order creation to payment flow
  - Real SQL Server Profiler traces from production

#### 5. Table Analysis
- **`info-softrest11/table-analysis/`**:
  - `turnos-table-details.sql` - Critical shifts table analysis
  - Documents dual-key architecture (idturnointerno vs idturno)

### 📁 Integration Database Objects (analysis/db/)

#### 6. Avoqado Integration Components
- **Stored Procedures**:
  - `sp_AddPartialPayment.sql` - Partial payment processing
  - `sp_ProcessPartialPayments.sql` - Payment batch processing
  - `sp_GenerateEntityId.sql` - Entity ID generation
  - `sp_GetPendingChanges.sql` - Retrieves changes for sync
  - `sp_MarkChangesProcessed.sql` - Marks changes as processed

- **Functions**:
  - `fn_CanCompleteOrderPayment.sql` - Payment validation
  - `fn_GetPartialPaymentsTotal.sql` - Payment calculations
  - `fn_GetSoftRestaurantVersion.sql` - Version detection

- **Triggers**:
  - `Trg_Avoqado_Orders.sql` - Order change tracking
  - `Trg_Avoqado_OrderItems.sql` - Order item tracking
  - `Trg_Avoqado_Shifts.sql` - Shift tracking

- **Tables**:
  - `AvoqadoEntityTracking` - Change tracking
  - `AvoqadoPartialPayments` - Partial payment management
  - `AvoqadoInstanceInfo` - Instance information

---

## Core System Understanding

### 1. Entity ID Format
```
Orders:      {InstanceId}:{IdTurno}:{Folio}
Order Items: {InstanceId}:{IdTurno}:{Folio}:{Movimiento}
Shifts:      {IdTurno}
```

### 2. Key Tables Architecture

#### Sales Flow:
```
turnos (shifts) → tempcheques (orders) → tempcheqdet (order items) → tempchequespagos (payments)
```

#### Archival Flow:
```
temp* tables → permanent tables (cheques, cheqdet, chequespagos) → temp* cleanup
```

### 3. Multi-Tenant Isolation
- **WorkspaceId**: UUID for complete tenant separation
- **Present in**: All transactional and configuration tables
- **Critical Rule**: Never mix WorkspaceIds between clients

### 4. Invoice Series Management
- **Sales Notes**: Sequential numbering in `cheques` table
- **Invoices**: Series-based numbering (A, B, C) in `facturas` table
- **Configuration**: `foliosfacturas` table controls series ranges

---

## Integration Architecture

### Data Flow Pattern
1. **SoftRestaurant POS** generates transactions
2. **Windows Service** (Producer) detects changes via triggers
3. **RabbitMQ** queues changes for processing
4. **Backend Service** (Consumer) processes changes
5. **Avoqado API** receives processed data

### Entity Resolution System
Handles SoftRestaurant's unique behavior:
- Order creation with `idturno=0`
- Order payment with real `idturno`
- Smart resolution prevents duplicate orders

### Payment Processing
- **Partial Payments**: Managed via `AvoqadoPartialPayments` table
- **Payment Methods**: Configured in `formasdepago` table
- **TPV Integration**: MIT terminal configuration in `parametros`

---

## Database Reference

### Critical Tables

#### Transaction Tables:
- **`tempcheques`** - Active orders (temp during shift)
- **`tempcheqdet`** - Active order items
- **`tempchequespagos`** - Active payments
- **`turnos`** - Shifts management

#### Permanent Tables:
- **`cheques`** - Archived orders
- **`cheqdet`** - Archived order items
- **`chequespagos`** - Archived payments
- **`facturas`** - Invoices

#### Configuration Tables:
- **`foliosfacturas`** - Invoice series configuration
- **`formasdepago`** - Payment methods
- **`parametros`** - Main system configuration
- **`parametros2`** - Extended configuration
- **`parametros3`** - Additional features

#### Integration Tables:
- **`AvoqadoEntityTracking`** - Change tracking
- **`AvoqadoPartialPayments`** - Partial payments
- **`AvoqadoInstanceInfo`** - Instance management

### Performance Characteristics
- **Shift Close**: ~203ms for complete archival process
- **Order Creation**: Real-time via triggers
- **Payment Processing**: Batch processing for efficiency

---

## Business Flow Documentation

### 1. Shift Operations
**File**: `info-softrest11/sql-traces/shift-close-flow.sql`

**Process**:
1. Shift closure triggered
2. Archive: `temp*` → permanent tables
3. Cleanup temporary tables
4. Update shift status
5. Performance: 203ms complete cycle

### 2. Order Lifecycle
**File**: `info-softrest11/sql-traces/order-lifecycle-flow.sql`

**Process**:
1. Shift opening
2. Order creation (`idturno=0`)
3. Add order items
4. Print receipt
5. Payment processing (real `idturno`)
6. Shift archival

### 3. Payment Processing
**Files**: `analysis/db/sp_AddPartialPayment.sql`, `sp_ProcessPartialPayments.sql`

**Features**:
- Partial payment support
- Multiple payment methods
- Payment validation
- External payment ID tracking

---

## Configuration Management

### New Client Onboarding Process

#### 1. Workspace Setup
```sql
-- Verify unique WorkspaceId for new client
SELECT DISTINCT WorkspaceId FROM cheques
WHERE WorkspaceId = '[NEW_CLIENT_WORKSPACE_ID]'
```

#### 2. Invoice Series Configuration
```sql
-- For clients using Serie B (not A)
INSERT INTO foliosfacturas (
  serie, ultimofolio, consecutivoinicio, consecutivofin,
  electronico, estatus, tipoesquema, idempresa, WorkspaceId
) VALUES (
  'B', 0, 1, 99999999, 1, 1, 3, '0000000001', '[CLIENT_WORKSPACE_ID]'
)
```

#### 3. Payment Methods Setup
```sql
-- Standard payment methods already configured:
-- AEF (Cash), CRE (Credit), DEB (Debit), ACASH (Avoqado Cash)
-- Add client-specific methods as needed
```

#### 4. Critical Rules
- **NEVER** decrease `ultimofolio` numbers
- **NEVER** mix WorkspaceIds between clients
- **ALWAYS** test in staging before production
- **ALWAYS** backup before configuration changes

### 🕐 Fiscal Day Configuration (CRITICAL)

#### Overview
SoftRestaurant uses a **fiscal day cycle** that differs from calendar days. This configuration is stored in the `configuracion` table and determines when the system considers a "new business day" to begin.

**Table**: `configuracion`

```sql
SELECT cortezinicio, cortezfin, cortezfindiasiguiente FROM configuracion
-- Results:
-- cortezinicio: 06:00:00 AM        (fiscal day starts)
-- cortezfin: 05:59:59 AM           (fiscal day ends)
-- cortezfindiasiguiente: 1         (end time is next calendar day)
```

#### What This Means
- **Fiscal day window**: 6:00 AM to 5:59:59 AM (next day)
- All sales between 6:00 AM and 5:59:59 AM are grouped together for reporting
- Late-night sales (12 AM - 5:59 AM) belong to the **previous** business day
- A sale at 2 AM on January 2nd appears in the January 1st fiscal day report

#### Counter Behavior
- `idturno` in `turnos` table: **Never resets** - increments indefinitely (1, 2, 3...)
- `ultimofolio` in `folios` table: **Never resets** - continues forever
- `ultimaorden` in `folios` table: **Resets to 0** on shift close
- `ultimofolioproduccion` in `folios` table: **Resets to 0** on shift close

#### Impact on Client Onboarding
- Set client expectations: Reports use fiscal day (6 AM start), not calendar day
- Late-night operations: Sales after midnight belong to previous fiscal day
- Shift closures should ideally occur within fiscal day window
- Related setting: `parametros2.cierrediarioaperturarturno = 1` enables automatic daily shift management

**Full Details**: See `SoftRestaurant_Configuration_Guide.md` - Fiscal Day Configuration section

---

## Troubleshooting & Entity Resolution

### Common Issues & Solutions

#### 1. "Invoice folio already exists"
**File**: `SoftRestaurant_Configuration_Guide.md` - Troubleshooting section
**Solution**: Check and update `ultimofolio` in `foliosfacturas`

#### 2. Duplicate Orders
**File**: `SOFTRESTAURANT_ENTITY_RESOLUTION.md`
**Solution**: Smart entity resolution system handles `idturno=0` transitions

#### 3. Payment Processing Issues
**Files**: `analysis/db/fn_CanCompleteOrderPayment.sql`
**Solution**: Validate payment methods and partial payment totals

#### 4. Series Configuration Problems
**Solution**: Verify series don't overlap, check WorkspaceId consistency

### Monitoring & Debugging

#### Log Messages:
- `🔍 SmartResolution] Buscando orden huérfana con idturno=0`
- `🎯 SmartResolution] ¡Orden huérfana encontrada!`
- `Producer-Context] Ignorando eliminación... turno cerrado`

#### Key Metrics:
- Order creation vs payment processing rates
- Duplicate order detection rates
- Shift closure performance (target: <300ms)

---

## File Organization

### Documentation Structure
```
avoqado-windows-service/
├── docs/
│   └── SoftRestaurant_Master_Documentation.md    # This file
├── SoftRestaurant_Configuration_Guide.md         # Configuration & onboarding
├── SOFTRESTAURANT_ENTITY_RESOLUTION.md          # Technical solutions
├── info-softrest11/                             # Database reference
│   ├── README.md                                # Overview (Spanish)
│   ├── database-schema/                         # Schema information
│   │   ├── table-definitions.csv               # All tables
│   │   ├── table-relationships.csv             # Columns & types
│   │   ├── core-relationships.csv              # Key relationships
│   │   ├── table-create-statements.sql         # Recreation scripts
│   │   └── constraints/                        # Foreign keys, indexes
│   ├── sql-traces/                             # Business flows
│   │   ├── shift-close-flow.sql                # Shift operations
│   │   └── order-lifecycle-flow.sql            # Order processes
│   └── table-analysis/                         # Specific analysis
│       └── turnos-table-details.sql            # Shifts table
└── analysis/db/                                # Integration objects
    ├── sp_*.sql                                # Stored procedures
    ├── fn_*.sql                                # Functions
    ├── Trg_*.sql                               # Triggers
    └── *_columns.txt                           # Table structures
```

### File Status & Deprecation
- **Active**: All files are current and relevant
- **No deprecated files identified**
- **Maintenance**: Regular updates needed for configuration guides
- **Reference**: Database schema files are read-only historical reference

### Usage Patterns
```bash
# Quick table lookup
grep -i "tempcheques" info-softrest11/database-schema/table-definitions.csv

# Find relationships
grep -i "turnos" info-softrest11/database-schema/constraints/foreign-keys.csv

# Analyze business flows
grep -i "UPDATE turnos" info-softrest11/sql-traces/shift-close-flow.sql

# Check integration objects
ls analysis/db/sp_*.sql
```

---

## Best Practices

### Development
1. **Always reference this master documentation first**
2. **Use existing stored procedures and functions**
3. **Follow WorkspaceId isolation patterns**
4. **Test entity resolution scenarios**
5. **Monitor shift closure performance**

### Configuration
1. **Follow onboarding checklist exactly**
2. **Validate all changes in staging**
3. **Never modify existing client configurations**
4. **Document all custom payment methods**
5. **Maintain series number sequence**

### Troubleshooting
1. **Check entity resolution logs first**
2. **Verify WorkspaceId consistency**
3. **Review business flow traces**
4. **Validate payment method configuration**
5. **Monitor performance metrics**

---

*Last Updated: 2025-09-23*
*Maintainer: Avoqado Development Team*
*Database: SoftRestaurant v11 (avov2)*

---

## Quick Reference Links

- [Configuration Guide](../SoftRestaurant_Configuration_Guide.md)
- [Entity Resolution](../SOFTRESTAURANT_ENTITY_RESOLUTION.md)
- [Database Schema](../info-softrest11/database-schema/)
- [Business Flows](../info-softrest11/sql-traces/)
- [Integration Objects](../analysis/db/)