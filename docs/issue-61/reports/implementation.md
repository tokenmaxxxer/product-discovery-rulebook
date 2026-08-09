---
code_under_review:
  - tests/run-gate-tests.sh
  - tests/product-one-pager-gate-tests.sh
  - tests/product-opportunity-solution-tree-gate-tests.sh
  - tests/product-assumption-mapping-gate-tests.sh
  - tests/product-hypothesis-testing-gate-tests.sh
  - tests/product-guardrail-metrics-gate-tests.sh
  - docs/handbooks/tests.md
type: enhancement
breaking: false
verdict: pass
loop_state: landed
---

# Implementation record — issue #61

## What was done
Applied the canonical test-env resolution convention
(`docs/specs/test-env-resolution.md`, on-the-record issue #551) to all 6
in-scope gate-test scripts per the approved proposal
`docs/issue-61/proposals/2026-08-09-test-env-resolution-adoption.md`:

- `tests/run-gate-tests.sh`, `tests/product-one-pager-gate-tests.sh`,
  `tests/product-opportunity-solution-tree-gate-tests.sh`,
  `tests/product-hypothesis-testing-gate-tests.sh`,
  `tests/product-guardrail-metrics-gate-tests.sh`: replaced the resolution
  block's failure branch — same candidate lookup order, `-s` (non-empty)
  check instead of `-f`, on exhaustion prints
  `SKIP: core plugin unreachable — unverifiable outside spawn env` to
  stderr and `exit 75` instead of `echo ...; exit 1` — plus a comment
  citing `docs/specs/test-env-resolution.md`.
- `tests/product-assumption-mapping-gate-tests.sh`: this script's
  resolution block previously had no failure branch at all (it silently
  defaulted `CLAUDE_PLUGIN_ROOT_CORE` to a guessed path even when
  unresolved); rebuilt it to the same shape as the other 5 (env var ->
  candidate loop with `-s` check -> SKIP/exit-75), preserving its existing
  candidates.
- `tests/run-gate-tests.sh` dispatch loop: now captures each sub-suite's
  exit code, counts `75` as skip vs any other nonzero as a real failure,
  and (if every sub-suite skipped and none failed) the dispatcher itself
  prints the SKIP message and exits 75 instead of reporting
  "FAILURES present".
- `docs/handbooks/tests.md`: added a paragraph to the "Run" section
  documenting the SKIP message/exit-75 contract and pointing at
  `docs/specs/test-env-resolution.md`.

## Why
Requested by issue #61: this rulebook's gate-test scripts fail
misleadingly on a plain checkout outside the spawn env because they
assume `CLAUDE_PLUGIN_ROOT_CORE` is always resolvable. Adopting the
already-landed convention (issue #551) replaces that misleading failure
with an explicit, distinguishable SKIP, without touching any assertion
that runs once core is reachable.

## Upstream basis
docs/issue-61/proposals/2026-08-09-test-env-resolution-adoption.md

## Phase-2 continuation (live-check follow-up)
A live check (running every script under `tests/` with
`CLAUDE_PLUGIN_ROOT_CORE` unset AND `HOME` pointed at an empty scratch dir,
so neither the env var nor the `$HOME`-based candidates could resolve core)
found `tests/product-assumption-mapping-gate-tests.sh` still passing its
full 26-assertion suite (exit 0) instead of SKIPping (exit 75) — the other
5 scripts correctly SKIPped under the same simulated-unreachable
condition. Root cause: this script's candidate loop
(`tests/product-assumption-mapping-gate-tests.sh:10-12`) carried a
hardcoded absolute path, `/home/jwjung/tokenmaxxxer/tokenmaxxxer-core/core`,
left over from before the prior commit's convention rewrite — it bypasses
`$HOME` entirely, so on this machine it kept resolving core even when the
convention's own `$HOME`-based candidates were made unreachable. Fixed by
replacing the candidate list with the same two `$HOME`-based candidates
the other 5 scripts use (`$HOME/tokenmaxxxer/tokenmaxxxer-core/core`,
`$HOME/.claude/plugins/marketplaces/tokenmaxxxer/runs/rulebooks/tokenmaxxxer-core/core`).
Re-verified: all 6 scripts now exit 75 with the SKIP message under the
simulated-unreachable condition, and `product-assumption-mapping-gate-tests.sh`
still passes all 26 assertions unchanged with core reachable.
`tests/deny-only-check.sh` and `tests/parse-check.sh` were also checked —
both have no core dependency by design (require an explicit `<hooks-dir>`
argument; documented in `docs/handbooks/tests.md` and
`docs/issue-51/reports/product-discovery.md`) and are unaffected by this
convention; calling either with no argument is a usage error (`exit 2`),
not the SKIP contract's concern.

## What did not work
- Ran the full `tests/*.sh` sweep with only `CLAUDE_PLUGIN_ROOT_CORE`
  unset (no `HOME` override): every script exited 0/pass, because this
  machine's sibling core checkout at
  `$HOME/tokenmaxxxer/tokenmaxxxer-core/core` auto-resolves — expected
  per the convention, but it meant the sweep never actually exercised the
  SKIP path. Had to additionally override `HOME` to a directory with no
  core checkout to force genuine unreachability and expose the
  `product-assumption-mapping-gate-tests.sh` defect above.

## Doc placement
- [x] `docs/handbooks/tests.md` updated with the SKIP message/exit-75
  contract and a pointer to `docs/specs/test-env-resolution.md` (handbook
  ladder rung: env/config-adjacent behavior change, same turn as the
  code).

## Verification performed
- `bash -n` on all 6 changed scripts: syntax OK.
- Ran `tests/run-gate-tests.sh` with core reachable (this machine's spawn
  env resolves `CLAUDE_PLUGIN_ROOT_CORE` via the marketplace-installed
  candidate): all 5 plugin suites' assertions passed unchanged (20 + 23 +
  26 + 30 + 26 = 125 passing checks, 0 failed) — confirms no assertion
  that runs when core is reachable was weakened. `compliance-check.sh`
  reported one pre-existing, out-of-scope failure
  (`product-hypothesis-testing/hooks/methodology-gate.sh` calling
  `mktemp`) unrelated to this change — not touched, not masked.
- Simulated the plain-checkout SKIP path by pointing
  `CLAUDE_PLUGIN_ROOT_CORE` at a nonexistent path (both for a single
  plugin suite and for `run-gate-tests.sh` directly): both printed
  `SKIP: core plugin unreachable — unverifiable outside spawn env` to
  stderr and exited `75`.
- `grep -rl test-env-resolution tests/` returns all 6 in-scope files.

## Hunt record
Before-landing warrant hunt (stance 0: gate bypassability) dispatched via
`warrant-hunter`; record at
`docs/reports/2026-08-09-hunt-test-env-resolution-adoption.md`.
Finding: `run-gate-tests.sh`'s "all sub-suites skipped" SKIP-aggregation
branch is unreachable in practice, because the top-level resolution check
already exits 75 before the sub-suite loop runs if core is unresolved,
and once resolved, every sub-suite inherits the same exported, validated
`CLAUDE_PLUGIN_ROOT_CORE` and can never independently SKIP.

Resolution: kept as-is, not removed. The branch is dead but harmless —
it does not mask a real failure as SKIP (the opposite of the issue's
empty-state concern) and it does not change behavior in any reachable
state; it exists because the proposal's "What will be done" explicitly
required the dispatch loop to distinguish sub-suite SKIP from real
failure and propagate a dispatcher-level SKIP verdict, matching the
convention's per-consumer-shape guidance for a runner that wraps other
runners. Removing it would need re-litigating that requirement against
the approved proposal, which is out of this phase's scope; leaving
unreachable defensive code that provably never produces a wrong verdict
is not a blocking correctness defect.

closed_checks:
  - check: sub-suite SKIP/FAIL aggregation reachability
    code_sha: 3a1868ec9c2a748192234c2acfb931dbdaf91add

## Open findings
None blocking.
</content>
