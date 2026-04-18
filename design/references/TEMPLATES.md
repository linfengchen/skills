# Output Templates (design skill)

Use these verbatim (with substitutions) for files each phase produces.

---

## Phase 1 — Requirement Summary (`req/summary.md`)

```markdown
# <Product / Service Name>

## What
<1–2 sentences describing the product in the domain's own language.>

## For Whom
<Primary users. Roles, not companies.>

## Why
<The core pain being solved, or the business outcome enabled.>

## Success Criterion
<One observable, measurable signal that this is working. e.g.,
"95% of tasks created via API appear in the assignee's feed within 2 seconds".>

## Source
<path or URL to original requirement, ingestion timestamp>
```

## Phase 1 — Goals (`req/goals.md`)

```markdown
# Goals

## In Scope
- G1: <short capability>
- G2: <short capability>

## Out of Scope (Non-Goals)
- NG1: <explicitly excluded capability, with one-line reason>
- NG2: ...

## Assumptions
<Recorded when the requirement was ambiguous and a default was chosen.>
- A1: <assumption> — default chosen because <reason>
- A2: ...
```

## Phase 1 — Functional Requirements (`req/functional.md`)

```markdown
# Functional Requirements

| ID | Capability | Acceptance Criterion |
|---|---|---|
| FR-01 | Create task | POST /tasks returns 201 with task ID; record persists and appears in GET /tasks |
| FR-02 | Assign task to user | PATCH /tasks/:id/assign stores assignee; assignee receives notification within 5s |
| FR-03 | List tasks by assignee | GET /users/:id/tasks returns paginated list ordered by due date |
```

## Phase 1 — Non-Functional Requirements (`req/non_functional.md`)

```markdown
# Non-Functional Requirements

| Category | Target |
|---|---|
| Latency (p95) | < 150ms for reads, < 300ms for writes |
| Throughput | 500 rps sustained |
| Availability | 99.9% monthly |
| Security | JWT bearer auth; TLS 1.2+; PII encrypted at rest |
| Compliance | GDPR: delete endpoint removes within 30 days |
| Observability | Structured logs, RED metrics per endpoint, distributed tracing |
| Scalability | Horizontal via stateless API + shared Postgres |
```

## Phase 1 — Module Card (`modules/<name>.md`)

```markdown
# Module: <name>

**Layer:** presentation | service | domain | repo | infra | config | shared
**Depends on:** <list of other modules>

## Responsibility
<1–2 sentences. If "and"/"also" appears, likely 2 modules.>

## Public Interface
<pseudocode signatures, target-lang-agnostic>
- `createTask(userID, input) -> Task | ValidationError`
- `assignTask(taskID, assigneeID, actor) -> void | NotFoundError | ForbiddenError`

## Domain Entities
- `Task { id, title, status, assigneeID, dueAt, createdAt }`
- `TaskEvent { taskID, type, actor, at }`

## Side Effects
- DB: `tasks` (rw), `task_events` (w)
- Queue: publishes `task.assigned` event
- External: none

## Business Rules
- A task in `done` status cannot be reassigned.
- Assignment is idempotent on (taskID, assigneeID).
- Due date in the past is rejected with ValidationError unless actor has `admin` role.

## Notes
<quirks, legacy constraints, future extension points>
```

## Phase 1 — Module Index (`modules/00_index.md`)

```markdown
# Module Map

| Module | Layer | Responsibility | Depends On |
|---|---|---|---|
| domain_task | domain | Task entity + invariants | — |
| repo_task | repo | Task persistence | domain_task |
| service_task | service | Task use cases (create, assign, list) | domain_task, repo_task, queue_publisher |
| handler_task | presentation | HTTP routes for tasks | service_task, auth |
| queue_publisher | infra | Publish domain events | — |
| auth | shared | JWT verification + role extraction | — |
```

## Phase 1 — Endpoints (`api/endpoints.md`)

```markdown
# External Endpoints

## POST /tasks
- **Auth:** required (any role)
- **Request body:** `{ title, description?, dueAt?, assigneeID? }`
- **201 Response:** `Task`
- **Errors:** 400 validation, 401 auth, 403 role
- **Idempotency:** no (use `Idempotency-Key` header for at-least-once clients)

## PATCH /tasks/:id/assign
- **Auth:** required (role: owner or admin)
- **Request body:** `{ assigneeID }`
- **200 Response:** `Task`
- **Errors:** 400 validation, 401 auth, 403 role, 404 not found, 409 task in terminal state
- **Idempotency:** yes (assigning same user twice is a no-op)
```

## Phase 1 — Events (`api/events.md`)

```markdown
# Events

| Name | Direction | Schema | Delivery | Ordering |
|---|---|---|---|---|
| task.created | publish | `{ taskID, creatorID, createdAt }` | at-least-once | per-task |
| task.assigned | publish | `{ taskID, assigneeID, actorID, at }` | at-least-once | per-task |
| user.deleted | consume | `{ userID, at }` | at-least-once | none |
```

---

## Phase 2 — Unit Test Plan (`tests/unit_plan.md`)

```markdown
# Unit Test Plan

| Module | Function | Scenario | Expected Outcome | Mocks |
|---|---|---|---|---|
| service_task | createTask | happy path | Task returned with status=open | repo_task, queue_publisher |
| service_task | createTask | empty title | ValidationError("title_required") | — |
| service_task | assignTask | task in done state | StateError("terminal_state") | repo_task |
| service_task | assignTask | assigning same user twice | no-op; returns current state | repo_task |
| domain_task | validateDueAt | past date, non-admin actor | ValidationError | — |
| domain_task | validateDueAt | past date, admin actor | ok | — |
```

## Phase 2 — Integration Test Plan (`tests/integration_plan.md`)

```markdown
# Integration Test Plan

| Method | Path | Scenario | Request | Expected Status | Expected Response |
|---|---|---|---|---|---|
| POST | /tasks | happy | `{title:"x"}` + JWT | 201 | `{id, status:"open", title:"x"}` |
| POST | /tasks | missing JWT | `{title:"x"}` | 401 | `{error:"unauthorized"}` |
| POST | /tasks | empty title | `{title:""}` + JWT | 400 | `{error:"title_required"}` |
| PATCH | /tasks/:id/assign | not found | `{assigneeID:"u"}` + JWT | 404 | `{error:"task_not_found"}` |
| PATCH | /tasks/:id/assign | task done | `{assigneeID:"u"}` + JWT | 409 | `{error:"terminal_state"}` |
```

---

## Phase 4 — Step Card (`steps/NN_<name>.md`)

```markdown
# Step NN: <short descriptive name>

**Status:** pending | in-progress | done | blocked

## What to Implement
<2–4 sentences describing exactly what this step produces. Reference functions
and types by name.>

## Source Reference
- Requirement / module card(s): `modules/service_task.md`, `api/endpoints.md#POST-tasks`

## Target Location
- `internal/service/task.go` (new)
- `internal/service/task_test.go` (new)

## Interface Contract
```go
package service

type TaskService interface {
    Create(ctx context.Context, actorID string, in CreateTaskInput) (*domain.Task, error)
    Assign(ctx context.Context, actorID, taskID, assigneeID string) (*domain.Task, error)
}

type taskService struct {
    repo   repo.TaskRepo
    events queue.Publisher
    clock  clock.Clock
}

func NewTaskService(r repo.TaskRepo, p queue.Publisher, c clock.Clock) TaskService
```

## Test Hook
- `service_task / createTask / happy path`
- `service_task / createTask / empty title`
- `service_task / assignTask / task in done state`

## Done Criteria
- [ ] Compiles / type-checks
- [ ] Listed unit tests pass
- [ ] Linter clean
- [ ] No function > 40 lines
- [ ] No TODO/FIXME in committed code

## Blocker
<only if Status == blocked>
```

## Phase 4 — Step Index (`steps/00_index.md`)

```markdown
# Implementation Steps (Ordered)

| # | Step Name | Status | Target Files | Tests |
|---|---|---|---|---|
| 00 | domain_task_model | pending | internal/domain/task.go | task_test.go |
| 01 | domain_task_validation | pending | internal/domain/validate.go | validate_test.go |
| 02 | repo_task_interface | pending | internal/repo/task.go | — |
| 03 | repo_task_pg | pending | internal/repo/task_pg.go | task_pg_test.go |
| 04 | queue_publisher | pending | internal/queue/publisher.go | publisher_test.go |
| 05 | service_task | pending | internal/service/task.go | task_service_test.go |
| 06 | handler_task | pending | internal/handler/task.go | task_handler_test.go |
| 07 | auth_middleware | pending | internal/auth/middleware.go | middleware_test.go |
| 08 | wiring_main | pending | cmd/api/main.go | — |
| 09 | integration_happy_path | pending | test/integration/task_test.go | — |
```

---

## Phase 6 — Failures Table (`coverage/failures.md`)

```markdown
# Regression — Round <N>

Last run: <timestamp>
Totals: <passing> / <total> passing, <failing> failing (delta: +<fixed> this round).

| Test | Category | Owning Module | First Seen | Note |
|---|---|---|---|---|
| TestTaskService_Create_EmptyTitle | assertion | service_task | 1 | returns nil err instead of ValidationError |
| TestTaskHandler_Assign_NotFound | status code | handler_task | 1 | returns 500, expected 404 — missing errors.Is(err, ErrNotFound) |
```

Categories: `compile`, `assertion`, `status code`, `panic`, `timeout`, `flake`, `contract`, `schema`.

---

## Phase 7 — ADR (`docs/decisions.md`)

```markdown
# Architectural Decisions

| # | Decision | Alternatives | Reason |
|---|---|---|---|
| 1 | chi router | gin, echo, stdlib | middleware-friendly, stdlib-compatible handlers |
| 2 | sqlc for data access | gorm, ent | compile-time-checked SQL, no runtime reflection |
| 3 | slog for logs | zerolog, zap | stdlib, structured, no external dep |
| 4 | JWT HS256 | RS256, opaque | symmetric key is simpler for single-service scope |
```

## Phase 7 — Operations (`docs/operations.md`)

```markdown
# Operations

## Deploy
<one-paragraph deploy flow; container image, env vars, migration command>

## Observe
- Logs: structured JSON on stdout. Fields: `level, ts, msg, request_id, actor_id`.
- Metrics: `/metrics` Prometheus endpoint. RED metrics per route.
- Traces: OTel exporter to `OTEL_EXPORTER_OTLP_ENDPOINT`.

## Rollback
- Container image: redeploy previous tag.
- DB migration: each migration has a paired `down.sql`; run `make migrate-down`.

## Runbooks
- **High 5xx rate:** check DB connection pool saturation; scale replicas; check upstream auth service.
- **Queue backlog:** consumer is single-threaded by design; check `task.assigned` DLQ.
```
