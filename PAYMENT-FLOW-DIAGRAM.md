# Avoqado Payment Flow Architecture Diagram

## Complete Payment Flow

```mermaid
sequenceDiagram
    participant Customer
    participant AvoqadoApp as Avoqado App
    participant Backend as Avoqado Backend
    participant RabbitMQ
    participant WinService as Windows Service
    participant Adapter as SR11 Adapter
    participant SP as sp_ApplyPartialPayment
    participant DB as SQL Server Database

    Customer->>AvoqadoApp: Scan QR & Pay $7
    AvoqadoApp->>Backend: Process Payment
    Backend->>Backend: Map payment method to 'DEB'
    Backend->>RabbitMQ: Publish Payment Command
    Note over Backend,RabbitMQ: payment_method: 'DEB'<br/>amount: 7<br/>order_id: WorkspaceId

    RabbitMQ->>WinService: Consume Command
    WinService->>Adapter: applyPayment(WorkspaceId, 7, 'DEB')
    Adapter->>DB: Query folio by WorkspaceId
    DB-->>Adapter: folio: 1

    Adapter->>SP: EXEC sp_ApplyPartialPayment<br/>@Folio=1, @PaymentAmount=7,<br/>@PaymentMethod='DEB'

    Note over SP,DB: Transaction begins

    SP->>DB: SELECT total, subtotal, idturno<br/>FROM tempcheques WHERE folio=1
    DB-->>SP: total=777, idturno=0

    alt idturno = 0
        SP->>DB: SELECT idturno FROM turnos<br/>WHERE cierre IS NULL
        DB-->>SP: idturno=963
        SP->>DB: UPDATE tempcheques<br/>SET idturno=963 WHERE folio=1
        Note over SP: ✅ Shift Assignment Fix
    end

    SP->>DB: SELECT SUM(importe)<br/>FROM tempchequespagos WHERE folio=1
    DB-->>SP: PaidSoFar=0

    SP->>SP: Calculate @Remaining<br/>= 777 - (0 + 7) = 770

    SP->>DB: INSERT INTO tempchequespagos<br/>(folio, idformadepago='DEB',<br/>importe=7)
    Note over SP,DB: ✅ DEB (tipo=2) preserves amount

    alt Remaining > 0 (Partial Payment)
        SP->>SP: Calculate ratio<br/>DECIMAL(38,10): 770/777
        SP->>DB: UPDATE tempcheqdet<br/>SET cantidad = cantidad × ratio
        SP->>SP: Calculate new subtotal/tax<br/>from ORIGINAL values
        SP->>DB: UPDATE tempcheques<br/>SET total=770, subtotal=..., tax=...
        Note over SP: ✅ High Precision Fix
    else Remaining = 0 (Full Payment)
        SP->>DB: UPDATE tempcheques<br/>SET pagado=1
    end

    Note over SP,DB: Transaction commits

    SP-->>Adapter: Success=1, Remaining=770
    Adapter-->>WinService: Payment applied
    WinService->>DB: Poll sp_GetPendingChanges
    DB-->>WinService: Order UPDATE, Payment CREATE
    WinService->>RabbitMQ: Publish order.updated event
    RabbitMQ->>Backend: Consume event
    Backend->>Customer: Payment confirmed ✅
```

## Database Architecture - v11 WorkspaceId Model

```mermaid
graph TB
    subgraph "Each Entity Has Unique WorkspaceId"
        Order[tempcheques<br/>folio=3<br/>WorkspaceId=3E4D9070-...]
        Item1[tempcheqdet<br/>foliodet=3, movimiento=1<br/>WorkspaceId=309FF1B2-...]
        Item2[tempcheqdet<br/>foliodet=3, movimiento=2<br/>WorkspaceId=2FDB2D3F-...]
        Payment[tempchequespagos<br/>folio=3<br/>WorkspaceId=A1B2C3D4-...]
        Shift[turnos<br/>idturno=963<br/>WorkspaceId=994FEBE1-...]
    end

    Order -->|folio=3| Item1
    Order -->|folio=3| Item2
    Order -->|folio=3| Payment
    Order -->|idturno=963| Shift

    style Order fill:#e1f5e1
    style Item1 fill:#e3f2fd
    style Item2 fill:#e3f2fd
    style Payment fill:#fff3e0
    style Shift fill:#f3e5f5
```

## Entity ID Generation (v11)

```mermaid
flowchart TD
    Start[Trigger fires on table change]
    Start --> CheckVersion{Version >= 11.0?}

    CheckVersion -->|Yes v11| GetType[Get EntityType]
    CheckVersion -->|No v10| V10Format[Generate v10 format<br/>InstanceId:IdTurno:Folio:Mov]

    GetType --> OrderType{EntityType?}

    OrderType -->|order| QueryOrder[SELECT WorkspaceId<br/>FROM tempcheques<br/>WHERE folio=@Folio]
    OrderType -->|orderitem| QueryItem[SELECT WorkspaceId<br/>FROM tempcheqdet<br/>WHERE foliodet=@Folio<br/>AND movimiento=@Mov]
    OrderType -->|payment| QueryPayment[SELECT TOP 1 WorkspaceId<br/>FROM tempchequespagos<br/>WHERE folio=@Folio]
    OrderType -->|shift| QueryShift[SELECT WorkspaceId<br/>FROM turnos<br/>WHERE idturno=@IdTurno]

    QueryOrder --> V11Format[EntityId = WorkspaceId<br/>e.g., 309FF1B2-BE05-...]
    QueryItem --> V11Format
    QueryPayment --> V11Format
    QueryShift --> V11Format

    V11Format --> Insert[INSERT INTO AvoqadoTracking]
    V10Format --> Insert

    style V11Format fill:#c8e6c9
    style V10Format fill:#ffccbc
```

## Payment Method Types & Archiving

```mermaid
graph LR
    subgraph "Payment Methods in formasdepago"
        DEB[DEB<br/>TAR. DEBITO<br/>tipo=2 CARD]
        ACASH[ACASH<br/>AVOQADO CASH<br/>tipo=1 CASH]
        ACARD[ACARD<br/>AVOQADO CARD<br/>tipo=2 CARD]
        CRE[CRE<br/>CREDITO<br/>tipo=2 CARD]
    end

    subgraph "Shift Close Archiving"
        TempPayment[tempchequespagos<br/>idformadepago=DEB<br/>importe=7.00]
        ArchiveQuery[INSERT INTO chequespagos<br/>SELECT * FROM tempchequespagos p<br/>INNER JOIN tempcheques t<br/>ON p.folio = t.folio<br/>WHERE t.idturno = 963]
        ArchivedPayment[chequespagos<br/>idformadepago=DEB<br/>importe=7.00 ✅]
    end

    DEB -.->|✅ Used by Avoqado| TempPayment
    ACASH -.->|❌ Deprecated| TempPayment

    TempPayment -->|Shift Close| ArchiveQuery
    ArchiveQuery -->|tipo=2 preserved| ArchivedPayment

    style DEB fill:#c8e6c9
    style ACASH fill:#ffccbc
    style ArchivedPayment fill:#c8e6c9
```

## Shift Assignment Logic

```mermaid
flowchart TD
    Start[sp_ApplyPartialPayment called]
    Start --> GetOrder[SELECT idturno<br/>FROM tempcheques<br/>WHERE folio=@Folio]
    GetOrder --> CheckTurno{idturno = 0?}

    CheckTurno -->|No| ProceedPayment[Proceed with payment]
    CheckTurno -->|Yes| FindShift[SELECT idturno FROM turnos<br/>WHERE cierre IS NULL]

    FindShift --> HasShift{Open shift found?}
    HasShift -->|No| Error[RETURN ERROR:<br/>No open shift]
    HasShift -->|Yes| Assign[UPDATE tempcheques<br/>SET idturno = @OpenShiftId<br/>WHERE folio = @Folio]

    Assign --> Log[INSERT INTO AvoqadoDebugLog<br/>'Order assigned to shift XXX']
    Log --> ProceedPayment

    ProceedPayment --> InsertPayment[INSERT INTO tempchequespagos]
    InsertPayment --> CalcRatio[Calculate ratio with<br/>DECIMAL38,10 precision]
    CalcRatio --> UpdateQty[UPDATE tempcheqdet quantities]
    UpdateQty --> UpdateOrder[UPDATE tempcheques totals]
    UpdateOrder --> Commit[COMMIT]

    style Assign fill:#c8e6c9
    style Error fill:#ffccbc
    style Commit fill:#c8e6c9
```

## Precision Calculation (High Precision Fix)

```mermaid
flowchart TD
    Start[Payment Applied: $7 of $777]
    Start --> SaveOriginal[Save ORIGINAL values:<br/>@OriginalSubtotal<br/>@OriginalTax]

    SaveOriginal --> CalcRemaining[@Remaining = Total - PaidSoFar - Payment<br/>= 777 - 0 - 7 = 770]

    CalcRemaining --> CalcRatio[@RemainingRatio<br/>= DECIMAL38,10<br/>770 / 777<br/>= 0.9909909910]

    CalcRatio --> UpdateQty[UPDATE tempcheqdet<br/>cantidad = CAST<br/>cantidad × ratio<br/>AS DECIMAL18,6]

    UpdateQty --> CalcSubtotal[@NewSubtotal<br/>= ROUND<br/>OriginalSubtotal × ratio<br/>2 decimals]

    CalcSubtotal --> CalcTax[@NewTax<br/>= @Remaining - @NewSubtotal<br/>✅ Ensures subtotal + tax = total]

    CalcTax --> UpdateOrder[UPDATE tempcheques<br/>total = 770<br/>subtotal = NewSubtotal<br/>tax = NewTax]

    style CalcRatio fill:#e1f5e1
    style CalcTax fill:#e1f5e1
    style UpdateOrder fill:#c8e6c9
```

## Windows Service Components

```mermaid
graph TB
    subgraph "Windows Service Architecture"
        Main[main.ts<br/>Service Entry Point]
        Service[service.ts<br/>Orchestrator]

        subgraph "Core Components"
            Producer[producer.ts<br/>Polls DB every 2s<br/>Debounces order updates]
            Commander[commander.ts<br/>Consumes RabbitMQ commands<br/>Executes POS operations]
            ConfigConsumer[configurationErrorConsumer.ts<br/>Handles venue ID errors]
        end

        subgraph "Infrastructure"
            DB[db.ts<br/>SQL Server 2014 connection<br/>Pool management]
            RMQ[rabbitmq.ts<br/>Exchange binding<br/>Message routing]
            Logger[logger.ts<br/>Winston with rotation]
        end

        subgraph "Adapters"
            IAdapter[IPosAdapter<br/>Interface]
            SR11[SoftRestaurant11Adapter<br/>Implementation]
        end
    end

    Main --> Service
    Service --> Producer
    Service --> Commander
    Service --> ConfigConsumer

    Producer --> DB
    Producer --> RMQ
    Commander --> RMQ
    Commander --> SR11
    SR11 --> DB

    Producer -.-> Logger
    Commander -.-> Logger
    SR11 -.-> Logger

    style Producer fill:#e3f2fd
    style Commander fill:#fff3e0
    style SR11 fill:#f3e5f5
```

## Producer Event Flow (v11 Entity IDs)

```mermaid
sequenceDiagram
    participant DB as SQL Server
    participant Trigger as Database Trigger
    participant Track as AvoqadoTracking
    participant Producer as Producer (polling)
    participant Validate as Entity ID Validator
    participant Process as Event Processor
    participant RMQ as RabbitMQ

    DB->>Trigger: INSERT/UPDATE on tempcheqdet
    Trigger->>Trigger: fn_GetAvoqadoEntityIdWithWorkspace<br/>Query item's WorkspaceId
    Trigger->>Track: INSERT EntityId=309FF1B2-...<br/>EntityType=orderitem

    loop Every 2 seconds
        Producer->>Track: sp_GetPendingChanges<br/>(max 100 results)
        Track-->>Producer: EntityId=309FF1B2-..., Type=orderitem

        Producer->>Validate: Split EntityId by ':'
        Validate->>Validate: parts.length === 1? ✅
        Note over Validate: v11 format validation

        Validate->>Process: processOrderItemChangeV11
        Process->>DB: SELECT * FROM tempcheqdet<br/>WHERE WorkspaceId = '309FF1B2-...'
        DB-->>Process: Item data + parent order WorkspaceId

        Process->>Process: Build payload with<br/>externalId=309FF1B2-...<br/>parentOrderExternalId=3E4D9070-...

        Process->>RMQ: Publish orderitem.created event
        Process->>Track: Mark as processed
    end

    style Validate fill:#c8e6c9
    style Process fill:#e3f2fd
```

## Error Handling & Recovery

```mermaid
flowchart TD
    Start[Payment Command Received]
    Start --> ValidateVenue{Venue ID valid?}

    ValidateVenue -->|No| PublishError[Publish configuration.error<br/>to RabbitMQ]
    PublishError --> StopHeartbeats[Stop heartbeats<br/>Service state: CONFIG_ERROR]
    StopHeartbeats --> WaitRecovery[Wait for recovery command]
    WaitRecovery --> ValidateVenue

    ValidateVenue -->|Yes| ValidateDB{Database<br/>connection OK?}
    ValidateDB -->|No| RetryDB[Retry with exponential backoff]
    RetryDB --> ValidateDB

    ValidateDB -->|Yes| ValidateShift{Open shift<br/>exists?}
    ValidateShift -->|No| ErrorNoShift[Return error:<br/>No open shift]
    ValidateShift -->|Yes| ProcessPayment[Execute sp_ApplyPartialPayment]

    ProcessPayment --> Success{Success?}
    Success -->|Yes| UpdateTracking[Update AvoqadoTracking]
    UpdateTracking --> PublishEvent[Publish order.updated event]

    Success -->|No| LogError[Log to AvoqadoDebugLog]
    LogError --> Rollback[ROLLBACK transaction]
    Rollback --> ReturnError[Return error to backend]

    style ProcessPayment fill:#e3f2fd
    style PublishEvent fill:#c8e6c9
    style ErrorNoShift fill:#ffccbc
    style Rollback fill:#ffccbc
```

## Key Metrics & Monitoring

```mermaid
graph LR
    subgraph "Performance Metrics"
        Polling[Producer Polling<br/>Every 2 seconds<br/>Max 100 records]
        Debounce[Order Debouncing<br/>2.5 second window<br/>Reduces message volume]
        Heartbeat[Heartbeat<br/>Every 60 seconds<br/>Service health check]
    end

    subgraph "Database Operations"
        EntityID[Entity ID Generation<br/>< 1ms overhead<br/>DECIMAL(38,10) precision]
        Payment[Payment Processing<br/>Transaction safe<br/>High precision ratio calc]
        Tracking[Change Tracking<br/>Indexed by Timestamp<br/>Processed flag]
    end

    subgraph "Diagnostics"
        DebugLog[AvoqadoDebugLog<br/>All payment operations<br/>Indexed by Timestamp]
        Verification[00-VERIFICATION.sql<br/>System health check<br/>Trigger status validation]
        Diagnostic[03-DIAGNOSTICS.sql<br/>Performance analysis<br/>Cleanup recommendations]
    end

    Polling -.-> Tracking
    Payment -.-> DebugLog
    EntityID -.-> Tracking

    style EntityID fill:#c8e6c9
    style Payment fill:#c8e6c9
    style DebugLog fill:#e3f2fd
```

---

## How to Use This Diagram

1. **Copy the code blocks above** (each ```mermaid block)
2. **Paste into any Mermaid tool**:
   - Online: https://mermaid.live/
   - VS Code: Mermaid Preview extension
   - Documentation: Markdown files support Mermaid
   - Draw.io: Import as Mermaid

3. **Export options**:
   - PNG/SVG for presentations
   - PDF for documentation
   - Editable format for updates

## Diagram Sections

1. **Complete Payment Flow** - End-to-end sequence from customer to database
2. **Database Architecture** - v11 WorkspaceId model with unique IDs per entity
3. **Entity ID Generation** - SQL function logic for v10/v11 formats
4. **Payment Method Types** - DEB vs deprecated methods and archiving behavior
5. **Shift Assignment Logic** - Automatic idturno=0 → current shift assignment
6. **Precision Calculation** - High precision fix using DECIMAL(38,10)
7. **Windows Service Components** - Architecture and component relationships
8. **Producer Event Flow** - v11 Entity ID validation and processing
9. **Error Handling** - Configuration errors, database failures, recovery
10. **Key Metrics** - Performance characteristics and monitoring tools

---

**Generated**: 2025-10-01
**Version**: v2.5.0
**Status**: Production Ready ✅
