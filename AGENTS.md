# AGENTS.md

## Purpose
- Provide ChatGPT (Codex) with repository-specific guidance when implementing, reviewing, or documenting changes.
- Use this document together with `CLAUDE.md`, `docs/SoftRestaurant_Master_Documentation.md`, and the SQL scripts inside `scripts/sql`.

## Project Overview
- Windows service written in TypeScript/Node.js that syncs SoftRestaurant POS data with the Avoqado platform in near real time.
- Producer polls the SQL Server 2014 database for changes and publishes events to RabbitMQ; Commander consumes Avoqado commands and applies them to the POS.
- Supports SoftRestaurant v11 (WorkspaceId) today, with compatibility logic for v10 entity identifiers.
- Runs as a Windows background service via `node-windows`, but can also run in development mode with hot reload.

## Runtime Architecture

### Service bootstrap
- `startApp` (`src/service.ts:11`) initializes the logger, loads configuration, connects to SQL Server and RabbitMQ, starts the configuration-error consumer, commander, and producer, and records state transitions in `serviceStateManager`.
- `shutdown` (`src/service.ts:43`) handles SIGINT/SIGTERM by stopping the management console, producer, configuration-error consumer, updating service state, and closing RabbitMQ/SQL connections before exiting.
- `src/main.ts:5` installs or removes the Windows service wrapper, and runs `service.js` when launched by the Windows Service Control Manager.

### Producer
- Heartbeats are emitted by `sendHeartbeat` (`src/components/producer.ts:36`) every 60s when the service is healthy.
- Order updates are debounced for 2.5s in `debounceAndSendOrderUpdate` (`src/components/producer.ts:71`) to collapse rapid changes into one publish.
- `pollForChanges` (`src/components/producer.ts:107`) executes `sp_GetPendingChanges`, enriches context (e.g., closed shifts), routes each record to an entity-specific processor, and acknowledges processed IDs through `sp_MarkChangesProcessed`.
- `processOrderChange` and its v10/v11 helpers (`src/components/producer.ts:331`) construct payloads from `tempcheques`, `tempcheqdet`, related staff/customer data, and guard against false deletes during shift close.
- `processOrderItemChange` (`src/components/producer.ts:589`) and `processShiftChange` (`src/components/producer.ts:735`) publish order-item and shift events, mapping SoftRestaurant fields to Avoqado schemas.
- `detectSoftRestaurantVersion` (`src/components/producer.ts:848`) reads `parametros2.versiondb`, stores the result via `updateDetectedVersion`, and `startProducer` (`src/components/producer.ts:953`) launches polling and heartbeat loops while marking the service RUNNING.

### Commander
- `handleCommand` (`src/components/commander.ts:18`) parses RabbitMQ messages, validates payloads, and dispatches to the POS adapter (`SoftRestaurant11Adapter`) for order, item, payment, and shift operations.
- `startCommander` (`src/components/commander.ts:134`) binds a venue-specific queue to `pos_commands_exchange` and selects the proper adapter based on `config.posVersion`.

### Configuration error consumer
- `startConfigurationErrorConsumer` (`src/components/configurationErrorConsumer.ts:179`) creates an instance-specific queue bound to `command.{posType}.configuration.error`.
- Consecutive configuration errors are tracked; after three strikes, the consumer stops heartbeats, raises Windows notifications, transitions the service into `CONFIGURATION_ERROR`, and persists context for the operator.

### Connection resilience
- `ConnectionResilienceManager` (`src/core/connectionResilience.ts:7`) runs 30-second health checks, opens a circuit breaker on repeated failures, tears down and rebuilds SQL/RabbitMQ connections, restarts the configuration-error consumer, and restarts the producer when the service should stay RUNNING.
- `serviceStateManager` (`src/core/serviceState.ts:4`) maintains state history, controls heartbeat eligibility, and exposes helpers for reconfiguration flows.

## Database Contracts
- Target system is Microsoft SQL Server 2014 Express 32-bit; keep all queries/stored procedures compatible with this version.
- Core tables: `tempcheques` (active orders), `tempcheqdet` (line items), `tempchequespagos` (payments), `turnos` (shifts), archived counterparts (`cheques`, `cheqdet`, `chequespagos`).
- Stored procedures: `sp_GetPendingChanges`, `sp_MarkChangesProcessed`, and POS operations invoked by adapters must remain idempotent and performant.
- `sp_ApplyPartialPayment` handles partial payment processing and validation. Fixed C-1 (remaining computed from the running balance, not re-derived from the mutated total → no balance drift/under-collection) and made idempotent by `@Reference` (redelivered Payment.APPLY no longer double-applies).
- Entity IDs: v10 uses `{InstanceId}:{IdTurno}:{Folio}`; v11 uses `WorkspaceId` (plus `:Movimiento` for items). Always treat `turnos.idturno` as the business key, not `idturnointerno`.
- Shift closure detection relies on `turnos.cierre` updates (see `CLAUDE.md` and `scripts/sql/shift-close-flow` notes). Deletions during archival should not be treated as cancellations.

## Messaging Topology
- Exchanges: `pos_events_exchange` and `pos_commands_exchange`; dead-letter exchange `dead_letter_exchange` with queue `avoqado_events_dead_letter_queue`.
- Producer routing keys: `pos.softrestaurant.order.{created|updated|deleted}`, `pos.softrestaurant.orderitem.{created|updated|deleted}`, `pos.softrestaurant.shift.{created|updated|closed}`, `pos.softrestaurant.system.heartbeat`.
- Commander queue: `commands_queue.venue_{venueId}` bound to `command.softrestaurant.{venueId}`.
- Configuration error queue: `config_errors_{posType}_{instanceId}` bound to `command.{posType}.configuration.error`.

## Configuration and Secrets
- Development loads variables from `.env` via `loadConfig` (`src/config.ts:17`). Production reads `%ProgramData%\AvoqadoSync\config.json`.
- `SecureConfigManager` (`src/core/secureConfig.ts:13`) supports encrypted production configs tied to machine identifiers; use it when hardening deployments.
- Update `config.detectedVersion` through `updateDetectedVersion` when runtime detection changes POS assumptions.
- Never hard-code credentials; rely on environment or machine-specific config files.

## Development Workflow
- Install dependencies: `npm install`.
- Dev mode: `npm run dev` (nodemon + ts-node on `src/service.ts`).
- Build: `npm run build` (outputs to `dist/`). Run `npm start` to execute compiled JS.
- Package: `npm run package` to produce `AvoqadoSyncService.exe` via `pkg`.
- Formatting: `npm run check-format` / `npm run format`.
- Prefer built-in helpers (`executeTransaction`, `publishMessage`, `serviceStateManager`) rather than reimplementing infrastructure pieces.
- Ensure code remains ASCII; only introduce explanatory comments where the flow is non-obvious.

## Windows Service Operations
- Install service (admin shell): `npm run svc:install`; uninstall: `npm run svc:uninstall`.
- Service metadata is defined in `src/main.ts:5`. When running as a service, avoid interactive prompts (the management console remains disabled by default).

## Logging and Monitoring
- `src/core/logger.ts:5` configures console and daily-rotating file transports under `logs/`.
- Heartbeats double as liveness signals; monitor them downstream.
- `managementConsole` (`src/core/managementConsole.ts:16`) offers a local CLI in development for state inspection, configuration history, and manual recovery.
- `npm run monitor` and `npm run monitor:build` execute the SQL monitoring tool (`src/tools/sqlMonitor.ts`) to inspect pending changes and queue health.

## SQL Toolkit
- `scripts/sql/README-SCRIPTS.md` describes the rollout order: verification, diagnostics, cleanup, installation, testing, fixes.
- Key scripts (`01-COMPLETE-INSTALL.sql`, `02-TESTING.sql`, `03-DIAGNOSTICS.sql`, etc.) provision triggers, functions, and stored procedures required by the producer.
- `Trg_Avoqado_OrderItems` tracks item changes on `tempcheqdet` (v11/v12: DELETE emite el WorkspaceId de la línea borrada, no el de la orden — H-1 fix).
- All scripts assume SQL Server 2014 compatibility and the presence of the SoftRestaurant schema documented in `docs/`.

## Documentation Synchronization Rule
- Any change to database schema, stored procedures, triggers, integration logic, entity IDs, or core runtime behavior must be reflected immediately in **all** related docs: `CLAUDE.md`, `AGENTS.md`, `docs/SoftRestaurant_Master_Documentation.md`, and affected SQL scripts.
- Verify that examples and queries in the docs still execute successfully after modifications.

## Agent Workflow
1. **Before coding**
   - Review the relevant sections of `CLAUDE.md`, this file, and associated SQL scripts.
   - Identify whether tasks touch the POS data model, messaging topology, or Windows service operations.
2. **While coding**
   - Use the planning tool for multi-step efforts; keep plans updated as work progresses.
   - Always set `workdir` when invoking shell commands; prefer `rg`/`Get-Content` for searches.
   - Leverage existing utilities (DB helpers, adapters, state manager) instead of bypassing them.
   - Maintain ASCII output and avoid unnecessary commentary.
3. **After coding**
   - Run targeted checks (`npm run build`, `npm run format`, or relevant SQL/unit scripts) as appropriate.
   - Re-read diffs to ensure no stray credentials, debugging output, or plan remnants remain.
   - Update all mandated documentation and mention follow-up actions or tests in the final response.

## Troubleshooting
- **SQL connectivity**: confirm server/instance strings (`localhost\NATIONALSOFT`, escaped backslash, or TCP with port). Use creds defined in config; failures trigger retries in `db.ts`.
- **RabbitMQ issues**: connection drops cause `connectWithRetry` in `src/core/rabbitmq.ts` to rebuild channels; ensure exchanges/queues remain declared before publishing.
- **Version detection**: if `parametros2.versiondb` is missing, producer falls back to v10; update the database or handle gracefully in code.
- **Shift deletions**: if bogus delete events appear, verify `turnos.cierre` timestamps and the archival pipeline (`CLAUDE.md`, `scripts/sql/shift-close-flow`).
- **Configuration errors**: inspect `logs/error-*.log` and the event history from `serviceStateManager`; use the configuration manager and Windows notifications for recovery.

## Key References
- `src/service.ts`, `src/main.ts`
- `src/components/producer.ts`, `commander.ts`, `configurationErrorConsumer.ts`
- `src/core/db.ts`, `rabbitmq.ts`, `logger.ts`, `serviceState.ts`, `connectionResilience.ts`, `configurationManager.ts`, `windowsNotification.ts`
- `src/adapters/SoftRestaurant11Adapter.ts`, `src/services/Orders/createEmptyOrder.ts`
- `CLAUDE.md`, `docs/SoftRestaurant_Master_Documentation.md`, `scripts/sql/README-SCRIPTS.md`
