---
status: proposed
files:
  - product-opportunity-solution-tree/hooks/methodology-gate.sh
  - product-hypothesis-testing/hooks/methodology-gate.sh
  - product-guardrail-metrics/hooks/methodology-gate.sh
  - product-one-pager/hooks/methodology-gate.sh
  - product-assumption-mapping/hooks/methodology-gate.sh
  - tests/product-opportunity-solution-tree-gate-tests.sh
  - tests/product-hypothesis-testing-gate-tests.sh
  - tests/product-guardrail-metrics-gate-tests.sh
  - tests/product-one-pager-gate-tests.sh
  - tests/product-assumption-mapping-gate-tests.sh
---

## Request

methodology-gate.sh sometimes fail-closed-refuses a Write/Bash call with
"No stderr output" — no diagnostic naming which methodology element is
unmet or which spec condition it violates, so the calling session can't
self-correct. Fix so every refusal carries a non-empty reason.

## Constraints

- Fail-closed behavior itself must not change — only the diagnostic
  content of the refusal.
- Acceptance (issue #60): a forced-refusal fixture must produce a
  non-empty reason naming the unmet element and a spec pointer; gate
  tests must pass; if the root cause turns out to be an environment
  crash rather than gate logic, that crash path must be recorded and
  guarded, not silently "fixed" over.
- No new dependency, no schema change, no new env var.

## Rationale

Two fixes were considered:

1. **Add `>&2` to bash-level `deny()`** (chosen): the local `deny()` in
   each of the five gate scripts already builds the full JSON reason
   string; adding a mirrored `printf '%s\n' "$reason" >&2` (or writing
   the same message to both fds) makes every refusal path — early
   guards, ERR traps, judge-crash fallback — carry a stderr message with
   no change to control flow or exit codes.
2. **Route all bash-level denies through the embedded Python judge's
   `deny(m)`** (rejected): that function already writes to stderr, so
   funneling every early guard through it would also fix the symptom.
   Rejected because it requires restructuring each script's control flow
   so bash-level guards (missing python3, empty stdin, no project root)
   execute *after* Python is confirmed available — but several of those
   guards exist precisely to catch the case where Python/the interpreter
   chain isn't usable yet. Forcing them through the Python-side denier
   would make the fix depend on the very precondition some of the guards
   exist to check, and would touch far more lines per file for no
   behavioral gain over a direct `>&2` addition.

Per the survey, `gate_trap_fail_closed` (the core-provided EXIT trap) is
defined in an external "core" plugin not vendored in this repo and not
part of the write set — its stderr behavior on an unbound-variable crash
is unauditable here and is called out as an explicit residual risk
rather than silently assumed fixed.

## What will be done

- In each of the five `hooks/methodology-gate.sh` files, change the
  local `deny()` (and any inline denial code path that bypasses it,
  e.g. the ERR traps in product-hypothesis-testing and
  product-guardrail-metrics) so the human-readable reason string is
  written to stderr in addition to the stdout JSON payload, for every
  call site (missing python3, empty stdin, no project root, Bash-write
  coverage, judge-crash fallback, ERR trap).
- Extend each deny message to name the unmet methodology element and a
  spec pointer, following the existing informal citation convention
  already used by the deeper Python-side denials in this file (e.g.
  `product-opportunity-solution-tree/hooks/methodology-gate.sh:172`
  cites `docs/issue-36/...`) — early bash-level guards get an equivalent
  pointer (e.g. "python3 not found on PATH — required by
  <plugin>/hooks/methodology-gate.sh; see docs/handbooks/tests.md").
- Add one stderr-content assertion per existing forced-refusal test case
  in each `tests/product-<name>-gate-tests.sh`, replacing the current
  `>/dev/null 2>&1` discard with a captured-stderr check that the
  message is non-empty and names the unmet element.
- If any refusal path turns out to originate from an unguarded crash
  (unbound variable, missing command) rather than an intentional
  `deny()` call, add a guard around that specific path in the same file
  and document the crash path inline as a comment at the site.

## Residual risk (flagged, not fixed here)

Warrant-hunt (after-proposal, stance 0, `docs/reports/2026-08-09-hunt-methodology-gate-nonempty-refusal-reason.md`)
found that `product-assumption-mapping/hooks/methodology-gate.sh` has no
`ERR` trap (unlike `product-hypothesis-testing` and
`product-guardrail-metrics`, which both install
`trap 'deny "..."' ERR`). An ungated `python3 -c` crash in that file can
fall through to an allow-shaped exit without ever calling `deny()` — a
fail-open bypass distinct from #60's empty-reason symptom, since the
crash never reaches `deny()` in the first place. This proposal's stderr
fix does not address it (there is no deny() call on that path to add
`>&2` to). Flagged for a follow-up issue rather than pulled into this
proposal's write set, since it's a different defect class (fail-open vs.
silent-reason) with its own fix shape (add an ERR trap, not touch
`deny()`).

## Out of scope

- The external "core" plugin's `gate-lib.sh` (not in this repo).
- Building a machine-readable `spec.json` — the fix reuses the existing
  informal docs/issue-<n> citation convention, per the survey's finding
  that no structured spec exists to point at.
- issue #61's test-env SKIP/exit-75 convention (different call site:
  test-harness environment resolution, not production gate deny
  messages) — not adopted here, no scope overlap beyond both potentially
  touching `docs/handbooks/tests.md`, which this proposal does not
  modify.

## How you'll know it worked

- A forced-refusal fixture (empty stdin, or missing-python3 simulation)
  run against each of the five gate scripts produces a non-empty stderr
  reason naming the unmet element and a spec pointer.
- All five `tests/product-<name>-gate-tests.sh` suites pass, including
  the new stderr-content assertions.
- `tests/run-gate-tests.sh` (the dispatcher) passes end to end.
