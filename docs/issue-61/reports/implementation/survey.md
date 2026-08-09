# Current-state survey — issue #61

## Scout skip record
Scouting skipped. Skip condition: "the spec literally leaves no design
decision open." The convention this issue adopts is already landed and
fully specified externally at on-the-record's
`docs/specs/test-env-resolution.md` (issue #551, merged via PR #552/#553):
resolution order, exact SKIP message, exit code (75), and per-consumer-shape
adoption guidance are all fixed. This repo's job is to apply that fixed
contract to its own scripts, not to make a new design choice.

## Write set found (grep for CLAUDE_PLUGIN_ROOT_CORE across tests/)
`grep -rl CLAUDE_PLUGIN_ROOT_CORE tests/` returns 6 files, all with an
identical hand-rolled resolution block (env var check -> hardcoded sibling
candidates -> `exit 1` on failure, no SKIP contract, no exit-75, no
reference to the convention doc):

- `tests/run-gate-tests.sh` — root dispatcher; resolves core once, exports
  it, then runs the 5 suites below as subprocesses plus core's
  `compliance-check.sh`. 3 sibling candidates (includes one relative to
  `$ROOT/..`).
- `tests/product-one-pager-gate-tests.sh`
- `tests/product-opportunity-solution-tree-gate-tests.sh`
- `tests/product-assumption-mapping-gate-tests.sh`
- `tests/product-hypothesis-testing-gate-tests.sh`
- `tests/product-guardrail-metrics-gate-tests.sh`

Each of the 5 plugin suites has the same block (2 sibling candidates,
missing the `$ROOT/..` variant `run-gate-tests.sh` has) followed by its own
`run_write`/gate-invocation assertions, all of which pass unchanged once
core is resolved — those assertions are not touched by this issue.

## Out of scope (no core dependency)
- `tests/deny-only-check.sh` — greps hooks source + runs gates directly by
  path; never touches `CLAUDE_PLUGIN_ROOT_CORE` or `gate-lib.sh`.
- `tests/parse-check.sh` — `bash -n` syntax check only; no core dependency.

This matches the convention doc's own enumerated exception
(`gates/test_skip_gate.py` in on-the-record having no core dependency
either) — same shape, different repo.

## What changes
All 6 in-scope scripts get their hand-rolled resolution block replaced by
one that: (1) still checks `CLAUDE_PLUGIN_ROOT_CORE` first, then the same
sibling candidates already in each file (candidates are caller-supplied per
the convention — no change to the candidate lists themselves), but (2) on
exhaustion prints the exact convention message
`SKIP: core plugin unreachable — unverifiable outside spawn env` to stderr
and exits `75` instead of `exit 1`, and (3) carries a comment referencing
`docs/specs/test-env-resolution.md` so the adoption is greppable (issue
acceptance check). No assertion that runs when core IS reachable changes.

## Unknowns / risks
- `run-gate-tests.sh` treats its own resolution failure as fatal for the
  whole dispatcher; switching it to SKIP/exit-75 changes what a caller
  script sees on a plain checkout (was 1, becomes 75) — flagged in the
  proposal's constraints.
- Because this repo's suites are bash (not pytest), the convention's
  reference Python module (`gates/test_env_resolve.py`) is not directly
  importable; adoption here is the bash-shape branch the convention
  document itself describes ("Bash test runner" invoking the module as a
  CLI) or an equivalent inline bash port of the same order/message/code —
  decided in the proposal.
