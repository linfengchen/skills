---
name: design
description: >-
  Greenfield product-to-code orchestrator. Turns a product requirement (PRD,
  user story list, spec doc, or natural-language description) into a layered
  target-language implementation via a 7-phase checkpointed pipeline:
  requirement + module + external-interface design, test contract, architecture,
  step-by-step breakdown, iterative implementation, regression-to-zero, and
  concise final docs. Use when the user asks to design, build, implement, or
  scaffold a new product/feature/service from a requirement description, or
  mentions "产品需求", "从零实现", "新项目", "PRD", "设计并实现". Runs with
  default authorization — never asks for approval mid-flow. Works identically
  on Claude Code and Cursor.
---

# design — Requirement → Implementation Orchestrator

Takes a product requirement as input and produces a working, tested codebase in the target language via a deterministic, checkpointed 7-phase pipeline. Optimized for greenfield work (no existing code to port).

Invocation (either platform):
- `design <requirement_source> <target_lang> [project_dir]`
- Or natural language: "根据这份 PRD 设计并实现一个 go 服务，项目目录 ./order-svc"
- `requirement_source` can be: a file path (`.md`, `.txt`, `.pdf`), a URL, or a raw description in the chat.
- Supported target languages: go, rust, node/typescript, python. Others work with best-effort idioms.

Examples:
- `design ./prd.md go ./order-svc`
- `design "管理团队任务的 REST API，支持任务 CRUD、指派、到期提醒" rust ./tasks-rs`
- `design https://internal/wiki/feature-x ts ./feature-x`

---

## Core Principles

1. **Default authorization.** Never prompt for approval. Never ask "shall I continue?". All actions pre-authorized.
2. **Auto-advance phases.** Unless the user explicitly intervenes or context is saturated, proceed phase-to-phase in one invocation. Checkpoint state between phases so interruption is still safe.
3. **Checkpoint everything.** State lives in `<project_dir>/.design/state.json`. Resumable from any phase boundary or step.
4. **Summaries, not re-reads.** Phase 1 extracts structured knowledge from the requirement. Later phases read those summaries — not the raw requirement — to save tokens.
5. **Tests before code.** Phase 2 defines the full test contract before Phase 5 writes a line of implementation.
6. **Small steps.** Phase 4 shards implementation into 30–120 LOC units; Phase 5 implements one per invocation (prevents scope drift in long sessions).
7. **YAGNI / KISS / DRY / SRP.** Enforced inline during Phase 5.
8. **Zero-failure gate.** Phase 6 iterates until every test is green before Phase 7.
9. **Minimal docs.** Phase 7 caps length hard.

---

## Directory Layout (created by Phase 0)

```
<project_dir>/
├── .design/
│   ├── state.json              # phase tracker + module status
│   ├── req/                    # Phase 1 outputs
│   │   ├── summary.md          # condensed requirement (the source of truth)
│   │   ├── goals.md            # goals + non-goals
│   │   ├── users.md            # actors / user stories
│   │   ├── functional.md       # functional requirements
│   │   ├── non_functional.md   # NFR: perf, security, availability, scale
│   │   └── glossary.md         # domain terms
│   ├── modules/                # Phase 1: module decomposition
│   │   ├── 00_index.md         # module map
│   │   └── <module>.md         # one card per module
│   ├── api/                    # Phase 1: external interface contracts
│   │   ├── endpoints.md        # HTTP/RPC/CLI surface
│   │   ├── events.md           # queue / pubsub / webhook contracts
│   │   └── schemas.md          # request/response/DTO shapes
│   ├── tests/                  # Phase 2 outputs
│   │   ├── unit_plan.md
│   │   ├── integration_plan.md
│   │   ├── contract_plan.md
│   │   └── infra_plan.md
│   ├── arch/                   # Phase 3 outputs
│   │   ├── architecture.md
│   │   ├── data_models.md
│   │   ├── directory_tree.md
│   │   └── tech_choices.md
│   ├── steps/                  # Phase 4 step cards
│   │   ├── 00_index.md
│   │   └── NN_<name>.md
│   ├── coverage/               # Phase 6 regression tracking
│   │   ├── failures.md
│   │   └── summary.md
│   └── docs/                   # Phase 7 final docs
└── <actual target code>        # populated from Phase 5 onward
```

---

## Workflow Control

**On every invocation:**

1. If `<project_dir>/.design/state.json` does not exist → run **Phase 0** (bootstrap).
2. Else load it, read `phase`, execute that phase.
3. **Auto-advance rule:** after a phase completes, check `auto_advance` in state.json (default `true`). If true and context allows, immediately execute the next phase in the same invocation. Stop conditions:
   - `phase == 5` (implementation): always stop after each individual step card completes — they accumulate context fast.
   - `phase == 6` (regression): stop after each round — lets user inspect delta.
   - Context usage is saturating (assistant's judgment): stop, write state, print resume hint.
   - User has explicitly set `auto_advance = false` via flag.
4. Never re-run a phase marked `done` unless user passes `--reset-phase N`.
5. **No confirmation prompts.** The user pre-authorized all actions. Decisions (framework choice, module boundaries, test strategy) are made by the skill based on best practice + `references/LANGUAGE_STACKS.md`, then written to the output files. If the user wants to change something, they edit the file or re-run with `--reset-phase`.

**Flags:**
- `--status` → print current state and exit.
- `--reset-phase <N>` → mark phase N pending, clear its outputs, set `phase = N`.
- `--repair` → reconstruct state.json from `.design/` contents.
- `--no-auto` → disable auto-advance for this invocation (runs only current phase).
- `--step-only` → force stop-per-phase permanently (writes `auto_advance = false` to state).

State schema: see [references/STATE_SCHEMA.md](references/STATE_SCHEMA.md).

---

## PHASE 0 — Bootstrap

Runs once. Parse args, read the requirement source (file / URL / inline text), detect target language, create `.design/` tree, write initial state.json with `phase=1`, `auto_advance=true`. Auto-advance to Phase 1 unless `--no-auto`.

---

## PHASE 1 — Requirement Understanding, Module Design, External Interface

**Goal:** Compress the requirement into a structured knowledge base. Define modules and external interfaces. This is the single source of truth for all later phases.

Execute in this fixed order:

### 1.1 — Requirement condensation (`req/`)

- **`req/summary.md`** — ≤ 300 words. What is being built, for whom, why, and the critical success criterion. Everything downstream derives from this.
- **`req/goals.md`** — bullet lists: in-scope goals; explicit non-goals (equally important — prevents scope creep).
- **`req/users.md`** — actors + representative user stories in `As a <role>, I want <outcome>, so that <value>` form. Include admin / ops / external-system actors, not just end users.
- **`req/functional.md`** — numbered functional requirements. Each: `FR-NN: <one-sentence capability>. Acceptance: <observable criterion>`.
- **`req/non_functional.md`** — performance (latency, throughput), availability, security, compliance, scalability, observability. Include targets (numbers), not vibes.
- **`req/glossary.md`** — domain terms with one-sentence definitions. Use these consistently throughout the project.

**Rule:** If the source requirement is ambiguous on a point, make a reasonable default, record it in `glossary.md` or `goals.md` under "Assumptions", and continue. Do not block to ask.

### 1.2 — Module decomposition (`modules/`)

Decompose into modules applying **high cohesion, low coupling**. One card per module at `modules/<name>.md` (see [references/TEMPLATES.md](references/TEMPLATES.md#phase-1--module-card)):

- Responsibility (1–2 sentences; if you need "and" / "also" you probably have 2 modules).
- Public interface (functions/methods with pseudocode signatures).
- Domain entities owned by this module.
- Side effects (DB tables, external calls, queues, filesystem, env).
- Business rules and invariants (the "why", the gotchas).
- Dependencies on other modules.

Write `modules/00_index.md` as a table: `module | layer | responsibility | depends on`.

### 1.3 — External interfaces (`api/`)

- **`api/endpoints.md`** — every HTTP/RPC/CLI endpoint: method, path, input shape, output shape, auth requirement, error codes, idempotency, rate limits.
- **`api/events.md`** — queue messages / pubsub topics / webhooks: name, direction (publish/consume), schema, ordering/delivery guarantees.
- **`api/schemas.md`** — DTOs / request & response shapes referenced by the above. Keep definitions in one place for reuse.

**Completion:** Mark `phases.1 = done`, `phase = 2`. Print 3-bullet summary (module count, endpoint count, flagged assumptions). Auto-advance to Phase 2.

---

## PHASE 2 — Test Contract Design

**Goal:** Define the full regression surface before any implementation.

1. **`tests/unit_plan.md`** — table: `module | function | scenario | expected outcome | mocks needed`. Cover happy path, edge cases, error paths, boundary values for every public function surfaced in Phase 1.
2. **`tests/integration_plan.md`** — table: `METHOD path | scenario | request | expected status | expected response shape`. Include auth scenarios, validation scenarios, idempotency, pagination.
3. **`tests/contract_plan.md`** — external contracts the service consumes (upstream APIs, message shapes, DB schema assumptions).
4. **`tests/infra_plan.md`** — target-language test harness, fixtures, seed data, mock strategy.

**Rule:** Specs, not code. Another engineer could implement any test from the description alone.

**Completion:** Mark `phases.2 = done`, `phase = 3`. Auto-advance.

---

## PHASE 3 — Target Architecture Design

**Goal:** Design the new codebase structure. **No approval pause** — commit decisions to files; user can modify later via `--reset-phase 3`.

Consult [references/LANGUAGE_STACKS.md](references/LANGUAGE_STACKS.md) for the chosen target.

1. **`arch/architecture.md`** — target layers (idiomatic), module-to-package mapping table, dependency injection pattern, error handling strategy, concurrency model, observability hooks.
2. **`arch/data_models.md`** — target-language struct/type/interface definitions for all domain entities. Apply target idioms (Go interfaces at consumer side; Rust `Result<T,E>` + error enums; TS discriminated unions; Python pydantic/dataclass).
3. **`arch/directory_tree.md`** — full proposed skeleton tree (file names only, no bodies).
4. **`arch/tech_choices.md`** — router/web framework, DB/query builder, test framework, logger, config lib, linter/formatter, CI hooks. One-sentence justification per choice.

**Design rules:**
- High cohesion, low coupling. Each module has a single clear responsibility.
- Prefer constructor-injected interfaces/traits over globals or singletons.
- Public surface per module < 10 symbols unless justified.
- No layer skips (handler → repo without service) unless the operation is truly trivial.
- Explicit, typed error taxonomy.

**Completion:** Scaffold the directory tree in `project_dir` (empty files per `directory_tree.md`). Mark `phases.3 = done`, `phase = 4`. Auto-advance.

---

## PHASE 4 — Step-by-Step Implementation Plan

**Goal:** Shard implementation into the smallest independently-testable units.

Ordering:
1. Domain models / types (no deps)
2. Shared utilities
3. Repo / data-access layer
4. Service / use-case layer
5. Handlers / adapters / routes
6. Wiring / `main` / bootstrap
7. Integration glue last

Each step:
- ~30–120 lines of target code
- Compiles (or type-checks) on its own
- Has at least one test from Phase 2 attached

Write `.design/steps/NN_<name>.md` per step using the template in [references/TEMPLATES.md](references/TEMPLATES.md#phase-4--step-card). Write `.design/steps/00_index.md` as an ordered table: `step # | name | status | target files | tests`. Update `state.json → modules` and set `current_step = 0`.

**Completion:** Mark `phases.4 = done`, `phase = 5`, `current_step = 0`. Auto-advance to Phase 5 first step.

---

## PHASE 5 — Iterative Implementation

**Goal:** Implement one step at a time. **Always stop after each step** — this is the one place auto-advance does NOT apply, because per-step accumulation would blow context.

**Per step:**

1. Read state → `current_step = N`.
2. Read `steps/NN_<name>.md` (the step card).
3. Implement only what the card specifies. Write target files.
4. **Enforce inline:**
   - **YAGNI** — no speculative abstractions or config knobs.
   - **KISS** — simplest correct form wins. No clever one-liners.
   - **DRY** — grep existing target code for a helper before writing a new one.
   - **SRP** — one function, one job. Functions > ~40 lines must be split.
   - **Rule of three** — no shared helper until the third similar call site exists.
   - **Naming** — describe intent, not type. `userByID`, not `getUserFunc`.
5. Compile / type-check. Fix errors.
6. Run the step's attached unit tests. Fix failures.
7. Run linter. Fix warnings.
8. Mark step card `Status: done`. Update `state.json → modules[N].status = done`, `current_step = N + 1`.
9. Print: step name, files written, LOC added, tests run, pass/fail counts.
10. **Stop.** User re-invokes for the next step (or runs `design --continue-all` to auto-iterate steps — see flags).

**If a step is blocked:**
- Mark `Status: blocked`. Add a `## Blocker` section to the card.
- Update `state.json → blocked_step = N`.
- Print the blocker. Do not skip ahead.

**Completion:** When `current_step` exceeds the last index, mark `phases.5 = done`, `phase = 6`. Auto-advance to Phase 6 round 1.

**Optional flag `--run-all-steps`:** Execute multiple steps back-to-back in one invocation until (a) context saturates, (b) a step is blocked, or (c) all steps complete. Use this when the user says "把步骤都跑完" / "implement everything".

---

## PHASE 6 — Regression Loop (Bug Zeroing)

**Goal:** Full suite green.

**Per round:**

1. Run full test suite.
2. Parse results into `coverage/failures.md`: `test | category | owning module | first seen round | note`.
3. Group by owning module. Fix module with the most failures first.
4. Fix up to **5 failures or 1 module per round** (whichever is smaller).
5. Re-run affected tests to confirm fixes.
6. Update `coverage/failures.md`.
7. Print: total / passing / failing / delta / next module.
8. Stop.

**Anti-pattern:** "Fix by deleting the test." Only valid if the test was wrong per Phase 2 spec; then update the spec + test, and log in `coverage/failures.md`.

**When failures = 0:**
- Run coverage report. Write `coverage/summary.md`.
- Mark `phases.6 = done`, `phase = 7`. Auto-advance to Phase 7.

---

## PHASE 7 — Final Documentation

**Goal:** Minimum useful docs. Hard caps.

Exactly five files, nothing more:

1. **`docs/README.md`** — ≤ 3 paragraphs: what the service does, how to run locally, how to run tests.
2. **`docs/architecture.md`** — ≤ 3 pages: ASCII layer diagram, module responsibility table, data-flow for the 2–3 most important operations.
3. **`docs/api.md`** — endpoint reference generated from code if the target language supports it (godoc / rustdoc / typedoc), otherwise from `tests/integration_plan.md`.
4. **`docs/decisions.md`** — ADR list, max 10 rows: `Decision | Alternatives | Reason chosen`.
5. **`docs/operations.md`** — how to deploy, how to observe (logs/metrics/traces), how to roll back, known runbooks. ≤ 500 words.

**Rule:** Any single doc exceeding 500 words → cut.

**Completion:** Mark `phases.7 = done`. Print final status: phase counts, total LOC, test count, coverage %.

---

## Anti-Patterns

- **Asking for approval.** The user pre-authorized. Make a decision, write it to the design file, move on.
- **Skipping module / interface design.** Phase 1 is non-negotiable — later phases depend on its outputs.
- **Skipping tests.** Phase 2 must finish before Phase 5 starts.
- **Reading the raw requirement repeatedly.** Read `req/summary.md` and the specific `req/*.md` / `modules/*.md` you need. The original requirement is only re-read if a specific new question arises.
- **Over-engineering day one.** Straight-line code first. Rule of Three before shared abstractions.
- **Porting patterns from other languages.** Use target-native idioms per `LANGUAGE_STACKS.md`.
- **Over-documenting.** Phase 7 hard caps are not suggestions.

---

## Cross-Platform Notes

Works identically on **Claude Code** and **Cursor** — both auto-discover the skill via SKILL.md frontmatter. No platform-specific syntax. Tool invocations described in natural language; each host uses its native file/shell tools.

---

## References (loaded on demand)

- [references/STATE_SCHEMA.md](references/STATE_SCHEMA.md) — `state.json` schema, repair protocol, auto_advance semantics.
- [references/TEMPLATES.md](references/TEMPLATES.md) — output templates for every phase.
- [references/LANGUAGE_STACKS.md](references/LANGUAGE_STACKS.md) — per-target-language layer patterns, preferred stacks, idioms. Read during Phase 3.
