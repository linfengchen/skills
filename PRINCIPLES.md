# PRINCIPLES — Shared software design principles

Shared by `design`, `evolve`, and `rewrite` skills. Each skill's SKILL.md references this file in lieu of restating the rules.

Principles are organized in **four tiers** by scope:

- **Tier 1 — Code** (per function, per line)
- **Tier 2 — Module** (per package / per file group)
- **Tier 3 — System** (per service / cross-module)
- **Tier 4 — Meta** (when to apply the above)

Each entry uses a fixed three-part format:

> **One-line definition** — what the principle says.
> **Violation looks like** — concrete smell that means you broke it.
> **Doesn't apply when** — exceptions, so the principle doesn't become dogma.

---

## Tier 1 — Code-level

### YAGNI (You Aren't Gonna Need It)
- **Definition:** Do not add code, parameters, options, or abstractions that no current test or caller requires.
- **Violation:** Function with an unused arg "for future use"; config knob with no consumer; interface with one impl and no test fake; generics with one concrete instantiation.
- **Doesn't apply:** Error types and DTOs may precede consumers when they are part of an external contract (already in `api/`).

### KISS (Keep It Simple, Stupid)
- **Definition:** Among equally-correct solutions, pick the one that takes the least cognition to read.
- **Violation:** Reflection / metaprogramming where a switch would do; clever one-liners that need a comment to parse; channels/async where sequential is fine.
- **Doesn't apply:** Complexity is intrinsic (e.g. the algorithm itself is hard); then isolate it behind a small, well-named function.

### DRY + Rule of Three
- **Definition:** Extract a shared helper only when the **third** similar call site appears. The first two duplications are tolerable; premature extraction is worse.
- **Violation:** A `processX` "swiss army" function created on the second call site, that grows flags every quarter.
- **Doesn't apply:** Test code (duplication aids readability); declarative config; cross-cutting infra already standardized in the project.

### SRP (Single Responsibility)
- **Definition:** A function (or struct/class) has exactly one reason to change. The one-sentence summary contains no "and" / "also".
- **Violation:** `validateAndPersist`, `parseAndCache`, `loadAndAuthorize` — names that name two verbs.
- **Doesn't apply:** Orchestration functions that explicitly coordinate steps (`handleCheckoutRequest`) — but the body should be a sequence of single-responsibility calls, not inline business logic.

### Function size cap
- **Definition:** Soft target ≤ 60 LOC; hard cap depends on skill. `evolve` enforces ≤ 200 LOC absolutely.
- **Violation:** A function that scrolls past one screen with no extraction.
- **Doesn't apply:** Auto-generated code; truly exhaustive switches over a closed enum (consider a table-driven dispatcher instead).

### Naming describes intent
- **Definition:** Names describe **what the code does for the caller**, not the type or mechanism it uses.
- **Violation:** `processData`, `getUserFunc`, `manager`, `helper`, `data`, `info`.
- **Good:** `cancelExpiredOrders`, `userByEmail`, `idempotencyKeyMissing`.
- **Doesn't apply:** Generic algorithms (`cmp`, `eq`, `swap`).

### Fail fast
- **Definition:** Validate at the boundary; reject bad input on entry, not three layers deep.
- **Violation:** Silent coercion of bad data; deep null/None checks; exceptions caught and re-thrown without context.
- **Doesn't apply:** Batch processing where one bad record shouldn't kill the batch — then explicitly partition good/bad and report both.

### Explicit > Implicit
- **Definition:** Dependencies, types, and side effects are stated in the signature, not hidden.
- **Violation:** Globals, singletons, magic strings, implicit time/random/IO inside a "pure" function, hidden mutation of arguments.
- **Doesn't apply:** Language idioms that everyone knows (Go zero values, Python `None`-default-mutable warnings already handled).

### Pure where possible
- **Definition:** Domain/calculation functions take inputs, return outputs, no IO. Push side effects to the edges.
- **Violation:** `service.CalculatePrice` reads from DB inside; `domain.ValidateOrder` calls `time.Now()` directly.
- **Doesn't apply:** Adapter / handler / repo layers, whose entire purpose is IO. Inject the IO; don't fake purity.

---

## Tier 2 — Module-level

### High cohesion
- **Definition:** All symbols in a module serve one tightly-related responsibility.
- **Violation:** A `utils/` or `common/` package; a file containing user CRUD + auth + email sending.
- **Doesn't apply:** Truly orthogonal small helpers (`internal/clock`, `internal/idgen`) — these are single-purpose modules, not "utils".

### Low coupling
- **Definition:** Modules depend on a small, stable surface of other modules — preferably through abstractions, not concrete types.
- **Violation:** Module A imports B's internal package; circular imports; "god struct" passed everywhere.
- **Heuristic:** Public surface per module ≤ ~10 symbols unless justified.
- **Doesn't apply:** Domain types are allowed (and encouraged) to be widely imported as long as they remain stable.

### Open / Closed
- **Definition:** A module should be open to extension (add new behavior) without modification (changing existing code).
- **Violation:** Adding a new payment method requires editing five `switch` statements scattered across the code.
- **Doesn't apply:** When extension would create a worse API than just editing in place — premature OCP can fragment logic. Apply on the third extension, like Rule of Three.

### Liskov Substitution
- **Definition:** Subtypes must be usable wherever the parent type is, with no surprises (no extra exceptions, no weakened invariants).
- **Violation:** Subclass throws an error the parent didn't declare; subclass narrows a return value the caller relied on.
- **Doesn't apply:** Sealed hierarchies where subtypes are not interchangeable by design — make that explicit, don't fake polymorphism.

### Interface segregation
- **Definition:** Small, role-shaped interfaces (`Reader`, `Closer`, `UserLookup`) beat fat ones (`IUserRepo` with 25 methods).
- **Violation:** Tests must mock 20 methods to exercise a function that uses 2.
- **Doesn't apply:** When an interface is purely the concrete type's natural shape (e.g. one impl, defined for testing). Don't shred it pre-emptively.

### Dependency inversion
- **Definition:** High-level modules define the interface they need; low-level modules implement it. Wiring happens at composition root.
- **Violation:** `service.OrderService` directly imports `mysql.Client`; can't be tested without a DB.
- **Doesn't apply:** Adapter layers themselves (the place where concrete tech lives) — they are the implementation side.

### Tell, Don't Ask
- **Definition:** Ask an object to do work; don't fetch its state and decide externally.
- **Violation:** `if user.role == admin && user.active && !user.banned { ... }` repeated in five call sites.
- **Better:** `user.canModerate()` once, called everywhere.
- **Doesn't apply:** Pure data records (DTOs) — those exist to be queried.

### Law of Demeter
- **Definition:** A function should only invoke methods on (1) its arguments, (2) objects it created, (3) its own fields. Avoid `a.b.c.d`.
- **Violation:** `order.user.account.balance.subtract(...)` — caller knows too much about the object graph.
- **Doesn't apply:** Builder/fluent APIs explicitly designed to chain.

### Composition over inheritance
- **Definition:** Reuse via composition (embedding/delegation) is preferable to inheritance, which couples lifetime + interface + behavior.
- **Violation:** `class AdminUser extends User extends Auditable extends Persistent` — fragile base class problem incoming.
- **Doesn't apply:** True IS-A relationships in languages where inheritance is idiomatic for it (e.g. an `Exception` hierarchy).

---

## Tier 3 — System-level

### Layer respect (no skip)
- **Definition:** Calls flow top-down through declared layers (e.g. handler → service → repo → db). Skipping is forbidden.
- **Violation:** Handler reads from DB directly; repo emits events.
- **Doesn't apply:** Truly cross-cutting concerns (logging, tracing) that ride alongside the call rather than through it.

### Stable abstractions, unstable implementations
- **Definition:** The more a module is depended on, the more stable its public API must be. Frequent churn belongs in leaves, not hubs.
- **Violation:** Domain types' field set changes every sprint, breaking 30 callers.
- **Doesn't apply:** Pre-1.0 software — but mark it as such and version accordingly.

### Explicit error taxonomy
- **Definition:** Errors are typed values with categories (validation / not-found / conflict / forbidden / external / internal). Callers pattern-match, not string-grep.
- **Violation:** `errors.New("user not found")` returned everywhere; HTTP layer regex-matches messages to pick a status code.
- **Doesn't apply:** One-off CLI tools where one error category is enough.

### Idempotency by default
- **Definition:** Write operations are idempotent (or explicitly declared non-idempotent) so retries are safe.
- **Violation:** POST that doubles a charge on retry; queue consumer that double-publishes side effects.
- **Doesn't apply:** Genuinely non-idempotent ops (e.g. "send a one-time code") — then surface that explicitly in the API and use a dedupe key.

### Make illegal states unrepresentable
- **Definition:** Use the type system (sum types, NewType wrappers, smart constructors) so that bad combinations cannot compile.
- **Violation:** "If `status == closed` then `reason` is required" enforced only by runtime `if` checks scattered across code.
- **Better:** `Open { ... } | Closed { reason: NonEmpty }` as a sum type.
- **Doesn't apply:** Languages with weak type systems where the workaround costs more than runtime checks.

### Observability built-in
- **Definition:** Every external boundary (HTTP, RPC, queue, DB, retry) emits structured logs / metrics / traces consistently.
- **Violation:** Diagnosing prod requires adding `print` and re-deploying.
- **Doesn't apply:** Local-only tools / scripts.

### Principle of least astonishment
- **Definition:** Function behavior matches the name and signature. No hidden writes, no quiet retries, no surprise side effects.
- **Violation:** `getUser` writes a `last_seen_at` audit row; `validate` mutates the input.
- **Doesn't apply:** When the surprise IS documented and is the point (e.g. memoization helpers).

### Boy Scout Rule (gated)
- **Definition:** Leave the code cleaner than you found it.
- **Caveat for `evolve`:** Cleanup is **not free** — it must go through the refactor confirmation gate. Silent cleanup is a violation of the gate, not a virtue.
- **Doesn't apply (silently):** When the gate hasn't been crossed.

---

## Tier 4 — Meta

### Rule of Three applies to every abstraction
- Not just code (DRY): also interfaces, base classes, plugins, configuration knobs. **Until the third real instance exists, hard-code.**

### Testability is a design feedback signal
- If a function is hard to test, the design is wrong, not the test framework.
- Specific symptoms: needs many mocks → too many dependencies; needs `monkeypatch` or `unsafe.Pointer` to test → hidden coupling; setup is longer than the test → SRP violation.

### Delete > Refactor > Add
- In priority order:
  1. **Delete:** dead code, unused branches, vestigial flags.
  2. **Refactor:** simplify what stays.
  3. **Add:** only after the surface area has been compressed.
- A new feature is rarely the right place to "also add abstraction" — see YAGNI.

### Cost vs value of every abstraction
- Abstraction has a fixed cost: more files, more indirection, more cognitive load on every reader.
- Introduce only when the savings (clarity, reuse, testability) clearly exceed that cost. "Cleaner" is not a savings; cite a concrete benefit.

### Consistency > local optimum
- If the existing codebase has a convention, new code matches it — even if you'd write it differently in greenfield.
- `evolve` makes this a hard rule: see `arch_scan/conventions.md`.
- If you genuinely think the convention is wrong, raise a refactor proposal; don't introduce a second style.

### Tests embody specs
- A test passing/failing is a fact about whether the spec holds.
- Therefore: do not "fix" a test by relaxing it without changing the spec it embodies. Update spec + test together, in the open.

### Reversibility shapes risk tolerance
- Cheap-to-reverse decisions (a function name, a file location) — pick fast, change later.
- Expensive-to-reverse decisions (DB schema, public API, framework choice) — slow down, document the call, leave a migration plan.

---

## How the three skills use this file

| Skill | Where principles are enforced |
|---|---|
| `design` | Phase 5 implementation steps reference Tier 1; Phase 3 architecture uses Tier 2/3. |
| `evolve` | Phase 4 per-step "done" checklist enforces Tier 1; `arch_scan` fidelity enforces Tier 2/3 + "Consistency > local optimum"; refactor gate enforces "Boy Scout Rule (gated)" + "Delete > Refactor > Add". |
| `rewrite` | Phase 5 implementation steps reference Tier 1 with target-language idioms layered on top via `LANGUAGE_MAPPING.md`. |

This file is **not** a coding-style guide (formatting, naming case, file headers — that lives in each project's lint config). It is the **why-and-when** layer above style.
