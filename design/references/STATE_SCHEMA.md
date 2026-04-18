# state.json Schema (design skill)

Single source of truth for design progress. Located at `<project_dir>/.design/state.json`. Every phase reads on entry and writes on exit.

## Schema

```json
{
  "schema_version": 1,
  "requirement_source": "<file path | URL | 'inline'>",
  "requirement_digest": "<sha256 of the requirement text, for drift detection>",
  "project_dir": "<absolute path>",
  "target_lang": "go | rust | node | ts | python",
  "phase": 1,
  "auto_advance": true,
  "started_at": "<ISO 8601>",
  "last_updated_at": "<ISO 8601>",
  "phases": {
    "1": "pending | in_progress | done",
    "2": "pending | in_progress | done",
    "3": "pending | in_progress | done",
    "4": "pending | in_progress | done",
    "5": "pending | in_progress | done",
    "6": "pending | in_progress | done",
    "7": "pending | in_progress | done"
  },
  "modules": [
    {
      "n": 0,
      "name": "domain_task_model",
      "status": "pending | in_progress | done | blocked",
      "target_files": ["internal/domain/task.go"],
      "tests": ["task_test.go::TestValidate"],
      "loc_added": 0
    }
  ],
  "current_step": 0,
  "blocked_step": null,
  "regression": {
    "rounds": 0,
    "total_tests": 0,
    "passing": 0,
    "failing": 0,
    "last_run_at": null
  },
  "assumptions": [
    { "topic": "auth", "assumption": "JWT bearer; 24h expiry; HS256", "recorded_in": "req/goals.md" }
  ],
  "notes": []
}
```

## Field Semantics

- **`requirement_source`** — original pointer to the PRD/spec. Useful for re-reads and for Phase 7 docs.
- **`requirement_digest`** — sha256 hash of the requirement text at ingestion time. If the user updates the source doc mid-design, subsequent runs can detect drift and warn.
- **`phase`** — phase to execute on next invocation. Lowest non-`done` phase unless reset.
- **`auto_advance`** — default `true`. When `true`, a phase completion triggers the next phase within the same invocation (except Phase 5/6, which always stop per step/round).
  - Flipped to `false` by `--no-auto` (one-shot) or `--step-only` (persistent).
- **`modules`** — populated in Phase 4. Iterated in Phase 5 via `current_step`.
- **`current_step`** — index into `modules`. Phase 5 advances by 1 per invocation (or by N if `--run-all-steps` was used).
- **`blocked_step`** — set when Phase 5 hits a blocker; must be cleared before `current_step` advances.
- **`regression`** — updated each Phase 6 round.
- **`assumptions`** — decisions made without user input, per the "default authorization" rule. Recorded so the user can audit later. Each entry lists the file the assumption was also written into.
- **`notes`** — free-form strings appended by any phase for caveats.

## Auto-Advance Rules (canonical)

| Current phase just completed | Next behavior |
|---|---|
| 0 → 1 | Auto-advance to Phase 1. |
| 1 → 2 | Auto-advance to Phase 2. |
| 2 → 3 | Auto-advance to Phase 3. |
| 3 → 4 | Auto-advance to Phase 4. |
| 4 → 5 | Auto-advance to the **first** Phase 5 step, execute it, then stop. |
| 5 step done, more steps remain | **Stop.** User re-invokes for next step. (Exception: `--run-all-steps` keeps going.) |
| 5 last step done | Auto-advance to Phase 6 round 1, execute it, then stop. |
| 6 round done, failing > 0 | **Stop.** User re-invokes for next round. |
| 6 failing = 0 | Auto-advance to Phase 7, complete it. |
| 7 done | Print final summary, stop. |

Auto-advance is skipped if the assistant judges context is saturating; it writes state and prints a clear resume hint.

## Example: Mid Phase 5

```json
{
  "schema_version": 1,
  "requirement_source": "/Users/joy/prd/task-svc.md",
  "requirement_digest": "a3f9...c12",
  "project_dir": "/Users/joy/code/task-svc",
  "target_lang": "go",
  "phase": 5,
  "auto_advance": true,
  "started_at": "2026-04-18T10:00:00Z",
  "last_updated_at": "2026-04-18T14:32:00Z",
  "phases": {
    "1": "done", "2": "done", "3": "done", "4": "done",
    "5": "in_progress", "6": "pending", "7": "pending"
  },
  "modules": [
    { "n": 0, "name": "domain_task", "status": "done", "target_files": ["internal/domain/task.go"], "tests": ["task_test.go"], "loc_added": 72 },
    { "n": 1, "name": "repo_task_pg", "status": "in_progress", "target_files": ["internal/repo/task_pg.go"], "tests": ["task_pg_test.go"], "loc_added": 0 }
  ],
  "current_step": 1,
  "blocked_step": null,
  "regression": { "rounds": 0, "total_tests": 0, "passing": 0, "failing": 0, "last_run_at": null },
  "assumptions": [
    { "topic": "db", "assumption": "Postgres 15; sqlc for queries", "recorded_in": "arch/tech_choices.md" },
    { "topic": "auth", "assumption": "JWT HS256; 24h", "recorded_in": "req/non_functional.md" }
  ],
  "notes": []
}
```

## Repair Protocol

If `state.json` is corrupt/missing and `.design/` has content, `design --repair`:

1. Detect phases done by presence of expected outputs:
   - Phase 1 done ⇔ `req/summary.md` + `modules/00_index.md` + `api/endpoints.md` exist
   - Phase 2 done ⇔ all four `tests/*_plan.md` exist
   - Phase 3 done ⇔ all four `arch/*.md` exist AND tree scaffolded in `project_dir`
   - Phase 4 done ⇔ `steps/00_index.md` exists with rows
   - Phase 5 progress ⇔ count step cards with `Status: done`
   - Phase 6 progress ⇔ `coverage/failures.md` exists
   - Phase 7 done ⇔ all five `docs/*.md` exist
2. Rebuild `modules` from `steps/NN_*.md` frontmatter.
3. Set `phase` to lowest non-`done` phase.
4. Set `current_step` to first non-`done` module.
5. Restore `auto_advance = true` unless `.design/no_auto` marker file exists.
6. Write repaired state.json. Print a summary of what was recovered.
