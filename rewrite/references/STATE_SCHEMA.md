# state.json Schema

Single source of truth for rewrite progress. Located at `<target_dir>/.rewrite/state.json`. Every phase reads it on entry and writes it on exit.

## Schema

```json
{
  "schema_version": 1,
  "source_dir": "<absolute path>",
  "target_dir": "<absolute path>",
  "source_lang": "node | python | go | rust | ts",
  "target_lang": "go | rust | node | python | ts",
  "phase": 1,
  "started_at": "<ISO 8601 timestamp>",
  "last_updated_at": "<ISO 8601 timestamp>",
  "phases": {
    "1": "pending | in_progress | done",
    "2": "pending | in_progress | done",
    "3": "pending | in_progress | done | awaiting_approval",
    "4": "pending | in_progress | done",
    "5": "pending | in_progress | done",
    "6": "pending | in_progress | done",
    "7": "pending | in_progress | done"
  },
  "arch_progress": {
    "total_modules": 0,
    "processed_modules": 0,
    "pending_batch": []
  },
  "modules": [
    {
      "n": 0,
      "name": "domain_user_model",
      "status": "pending | in_progress | done | blocked",
      "target_files": ["internal/domain/user.go"],
      "tests": ["user_test.go::TestUserValidate"],
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
  "notes": []
}
```

## Field Semantics

- **`schema_version`** — bump when fields change incompatibly.
- **`phase`** — the phase to execute on next invocation. Always equals the lowest non-`done` phase unless explicitly reset.
- **`phases.3`** may be `awaiting_approval` between writing design docs and user saying "approved".
- **`arch_progress`** — used in Phase 1 for large codebases processed in batches. `pending_batch` holds source directories or modules still to analyze.
- **`modules`** — populated in Phase 4. Iterated in Phase 5 via `current_step`. Stable ordering once Phase 4 ends.
- **`current_step`** — index into `modules`. Phase 5 increments by 1 per invocation. When `current_step == len(modules)`, Phase 5 completes.
- **`blocked_step`** — set when Phase 5 hits a blocker. Must be cleared before `current_step` can advance.
- **`regression`** — updated each Phase 6 round.
- **`notes`** — free-form strings appended by any phase for important caveats (e.g., "Phase 1 skipped module X — deprecated, confirmed with user").

## Example: Mid-Phase-5

```json
{
  "schema_version": 1,
  "source_dir": "/Users/me/proj/api",
  "target_dir": "/Users/me/proj/api-go",
  "source_lang": "node",
  "target_lang": "go",
  "phase": 5,
  "started_at": "2026-04-18T10:00:00Z",
  "last_updated_at": "2026-04-18T14:32:00Z",
  "phases": {
    "1": "done", "2": "done", "3": "done",
    "4": "done", "5": "in_progress",
    "6": "pending", "7": "pending"
  },
  "arch_progress": { "total_modules": 42, "processed_modules": 42, "pending_batch": [] },
  "modules": [
    { "n": 0, "name": "domain_user", "status": "done", "target_files": ["internal/domain/user.go"], "tests": ["user_test.go"], "loc_added": 58 },
    { "n": 1, "name": "domain_order", "status": "done", "target_files": ["internal/domain/order.go"], "tests": ["order_test.go"], "loc_added": 94 },
    { "n": 2, "name": "repo_user_pg", "status": "in_progress", "target_files": ["internal/repo/user_pg.go"], "tests": ["user_pg_test.go"], "loc_added": 0 }
  ],
  "current_step": 2,
  "blocked_step": null,
  "regression": { "rounds": 0, "total_tests": 0, "passing": 0, "failing": 0, "last_run_at": null },
  "notes": []
}
```

## Repair Protocol

If `state.json` is corrupt or missing and `.rewrite/` has content, invoke `--repair`:

1. Detect completed phases by presence of expected output files:
   - Phase 1 done ⇔ `arch/inventory.md` + `arch/modules/*.md` exist
   - Phase 2 done ⇔ all four `tests/*_plan.md` exist
   - Phase 3 done ⇔ all four `design/*.md` exist AND directory tree scaffolded in `target_dir`
   - Phase 4 done ⇔ `modules/00_index.md` exists with rows
   - Phase 5 progress ⇔ count step cards with `Status: done`
   - Phase 6 progress ⇔ `coverage/failures.md` exists
   - Phase 7 done ⇔ all five `docs/*.md` exist
2. Rebuild `modules` array from `modules/NN_*.md` cards (parse frontmatter `Status:` field).
3. Set `phase` to the lowest non-`done` phase.
4. Set `current_step` to index of first non-`done` module.
5. Write repaired state.json. Print a summary of what was recovered.
