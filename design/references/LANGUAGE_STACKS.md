# Language Stacks Reference (design skill)

Opinionated defaults per target language for greenfield service work. Consult during **Phase 3 (Architecture)** and **Phase 5 (Implementation)**.

Each section covers: layer pattern, preferred stack, error model, testing, idioms to apply, common pitfalls to avoid.

Sections:
- [Go](#go)
- [Rust](#rust)
- [Node / TypeScript](#node--typescript)
- [Python](#python)

---

## Go

### Layer Pattern
```
cmd/<binary>/main.go          entry point; wiring only
internal/
  domain/                     pure types + invariants, no imports from outer layers
  repo/                       data access interfaces + implementations
  service/                    use cases; depends on repo interfaces
  handler/                    HTTP/RPC adapters; depends on service interfaces
  client/                     outbound clients (external APIs, queue)
  middleware/                 auth, logging, request ID, recovery
  config/                     typed config, loaded once at startup
  platform/                   shared utilities (clock, id gen, errors)
pkg/                          public reusable (rare; default to internal/)
test/integration/             black-box integration tests
```

### Preferred Stack
- Router: `chi` (stdlib-compatible, middleware-friendly)
- DB: `pgx` + `sqlc` (compile-time SQL validation)
- Migrations: `goose` or `golang-migrate`
- Config: `envconfig` or `viper` (prefer envconfig for simplicity)
- Logging: `log/slog` (stdlib, structured)
- Validation: struct tags + `go-playground/validator`
- Tests: `testing` + `testify/require` + `testify/mock` (or `go.uber.org/mock`)
- Errors: sentinel `var ErrX = errors.New(...)` + wrapping via `fmt.Errorf("...: %w", err)`; `errors.Is`/`errors.As` at boundaries

### Error Model
- Return `(T, error)`. No panics for expected failures.
- One error type per domain meaning (e.g., `ErrNotFound`, `ErrConflict`, `ErrValidation`). Handlers map these to HTTP codes in one place.
- Wrap with context: `fmt.Errorf("repo.task.findByID %s: %w", id, err)`.

### Idioms to Apply
- Accept interfaces, return structs.
- Define interfaces on the consumer side, not the producer side.
- Keep interface surface < 5 methods when possible.
- No init() side effects beyond registration. Main wires dependencies explicitly.
- Context is the first parameter of every IO function.
- Prefer composition over embedding; embedding only for clear is-a.

### Testing
- Table-driven tests with `tests := []struct { name string; ... }{}` + `t.Run(tc.name, ...)`.
- HTTP handlers tested via `httptest.NewRecorder`.
- Integration tests use real Postgres via `testcontainers-go` or a reserved test DB.
- Mock only boundaries (repo, external client). Don't mock domain code.

### Pitfalls
- Don't over-use generics. Start concrete; refactor when the third implementation appears.
- Don't write micro-packages. A package per layer per bounded context is usually enough.
- Don't use `panic` as flow control. Use it only for programmer errors.
- Don't leak repo types into service return values; map to domain types.

---

## Rust

### Layer Pattern
```
src/
  main.rs                     entry point + router wiring
  config.rs                   typed config, parsed once
  domain/                     mod.rs + per-entity files
    mod.rs
    task.rs
    error.rs                  domain error enum
  repo/                       trait + impls
    mod.rs                    traits
    task_pg.rs                Postgres impl
  service/                    use-case layer
    mod.rs
    task.rs
  handler/                    axum handlers
    mod.rs
    task.rs
  middleware/
  queue/
  telemetry.rs                tracing init
tests/                        integration tests (outside src)
```

### Preferred Stack
- Web: `axum` (tower-based, ergonomic)
- Async runtime: `tokio` (multi-thread)
- DB: `sqlx` (compile-time-checked queries) with `postgres` feature; `sea-orm` if ORM preferred
- Migrations: `sqlx migrate` or `refinery`
- Config: `config` crate + `serde` into typed struct; or `envy`
- Logging: `tracing` + `tracing-subscriber` (JSON formatter in prod)
- Validation: `validator` crate with derive macros
- Tests: built-in `#[cfg(test)]` + `#[tokio::test]`; `mockall` for trait mocks; `assert_matches` for ergonomic pattern asserts
- Errors: `thiserror` for library/domain enums; `anyhow` only at binary edges

### Error Model
- Domain errors: `#[derive(thiserror::Error, Debug)] enum TaskError { ... }` with variants mapped to HTTP status in handler.
- Propagate with `?`. Use `anyhow::Result<T>` only for internal glue (main.rs, scripts).
- Never `unwrap()` in production code paths.

### Idioms to Apply
- Prefer `&str` over `String` in params unless ownership needed.
- Prefer small focused traits. `trait TaskRepo { ... }` consumed via generics or `Arc<dyn TaskRepo + Send + Sync>`.
- Use `Arc` for shared state; avoid `Mutex` unless truly shared mutable state.
- Start owned (`String`, `Vec<T>`); introduce lifetimes when you profile a hot path.
- Use newtype pattern for IDs (`struct TaskId(Uuid);`) — prevents ID mixups at compile time.

### Testing
- Unit tests in `#[cfg(test)] mod tests` at the bottom of each file.
- Integration tests in `tests/` directory; each file is its own crate.
- `mockall::automock` on traits for mocks.
- Use `tokio::test` for async tests; `tokio::test(flavor = "multi_thread")` for concurrency.

### Pitfalls
- Fighting the borrow checker: usually a sign to clone or use `Arc`. Optimize later.
- Over-using `&'static str`: most strings should be `String`.
- `async fn` in traits: use `async-trait` macro or design around it.
- Premature `Cow`, lifetimes, generic bounds — keep it concrete first.

---

## Node / TypeScript

### Layer Pattern
```
src/
  index.ts                    entry point
  config.ts                   zod-parsed env config
  domain/
    task.ts                   types + validators
    errors.ts                 error class hierarchy
  repo/
    task.ts                   interface
    taskPg.ts                 impl
  service/
    task.ts                   use cases
  handler/
    task.ts                   fastify routes
  middleware/
    auth.ts
  queue/
    publisher.ts
  telemetry/
    logger.ts
test/
  integration/
```

### Preferred Stack
- Runtime: Node 20+ (ESM only)
- Language: TypeScript with `"strict": true`, `"noUncheckedIndexedAccess": true`
- Web: `fastify` (schema-first, fast) — use Express only for legacy compatibility
- Validation: `zod` (schema + inferred types)
- DB: `kysely` (type-safe query builder) or `prisma`; raw `pg` for perf-critical paths
- Migrations: kysely-migrate, or `db-migrate`
- Config: `zod` schema over `process.env`, parsed once at startup
- Logging: `pino` (fast, structured, pino-pretty in dev)
- Tests: `vitest` (fast, ESM-native) — use `jest` only if ecosystem requires
- Build: `tsc` for libraries; `tsx` for dev; `esbuild` / `swc` for bundling

### Error Model
- `class AppError extends Error` with a `code: string` field. Subclasses: `ValidationError`, `NotFoundError`, `ForbiddenError`, `ConflictError`.
- Handlers map `err.code` → HTTP status in one place.
- Never `throw` string literals. Always an Error subclass.
- Alternative: `neverthrow` `Result<T, E>` if team prefers no-throws. Pick one, be consistent.

### Idioms to Apply
- `interface` for shapes/contracts; `type` for unions, aliases, mapped types.
- `readonly` fields for DTOs.
- Discriminated unions for state: `type State = { kind: 'loading' } | { kind: 'ok'; data: T } | { kind: 'err'; e: Error }`.
- Branded types for IDs: `type TaskId = string & { readonly __brand: unique symbol }`.
- No `any`. Use `unknown` + runtime validation via zod.
- Prefer explicit return types on exported functions.

### Testing
- `vitest` with `describe`/`it`; fixture factories as plain functions.
- Schema-based fastify routes → request/response types inferred; integration tests exercise schemas.
- Mock boundaries only. For repo mocks, define an interface and provide an in-memory fake; use `vi.fn()` for spy behavior.

### Pitfalls
- Mixing CommonJS and ESM — commit to ESM from day one.
- Overusing classes — prefer plain objects + functions unless state genuinely belongs together.
- `async` without `await` (silent promise loss) — turn on `@typescript-eslint/no-floating-promises`.
- Ad-hoc `any` to silence type errors — ban it via lint rule.

---

## Python

### Layer Pattern
```
src/
  <pkg>/
    __init__.py
    main.py                   entry point
    config.py                 pydantic Settings
    domain/
      __init__.py
      task.py                 pydantic models + invariants
      errors.py
    repo/
      __init__.py
      task.py                 Protocol
      task_pg.py              impl
    service/
      task.py
    handler/
      task.py                 FastAPI router
    middleware/
    queue/
    telemetry.py
tests/
  unit/
  integration/
pyproject.toml
```

### Preferred Stack
- Python 3.12+
- Web: FastAPI (async, type-driven) — Flask only for legacy or sync-simple
- Validation: `pydantic` v2 (models are the contract)
- DB: SQLAlchemy 2.0 async (ORM) or `asyncpg` for raw; `alembic` for migrations
- Config: `pydantic-settings` (env parsing, validation at startup)
- Logging: stdlib `logging` with `structlog` overlay, or pure `structlog`
- Tests: `pytest` + `pytest-asyncio` + `pytest-cov`; `httpx` AsyncClient for API tests
- Lint/format: `ruff` (lint + format in one) + `mypy --strict` (or `pyright`)
- Package/deps: `uv` (fast) or `poetry`

### Error Model
- Custom exception hierarchy: `class AppError(Exception)`, subclasses for each domain meaning.
- Handlers translate exceptions → HTTP responses in one place (FastAPI exception handlers).
- Don't raise bare `Exception` or strings.

### Idioms to Apply
- Type-hint everything. `mypy --strict` (or pyright strict) in CI.
- Pydantic models over dicts for all I/O boundaries.
- `Protocol` classes (structural typing) for repo interfaces — avoids ABC ceremony.
- `@dataclass(slots=True, frozen=True)` for internal value types; pydantic for I/O shapes.
- `async def` end-to-end; do not mix sync DB calls in async handlers.
- Dependency injection via FastAPI `Depends` (request-scoped) and constructor args (service layer).

### Testing
- `pytest` with fixtures in `conftest.py` at appropriate scope.
- Async tests: `@pytest.mark.asyncio` (or `asyncio_mode = "auto"` in config).
- API tests: `httpx.AsyncClient` against `app` directly (no network).
- Fakes for repos (plain in-memory Python classes implementing the Protocol). Avoid `unittest.mock.Mock` for domain code.

### Pitfalls
- Mixing sync and async ORM calls — pick one lane per service.
- Circular imports — use TYPE_CHECKING guards or restructure.
- Over-reliance on `**kwargs` erasing types. Use typed params or pydantic models.
- Skipping `mypy`/`pyright` — the skill assumes strict mode. Do not disable.

---

## Universal Cross-Language Principles

1. **Layer purity.** Domain depends on nothing. Repo depends on domain only. Service depends on domain + repo interfaces. Handler depends on service. No reverse arrows.
2. **DI at the edges.** Wiring happens in `main`. Modules accept dependencies via constructor / params — never via global state.
3. **Explicit errors.** Typed, named, mapped to HTTP at one place. No stringly-typed errors crossing layers.
4. **One I/O model per service.** Pick async or sync and commit. No hybrids.
5. **Config parsed once.** Validate all config at startup. Fail fast if anything is missing/malformed.
6. **Observability from day one.** Request ID, structured logs, basic metrics. Not Phase 7 paperwork.
7. **Small interfaces.** A module's public surface should fit on one screen. If not, split.
8. **Naming conventions.** Follow the target language's official style guide. Don't import conventions from another language.
