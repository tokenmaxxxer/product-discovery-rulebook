---
status: proposed
files:
  - tests/run-gate-tests.sh
  - tests/product-one-pager-gate-tests.sh
  - tests/product-opportunity-solution-tree-gate-tests.sh
  - tests/product-assumption-mapping-gate-tests.sh
  - tests/product-hypothesis-testing-gate-tests.sh
  - tests/product-guardrail-metrics-gate-tests.sh
  - docs/handbooks/tests.md
---

## Request
Adopt the canonical test-env resolution convention landed at on-the-record
`docs/specs/test-env-resolution.md` (issue #551) across this rulebook's
gate-test scripts, so that on a plain checkout without
`CLAUDE_PLUGIN_ROOT_CORE` they SKIP with the convention's exact message and
exit code instead of failing misleadingly, while every assertion that runs
when core IS reachable stays unchanged.

## Constraints
- Zero assertions that run when core is reachable may weaken or change
  behavior — only the failure-path branch changes.
- The convention's SKIP contract is fixed externally: message
  `SKIP: core plugin unreachable — unverifiable outside spawn env` on
  stderr, exit code `75` (never colliding with a gate's own 0/1/2).
- `run-gate-tests.sh`'s existing candidate list already includes a 3rd
  sibling path (`$ROOT/../tokenmaxxxer-core/core`) the 5 plugin suites
  lack; that asymmetry is pre-existing and out of scope to reconcile here.
- Each script must reference `docs/specs/test-env-resolution.md` in a
  comment (issue acceptance check: greppable).
- No network fallback (the convention explicitly excludes it from the
  canonical contract).

## Rationale
Two ways to consume the landed convention were considered:

1. **Vendor on-the-record's reference module** (`gates/test_env_resolve.py`)
   into this repo and call it via `python3 -m gates.test_env_resolve
   <candidates...>` from each bash script, per the convention doc's own
   "Bash test runner" adoption guidance. Rejected: that guidance assumes
   the module already lives inside the consuming repo (as it does in
   on-the-record itself); pulling it into this repo means either a new
   cross-repo dependency/submodule or a hand-copied `.py` file that then
   needs its own test suite to stay honest — more moving parts than the
   two-line branch it replaces, for a repo whose test harnesses are
   otherwise pure bash.
2. **Inline bash port of the same order/message/exit-code** (chosen): keep
   each script self-contained bash, replace only the failure branch of the
   existing resolution block (env var -> sibling candidates -> now SKIP
   instead of `exit 1`), and add the exact message/code/doc-reference the
   convention specifies. This changes the minimum surface, adds no new
   dependency or file, and every one of the 6 scripts already had its own
   copy of the resolution block (verbatim-copy pattern this repo already
   uses for `deny-only-check.sh`/`parse-check.sh`), so a verbatim inline
   port matches the existing distribution shape instead of fighting it.

## What will be done
In each of the 6 listed files, replace the existing
`if [ -z "${CLAUDE_PLUGIN_ROOT_CORE:-}" ]; then ... exit 1; fi`
resolution block with one that:
- keeps the same candidate lookup (env var first, then that file's
  existing sibling-candidate list, unchanged),
- checks `gate-lib.sh` is present *and non-empty* (`-s`, not just `-f`) at
  each candidate, matching the convention's zero-byte-stub guard,
- on exhaustion, prints `SKIP: core plugin unreachable — unverifiable
  outside spawn env` to stderr and `exit 75` instead of the current
  `echo ...; exit 1`,
- carries a one-line comment citing `docs/specs/test-env-resolution.md`
  (on-the-record issue #551) as the source of the contract.

`run-gate-tests.sh` additionally needs two spots fixed, not just its own
top-level resolution block (warrant hunt, after-proposal):
- its own resolution failure changes from `exit 1` to `exit 75`, and
- its per-suite dispatch loop —
  `bash "$HERE/$suite-gate-tests.sh" || plugin_fail=1` — must stop
  collapsing a sub-suite's SKIP (`75`) into `plugin_fail=1`. Once the 5
  plugin suites can legitimately exit 75, the loop needs to distinguish
  "sub-suite exited 75 (SKIP)" from "sub-suite exited nonzero for any
  other reason (real failure)" and propagate a SKIP verdict for the whole
  dispatcher instead of reporting "FAILURES present" for an unverifiable
  environment.

`docs/handbooks/tests.md`'s "Run" section documents today's auto-detect
fallback behavior but not the SKIP outcome; it gets one paragraph added
describing the SKIP message/exit-75 contract and pointing at
`docs/specs/test-env-resolution.md`, so the handbook doesn't go stale the
moment the scripts change under it.

## Out of scope
- `tests/deny-only-check.sh` and `tests/parse-check.sh` — no
  `CLAUDE_PLUGIN_ROOT_CORE`/`gate-lib.sh` dependency, so the convention
  does not apply (matches the convention doc's own enumerated exception
  shape).
- Vendoring or importing on-the-record's Python reference module (see
  Rationale).
- Any change to the 5 plugins' `methodology-gate.sh` gate logic itself, or
  to any assertion that runs once core is resolved.
- Reconciling the candidate-list asymmetry between `run-gate-tests.sh` and
  the 5 plugin suites.

## How you'll know it worked
- On a plain checkout with `CLAUDE_PLUGIN_ROOT_CORE` unset and no sibling
  core checkout present, each of the 6 scripts exits `75` and prints the
  exact SKIP message to stderr — no misleading pass/fail.
- With `CLAUDE_PLUGIN_ROOT_CORE` pointed at a real core checkout, all 6
  scripts run exactly as before (same pass/fail assertions, same output),
  confirmed by running `tests/run-gate-tests.sh` in that environment.
- `grep -rl test-env-resolution tests/` returns all 6 files.
- If a script's failure turns out to be a real defect and not an
  environment issue, that is recorded as a finding, not masked with SKIP
  (issue #61 empty-state clause) — none is expected here since this
  change only touches the environment-resolution branch.
