# state.json — Schema, Repair Protocol, Gate Semantics

`state.json` is the single source of truth for workflow position. It lives at `<project_dir>/.evolve/state.json` and is written by the skill at every phase/step boundary.

---

## Schema

```jsonc
{
  "version": 1,
  "skill": "evolve",
  "project_dir": ".",
  "language": ["go"],                 // detected by Phase 0
  "requirement_source": "./prd/mute-user.md",  // file path, URL, or "inline"
  "requirement_hash": "sha256:...",   // change → invalidates Phase 1 outputs
  "auto_advance": true,
  "phase": 4,                         // 0..6 — current phase
  "phases": {
    "0": "done",
    "1": "done",
    "2": "done",
    "3": "done",                      // or "waiting_refactor_decision"
    "4": "in_progress",               // or "waiting_refactor_decision" if mid-impl gate hit
    "5": "pending",
    "6": "pending"
  },
  "current_step": 7,                  // Phase 4 cursor; index into plan/steps.md
  "blocked_step": null,               // step number if Phase 4 is blocked
  "regression_round": 0,              // Phase 5 round counter
  "refactor": {
    "proposed": ["RP-01", "RP-02", "RP-03"],
    "approved": ["RP-01", "RP-03"],
    "rejected": [],
    "deferred": ["RP-02"],
    "decision_at": "2026-04-19T10:00:00Z"
  },
  "stats": {
    "files_added": 0,
    "files_modified": 0,
    "loc_added": 0,
    "loc_removed": 0,
    "tests_added": 0,
    "last_test_run": null             // {total, passed, failed, at}
  },
  "history": [
    { "at": "...", "phase": 0, "event": "bootstrap", "note": "..." },
    { "at": "...", "phase": 1, "event": "completed" }
  ]
}
```

### Field rules

- `phase` — the **next** phase to execute (or the one currently in progress). When `phases.N == "done"`, `phase` should be `N+1` unless paused.
- `phases.N` values: `"pending" | "in_progress" | "waiting_refactor_decision" | "done"`.
- `current_step` is only meaningful when `phase == 4`. After Phase 4 completes, leave it set (informational).
- `auto_advance` defaults to `true`. `--no-auto` flips it for one invocation only (do not write to disk). `--step-only` writes `false` permanently.
- `requirement_hash` lets you detect "the user edited the source PRD"; if it changes, the skill warns and offers `--reset-phase 1`.

---

## Auto-Advance Semantics

After completing a phase:

1. Set `phases.<n> = "done"`, `phase = n+1`.
2. If `auto_advance` is true AND none of the mandatory stops apply, immediately execute Phase `n+1`.
3. Mandatory stops (the skill must yield even with auto_advance = true):
   - `phase == 3` AND `plan/refactor_proposals.md` is non-empty AND `--skip-refactor` not set → set `phases.3 = "waiting_refactor_decision"`, stop.
   - `phase == 4` after each step → stop (per-step rule). Exception: `--run-all-steps`.
   - `phase == 4` if a *new* refactor proposal was raised mid-implementation → set `phases.4 = "waiting_refactor_decision"`, stop.
   - `phase == 5` after each round → stop.
   - Skill judges context is saturating → stop.

When stopping, always print:
- Current phase + phase status
- What just happened (1–2 lines)
- How to resume (e.g. "say `继续`" or "reply `approve <ids>`")

---

## Refactor Gate Semantics

The gate fires from two phases:

### Phase 3 gate (planned)

Triggered when `plan/refactor_proposals.md` lists ≥ 1 item.

- `phases.3` becomes `"waiting_refactor_decision"`.
- `refactor.proposed` is populated.
- Skill stops and prints proposal IDs + one-line titles.
- User reply is parsed on next invocation; recognized verbs: `approve`, `reject`, `defer`, optional `all`.
- Skill writes `plan/refactor_decision.md`, updates `plan/steps.md` to insert approved-refactor steps in dependency order before the affected feature step.
- `phases.3 = "done"`, `phase = 4`, auto-advance.

### Phase 4 gate (discovered)

Triggered when, while implementing a step, the skill finds new unreasonable existing code blocking progress.

- Append entry to `plan/refactor_proposals.md` with `(discovered in Phase 4 step NN)` tag and an ID like `RP-04`.
- `phases.4` becomes `"waiting_refactor_decision"`. `current_step` is preserved.
- Same resolution protocol as Phase 3 gate. After verdict:
  - Approved refactors are inserted as new steps before the current step.
  - `current_step` is rewound to point at the first new refactor step.
  - `phases.4 = "in_progress"`, auto-advance into that step.

### Verb parsing

Examples of recognized user replies after a gate:

- `approve all` → all proposed → approved.
- `reject all` → all proposed → rejected.
- `approve RP-01 RP-03` → those two approved; rest default to rejected unless `defer` is also used.
- `approve RP-01; defer RP-02; reject RP-03` → explicit per-item.
- Unrecognized reply → re-print proposals, ask again (this is the only re-prompt the skill ever does).

---

## `--repair` Protocol

If `state.json` is missing or corrupt, run `evolve --repair`. The skill reconstructs state by inspecting `.evolve/`:

1. Walk phase output dirs. A non-empty dir with required files implies that phase completed.
   - `req/` has all 6 files → Phase 1 done.
   - `arch_scan/` has all 4 + `tests/` has all 3 → Phase 2 done.
   - `plan/steps.md` exists → Phase 3 at least started; `plan/refactor_decision.md` exists → Phase 3 done.
   - Any production code matches a "done" step in `plan/steps.md` → mark step done.
   - `coverage/summary.md` with `failures = 0` → Phase 5 done.
   - `DESIGN.md` exists → Phase 6 done.
2. Compute `current_step` as the first step in `plan/steps.md` whose status is not `done`.
3. Re-hash the requirement source; warn on mismatch.
4. Write a fresh `state.json`. Do not delete any other files.

---

## `--reset-phase N` Protocol

1. Set `phases.N = "pending"` and all `phases.M` for `M > N` to `"pending"`.
2. Set `phase = N`.
3. Delete files under the dirs owned by phases ≥ N (e.g. reset 3 → delete `plan/`, `coverage/`, `DESIGN.md`; reset 4 → delete generated production code listed in completed steps + `coverage/`, `DESIGN.md`; do **not** delete pre-existing repo code).
4. For Phase 4 reset: enumerate steps marked `done` in the (now-deleted) `plan/steps.md`; the skill keeps a backup copy at `plan/.steps.backup.md` before deletion so the user can review what was undone.
5. Re-run from Phase N on next invocation.

Reset is destructive on `.evolve/` outputs and on production files the skill itself wrote. It never touches files that existed before Phase 0 (tracked via `state.json → stats.files_added` vs `files_modified`).
