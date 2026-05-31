---
name: retry-524
description: >-
  Recovery procedure for HTTP 524 (and equivalent gateway/upstream timeouts:
  522, 502, 504, "gateway timeout", "upstream request timeout") hit during any
  tool call, web fetch, API request, subagent run, or long command. Triggers
  whenever such an error surfaces mid-task. Procedure: retry the SAME operation
  exactly once; if it still 524s, STOP retrying and split the work into several
  smaller independent subagents run in parallel, then merge their results. Use
  when a 524/gateway-timeout appears, or when the user says "遇到524" / "超时了"
  / "网关超时" / "retry on timeout".
---

# retry-524 — Gateway-Timeout Recovery

A 524 (and its cousins 522/502/504, "gateway timeout", "upstream request
timeout") means an upstream/edge proxy gave up waiting for a slow origin. It is
almost always **transient or size-driven**, not a logic error. Do not treat it
as a hard failure and do not surface it to the user as "it broke" before
running this procedure.

## Procedure

When a 524 / gateway-timeout surfaces from any tool call, fetch, API request,
subagent, or long-running command:

1. **Retry once.** Re-issue the *same* operation verbatim, exactly one time. A
   large fraction of 524s clear on an immediate retry. Do not loop — one retry
   only.

2. **If it still times out → decompose and parallelize.** Stop retrying the
   monolithic call. Break the work into several smaller, independent pieces and
   dispatch each as its own subagent (`Agent` tool), running them
   **concurrently** in a single message. Smaller units finish under the gateway
   deadline and isolate any one slow piece.

   - Split along natural seams: per-file, per-directory, per-endpoint,
     per-record, per-section, per-time-window.
   - Keep each subagent's scope small enough to comfortably beat the timeout.
   - Launch them in parallel (multiple `Agent` calls in one response), not
     sequentially.

3. **Merge.** Collect the subagent results and assemble the final answer. If a
   single subagent itself 524s, apply this same procedure recursively to that
   slice (retry once, then split further).

## Notes

- One retry, then split — never retry the same big call more than once.
- Prefer parallel subagents over serial retries: serial retries waste
  wall-clock and usually hit the same timeout again.
- This is the user's standing preference for handling gateway timeouts.
