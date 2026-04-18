# Language Mapping Reference

Idiomatic translations between language pairs. Consult during **Phase 3 (Target Architecture)** and **Phase 5 (Implementation)**. Do NOT translate literally — apply the target language's native patterns.

Sections:
- [Node/TypeScript → Go](#nodetypescript--go)
- [Python → Rust](#python--rust)
- [Python → Node/TypeScript](#python--nodetypescript)
- [Node → Python](#node--python)
- [Go → Node/TypeScript](#go--nodetypescript)
- [Universal anti-patterns](#universal-anti-patterns)

---

## Node/TypeScript → Go

### Concurrency
- `async/await` → plain functions; caller passes `context.Context` for cancellation.
- `Promise.all(...)` → `errgroup.Group` with `g.Go(fn)` + `g.Wait()`.
- `setInterval` / `setTimeout` → `time.Ticker` / `time.AfterFunc`.
- Event emitters → channels (prefer) or callback-typed fields.

### HTTP / Routing
- Express → `chi` (preferred) or `net/http` with middleware chaining.
- Express middleware `(req, res, next) => {}` → `func(http.Handler) http.Handler`.
- Body parsing with `express.json()` → manual `json.NewDecoder(r.Body).Decode(&v)` + validation.
- Validation (joi/zod) → `go-playground/validator` struct tags, or hand-rolled per-type `Validate() error`.

### Errors
- `throw new Error("x")` → `return fmt.Errorf("x: %w", cause)`.
- Custom error classes → typed error variables (`var ErrNotFound = errors.New("not found")`) + `errors.Is` / `errors.As`.
- Never use `panic` for expected errors; only for programmer bugs.

### Data access
- `pg` / `knex` / `prisma` → `pgx` + `sqlc` (generated type-safe queries), or `sqlx`.
- Transaction callback → `tx, err := db.Begin(ctx)` + `defer tx.Rollback(ctx)` + explicit `tx.Commit(ctx)`.

### Config / env
- `process.env.FOO` → load once at startup into a typed struct via `envconfig` or `viper`. Validate on parse.

### Testing
- Jest → `testing` package + `testify/assert`, `testify/require`, `testify/mock`.
- `describe`/`it` → `t.Run("scenario", func(t *testing.T) { ... })`.
- `beforeEach` → table-driven tests with setup per row, or `t.Cleanup`.
- HTTP tests → `httptest.NewRecorder` + `httptest.NewServer`.

### Idioms
- No `null` — use pointers (`*T` for nullable) or sentinel values.
- No exceptions — every fallible function returns `(T, error)`.
- Capitalize exported identifiers; lowercase = package-private.
- Interfaces are defined at the consumer side (accept interfaces, return structs).
- Avoid generics unless collapsing 3+ near-identical implementations.

### Preferred stack
Router `chi` · DB `pgx` + `sqlc` · Config `envconfig` · Logger `slog` or `zerolog` · Validator struct tags · Tests `testing`+`testify`.

---

## Python → Rust

### Types & structure
- `class Foo:` with methods → `struct Foo { ... }` + `impl Foo { ... }`.
- `@dataclass` → plain `struct` with `#[derive(Debug, Clone, Serialize, Deserialize)]`.
- `dict[str, Any]` (loose) → define a `struct` with typed fields; if truly heterogeneous, use `serde_json::Value` but prefer a tagged enum.
- `Enum` → Rust `enum` (often with data variants — use this aggressively, it's the biggest win).
- Dataclass inheritance → compose via fields or use trait objects; avoid deep hierarchies.

### Errors
- `raise ValueError(...)` → `return Err(MyError::Validation(msg))`.
- Exception hierarchy → error enum with `#[derive(thiserror::Error)]`.
- Ad-hoc errors / scripts → `anyhow::Result<T>` + `?`.
- Never `panic!` for recoverable errors.

### Async
- `asyncio` → `tokio` runtime; `async fn` is the same shape.
- `asyncio.gather(...)` → `tokio::join!` (static) or `futures::future::try_join_all` (dynamic).
- `async with lock:` → `let guard = mutex.lock().await;`.

### HTTP
- FastAPI / Flask → `axum` (preferred) or `actix-web`.
- Pydantic models → `serde` structs with `#[serde(deny_unknown_fields)]` + `validator` crate for rules.
- Dependency injection via function params → `axum` extractors + `State`.

### Data access
- SQLAlchemy / asyncpg → `sqlx` (compile-time checked queries) or `sea-orm`.
- Sessions / transactions → `sqlx::Transaction` + `?` propagation + explicit `commit().await`.

### Testing
- pytest → `#[cfg(test)] mod tests { ... }` with `#[test]` / `#[tokio::test]`.
- Fixtures → helper functions returning test structs; parameterize with `rstest` if needed.
- Mocks → `mockall` for traits.

### Idioms
- Prefer `&str` over `String` in function params unless ownership is needed.
- Use `Option<T>` not sentinel nulls. Use `Result<T, E>`, not panics.
- Lifetimes: don't overthink. Start with owned types (`String`, `Vec<T>`), optimize later.
- Clone freely in business logic; optimize after profiling.
- Prefer small traits over large ones.

### Preferred stack
Web `axum` · DB `sqlx` · Runtime `tokio` · Errors `thiserror` + `anyhow` · Logging `tracing` · Serde for (de)serialization · Tests built-in + `mockall`.

---

## Python → Node/TypeScript

### Types
- `@dataclass` / pydantic → `zod` schema + `z.infer<typeof schema>` type.
- Type hints → TypeScript `strict: true` mode.
- `dict` → typed interface or `Record<string, T>` (only when truly dynamic).
- Duck typing → structural interfaces (TS already does this).

### Errors
- Exceptions → typed error classes extending a base `AppError`; or `Result<T, E>` via `neverthrow` if team prefers explicit returns.
- `raise SomeError(...)` → `throw new SomeError(...)` with a custom class that has a `code` field.

### HTTP
- FastAPI / Flask → Fastify (preferred, type-safe) or Express.
- Pydantic request validation → `zod` + Fastify schemas (or Express middleware).
- Async routes translate 1:1 (`async function handler(req, res)`).

### Data access
- SQLAlchemy → `kysely` (type-safe query builder) or `prisma`.
- asyncpg → `pg` with typed result adapters.

### Testing
- pytest → `vitest` (preferred) or `jest`.
- Fixtures → setup helper functions; `beforeEach` / `describe` blocks.
- Mocks → `vi.mock(...)` / manual fakes.

### Idioms
- Prefer `interface` for public shapes, `type` for unions/aliases.
- `readonly` fields for immutable structs.
- Discriminated unions for state (`{kind: "loading"} | {kind: "ok", data}`).
- No `any`. If truly unknown, `unknown` + runtime validation.
- Top-level `await` is fine in ESM.

### Preferred stack
Runtime Node 20+ (ESM) · Web `fastify` · Validation `zod` · DB `kysely` · Logger `pino` · Tests `vitest`.

---

## Node → Python

### Types
- TS interfaces → `@dataclass(slots=True)` or `pydantic.BaseModel`.
- Discriminated unions → `typing.Literal` fields + `typing.Union`, or tagged pydantic models.
- JS objects → typed dicts only as last resort; prefer models.

### Async
- `async/await` maps 1:1 — both use promises/coroutines.
- `Promise.all` → `asyncio.gather(*coros)`.
- `setInterval` → `asyncio.create_task` with a loop.

### HTTP
- Express / Fastify → FastAPI (preferred — mirrors TS + zod ergonomics) or Flask (legacy).
- Zod schemas → pydantic models.

### Data access
- `knex` / `prisma` → `SQLAlchemy 2.0` (async) or `asyncpg` for raw.
- Transactions → `async with session.begin(): ...`.

### Testing
- vitest / jest → pytest with `pytest-asyncio`.
- `describe/it` → `class Test...:` + `def test_...`.

### Preferred stack
Python 3.12+ · Web FastAPI · Validation pydantic v2 · DB SQLAlchemy 2 async or asyncpg · Tests pytest + pytest-asyncio.

---

## Go → Node/TypeScript

### Types
- Struct + interface → interface (data) + interface (behavior).
- `(T, error)` returns → throw exceptions OR return `Result<T,E>` via `neverthrow`. Pick one and be consistent.
- Go generics → TS generics (similar constraints via `extends`).

### Concurrency
- goroutines + channels → async functions + (maybe) event emitters or queues; be careful, JS is single-threaded — CPU-bound goroutines become worker threads.
- `sync.Mutex` around shared state → rethink design; usually unnecessary in Node's single-thread model.
- `context.Context` → `AbortSignal` passed as first or last arg.

### HTTP
- `chi` / `gin` → Fastify.
- Middleware signature changes but concept maps directly.

### Idioms
- Go's explicit errors vs JS's exceptions — commit to one. Mixing is the worst option.
- No `null` / `undefined` sloppiness — use strict null checks.

---

## Universal Anti-Patterns

Apply regardless of pair:

1. **Direct syntactic translation.** Don't port `for (let i=0; i<n; i++)` into a language with native iteration — use the idiom.
2. **Porting the original's error handling without review.** If source throws strings, target should have a real error type.
3. **Preserving file structure 1:1.** The source's module layout reflects its language's constraints. Redesign in Phase 3.
4. **Preserving naming conventions literally.** `snake_case` → `camelCase` / `PascalCase` per target convention.
5. **Preserving comments verbatim.** Re-comment for target idioms; drop comments that restate obvious code.
6. **Porting dead code.** Phase 1's `pain_points.md` flagged candidates — delete them, don't rewrite them.
7. **Porting the ORM.** Target ORM choice should reflect target ecosystem strengths, not match source by name.
8. **Porting the tests literally.** Rebuild the test suite from `tests/unit_plan.md` + `tests/integration_plan.md` in target idiom.
9. **Over-abstracting on day one.** Write straight-line code first. Extract only when the Rule-of-Three hits.
10. **Hand-rolling what the ecosystem provides.** Use target-native libraries for config, logging, validation, retries, etc.
