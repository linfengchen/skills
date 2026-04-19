# TEMPLATES — Output shapes for every phase artifact

Use these verbatim. Skip sections that genuinely don't apply (write `_N/A — reason_`); never invent sections to look thorough.

---

## Phase 1 — `req/summary.md`

```md
# Requirement Summary

**What:** <1 sentence — the change in plain language>
**For whom:** <primary user / actor>
**Why:** <business or technical motivation>
**Success criterion:** <one observable, measurable signal>

**In one paragraph (≤ 200 words):**
<the meat — what triggers it, what it produces, what changes about the system after this ships>
```

---

## Phase 1 — `req/goals.md`

```md
# Goals

## In Scope
- ...

## Non-Goals (explicit)
- ...

## Assumptions (defaults chosen where source was ambiguous)
- A1: <assumption> — default chosen: <decision>
- A2: ...
```

---

## Phase 1 — `req/functional.md`

```md
# Functional Requirements

| ID    | Capability                                | Acceptance criterion                              |
|-------|-------------------------------------------|---------------------------------------------------|
| FR-01 | Mute a user for a duration                | POST returns 200; user `muted_until > now`         |
| FR-02 | Unmute (admin override)                   | DELETE returns 204; `muted_until` cleared          |
```

---

## Phase 1 — `design/00_overview.md`

```md
# Top-Level Design

## Diagram
```
client ──HTTP──> [api/handler/mute.go]
                       │
                       ▼
                 [service/mute.go] ──audit──> [logger]
                       │
                       ▼
                  [repo/user.go] ─SQL→ users.muted_until
```

## Critical invariants
- I1: A muted user's `muted_until` is always > `now()` while muted.
- I2: Mute action is idempotent on (user_id, until) pair.

## Side effects
- Writes `audit_log` row per action.
- Emits `user.muted` / `user.unmuted` event.
```

---

## Phase 1 — `design/modules.md`

```md
# Modules

| Module             | New / Affected | Responsibility                              | Depends on              |
|--------------------|----------------|---------------------------------------------|-------------------------|
| api/handler/mute   | New            | HTTP layer for mute/unmute                  | service/mute            |
| service/mute       | New            | Business rules: duration cap, idempotency   | repo/user, audit, events|
| repo/user          | Affected       | New methods: SetMuteUntil, ClearMute        | db                      |
| audit              | Affected       | New action codes USER_MUTED / USER_UNMUTED  | logger                  |
```

---

## Phase 1 — `api/endpoints.md`

```md
# Endpoints

## POST /v1/users/{id}/mute

- Auth: admin or moderator role
- Idempotent: yes (same body within 5s → 200, no duplicate audit)
- Rate limit: 60/min/admin

### Request
```json
{ "duration_seconds": 3600, "reason": "spam" }
```

### Response 200
```json
{ "user_id": "u_123", "muted_until": "2026-04-19T11:00:00Z" }
```

### Errors
| Code | When                                   |
|------|----------------------------------------|
| 400  | duration_seconds out of [60, 7*24*3600]|
| 403  | caller lacks role                      |
| 404  | user not found                         |
| 409  | user already muted with longer duration|
```

---

## Phase 1 — `api/compat.md`

```md
# Compatibility Impact

- Breaking change? **No.** Pure additive.
- Deprecations? None.
- DB migration: additive column `users.muted_until TIMESTAMP NULL`. Default null. Backfill not required.
- Client SDK: bump minor.
- Feature flag: `feature.user_mute` (default off in prod for first 7 days).
```

---

## Phase 2 — `arch_scan/layout.md`

```md
# Existing Layout

```
internal/
├── api/handler/      HTTP handlers (one file per resource)
├── service/          Business logic (one struct per use-case)
├── repo/             DB access (one file per table)
├── domain/           Pure types, no IO
├── audit/            Audit log writer
├── events/           NATS publisher
└── platform/         Logger, config, db, http server bootstrap
```

## Layers (top → bottom)
1. handler → service → repo → db
2. handler may call audit/events directly only for cross-cutting concerns; otherwise via service.

## Observed violations (candidates for refactor proposals)
- `handler/order.go` calls `repo/order.go` directly, skipping service. (-> RP candidate)
```

---

## Phase 2 — `arch_scan/conventions.md`

```md
# Conventions

| Concern         | Convention                                                        |
|-----------------|-------------------------------------------------------------------|
| Naming          | Go std: PascalCase exported, camelCase unexported                 |
| Errors          | wrap with `fmt.Errorf("%s: %w", op, err)`; sentinel via `errors.Is`|
| Logging         | `slog` with structured kv: `slog.Info("msg", "user_id", id)`      |
| Config          | `envconfig`-style struct in `platform/config`                     |
| DI              | constructor injection; no globals; service interfaces declared at consumer |
| Validation      | `go-playground/validator` on request DTOs                         |
| Tx boundary     | service layer (`db.WithTx(ctx, fn)`)                              |
| Idempotency     | `Idempotency-Key` header; cached in `repo/idempotency`            |
| Time            | `clock.Now()` injected, not `time.Now()`                          |
| Tests           | `testing` + `testify/require`, table-driven                       |
```

---

## Phase 2 — `arch_scan/extension_points.md`

```md
# Extension Points (for THIS change)

## Files to add
- `internal/api/handler/mute.go`         — new handler
- `internal/api/handler/mute_test.go`    — interface tests
- `internal/service/mute.go`             — new service
- `internal/service/mute_test.go`        — unit tests
- `migrations/00NN_add_muted_until.sql`  — DB migration

## Files to modify
- `internal/repo/user.go`                — add `SetMuteUntil`, `ClearMute`
- `internal/api/router.go`               — register routes
- `internal/audit/codes.go`              — add USER_MUTED, USER_UNMUTED

## Do NOT touch
- `internal/api/handler/order.go`        — out of scope
- `platform/`                            — no platform changes needed
```

---

## Phase 2 — `tests/unit_plan.md`

```md
# Unit Test Plan

| Module        | Function          | Scenario                          | Input                  | Expected outcome                | Mocks            |
|---------------|-------------------|-----------------------------------|------------------------|---------------------------------|------------------|
| service/mute  | Mute              | happy path                        | (u_1, 3600s, "spam")   | muted_until = now+1h, audit row | repo, audit, evt |
| service/mute  | Mute              | duration below floor              | (u_1, 30s, "x")        | err DurationOutOfRange          | -                |
| service/mute  | Mute              | duration above ceiling            | (u_1, 30d, "x")        | err DurationOutOfRange          | -                |
| service/mute  | Mute              | already muted longer              | existing 7d, new 1h    | err AlreadyMutedLonger          | repo             |
| service/mute  | Mute              | repo failure                      | repo returns err       | err wrapped, no audit, no event | repo             |
| service/mute  | Unmute            | happy path                        | (u_1, admin)           | muted_until cleared, audit row  | repo, audit, evt |
| service/mute  | Unmute            | not muted                         | (u_1)                  | err NotMuted                    | repo             |
```

---

## Phase 2 — `tests/interface_plan.md`

```md
# Interface Test Plan

| METHOD path                  | Scenario             | Request                                  | Status | Body / shape                | Auth     |
|------------------------------|----------------------|------------------------------------------|--------|-----------------------------|----------|
| POST /v1/users/{id}/mute     | happy                | {duration_seconds:3600, reason:"spam"}   | 200    | {user_id, muted_until}      | admin    |
| POST /v1/users/{id}/mute     | duration too small   | {duration_seconds:10}                    | 400    | {error:"DurationOutOfRange"}| admin    |
| POST /v1/users/{id}/mute     | not authorized       | {...}                                    | 403    | {error:"Forbidden"}         | user     |
| POST /v1/users/{id}/mute     | user not found       | {...}                                    | 404    | {error:"NotFound"}          | admin    |
| POST /v1/users/{id}/mute     | idempotent retry     | same body within 5s                       | 200    | identical body              | admin    |
| DELETE /v1/users/{id}/mute   | happy                | -                                         | 204    | -                           | admin    |
```

---

## Phase 3 — `plan/steps.md` entry

```md
## Step 03 — service/mute happy path + duration validation

- **Status:** pending
- **Target files:** `internal/service/mute.go`, `internal/service/mute_test.go`
- **Summary:** Implement `Mute(ctx, userID, duration, reason)` with duration floor/ceiling check and successful repo+audit+event flow.
- **Expected LOC:** ~120
- **Tests covered:** unit_plan rows 1, 2, 3 (happy, below floor, above ceiling)
- **Depends on:** Step 01 (repo methods), Step 02 (audit codes)
```

---

## Phase 3 — `plan/refactor_proposals.md` entry

```md
## RP-01 — Hoist user-lookup into a service helper

- **Why blocking:** new mute service needs the same "load user, 404 if missing" pattern that exists in 3 handlers; without a helper we'd write the 4th copy.
- **Risk:** low — pure extraction, behavior preserved, covered by existing tests.
- **Files touched:** `internal/service/user_lookup.go` (new), `internal/api/handler/{order,profile,session}.go` (3 callers).
- **Cost:** 1 step (~80 LOC including its unit tests).
- **Test situation:** existing handler tests cover all 3 callers; one new unit test for the helper.
```

---

## Phase 3 — `plan/refactor_decision.md`

```md
# Refactor Decisions

| ID    | Title                              | Verdict   | Notes                                          |
|-------|------------------------------------|-----------|------------------------------------------------|
| RP-01 | Hoist user-lookup helper           | approved  | Inserted as Step 02 (before service/mute).      |
| RP-02 | Split god-function OrderProcess    | deferred  | Tracked as DESIGN.md follow-up TODO.            |
| RP-03 | Replace global logger              | rejected  | Out of scope; service uses injected slog OK.    |

Decision recorded: 2026-04-19T10:30Z
```

---

## Phase 5 — `coverage/failures.md`

```md
# Failures (Round 2)

| Test                                       | Category  | Owning module   | First seen | Note                          |
|--------------------------------------------|-----------|-----------------|------------|-------------------------------|
| TestMuteService_AlreadyMutedLonger         | unit      | service/mute    | round 1    | Off-by-one on time comparison |
| TestMuteHandler_Idempotent                 | interface | api/handler/mute| round 2    | Missing Idempotency-Key check |

Total: 185 / Pass: 183 / Fail: 2 (Δ from round 1: -3)
```

---

## Phase 6 — `DESIGN.md`

Use the section order below. Hard cap: 1500 words.

```md
# <Feature name> — Design

## Overview
<≤150 words. What was built, why, success criterion.>

## Code Structure
```
internal/
├── api/handler/mute.go         HTTP handlers (POST/DELETE mute)
├── service/mute.go             Business rules: duration cap, idempotency
├── service/user_lookup.go      Shared user-load helper (refactor RP-01)
└── repo/user.go                +SetMuteUntil, +ClearMute
migrations/
└── 0042_add_muted_until.sql    additive column
```

## Module Responsibilities
| Module               | Responsibility                                   | Key public symbols           |
|----------------------|--------------------------------------------------|------------------------------|
| api/handler/mute     | HTTP layer for mute/unmute                        | `MuteHandler`                |
| service/mute         | Validate, persist, audit, emit event              | `Service.Mute`, `.Unmute`    |
| service/user_lookup  | Load user-or-404 (shared)                         | `LoadUserOrNotFound`         |
| repo/user            | DB access                                         | `SetMuteUntil`, `ClearMute`  |

## External Interface
| Endpoint                       | Input                            | Output                        | Errors            | Auth  |
|--------------------------------|----------------------------------|-------------------------------|-------------------|-------|
| POST /v1/users/{id}/mute       | {duration_seconds, reason}       | {user_id, muted_until}        | 400/403/404/409   | admin |
| DELETE /v1/users/{id}/mute     | -                                | -                             | 403/404           | admin |

Events emitted: `user.muted`, `user.unmuted` (NATS subject `events.user.*`).

## Data Model Changes
- `users.muted_until TIMESTAMP NULL` (additive). Migration `0042`. No backfill.

## How To Use
```bash
make run                 # local dev
make test-unit           # unit suite
make test-interface      # interface suite
curl -X POST -H "Authorization: Bearer <admin>" \
     -d '{"duration_seconds":3600,"reason":"spam"}' \
     http://localhost:8080/v1/users/u_123/mute
```

Env vars introduced: `FEATURE_USER_MUTE=true|false` (default false).

## Refactors Applied / Deferred
| RP    | Title                              | Status   | Follow-up                                    |
|-------|------------------------------------|----------|----------------------------------------------|
| RP-01 | Hoist user-lookup helper           | applied  | -                                            |
| RP-02 | Split god-function OrderProcess    | deferred | Track in backlog; recommended next sprint.   |
| RP-03 | Replace global logger              | rejected | -                                            |

## Tests & Coverage
185 tests, all passing. New: 24 unit, 9 interface. Coverage on changed files: 91%.

## Assumptions & Open Questions
- A1 (req/goals.md): mute duration ceiling = 7 days. Default chosen.
- Open: should `user.muted` event include reason text? Currently yes; confirm with privacy review.
- TODO (deferred RP-02): refactor `OrderProcess` god-function.
```
