---
name: evolve
description: >-
  Brownfield code-assistant orchestrator for evolving an existing codebase —
  adding features, fixing bugs, or making targeted changes. Runs a 6-phase
  checkpointed pipeline: requirement + top-level design + external-interface
  (categorized), existing architecture familiarization + test design (unit +
  interface), implementation plan + refactor proposal (the ONE confirmation
  point), iterative coding with YAGNI/DRY/KISS/SRP enforcement and a 200-line
  function cap, regression to zero failures, and a single final design doc
  covering code structure + usage. Use when the user asks to add a feature /
  modify / extend / iterate on an existing project, or says "在现有项目上做…",
  "给这个 repo 加…", "改这个服务", "加个接口", "实现一个功能". All actions
  default-authorized — only refactor proposals require user confirmation.
  Works identically on Claude Code and Cursor.
---

# evolve — Brownfield Feature/Change Orchestrator

Drives a feature, change, or bugfix through an existing codebase via a deterministic, checkpointed 6-phase pipeline. Optimized for **棕地** (existing code) work — Phase 2 reads the current architecture before any test or code is written, and Phase 3 surfaces unreasonable parts of the existing code as refactor proposals.

Invocation (either platform):
- `evolve <requirement_source> [project_dir]`
- Or natural language: "在当前 repo 加一个用户禁言接口，需求见 ./prd/mute.md"
- `requirement_source`: file path (`.md`/`.txt`/`.pdf`), URL, or raw description.
- `project_dir` defaults to the repo root (`.`). The skill detects target language from file extensions + lockfiles.

Examples:
- `evolve ./prd/mute-user.md ./`
- `evolve "给订单服务加一个'部分退款'接口，金额校验、幂等、审计日志" ./order-svc`
- `evolve https://wiki.internal/feature-x`

---

## Core Principles

1. **Default authorization.** Never prompt for approval — except the single Refactor Confirmation Gate in Phase 3 (see below). Every other decision is made by the skill, written to a design file, and considered done.
2. **One confirmation gate only.** When the skill identifies existing code that is in the way (poor cohesion, leaked abstraction, dead branch, silent error, layering violation) it emits a `refactor_proposals.md` and **stops**. The user replies `approve <ids>` / `reject <ids>` / `approve all` / `reject all`. No other phase pauses for approval.
3. **Auto-advance phases.** Outside the refactor gate and per-step stops in Phase 4, phases chain automatically in one invocation. State checkpoints between phases so interruption is safe.
4. **Architecture first, code second.** Phase 2 always reads the existing layout (modules, layers, DI pattern, error model, test infra) before designing tests; Phase 3 plans code changes inside that architecture, not on top of it.
5. **Tests before code.** Phase 2 finalizes the unit + interface test plan before Phase 4 writes any production code.
6. **YAGNI / KISS / DRY / SRP, hard.** Enforced inline in Phase 4. Hard cap: any single function > 200 lines is split before the step is marked done.
7. **Bug zero before docs.** Phase 5 iterates the test loop until 0 failures. Phase 6 only runs after that.
8. **One doc, not five.** Phase 6 produces exactly one `DESIGN.md` containing code structure + usage. Anything more belongs in code comments or commit messages.

---

## Directory Layout (created by Phase 0)

All planning artifacts live under `<project_dir>/.evolve/`. Production code lives wherever the existing repo says it should.

```
<project_dir>/
├── .evolve/
│   ├── state.json              # phase tracker + step status
│   ├── req/                    # Phase 1: requirement, categorized
│   │   ├── summary.md          # ≤300 words — the source of truth
│   │   ├── goals.md            # in-scope / non-goals / assumptions
│   │   ├── users.md            # actors + user stories
│   │   ├── functional.md       # FR-NN with acceptance criteria
│   │   ├── non_functional.md   # perf/security/availability targets
│   │   └── glossary.md         # domain terms
│   ├── design/                 # Phase 1: top-level design, categorized
│   │   ├── 00_overview.md      # one-page top-level design
│   │   ├── modules.md          # affected/new modules + responsibilities
│   │   ├── data_flow.md        # request → response (or event) walk-through
│   │   ├── data_models.md      # new/changed entities, schema deltas
│   │   └── error_model.md      # error taxonomy for this change
│   ├── api/                    # Phase 1: external interface, categorized
│   │   ├── endpoints.md        # HTTP/RPC/CLI surface (new + changed)
│   │   ├── events.md           # queue/pubsub/webhook contracts
│   │   ├── schemas.md          # DTOs / request-response shapes
│   │   └── compat.md           # backward-compat impact + migration notes
│   ├── arch_scan/              # Phase 2: existing architecture knowledge
│   │   ├── layout.md           # current dirs/packages, layer assignment
│   │   ├── conventions.md      # naming, error, logging, DI conventions
│   │   ├── extension_points.md # exact files/symbols this change will touch
│   │   └── test_infra.md       # current test framework, fixtures, mocks
│   ├── tests/                  # Phase 2: test design (unit + interface)
│   │   ├── unit_plan.md        # function-level scenarios
│   │   ├── interface_plan.md   # endpoint/RPC/CLI-level scenarios
│   │   └── fixtures.md         # seed data, mocks, test doubles
│   ├── plan/                   # Phase 3: implementation plan + refactor
│   │   ├── steps.md            # ordered step list (≤200 LOC each)
│   │   ├── refactor_proposals.md  # ★ confirmation gate ★
│   │   └── refactor_decision.md   # user verdict (after gate)
│   ├── coverage/               # Phase 5: regression tracking
│   │   ├── failures.md
│   │   └── summary.md
│   └── DESIGN.md               # Phase 6: the ONE final doc
└── <existing repo files...>
```

---

## Workflow Control

**On every invocation:**

1. If `<project_dir>/.evolve/state.json` does not exist → run **Phase 0** (bootstrap).
2. Else load it, read `phase`, execute that phase.
3. **Auto-advance rule:** after a phase completes, if `auto_advance` is true (default) and context allows, immediately execute the next phase. Mandatory stops:
   - End of Phase 3 if `refactor_proposals.md` is non-empty → wait for user verdict.
   - Per-step stop in Phase 4 (one step card per invocation).
   - Per-round stop in Phase 5 (one regression round per invocation).
   - Context saturating (skill's judgment) → checkpoint, print resume hint.
4. Never re-run a phase marked `done` unless user passes `--reset-phase N`.
5. **No confirmation prompts** outside the refactor gate. Decisions (test framework already in repo, where new files go, naming) are inferred from `arch_scan/conventions.md` and committed to design files. If the user disagrees, they edit the file or `--reset-phase`.

**Flags:**
- `--status` → print current state and exit.
- `--reset-phase <N>` → mark phase N pending, clear its outputs, set `phase = N`.
- `--repair` → reconstruct state.json from `.evolve/` contents.
- `--no-auto` → disable auto-advance for this invocation only.
- `--step-only` → write `auto_advance = false` permanently.
- `--run-all-steps` → in Phase 4, run consecutive step cards until done / blocked / context-full.
- `--skip-refactor` → in Phase 3, do not generate refactor proposals (treat all existing code as untouchable).

State schema: see [references/STATE_SCHEMA.md](references/STATE_SCHEMA.md).

---

## PHASE 0 — Bootstrap

Runs once.

1. Parse args. Read requirement source (file/URL/inline).
2. Detect target language(s) by scanning `<project_dir>` for lockfiles (`go.mod`, `Cargo.toml`, `package.json`, `pyproject.toml`, `pom.xml`, `build.gradle`, etc.). Record dominant language(s) into state.
3. Create `.evolve/` tree (empty files per the layout above).
4. Write initial `state.json` with `phase=1`, `auto_advance=true`, `language=<detected>`.
5. Auto-advance to Phase 1 unless `--no-auto`.

If `<project_dir>` has no recognizable build artifact, treat it as a fresh subproject and continue (the skill still works; it just won't have existing conventions to match).

---

## PHASE 1 — Requirement Understanding + Top-Level Design + External Interface (Categorized)

**Goal:** Compress the requirement into a structured knowledge base and design the top-level shape + external surface for *this change*. **Strictly categorized** — `req/` (what), `design/` (how, top-level), `api/` (external contract). Subsequent phases read these files, not the raw requirement.

### 1.1 — Requirement condensation (`req/`)

- **`req/summary.md`** — ≤ 300 words. What is being added/changed, for whom, why, and the critical success criterion.
- **`req/goals.md`** — bullets: in-scope; explicit non-goals (prevents scope creep); assumptions (when the source is ambiguous, default + record here).
- **`req/users.md`** — actors + user stories `As a <role>, I want <outcome>, so that <value>`. Include admin / ops / external-system actors.
- **`req/functional.md`** — numbered: `FR-NN: <capability>. Acceptance: <observable criterion>`.
- **`req/non_functional.md`** — perf, security, availability, observability targets (numbers, not vibes).
- **`req/glossary.md`** — domain terms with one-sentence definitions.

**Rule:** Never block on ambiguity. Default + record assumption. Move on.

### 1.2 — Top-level design (`design/`)

- **`design/00_overview.md`** — one page. Diagram (ASCII) of how the change slots into the existing system. Inputs, outputs, side effects, the 1–2 critical invariants.
- **`design/modules.md`** — table: `module | new or affected | responsibility | depends on`. Apply high cohesion / low coupling: if you write "and" / "also" in a responsibility, it's two modules.
- **`design/data_flow.md`** — for each major operation: request → validation → service → repo → response, including auth, errors, side effects.
- **`design/data_models.md`** — new/changed entities, field-level deltas, indices, migrations.
- **`design/error_model.md`** — error categories this change introduces or extends (validation / auth / not-found / conflict / external-failure / internal). Map to HTTP/RPC codes.

### 1.3 — External interface (`api/`)

- **`api/endpoints.md`** — every new/changed HTTP/RPC/CLI endpoint: method, path, input shape, output shape, auth requirement, error codes, idempotency, rate limit.
- **`api/events.md`** — queue/pubsub/webhook contracts: name, direction, schema, ordering/delivery guarantees.
- **`api/schemas.md`** — DTOs / request/response shapes referenced above. One place; reused by tests.
- **`api/compat.md`** — backward-compat impact: breaking? deprecation? migration? versioning strategy?

**Completion:** Mark `phases.1 = done`, `phase = 2`. Print 3-bullet summary (modules touched, endpoints added/changed, recorded assumptions). Auto-advance.

---

## PHASE 2 — Existing Architecture Familiarization + Test Design (Unit + Interface)

**Goal:** Become competent in the current codebase before designing tests. Then design the full unit + interface test plan grounded in `api/` from Phase 1.

### 2.1 — Architecture scan (`arch_scan/`)

Read the repo structure, then write:

- **`arch_scan/layout.md`** — tree of top-level packages/dirs with one-line responsibility each. Identify layers (handler / service / repo / domain / infra). Note any existing layering violations as observations (these may become refactor proposals in Phase 3).
- **`arch_scan/conventions.md`** — observed conventions: naming style, error type/wrapping, logging library, config loader, DI pattern, validation library, transaction boundary, idempotency mechanism. New code in Phase 4 must match these.
- **`arch_scan/extension_points.md`** — exact files & symbols Phase 4 will touch or extend, plus a short note on each ("add new handler in `internal/api/handlers/order.go` next to `RefundHandler`"). Also list files explicitly *not* to touch.
- **`arch_scan/test_infra.md`** — current test framework, runner command, fixture/mock pattern, where integration tests live, how the DB/HTTP test harness is bootstrapped.

**Rule:** Read existing code, don't summarize-then-imagine. Cite real file paths in every entry.

### 2.2 — Test design (`tests/`)

Specs only — no test code yet.

- **`tests/unit_plan.md`** — table: `module | function | scenario | input | expected outcome | mocks needed`. Cover happy path, edge cases, error paths, boundary values for every public function added/changed in Phase 1.
- **`tests/interface_plan.md`** — table: `METHOD path (or RPC) | scenario | request | expected status | expected body shape | auth context`. Include validation, auth, idempotency, pagination, error mapping, and (for events) consume/publish round-trips.
- **`tests/fixtures.md`** — seed data, factories, test doubles, container/harness setup. Reuse existing patterns from `arch_scan/test_infra.md`.

**Rule:** Another engineer must be able to implement any test from the description alone.

**Completion:** Mark `phases.2 = done`, `phase = 3`. Auto-advance.

---

## PHASE 3 — Implementation Plan + Refactor Proposal (★ Confirmation Gate ★)

**Goal:** Plan the implementation as small steps that fit the existing architecture, and surface any existing code that is in the way as **refactor proposals** for explicit user approval. This is the only place the skill ever stops for confirmation.

### 3.1 — Step-by-step implementation plan (`plan/steps.md`)

Order:
1. Domain models / types (no deps)
2. Shared utilities (only if Rule of Three triggers)
3. Repo / data-access layer (incl. migrations)
4. Service / use-case layer
5. Handlers / adapters / routes
6. Wiring / config / DI
7. Integration glue last

For each step: name, target files, summary (1–2 sentences), expected LOC (≤200), tests from Phase 2 it satisfies, dependencies on previous steps.

### 3.2 — Refactor proposals (`plan/refactor_proposals.md`)

While reading the code in Phase 2, the skill noted unreasonable parts that block clean implementation. List them now as numbered proposals:

```
RP-01  Split god-function `OrderService.Process` (412 LOC) into intake/validate/persist/dispatch
       Why blocking: new partial-refund flow needs to reuse validate + persist independently.
       Risk: medium. Touches: internal/service/order.go and 3 callers.
       Cost: ~1 step. Tests: covered by existing service tests + interface tests.
```

For each proposal: ID, one-line title, why it blocks the new feature, risk (low/medium/high), files touched, cost in steps, test coverage situation.

If `--skip-refactor` is set, write the file with header `# Skipped` and zero items.

### 3.3 — Confirmation gate

If `refactor_proposals.md` has ≥ 1 item AND `--skip-refactor` is not set:

1. Mark `phases.3 = waiting_refactor_decision`.
2. Print the proposal list with IDs and one-line titles.
3. **Stop.** Tell the user: reply `approve <ids>` (e.g. `approve RP-01 RP-03`), `reject <ids>`, `approve all`, `reject all`, or `defer <ids>` (defer = do as a follow-up after the feature ships).

On the next invocation:

1. Parse user reply, write `plan/refactor_decision.md`:
   - `approved`: list of IDs and steps inserted into `plan/steps.md` (prepended before the step that needs them, in dependency order).
   - `rejected`: list of IDs with note "implementation must work around this".
   - `deferred`: list of IDs (recorded but not implemented now; surfaces again in `DESIGN.md`).
2. Update `plan/steps.md` accordingly.
3. Mark `phases.3 = done`, `phase = 4`. Auto-advance to Phase 4 first step.

If `refactor_proposals.md` is empty (or `--skip-refactor`), mark `phases.3 = done` directly and auto-advance.

---

## PHASE 4 — Iterative Implementation

**Goal:** Implement one step at a time. **Always stop after each step** (per-step accumulation otherwise blows context).

**Per step:**

1. Read `state.json → current_step = N`.
2. Read step entry from `plan/steps.md`.
3. Read only the design files relevant to this step (e.g. one module card + the matching `api/` entries + the test plan rows). Do not re-read the raw requirement.
4. Implement only what the step specifies. Write target files using existing repo conventions (`arch_scan/conventions.md`).
5. **Enforce inline:**
   - All of [`../PRINCIPLES.md`](../PRINCIPLES.md) **Tier 1** (YAGNI / KISS / DRY+Rule-of-Three / SRP / naming / fail-fast / explicit / pure-where-possible).
   - All of [`../PRINCIPLES.md`](../PRINCIPLES.md) **Tier 2/3** at module/system boundaries (cohesion, coupling, layer respect, error taxonomy, idempotency).
   - `evolve`-specific gates from [`references/QUALITY_GATES.md`](references/QUALITY_GATES.md):
     - **E1 — Hard 200-LOC function cap.** Split before marking done.
     - **E2 — Match existing conventions** from `arch_scan/conventions.md` (formatter, linter, errors, logger, DI, tests).
     - No silent refactor of pre-existing code (must be in step card OR an approved RP).
6. Compile / type-check. Fix errors.
7. Run the step's attached unit + interface tests (write them too, per Phase 2 specs). Fix failures.
8. Run the project linter/formatter. Fix warnings.
9. Mark step status `done` in `plan/steps.md`. Update `state.json → current_step = N + 1`.
10. Print: step name, files written/modified, LOC, tests run, pass/fail.
11. **Stop.** User says "继续" or `evolve` to advance.

**If a step is blocked:**
- Mark `Status: blocked` on the step. Append a `## Blocker` line.
- Update `state.json → blocked_step = N`.
- Print the blocker. Do not skip ahead.

**If you discover *new* unreasonable existing code mid-implementation:**
- Do **not** silently refactor. Add a new entry to `plan/refactor_proposals.md` with a `(discovered in Phase 4)` tag, set `phases.4 = waiting_refactor_decision`, and stop for confirmation. After verdict, resume.

**Completion:** When `current_step` exceeds the last index, mark `phases.4 = done`, `phase = 5`. Auto-advance to Phase 5 round 1.

**Optional flag `--run-all-steps`:** Execute consecutive steps until done / blocked / context saturates / a new refactor proposal is needed.

---

## PHASE 5 — Regression Loop (Bug Zeroing)

**Goal:** Full unit + interface suite green before any docs.

**Per round:**

1. Run full test suite (use the runner from `arch_scan/test_infra.md`).
2. Parse results into `coverage/failures.md`: `test | category (unit/interface) | owning module | first seen round | note`.
3. Group by owning module. Fix the module with the most failures first.
4. Cap per round: **fix up to 5 failures or 1 module, whichever is smaller**.
5. Re-run only affected tests to confirm fixes. Then re-run full suite at end of round.
6. Update `coverage/failures.md`.
7. Print: total / passing / failing / delta vs last round / next module to fix.
8. **Stop.**

**Anti-pattern:** "Fix by deleting the test." Only valid if the test contradicts the Phase 2 spec; in that case, update the spec + the test together, log in `coverage/failures.md` with reason.

**When failures = 0:**
- Run coverage report (if available). Write `coverage/summary.md` with: total tests, pass rate, coverage % (if available), per-module breakdown.
- Mark `phases.5 = done`, `phase = 6`. Auto-advance to Phase 6.

---

## PHASE 6 — Final Documentation (One File Only)

**Goal:** Produce **exactly one** document: `<project_dir>/.evolve/DESIGN.md`.

**Hard rules:**
- One file, no others. Do not write README updates here. Do not write per-module docs.
- ≤ 1500 words total. If it doesn't fit, cut, don't split.
- No marketing language. No restating the requirement.

**Required sections (in order):**

1. **Overview** (≤ 150 words) — what was built, why, the critical success criterion. Pulled from `req/summary.md`.
2. **Code Structure** — ASCII tree of the *new + modified* files only (not the whole repo), each with a one-line responsibility. Pulled from `plan/steps.md` final state.
3. **Module Responsibilities** — table: `module | responsibility | key public symbols`. ≤ 12 rows; if more, group.
4. **External Interface** — endpoints / events table: `name | input | output | error codes | auth`. Pulled from `api/`.
5. **Data Model Changes** — list new/changed entities + migration notes. Pulled from `design/data_models.md`.
6. **How To Use** — runnable snippets:
   - How to run the service locally
   - How to call the new endpoint(s) (curl / SDK example)
   - How to run unit tests
   - How to run interface tests
   - Any config/env vars introduced
7. **Refactors Applied / Deferred** — table from `plan/refactor_decision.md`: `RP-id | title | status (applied / rejected / deferred) | follow-up if any`.
8. **Tests & Coverage** — one-line summary from `coverage/summary.md`.
9. **Assumptions & Open Questions** — any item from `req/goals.md` Assumptions, plus deferred refactors with follow-up TODOs.

**Completion:** Mark `phases.6 = done`. Print final status: phases completed, files written/modified, LOC delta, tests added, pass rate, refactor verdicts.

---

## Anti-Patterns

- **Asking for approval outside the refactor gate.** The user pre-authorized everything else. Decide, write, move on.
- **Refactoring without a proposal.** Any change to existing code that is not strictly required to satisfy the new requirement must be a numbered proposal in `plan/refactor_proposals.md`. No silent cleanup.
- **Skipping `arch_scan/`.** Tests and code that ignore existing conventions cause friction. Always read first.
- **Re-reading the raw requirement.** After Phase 1, read `req/*.md` and the targeted module/api/test cards only.
- **Writing functions > 200 lines.** Hard fail. Split before marking the step done.
- **Adding speculative abstractions.** Rule of Three before any shared helper. Interfaces only at consumer side, only when there's a real second implementation (or a real test fake).
- **Producing more than one final doc.** Phase 6 is one file. Inline anything else as code comments / commit messages.
- **Touching files listed under `arch_scan/extension_points.md` "do not touch".** If you must, raise a refactor proposal.

---

## Cross-Platform Notes

Works identically on **Claude Code** and **Cursor** — both auto-discover the skill via SKILL.md frontmatter. No platform-specific syntax. File and shell tools are invoked in natural language; each host uses its native tooling.

---

## References (loaded on demand)

- **[../PRINCIPLES.md](../PRINCIPLES.md)** — shared 4-tier software design principles (YAGNI/KISS/DRY/SRP, SOLID, cohesion/coupling, layering, error taxonomy, etc.). Read this before Phase 4 implementation.
- [references/STATE_SCHEMA.md](references/STATE_SCHEMA.md) — `state.json` schema, repair protocol, auto_advance + refactor-gate semantics.
- [references/TEMPLATES.md](references/TEMPLATES.md) — output templates for every phase artifact (req, design, api, arch_scan, tests, plan, refactor proposal, step entry, DESIGN.md).
- [references/QUALITY_GATES.md](references/QUALITY_GATES.md) — `evolve`-specific gates layered on top of PRINCIPLES.md: 200-LOC hard cap, convention-match rule, refactor-proposal rubric, per-step done checklist.
