# Avoqado Sync Service — Client Onboarding Runbook

**Canonical, current procedure** to onboard a new SoftRestaurant client to the Avoqado real-time sync.
Supersedes `TECHNICAL_ONBOARDING_GUIDE.md` (which has outdated script names).

> **Golden rule of order:** the venue must exist in the Avoqado **backend FIRST**. If the service
> starts publishing events for a venue that doesn't exist in the backend, those events are
> **dead-lettered (lost)** and heartbeats trigger a `configuration.error`. Backend → DB → service.

---

## 0. Compatibility (v10 / v11 / v12 — same binary)

- POS engine: **Microsoft SQL Server 2014 Express (32-bit)** for all SoftRestaurant versions (v12 is the POS app version, not the engine).
- Entity-id format is chosen by **WorkspaceId column presence**, not the version number — so:
  - **v11 / v12** (and any v10 that has `WorkspaceId`) → WorkspaceId path. ✅ validated live.
  - **true v10** (no `WorkspaceId` column) → `{Instance}:{IdTurno}:{Folio}` path. *(Rare in practice — validate against a real clean-v10 DB before go-live.)*

---

## 1. Prerequisites

**In the Avoqado backend (do this FIRST):**
- [ ] Create the **Venue** in the Avoqado platform → note its **`venueId`** (the backend Venue id).
- [ ] Set the venue's **`posType = SOFTRESTAURANT`** (required for the venue to receive commands).
- [ ] Confirm the backend is connected to the **shared RabbitMQ broker** (same one the service will use).

**On the client's POS server:**
- [ ] **Node.js 18** installed (or use the packaged `AvoqadoSyncService.exe`, which bundles Node).
- [ ] **Administrator** rights (to install the Windows service).
- [ ] Network egress to the RabbitMQ broker (port **5671** TLS / 5672).
- [ ] Local SQL reachable: `localhost\NATIONALSOFT` (sa or a SQL login).

**Collect from the client:**
- [ ] SoftRestaurant version (10 / 11 / 12) and the **database name**.
- [ ] SQL `sa` (or service) credentials.

---

## 2. Step-by-step

### Step 1 — Backup the venue database
```sql
BACKUP DATABASE [DB_NAME] TO DISK = 'C:\Backups\DB_NAME_PRE_AVOQADO.bak' WITH FORMAT, INIT, COMPRESSION
```

### Step 2 — Detect version (sanity check)
```sql
SELECT versiondb FROM parametros2;                       -- 10.x / 11.x / 12.x
SELECT COL_LENGTH('tempcheques','WorkspaceId') AS HasWID; -- 16 = WorkspaceId path, NULL = true v10
```

### Step 3 — Install the Avoqado SQL objects
Run against the **venue's** database. The script sets `QUOTED_IDENTIFIER ON` itself, so `-I` is optional:
```bash
sqlcmd -S "localhost\NATIONALSOFT" -U sa -P <PW> -d <DB_NAME> -i "scripts\sql\01-COMPLETE-INSTALL.sql"
```
*(If a previous/partial install exists, run `00-CLEANUP-ALL.sql` first.)*

### Step 4 — Verify the install
```bash
sqlcmd -S "localhost\NATIONALSOFT" -U sa -P <PW> -d <DB_NAME> -i "scripts\sql\00-VERIFICATION.sql"
```
Expect: 7 `Avoqado*` tables, the stored procedures, **4 triggers ENABLED**, payment methods `ACASH`/`ACARD`.

### Step 5 — Configure the service (production)
Production reads `%ProgramData%\AvoqadoSync\config.json` (NOT `.env`; `NODE_ENV` must not be `development`):
```json
{
  "venueId": "<VENUE_ID_FROM_BACKEND>",
  "posType": "softrestaurant",
  "posVersion": "11",
  "rabbitMqUrl": "amqps://user:pass@<SHARED_BROKER>/vhost",
  "sqlConfig": {
    "server": "localhost",
    "instanceName": "NATIONALSOFT",
    "database": "<DB_NAME>",
    "user": "sa",
    "password": "<PW>",
    "options": { "instanceName": "NATIONALSOFT", "encrypt": false, "trustServerCertificate": true }
  }
}
```
> `rabbitMqUrl` **must** be the same broker the backend consumes from — otherwise events never arrive.

### Step 6 — Install & start the Windows service (as Administrator)
```powershell
npm run svc:install            # registers "Avoqado POS Sync Service" and starts it (auto-start on boot)
Get-Service -Name "Avoqado POS Sync Service"
```
*(Or deploy the packaged `AvoqadoSyncService.exe` and register it.)*

---

## 3. Go-live verification checklist

- [ ] Service logs (`logs\info-YYYY-MM-DD.log`): `Versión detectada`, `Conexión con SQL Server establecida`, `Conexión con RabbitMQ establecida`, `Vinculando consumer(s)`.
- [ ] Heartbeat every 60s: `❤️ Latido enviado`.
- [ ] Backend: the venue shows **`PosConnectionStatus = ONLINE`** / `posStatus = CONNECTED`.
- [ ] Create a real order in the POS → it appears in the backend (`Order` row / dashboard).
- [ ] Close a shift in the POS → no spurious "deleted" events; `shift.closed` is published.

---

## 4. POS non-interference (why it's safe)

- Triggers are **set-based** (multi-row safe), `SET NOCOUNT ON`, and wrapped in **TRY/CATCH that logs but does NOT roll back** → a tracking failure **never aborts** a POS order/payment.
- Polling reads the separate `AvoqadoTracking` table (indexed), every 2s, with an anti-overlap guard.
- **Always run `00-VERIFICATION.sql` after install** — the only residual risk is a broken/missing tracking table, which verification catches.
- The **Commander** (Avoqado → POS, e.g. `Payment.APPLY`) does write to live POS tables by design; it is transactional and short.

---

## 5. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Events never reach backend; appear in `avoqado_events_dead_letter_queue` | Venue not created in backend (or wrong `venueId`) | Create the venue in the backend; use its exact id in `config.json` |
| Service emits repeated `configuration.error` / venue not ONLINE | Backend rejects an unknown `venueId` | Same as above |
| Commands (`Payment.APPLY`) never execute | Venue `posType` is null in backend | Set `posType = SOFTRESTAURANT` on the venue |
| Install fails with `Msg 1934` (QUOTED_IDENTIFIER) | Old script without the SET header | Use the current `01-COMPLETE-INSTALL.sql` (sets it) or pass `-I` |
| RabbitMQ `403 ACCESS_REFUSED` | Wrong/expired broker credentials | Fix `rabbitMqUrl`; ensure service + backend share the broker |
| Service won't start | Missing/invalid `config.json`, or required field absent | Verify `%ProgramData%\AvoqadoSync\config.json` (needs venueId, rabbitMqUrl, sqlConfig) |
| Heartbeat fails, polling paused | Broker unreachable at start | Bring the broker up; the service retries and resumes automatically |

---

*Service registers as `Avoqado POS Sync Service`. Logs: `logs\`. Config (prod): `%ProgramData%\AvoqadoSync\config.json`.*
