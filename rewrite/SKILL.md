---
name: rewrite
description: >-
  Large-scale cross-language codebase rewrite orchestrator (Node↔Go, Python↔Rust,
  Python↔Node, etc.) for 100K+ line projects. Runs a checkpointed 7-phase workflow
  with resumable state so long rewrites survive context limits and interruptions.
  Use when the user asks to rewrite, port, migrate, or translate a codebase from
  one language to another, or mentions "重构", "转 go/rust/node", "cross-language
  migration". Works identically on Claude Code and Cursor.
---

# rewrite — Cross-Language Codebase Rewrite Orchestrator

Turns a large-scale language migration into a deterministic, checkpointed pipeline. Designed for codebases of 100K–1M+ lines where a single-shot rewrite is impossible and context windows force interruption.

Invocation (either platform):
- Say: "rewrite this project to go" / "port to rust" / "重构成 node"
- Or invoke explicitly: `rewrite <source_dir> <target_lang> [target_dir]`
- Examples: `rewrite ./api go ./api-go`, `rewrite ./svc rust ./svc-rs`

Supported pairs (any direction): Node/TypeScript ↔ Go ↔ Python ↔ Rust. Same workflow applies to other pairs.

---

## Core Principles

1. **Checkpoint everything.** All state in `<target_dir>/.rewrite/state.json`. Resumable after any interruption.
2. **One phase per session.** Never auto-advance across phase boundaries. Print status, stop, let the user re-invoke. Keeps context clean.
3. **Summaries, not source.** Phase 1 extracts structured knowledge. Later phases read that — not the original source — to save tokens.
4. **Tests before code.** Phase 2 defines the full test contract before a single target line is written.
5. **Architecture before implementation.** Phase 3 pauses for explicit user approval. Wrong architecture is 10× more expensive later.
6. **Small steps.** Phase 4 shards implementation into 30–120 line units. Each step is independently testable.
7. **YAGNI / KISS / DRY / SRP.** Phase 5 enforces these inline.
8. **Zero-failure gate.** Phase 6 iterates until the full suite is green before Phase 7.
9. **Minimal docs.** Phase 7 caps length. Docs nobody reads are worse than none.

---

## Directory Layout (created by Phase 0)

```
<target_dir>/
├── .rewrite/
│   ├── state.json              # phase tracker + module status
│   ├── arch/                   # Phase 1: extracted knowledge
│   │   ├── inventory.md
│   │   ├── dependencies.md
│   │   ├── layers.md
│   │   ├── modules/<name>.md   # one file per logical module
│   │   ├── api.md
│   │   ├── cross_cutting.md
│   │   └── pain_points.md
│   ├── tests/                  # Phase 2: test specifications
│   │   ├── unit_plan.md
│   │   ├── integration_plan.md
│   │   ├── contract_plan.md
│   │   └── infra_plan.md
│   ├── design/                 # Phase 3: target architecture
│   │   ├── architecture.md
│   │   ├── data_models.md
│   │   ├── directory_tree.md
│   │   └── tech_choices.md
│   ├── modules/                # Phase 4: step cards
│   │   ├── 00_index.md
│   │   └── NN_<name>.md
│   ├── coverage/               # Phase 6: regression tracking
│   │   ├── failures.md
│   │   └── summary.md
│   └── docs/                   # Phase 7: final documentation
└── <actual target code>        # populated from Phase 5 onward
```

---

## Workflow Control

**On every invocation:**

1. If `<target_dir>/.rewrite/state.json` does not exist → run **Phase 0** (bootstrap).
2. Else load it, read `phase`, execute **exactly that phase**, update state, print a summary, **stop**.
3. Never auto-advance. Never batch phases. User re-invokes to proceed.
4. Never re-run a phase marked `done` unless user passes `--reset-phase N`.

**Flags (recognized in any invocation):**
- `--status` → print current state and exit.
- `--reset-phase <N>` → mark phase N pending, clear its outputs in `.rewrite/`, set `phase = N`.
- `--repair` → reconstruct state.json from the contents of `.rewrite/`.

State schema: see [references/STATE_SCHEMA.md](references/STATE_SCHEMA.md).

---

## PHASE 0 — Bootstrap

Runs once. Parse args, detect source language, create `.rewrite/` tree, write initial state.json with `phase=1`, print a brief detected-inventory summary (file count, LOC, language, entry points), stop.

---

## PHASE 1 — Architecture & Knowledge Extraction

**Goal:** Compress the source codebase into dense, structured markdown. Everything downstream reads these, not the source.

**For a 300K+ line codebase, partition first:** if LOC > 100K or module count > 30, split into batches and process one batch per invocation (track in `state.json → arch_progress`). Do NOT attempt all modules in one session.

Produce, in this order:

1. **`arch/inventory.md`** — file counts by extension, total LOC, binary entry points, build/run scripts, dependency manifest files.
2. **`arch/dependencies.md`** — external deps grouped by purpose (HTTP framework, DB driver, queue, auth, logging, observability, config, cache, etc.). One line per dep: name → purpose → replacement candidate in target language.
3. **`arch/layers.md`** — detected layers (presentation / service / domain / repo / infra / config / shared). Map top-level directories → layers.
4. **`arch/modules/<name>.md`** — one file per logical module. Each contains:
   - Responsibility (1–2 sentences)
   - Public interface (exported functions/classes/routes with signatures — target-lang-agnostic pseudocode)
   - Data models (key structs/types/schemas — names + fields only, types in pseudocode)
   - Side effects (DB tables touched, external APIs, queues, filesystem, env vars)
   - **Non-obvious business rules** (the "why" — invariants, gotchas, legacy constraints). This is the highest-value output.
   - Cross-module dependencies (who calls whom)
5. **`arch/api.md`** — every HTTP/RPC/CLI/event endpoint: method, path, input shape, output shape, auth requirement, rate-limit or idempotency notes.
6. **`arch/cross_cutting.md`** — logging format, error handling pattern, auth middleware, config loading, graceful shutdown, transaction scoping, observability hooks.
7. **`arch/pain_points.md`** — tech debt / workarounds / legacy constraints flagged for improvement in the rewrite. Do NOT port these.

**Rules:**
- No code block > 20 lines. If a function is complex, describe behavior in prose + pseudocode.
- Prioritize "why" over "what". The target code will re-derive the "what".
- If a module is pure glue (no business logic), say so in one line — don't pad.

**Completion:** Mark `phases.1 = done`, `phase = 2`. Print a 3-bullet summary (module count, API count, flagged pain points).

---

## PHASE 2 — Test Contract Design

**Goal:** Define the full regression surface before writing target code. These specs are the contract the rewrite must satisfy.

1. **`tests/unit_plan.md`** — table: `module | function | scenario | expected outcome | mocks needed`. Cover happy path, edge cases, error paths, boundary values for every public function surfaced in Phase 1.
2. **`tests/integration_plan.md`** — table: `METHOD path | scenario | request | expected status | expected response shape`. Include auth scenarios (missing / expired / unauthorized), validation (missing field, wrong type, oversized input), idempotency, pagination.
3. **`tests/contract_plan.md`** — external contracts this service consumes (upstream APIs, queue message shapes, DB schema assumptions). These become contract tests / schema assertions.
4. **`tests/infra_plan.md`** — target-language test harness, fixtures strategy, seed data, mock strategy (e.g., Go: `httptest` + `testify/mock`; Rust: `mockall`; Node: `vitest` + `msw`).

**Rule:** Write specs, not code. Another engineer should be able to implement any test from the description alone, without reading source.

**Completion:** Mark `phases.2 = done`, `phase = 3`.

---

## PHASE 3 — Target Architecture Design

**Goal:** Design the new codebase structure. **Pause for user approval before Phase 4.**

Load target-language idioms from [references/LANGUAGE_MAPPING.md](references/LANGUAGE_MAPPING.md) for the chosen target.

1. **`design/architecture.md`** — target layers (idiomatic for target language), module mapping table (source module → target package/module, with split/merge rationale), dependency injection pattern, error handling strategy.
2. **`design/data_models.md`** — target-language struct/type/interface definitions for all domain models. Apply target idioms (Go interfaces for DI, Rust `Result<T,E>` + error enums, TS discriminated unions, etc.).
3. **`design/directory_tree.md`** — full proposed skeleton tree (file names only, no bodies).
4. **`design/tech_choices.md`** — router/web framework, DB/query builder, test framework, logger, config lib, linter. One-sentence justification per choice.

**Design rules:**
- High cohesion, low coupling. Each module has a single clear responsibility.
- Prefer constructor-injected interfaces/traits over globals.
- Public surface per module should be < 10 symbols unless justified.
- No layer skips (handler → repo without service is a smell unless the operation is truly trivial).
- Error taxonomy is explicit (target-lang error type, not stringly-typed).

**⚠ PAUSE:** After writing design files, print the architecture summary (layers + module map + tech stack in ~15 lines) and ask:

> "Architecture proposed above. Reply `approved` to continue to Phase 4, or list changes."

**Do not proceed** until the user replies approval. If they request changes, edit the design files and re-present.

**Completion (after approval):** Scaffold empty files per `directory_tree.md` in `target_dir`. Mark `phases.3 = done`, `phase = 4`.

---

## PHASE 4 — Step-by-Step Module Plan

**Goal:** Shard the implementation into the smallest independently-testable units. Resumable execution depends on this sharding being right.

Build an ordered list of steps. Ordering rules:
- Domain models & types first (no deps)
- Shared utilities next
- Repo / data-access layer
- Service / use-case layer
- Handlers / adapters / routes
- Wiring / `main` / bootstrap
- Integration glue last

Each step:
- ~30–120 lines of target code
- Compiles (or type-checks) on its own
- Has at least one test from Phase 2 attached

For each step, write `.rewrite/modules/NN_<short_name>.md` using the template in [references/TEMPLATES.md](references/TEMPLATES.md#step-card).

Write `.rewrite/modules/00_index.md` as an ordered table: `step # | name | status | target files | tests`.

Update `state.json → modules` array with `{n, name, status}` for each step. Set `current_step = 0`.

**Completion:** Mark `phases.4 = done`, `phase = 5`.

---

## PHASE 5 — Iterative Implementation

**Goal:** Implement one step per invocation. Every invocation advances `current_step` by exactly one.

**On each invocation:**

1. Read state → `current_step = N`.
2. Read `.rewrite/modules/NN_<name>.md` (the step card).
3. If the card's source references need fresh detail, read the specific source file(s) — never the whole codebase.
4. Implement only what the card specifies. Write target files as specified.
5. **Enforce inline:** apply [`../PRINCIPLES.md`](../PRINCIPLES.md) **Tier 1** in full (YAGNI / KISS / DRY+Rule-of-Three / SRP / naming / fail-fast / explicit / pure-where-possible). Specifically for `rewrite`:
   - Soft target: functions ≤ ~40 LOC; split if exceeded.
   - Use target-language idioms from `LANGUAGE_MAPPING.md`, not source-language patterns.
   - Apply Tier 2/3 (cohesion, coupling, layer respect, error taxonomy) at module boundaries.
6. Compile / type-check. Fix errors before continuing.
7. Run the step's attached unit tests (only those). Fix failures.
8. Run linter. Fix warnings.
9. Mark step card `Status: done`. Update `state.json → modules[N].status = done`, `current_step = N + 1`.
10. Print: step name, files written, LOC added, tests run (passed/failed), any notes.
11. **Stop.** User re-invokes for the next step.

**If a step is blocked:**
- Mark `Status: blocked`. Add a `## Blocker` section to the card explaining exactly what's missing.
- Update `state.json → blocked_step = N`.
- Print the blocker clearly. Do not skip ahead — stop.

**Completion:** When `current_step` exceeds the last index, mark `phases.5 = done`, `phase = 6`.

---

## PHASE 6 — Regression Loop (Bug Zeroing)

**Goal:** Run the full suite, fix failures in priority order, iterate until zero failing tests.

**On each invocation:**

1. Run the full test suite (unit + integration + contract).
2. Parse results into `coverage/failures.md` as a table: `test | failure category | owning module | first seen`.
3. Group failures by owning module. Fix the module with the most failures first (fixing one root cause often clears many).
4. Fix up to **5 failures or 1 module per invocation** — whichever is smaller. Keeps context bounded and progress visible.
5. Re-run the affected tests (not full suite yet) to confirm fixes.
6. Update `coverage/failures.md`.
7. Print: total tests, passing, failing, delta this round, module being worked on next.
8. Stop.

**Anti-pattern to reject:** "Fix by adjusting the test." Only acceptable if the test was wrong per Phase 2 spec — in that case update the spec first, then the test, and note in `coverage/failures.md`.

**When failures = 0:**
- Run coverage report. Write `coverage/summary.md`: total coverage %, per-module coverage, any module < 70% with explanation.
- Mark `phases.6 = done`, `phase = 7`.

---

## PHASE 7 — Final Documentation

**Goal:** Minimum useful docs. Hard length limits.

Produce exactly five files, nothing more:

1. **`docs/README.md`** — ≤ 3 paragraphs: what the service does, how to run locally, how to run tests. Nothing else.
2. **`docs/architecture.md`** — ≤ 3 pages: ASCII layer diagram, module responsibility table (one row per module), data-flow description for the 2–3 most important operations.
3. **`docs/api.md`** — endpoint reference. Generated from code if target lang supports it (godoc / rustdoc / typedoc); otherwise written from `tests/integration_plan.md`. Endpoints only, no tutorials.
4. **`docs/decisions.md`** — ADR list, max 10 entries: `Decision | Alternatives | Reason chosen`. Cover only non-obvious choices.
5. **`docs/migration_delta.md`** — what changed vs the original: dropped endpoints, renamed fields, behavior changes, known regressions (should be zero). Handoff doc for running old + new in parallel.

**Rule:** If any single doc exceeds 500 words, cut.

**Completion:** Mark `phases.7 = done`. Print final status: phase counts, total target LOC, test count, coverage %, time elapsed (if tracked).

---

## Anti-Patterns

- **Do not translate idioms literally.** A Python `for i, x in enumerate(list)` becomes Go `for i, x := range list`, not a C-style index loop.
- **Do not port the pain points.** Phase 1 flagged them. Fix them in the rewrite.
- **Do not skip Phase 3 approval.** Architecture mistakes compound.
- **Do not batch phases.** One phase per session.
- **Do not read the whole source codebase after Phase 1.** Read the Phase 1 summaries; only open specific source files when a step card explicitly requires them.
- **Do not over-document.** Phase 7 limits are not suggestions.
- **Do not fix failures by deleting tests.** See Phase 6 anti-pattern.

---

## Cross-Platform Notes

This skill works identically on:
- **Claude Code** — auto-discovers via SKILL.md frontmatter.
- **Cursor** — auto-discovers via SKILL.md frontmatter (same format).

No platform-specific syntax is used. All tool invocations are expressed in natural language ("read file", "run tests") and the host agent uses its native file/shell tools.

---

## References (loaded on demand)

- **[../PRINCIPLES.md](../PRINCIPLES.md)** — shared 4-tier software design principles (YAGNI/KISS/DRY/SRP, SOLID, cohesion/coupling, layering, error taxonomy, etc.). Read this before Phase 5 implementation.
- [references/LANGUAGE_MAPPING.md](references/LANGUAGE_MAPPING.md) — idiom mappings per target language (Go, Rust, Node/TS, Python). Read during Phase 3.
- [references/TEMPLATES.md](references/TEMPLATES.md) — file templates for Phase 1 module cards, Phase 4 step cards, Phase 6 failure rows, etc.
- [references/STATE_SCHEMA.md](references/STATE_SCHEMA.md) — `state.json` schema + example.
