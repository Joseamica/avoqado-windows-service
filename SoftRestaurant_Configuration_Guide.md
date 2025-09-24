# SoftRestaurant v11 Configuration Guide
## Database Analysis and Onboarding Documentation

---

## 📋 Table of Contents
1. [Database Connection](#database-connection)
2. [Invoice Series Management](#invoice-series-management)
3. [Sales Notes (Notas de Venta)](#sales-notes-notas-de-venta)
4. [Payment Configuration](#payment-configuration)
5. [Parameter Tables Analysis](#parameter-tables-analysis)
6. [Onboarding Checklist](#onboarding-checklist)

---

## Database Connection
- **Server**: 100.80.118.68:49759
- **Instance**: NATIONALSOFT
- **Database**: avov2
- **Authentication**: SQL Server Auth (sa/National09)
- **Multi-tenant**: Yes (1000+ active WorkspaceIds)

---

## Multi-Tenant Architecture

### WorkspaceId Management
SoftRestaurant v11 uses `WorkspaceId` (UUID) for complete tenant isolation.

#### Key Facts:
- **1000+ active tenants** in the current database
- Each tenant has a unique GUID WorkspaceId
- WorkspaceId is present in most transactional tables
- Ensures data isolation between different restaurant clients

#### Tables with WorkspaceId:
- `cheques` - Sales transactions
- `facturas` - Invoices
- `formasdepago` - Payment methods
- `foliosfacturas` - Invoice series configuration
- `chequespagos` - Payment records
- Most other transactional and configuration tables

#### Critical Rule:
**NEVER mix WorkspaceIds between different clients**. Each client must maintain their unique WorkspaceId across all tables for proper data isolation.

---

## Invoice Series Management

### Table: `foliosfacturas`
Controls invoice numbering and series configuration.

#### Key Fields:
- `serie`: Invoice series letter (e.g., "A", "B", "C")
- `ultimofolio`: Last used folio number in the series
- `consecutivoinicio`: Starting number for the series (usually 1)
- `consecutivofin`: Maximum number for the series (99,999,999)
- `electronico`: Electronic invoicing enabled (1 = yes)
- `tipoesquema`: Schema type (3 = CFDI 4.0)
- `estatus`: Series status (1 = active)
- `idempresa`: Company ID
- `WorkspaceId`: Multi-tenant workspace identifier

### Current Configuration Example:
```sql
Serie: A
Last Folio: 1004
Range: 1 - 99,999,999
Electronic: Yes (CFDI 4.0)
Status: Active
```

### Important Notes:
- Each client can have different series (A, B, C, etc.)
- Series can run in parallel
- Electronic invoicing (CFDI) configured per series
- Must not overlap folio ranges between series

---

## Sales Notes (Notas de Venta)

### Table: `cheques`
Stores all sales transactions (despite the name "cheques").

#### Key Fields:
- `folio`: Sequential sales note number (bigint)
- `numcheque`: Internal check/ticket number
- `fecha`: Transaction date
- `facturado`: Boolean (1 = has been invoiced)
- `total`: Transaction total amount
- `WorkspaceId`: Multi-tenant identifier
- `seriefolio`: Optional series for sales notes

### Characteristics:
- Independent sequential numbering from invoices
- No mandatory series prefix
- Current maximum folio: 24481
- Can be converted to invoices later

---

## Payment Configuration

### Table: `formasdepago`
Defines all available payment methods in the system.

#### Key Fields:
- `idformadepago`: Unique payment method ID
- `descripcion`: Display name
- `tipo`: Payment type (1=Cash, 2=Card, 4=Other)
- `aceptapropina`: Accepts tips (1=yes)
- `visible`: Show in POS (1=yes)
- `idformapago_SAT`: SAT code for tax reporting
- `WorkspaceId`: Multi-tenant identifier

#### Current Payment Methods:
```
AEF     - EFECTIVO (Cash)           - Type 1, SAT: 01
DEB     - TAR. DEBITO (Debit)       - Type 2, SAT: 04
CRE     - TAR. CREDITO (Credit)     - Type 2, SAT: 04
08      - POR PAGAR (On Account)    - Type 4, SAT: 99
ACASH   - AVOQADO CASH              - Type 1, SAT: 01
10      - RAPPI                     - Type 4, SAT: 03
11      - UBER                      - Type 4, SAT: 01
```

### Table: `chequespagos`
Records payment details for each sale.

#### Payment Types:
- **Type 1**: Cash payments
- **Type 2**: Card payments (credit/debit)
- **Type 4**: Other (delivery apps, on account, etc.)

---

## Parameter Tables Analysis

### Table: `parametros` (Main Configuration)

#### Key Tax Configuration:
- `impuesto1`: 16.00 (IVA rate)
- `nombreimpuesto1`: "IVA:"
- `impuesto2`: 0.00 (not used)
- `impuesto3`: 0.00 (not used)

#### MIT Payment Terminal Settings:
- `mitclavecompania`: Company key (currently NULL)
- `mitclavesucursal`: Branch key (currently NULL)
- `mitusuario`: Terminal user (currently NULL)
- `mitnumeroafiliacion`: Merchant ID (currently NULL)
- `miturl`: Terminal URL (currently NULL)

#### CFDI Electronic Invoicing:
- `femex`: 1 (Electronic invoicing enabled)
- `femextipoesquema`: 3 (CFDI 4.0)
- `femexrutaarchivokey`: Key file path
- `femexrutaarchivocer`: Certificate file path

#### Other Important Settings:
- `solicitarnotaofactura`: 0 (Don't ask for invoice at sale)
- `facturasumarpropina`: 0 (Don't include tip in invoice)
- `cambio`: Currency code ("M.N.")

### Table: `parametros2` (Extended Configuration)

#### Key Settings:
- `foliocxc`: 81 (Current accounts receivable folio)
- `foliomovtoscaja`: 4635 (Cash movements folio)
- `idformadepagocompramonex`: Default payment for purchases
- `tipocapturadirecciones`: Address capture type
- `pac`: 2 (PAC provider for electronic invoicing)
- `femexarchivokey_pem`: PEM key file (encrypted)
- `femexarchivocer_pem`: PEM certificate (encrypted)

### Table: `parametros3` (Additional Settings)

#### Key Features:
- `versionfacturacion`: 4.000000 (CFDI version)
- `idconcepto_SAT`: 90101501 (Default SAT product code)
- `complementopago`: 0 (Payment complement disabled)
- `dev_estrateca`: 0 (Estrateca integration)
- `multiformaspago`: 0 (Multiple payment forms)

---

## POS Terminal Configuration

### Table: `pos_settings`
Station-specific settings.

#### Per-Station Configuration:
- `idestacion`: Station/terminal ID
- `sync_activo`: Synchronization status
- `cashdro_*`: Cash drawer settings
- `criterio_busqueda_catalogos`: Search criteria

#### Known Stations:
```
DESKTOP-1601QUU
DESKTOP-7
DESKTOP-ED6J9CU (sync active)
JOSEANTONIO721A
SALON-SISAO
TERRAZA-SISAO
```

---

## Enterprise Configuration

### Table: `empresas`
Company/restaurant information.

#### Key Fields:
- `idempresa`: "0000000001" (Company ID)
- `rfc`: Tax ID (encrypted)
- `regimen`: "General de Ley Personas Morales"
- `idregimen_SAT`: 601
- All sensitive data is encrypted

---

## Onboarding Checklist for New Clients

### 1. Pre-Onboarding Assessment
- [ ] **Workspace Identification**: Verify client's WorkspaceId for multi-tenant isolation
- [ ] **Current System Analysis**:
  - [ ] Check if migrating from another system
  - [ ] Note current invoice folio numbers if migrating
  - [ ] Identify payment methods currently used
  - [ ] Document tax requirements (IVA rate, other taxes)

### 2. Invoice Series Configuration (`foliosfacturas`)

#### For clients using Series A:
```sql
-- Check current configuration
SELECT * FROM foliosfacturas WHERE serie = 'A'

-- Update starting folio if needed (NEVER decrease)
UPDATE foliosfacturas
SET ultimofolio = [last_used_number]
WHERE serie = 'A' AND idempresa = '0000000001'
```

#### For clients NOT using Series A (using B, C, etc.):
```sql
-- Insert new series configuration
INSERT INTO foliosfacturas (
  serie, ultimofolio, consecutivoinicio, consecutivofin,
  electronico, estatus, tipoesquema, idempresa, WorkspaceId
) VALUES (
  'B', 0, 1, 99999999, 1, 1, 3, '0000000001', '[CLIENT_WORKSPACE_ID]'
)
```

### 3. Payment Methods Configuration (`formasdepago`)

#### Essential Payment Methods:
- [ ] **Cash (EFECTIVO)**: Already configured as AEF
- [ ] **Credit Card**: Already configured as CRE
- [ ] **Debit Card**: Already configured as DEB
- [ ] **Avoqado Cash**: Already configured as ACASH

#### Add Client-Specific Payment Methods:
```sql
-- Example: Add new payment method
INSERT INTO formasdepago (
  idformadepago, descripcion, tipo, tipodecambio,
  aceptapropina, visible, idformapago_SAT, WorkspaceId
) VALUES (
  'NEWPAY', 'PAYMENT NAME', 4, 1.0000,
  0, 1, '01', '[CLIENT_WORKSPACE_ID]'
)
```

### 4. Tax Configuration (`parametros`)
- [ ] Verify IVA rate (currently 16%)
- [ ] Configure additional taxes if needed
- [ ] Set up CFDI electronic invoicing if required

### 5. Terminal/POS Configuration (`pos_settings`)
- [ ] Register each POS terminal/station
- [ ] Configure synchronization settings
- [ ] Set up cash drawer if applicable

### 6. MIT Payment Terminal Setup (if using card processor)
```sql
-- Update parametros for MIT configuration
UPDATE parametros SET
  mitclavecompania = '[COMPANY_KEY]',
  mitclavesucursal = '[BRANCH_KEY]',
  mitusuario = '[TERMINAL_USER]',
  mitnumeroafiliacion = '[MERCHANT_ID]',
  miturl = '[TERMINAL_URL]'
```

### 7. Critical Configuration Rules

#### ⚠️ NEVER DO:
- **NEVER** decrease `ultimofolio` in `foliosfacturas`
- **NEVER** modify existing `WorkspaceId` values
- **NEVER** delete payment records from `chequespagos`
- **NEVER** change `idempresa` for existing records
- **NEVER** overlap invoice series ranges

#### ✅ ALWAYS DO:
- **ALWAYS** backup before configuration changes
- **ALWAYS** test in a staging environment first
- **ALWAYS** maintain WorkspaceId consistency
- **ALWAYS** verify series don't conflict
- **ALWAYS** increment folios sequentially

### 8. Post-Configuration Validation
```sql
-- Verify invoice series
SELECT serie, ultimofolio, estatus FROM foliosfacturas

-- Check payment methods
SELECT idformadepago, descripcion, visible FROM formasdepago

-- Verify tax configuration
SELECT impuesto1, nombreimpuesto1 FROM parametros

-- Check POS terminals
SELECT idestacion, sync_activo FROM pos_settings

-- Validate recent transactions
SELECT TOP 10 folio, fecha, total FROM cheques ORDER BY fecha DESC
```

### 9. Integration Notes

#### For Avoqado Integration:
- Sales notes (`cheques.folio`) are independent from invoice folios
- Invoice series (`facturas.serie` + `facturas.folio`) for fiscal documents
- Payment methods must match between systems
- WorkspaceId ensures data isolation

#### Common Integration Patterns:
1. **Sales Flow**: cheques → facturado flag → facturas
2. **Payment Flow**: formasdepago → chequespagos
3. **Series Management**: foliosfacturas controls numbering

---

## Troubleshooting Common Issues

### Issue: "Invoice folio already exists"
**Solution**: Check and update `ultimofolio` in `foliosfacturas`

### Issue: "Payment method not found"
**Solution**: Verify payment method exists in `formasdepago` with correct WorkspaceId

### Issue: "Tax calculation incorrect"
**Solution**: Check `impuesto1` value in `parametros` table

### Issue: "Series not available"
**Solution**: Insert new series in `foliosfacturas` with proper configuration

---

## Summary: Key Onboarding Considerations

### For New Avoqado Clients Using SoftRestaurant

1. **Workspace Isolation**
   - Each client MUST have a unique WorkspaceId (GUID)
   - This ID ensures complete data separation in the multi-tenant database
   - Never share WorkspaceIds between different clients

2. **Invoice Series Management**
   - Some clients use Serie A, others may use B, C, etc.
   - Check `foliosfacturas` table for existing series configuration
   - Never decrease folio numbers - only increment

3. **Payment Configuration**
   - Standard payment methods (cash, credit, debit) already configured
   - Add client-specific payment methods as needed (delivery apps, etc.)
   - MIT terminal settings in `parametros` for card processing

4. **Configuration Tables**
   - `parametros` - Main system configuration (tax rates, CFDI settings)
   - `parametros2` - Extended settings (PAC, certificates)
   - `parametros3` - Additional features (multi-payment, integrations)

5. **Integration Best Practices**
   - Sales notes in `cheques` table (independent numbering)
   - Invoices in `facturas` table (series-based numbering)
   - Always respect existing configurations
   - Test in staging before production deployment

---

*Last Updated: 2025-09-23*
*Database: SoftRestaurant v11 (avov2)*
*Documentation created for Avoqado integration project*