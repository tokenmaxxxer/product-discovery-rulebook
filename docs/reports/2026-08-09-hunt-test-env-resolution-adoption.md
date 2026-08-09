---
proposal: docs/issue-61/proposals/2026-08-09-test-env-resolution-adoption.md
---

# Hunt record — test-env-resolution-adoption

## after-proposal — stance 0: the write set cannot carry this work

Verdict: FINDING — write set omits docs/handbooks/tests.md and README.md, which document the exact fallback/failure behavior this proposal changes, and run-gate-tests.sh's own aggregation loop (`|| plugin_fail=1`) will misreport a legitimate SKIP (exit 75) from a sub-suite as a failure since it doesn't distinguish exit codes.
Kind: silent-failure
Seed: docs/issue-61/proposals/2026-08-09-test-env-resolution-adoption.md (write set: tests/run-gate-tests.sh + 5 product-*-gate-tests.sh, docs-only diff, 6 files listed)
cap_seconds: 120
tier: default
diff_stat_lines: proposal doc ~70 lines, no code diff yet
started_at: 2026-08-09T00:00:00Z
ended_at: 2026-08-09T00:06:00Z

### Reproduce
Read `tests/run-gate-tests.sh` lines 30-34:
```
for suite in product-one-pager product-opportunity-solution-tree \
             product-assumption-mapping product-hypothesis-testing \
             product-guardrail-metrics; do
  echo; echo "-- $suite --"
  bash "$HERE/$suite-gate-tests.sh" || plugin_fail=1
done
```
`|| plugin_fail=1` fires for *any* non-zero exit from the sub-suite. After
the proposal's own change, a sub-suite whose core is unreachable now exits
`75` (SKIP) instead of `1` — but this loop, in the same file already in
the write set, has no branch to recognize `75` as "skip, not fail". Proof
that `||` cannot discriminate exit codes:
```
$ bash -c 'ec=75; ( exit $ec ) || plugin_fail=1; echo $plugin_fail'
1
```
Separately, `grep -n "CLAUDE_PLUGIN_ROOT_CORE\|exit 1" README.md
docs/handbooks/tests.md` shows both files describe the current
auto-detect-or-fail contract for these same 6 scripts (README.md:89-92,
docs/handbooks/tests.md:24-29) and neither file is in the proposal's
frozen write set.

### Observed
`run-gate-tests.sh`'s dispatcher loop treats a compliant SKIP (exit 75)
from any of the 5 plugin suites identically to a real failure
(`plugin_fail=1` -> final banner "FAILURES present" and non-zero overall
exit) — the exact "misleading fail" outcome the proposal exists to
eliminate, except now surfacing one level up at the dispatcher instead of
in a single suite. This requires touching the aggregation loop, a second
spot in the already-listed file that the proposal's "What will be done"
section never mentions (it only discusses replacing the per-file
resolution block and run-gate-tests.sh's own top-level resolution exit
code, not the loop that consumes the 5 sub-suites' exit codes). In
addition, docs/handbooks/tests.md and README.md, which describe the
current fallback behavior in prose for these exact scripts, are not in
the write set and will read as stale/wrong once SKIP+75 lands with no
corresponding prose update.

### Expected
The write set (or "What will be done" section) should call out that
run-gate-tests.sh needs a *second* edit — teaching the `for suite in ...`
loop to treat a sub-suite's exit 75 as SKIP rather than folding it into
`plugin_fail`/the final failure banner — and should include
docs/handbooks/tests.md (and ideally README.md) as files phase-2 will
need to touch so the documented run/fallback contract doesn't go stale
the moment the SKIP behavior ships.

## before-landing — stance 0: assume the gate just touched is bypassable — find the bypass

Verdict: FINDING — the dispatcher's "all sub-suites skipped" aggregation branch in tests/run-gate-tests.sh (lines ~58-61) is dead code, unreachable given the script's own top-level resolution check, so the SKIP/FAIL aggregation it claims to provide for that case never actually runs.
Kind: design-error
Seed: tests/run-gate-tests.sh (SKIP/exit-75 aggregation logic added across the 6 test scripts)
cap_seconds: 120
tier: default
diff_stat_lines: 21-200
started_at: 2026-08-09T00:00:00Z
ended_at: 2026-08-09T00:03:30Z

### Reproduce
```
# 1. Core unreachable: dispatcher exits 75 at the TOP check, before the
#    suite loop (lines 33-45) ever runs a single subprocess.
export CLAUDE_PLUGIN_ROOT_CORE=""
export HOME=/nonexistent-home
bash tests/run-gate-tests.sh; echo "EXIT=$?"

# 2. Core reachable (normal dev machine): every sub-suite inherits the
#    exact same exported CLAUDE_PLUGIN_ROOT_CORE and re-runs the identical
#    "-s $CLAUDE_PLUGIN_ROOT_CORE/hooks/lib/gate-lib.sh" check, so none of
#    them skip either.
unset CLAUDE_PLUGIN_ROOT_CORE
bash tests/run-gate-tests.sh 2>&1 | tail -5
```

### Observed
Run 1: `SKIP: core plugin unreachable — unverifiable outside spawn env` printed by the
*top-level* check, exit 75, before the `for suite in ...` loop (which increments
`plugin_skip`) executes at all — `plugin_skip` never gets a chance to be set from a
subprocess in this path.

Run 2: with a real core plugin present, output ends `run-gate-tests: all 5 plugin
suites + compliance-check.sh passed`, `EXIT=0`, i.e. `plugin_skip=0` for every suite —
confirming the only way any suite could independently emit exit-75 (an inherited,
already-exported `CLAUDE_PLUGIN_ROOT_CORE` failing the identical `-s .../gate-lib.sh`
check that the parent already validated) cannot occur without the parent having
already exited 75 first.

So the block at the end of run-gate-tests.sh:
```
if [ "$plugin_fail" -eq 0 ] && [ "$plugin_skip" -eq "$suite_count" ]; then
  echo "SKIP: core plugin unreachable — unverifiable outside spawn env" >&2
  exit 75
fi
```
is written to catch "all 5 sub-suites individually reported SKIP," but under the
script's own inheritance model (`export CLAUDE_PLUGIN_ROOT_CORE` before the loop),
that condition is unreachable: either the top check already failed and the whole
script exited 75 before compliance-check.sh and the loop ever ran, or it succeeded
and every child necessarily passes the same check too, so `plugin_skip` stays 0.

### Expected
Either the code should not exist (since it can never fire and gives false confidence
the "partial/total sub-suite skip" case is handled), or the design should actually
allow sub-suites to skip independently of the parent's check (e.g. by not
pre-exporting a validated CLAUDE_PLUGIN_ROOT_CORE, or by each suite having its own
additional resolution axis) so the aggregation logic has a real code path to
exercise instead of being dead weight that will bit-rot unnoticed (a hunk that
"looks like" it handles the partial-skip / all-skip composition case but never
actually gets invoked in any real run).
