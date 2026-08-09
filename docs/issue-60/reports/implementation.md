---
code_under_review:
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
type: fix
breaking: false
verdict: pass
loop_state: landed
---

# implementation record — issue #60

## What was done

Applied the approved phase-1 proposal
(`docs/issue-60/proposals/2026-08-09-methodology-gate-nonempty-refusal-reason.md`)
to all five `product-*/hooks/methodology-gate.sh` files and their
`tests/product-*-gate-tests.sh` suites:

- `product-opportunity-solution-tree/hooks/methodology-gate.sh` — bash-level
  `deny()` now also writes the reason to stderr; python3-missing,
  empty-payload, no-project-root deny messages got a spec pointer appended.
- `product-hypothesis-testing/hooks/methodology-gate.sh` — same stderr write
  added to bash-level `deny()`; ERR trap and early guard messages
  (python3-missing, empty-stdin, Bash-write-target-scan) got spec pointers.
- `product-guardrail-metrics/hooks/methodology-gate.sh` — same stderr write;
  ERR trap and early guard messages got spec pointers.
- `product-one-pager/hooks/methodology-gate.sh` — same stderr write on the
  bash-level `deny()`; early guard messages got spec pointers. In addition
  (see Rationale for deviations below), the embedded Python `deny(m)` used
  by this file's JTBD-tuple facet check was stdout-only and got a matching
  `sys.stderr.write(...)` line.
- `product-assumption-mapping/hooks/methodology-gate.sh` — same stderr
  write on the bash-level `deny()`; early guard messages got spec pointers.
  No ERR trap added (out of scope per the proposal's flagged residual
  risk — fail-open defect, different fix shape, tracked as a follow-up).
- All five `tests/product-*-gate-tests.sh` — added stderr-capture
  assertions on every forced-refusal fixture (missing python3, empty
  stdin, no project root, Bash-write-target, vocabulary-missing writes,
  ERR-trap trigger, and — after the deviation below — one-pager's
  `missing-tuple-deny` / `solution-before-tuple-deny` fixtures) asserting
  a non-empty, element-naming stderr message.

## Why

Issue #60: `methodology-gate.sh` refusals sometimes surfaced with "No
stderr output," giving the calling session no way to self-correct. The
approved proposal's fix is a stderr mirror of the existing reason string
on every bash-level `deny()` path, plus spec-pointer text on the early
guards that previously had none — reusing the existing informal
docs/issue-<n> citation convention rather than inventing a machine-
readable spec format.

## Basis

docs/issue-60/proposals/2026-08-09-methodology-gate-nonempty-refusal-reason.md

## What did not work

- Expected: per the proposal's stated scope, "the deeper Python-side
  denials... already write to stderr" for all five files, so the fix
  set was bash-level `deny()` only. Actual: a before-landing warrant-hunt
  (stance 2, "assume this guard goes silent under malformed input")
  found `product-one-pager/hooks/methodology-gate.sh`'s embedded Python
  `deny(m)` (its JTBD-tuple facet check) writes only the stdout JSON
  payload, never stderr — unlike the other four files' Python-side
  `deny(m)`, which do write stderr. The two forced-refusal fixtures on
  that path (`missing-tuple-deny`, `solution-before-tuple-deny`)
  produced empty stderr and the test suite's `run_write` helper captured
  stderr but never asserted on it for those two cases, silently passing.
  Fixed in the same commit (see Rationale for deviations) rather than
  filed as a follow-up, since it falls inside this proposal's
  Acceptance criterion ("every refusal carries a non-empty reason") and
  inside the frozen write set (`product-one-pager/hooks/methodology-gate.sh`,
  `tests/product-one-pager-gate-tests.sh`).

## Rationale for deviations

The proposal's `## What will be done` scoped the fix to bash-level
`deny()` and explicitly carved out "the deeper Python-side denials in
this file" as already covering stderr. That assumption held for four of
the five files but not for `product-one-pager`, whose Python-side
`deny(m)` (unlike the sibling four) never wrote stderr. Since this is
still the same defect class named in the proposal's Acceptance
criterion, on a file and test already inside the frozen write set, it
was fixed in-scope rather than treated as a new proposal: added
`sys.stderr.write(payload + "\n")` to that `deny(m)`, and added the two
missing `report_stderr_nonempty` assertions to
`tests/product-one-pager-gate-tests.sh`.

## Doc placement ladder

- [x] No env var / config key / new dependency / migration / setup step
  introduced — nothing to add to a handbook.
- [x] No library-or-format choice over a named alternative and no
  changed public signature/wire format beyond what the phase-1 proposal
  already recorded — no new `docs/issue-60/decisions/` entry needed.
- [x] No benchmark or investigation numbers produced — no
  `docs/issue-60/reports/` entry beyond this record and the hunt record.
- [x] Hunt record appended:
  `docs/reports/2026-08-09-hunt-methodology-gate-nonempty-refusal-reason.md`
  (before-landing dispatch, stance 2, one FINDING — folded into this
  build per the deviation above).

## Open findings

None outstanding. The one before-landing warrant-hunt finding (one-pager's
missing stderr write on its Python-side `deny(m)`) was addressed in this
same commit; see "What did not work" / "Rationale for deviations" above.

## Next steps

Commit this record together with the code/test changes (single commit,
`Subject: issue-60` trailer + `Proposal:` trailer), push the branch, and
open the PR with `Closes #60` in the body.

## Open-finding resolution path

Not applicable — no open findings remain (see "Open findings" above).

## Verification run

`bash tests/run-gate-tests.sh` — all five plugin suites pass:
opportunity-solution-tree 27/27, hypothesis-testing 36/36,
guardrail-metrics 29/29, one-pager 26/26 (after the deviation fix, not
the 25/25 an earlier partial run showed), assumption-mapping 32/32.
`compliance-check.sh` reports one pre-existing FAIL on
`product-hypothesis-testing/hooks/methodology-gate.sh` (mktemp in the
gate's request-time path) — confirmed via `git stash` to be present on
the pre-change base commit (ca7ceba) identically, so it predates and is
unrelated to this change; not touched, since `product-hypothesis-testing`
was already in this proposal's write set only for the stderr/spec-pointer
fix, and fixing an unrelated pre-existing defect would exceed the frozen
scope.
