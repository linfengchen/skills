# Output Templates

Use these verbatim (with substitutions) for the files each phase produces. Keeps outputs consistent and parseable.

---

## Phase 1 — Module Card (`arch/modules/<name>.md`)

```markdown
# Module: <name>

**Source path:** `<dir>`
**Layer:** presentation | service | domain | repo | infra | config | shared
**LOC:** <approx>

## Responsibility
<1–2 sentences. What problem does this module solve?>

## Public Interface
<pseudocode signatures, one per line. Include params, return types, errors>
- `createOrder(customerID, items[]) -> Order | ValidationError`
- `cancelOrder(orderID, reason) -> void | NotFoundError | StateError`

## Data Models
- `Order { id, customerID, items[], status, createdAt, total }`
- `OrderItem { sku, qty, unitPrice }`

## Side Effects
- DB: `orders`, `order_items` (write); `customers` (read)
- External: `POST payments-service/charges`
- Queue: publishes `order.created` on success
- Env: `PAYMENTS_URL`, `PAYMENTS_API_KEY`

## Business Rules (the "why")
- An order with zero items must be rejected (not silently succeed).
- Cancellation is idempotent: second cancel on same order → no-op, returns current state.
- Total is recomputed server-side; any `total` in input is ignored (prevents tampering).
- Orders over $10k require a `managerApproval` field — legacy compliance constraint.

## Dependencies
- Consumed by: `handlers.order`, `jobs.order_reconciler`
- Depends on: `repo.order`, `repo.customer`, `client.payments`, `queue.publisher`

## Notes
<anything else a reimplementer needs — quirks, known bugs, deprecations>
```

---

## Phase 2 — Unit Test Row (`tests/unit_plan.md`)

Single-file table:

```markdown
# Unit Test Plan

| Module | Function | Scenario | Expected Outcome | Mocks |
|---|---|---|---|---|
| order | createOrder | happy path, 2 items, valid customer | Order returned with status=pending, total computed | repo.order, client.payments |
| order | createOrder | empty items array | ValidationError("items_required") | none |
| order | createOrder | unknown customer ID | NotFoundError("customer") | repo.customer |
| order | cancelOrder | order already cancelled | returns current state, no side effects | repo.order |
| ... | ... | ... | ... | ... |
```

## Phase 2 — Integration Test Row (`tests/integration_plan.md`)

```markdown
# Integration Test Plan

| Method | Path | Scenario | Request | Expected Status | Expected Response |
|---|---|---|---|---|---|
| POST | /orders | happy path | `{customerID, items:[{sku,qty}]}` + valid JWT | 201 | `{id, status:"pending", total}` |
| POST | /orders | missing JWT | valid body, no auth header | 401 | `{error:"unauthorized"}` |
| POST | /orders | empty items | `{customerID, items:[]}` + JWT | 400 | `{error:"items_required"}` |
| POST | /orders | customer not found | `{customerID:"unknown", items:[...]}` | 404 | `{error:"customer_not_found"}` |
| GET | /orders/:id | order exists, owned by caller | id in path + JWT | 200 | full Order |
| GET | /orders/:id | order owned by different user | id in path + JWT | 403 | `{error:"forbidden"}` |
```

---

## Phase 4 — Step Card (`modules/NN_<name>.md`)

```markdown
# Step NN: <short descriptive name>

**Status:** pending | in-progress | done | blocked

## What to Implement
<2–4 sentences describing exactly what code this step produces. Reference
specific functions / types by name.>

## Source Reference
<which Phase 1 module card(s) this maps to. List source file paths only if
implementation requires inspecting original source beyond the module card.>
- Source module: `arch/modules/order.md`
- Source files (if needed): `src/services/order.service.js` lines 40–120

## Target Location
- `internal/service/order.go` (new)
- `internal/service/order_test.go` (new)

## Interface Contract
```go
package service

type OrderService interface {
    Create(ctx context.Context, customerID string, items []OrderItem) (*Order, error)
    Cancel(ctx context.Context, orderID string, reason string) error
}

type orderService struct {
    orders    repo.OrderRepo
    customers repo.CustomerRepo
    payments  client.Payments
    publisher queue.Publisher
}

func NewOrderService(...) OrderService
```

## Test Hook
<which Phase 2 test rows this step must make pass>
- `order / createOrder / happy path`
- `order / createOrder / empty items`
- `order / createOrder / unknown customer ID`

## Done Criteria
- [ ] Compiles / passes type check
- [ ] Listed unit tests pass
- [ ] `go vet` / equivalent linter clean
- [ ] No function > 40 lines
- [ ] No TODO/FIXME left in code

## Blocker
<only populated if Status == blocked. Describe exactly what's missing.>
```

---

## Phase 4 — Index (`modules/00_index.md`)

```markdown
# Implementation Plan (Ordered)

| # | Step Name | Status | Target Files | Tests |
|---|---|---|---|---|
| 00 | domain_user_model | pending | internal/domain/user.go | user_test.go |
| 01 | domain_order_model | pending | internal/domain/order.go | order_test.go |
| 02 | repo_interfaces | pending | internal/repo/repo.go | — |
| 03 | repo_user_pg | pending | internal/repo/user_pg.go | user_pg_test.go |
| 04 | repo_order_pg | pending | internal/repo/order_pg.go | order_pg_test.go |
| 05 | client_payments | pending | internal/client/payments.go | payments_test.go |
| 06 | service_order | pending | internal/service/order.go | order_service_test.go |
| 07 | handler_order | pending | internal/handler/order.go | order_handler_test.go |
| 08 | wiring_main | pending | cmd/api/main.go | — |
| 09 | integration_happy_path | pending | test/integration/order_test.go | — |
```

---

## Phase 6 — Failures Table (`coverage/failures.md`)

```markdown
# Regression Failures — Round <N>

Last run: <timestamp>
Totals: <passing> / <total> passing, <failing> failing.

| Test | Category | Owning Module | First Seen (round) | Notes |
|---|---|---|---|---|
| TestOrderService_Create_EmptyItems | assertion | service/order | 1 | returns nil error instead of ValidationError |
| TestOrderHandler_Create_MissingAuth | status code | handler/order | 1 | returns 500, expected 401 |
| TestRepoUserPG_FindByID_NotFound | nil deref | repo/user_pg | 1 | scan panics on empty row — missing errors.Is(err, sql.ErrNoRows) |
```

Category values: `compile`, `assertion`, `status code`, `panic`, `timeout`, `flake`, `contract`, `schema`.

---

## Phase 7 — ADR Row (`docs/decisions.md`)

```markdown
# Architectural Decisions

| # | Decision | Alternatives Considered | Reason Chosen |
|---|---|---|---|
| 1 | Chose chi as HTTP router | gin, echo, stdlib mux | Middleware-friendly, zero-dep philosophy matches service style |
| 2 | sqlc over ORM | GORM, ent, raw pgx | Type-safe generated code; queries visible in repo; no runtime overhead |
| 3 | Error enum via custom `Err*` sentinels + `errors.Is` | multi-error, stringly-typed | Works with std errors, easy to switch on at handler layer |
```

---

## Phase 7 — Migration Delta (`docs/migration_delta.md`)

```markdown
# Migration Delta: <source_lang> → <target_lang>

## Dropped
- `POST /legacy/reconcile` — superseded by background job in target; not exposed as HTTP.

## Renamed Fields
- Response `created_at` → `createdAt` (camelCase throughout).
- Config `DB_URL` → `DATABASE_URL` (matches 12-factor convention).

## Behavior Changes
- Order cancellation is now idempotent (was 409 on second call; now 200 returning current state).
- Order total is always server-computed (was accepted from client with weak validation).

## Known Regressions
<should be empty; if not, list each with a tracking ticket>
- None.

## Running in Parallel
<if both versions will coexist during cutover>
- Target service reads/writes same Postgres schema; safe to run side by side behind a feature flag.
- Queue topic names unchanged; either service can consume.
```
