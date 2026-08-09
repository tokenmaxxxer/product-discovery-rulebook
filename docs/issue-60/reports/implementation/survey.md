# Current-state survey — issue #60

## Root cause

Every `deny()` in the five `hooks/methodology-gate.sh` scripts writes the
refusal JSON (including the human-readable reason) to **stdout only**:

```
product-opportunity-solution-tree/hooks/methodology-gate.sh:30-34
deny() {
  printf '{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":%s}}\n' \
    "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1" 2>/dev/null || echo '"product-opportunity-solution-tree: refused"')"
  exit 2
}
```

No `>&2` anywhere near it. All bash-level guard checks that call this
`deny()` before the Python judge runs (missing python3, empty stdin,
no project root, Bash-write coverage, judge-crash fallback — call sites
at `:36, :39, :94, :105, :283` in the OST copy) refuse the tool call with
an **empty stderr**, which is exactly the "No stderr output" symptom in
#60. By contrast the embedded Python judge's own `deny(m)` does
`sys.stderr.write(...)` in addition to stdout, so *some* refusals already
carry a message — this is why the bug is intermittent.

## Per-plugin severity

- `product-opportunity-solution-tree` (285 lines), `product-one-pager`
  (334 lines): only the early bash-level `deny()` call sites are silent;
  deeper methodology-vocabulary denials (inside the embedded Python
  block) already write to stderr.
- `product-hypothesis-testing` (284 lines), `product-guardrail-metrics`
  (283 lines): additionally install `trap 'deny "...failed closed..."' ERR`
  (`product-hypothesis-testing/hooks/methodology-gate.sh:36`,
  `product-guardrail-metrics/hooks/methodology-gate.sh:30`) — any
  unexpected internal error is *also* silent, not just the early guards.
- `product-assumption-mapping` (252 lines): **100% affected** — all 9
  deny call sites are bash-level, none write to stderr
  (`grep -n stderr` on the file returns nothing).

## Write-set implications

The five `methodology-gate.sh` files are independent regular files (5
distinct inodes, `diff` shows real divergence — different plugin-specific
checks, different fix-history headers), not symlinks and not derived from
a shared local copy. `deny()` is defined locally, verbatim per plugin
name, in each file. **A fix must be applied 5×** — there is no
single-source-of-truth in this repo to patch once.

Each script sources `hooks/lib/gate-lib.sh` from an external "core"
plugin (not vendored in this checkout, path resolved via
`CLAUDE_PLUGIN_ROOT_CORE` / marketplace install). That core-provided
`gate_trap_fail_closed` EXIT trap is out of this repo's write set and not
auditable here — flagged as an out-of-scope risk, not fixed by this
proposal.

## Existing tests

`tests/product-<name>-gate-tests.sh` (213–263 lines each) assert only on
exit code; every current stderr capture is discarded
(`>/dev/null 2>&1`, e.g. `tests/product-opportunity-solution-tree-gate-tests.sh:32`).
None of the five suites assert on stderr *content* — a regression back to
silent stderr would not be caught by the existing suite even after a
phase-2 fix, so the write set must add stderr-content assertions, not
just fix `deny()`.

`tests/run-gate-tests.sh` dispatches all five suites plus core's
`compliance-check.sh`; no bats framework, plain bash.

## Spec pointer

No machine-readable `spec.json` / canonical methodology spec exists in
this repo (`docs/specs/` holds only `approvers.md`). The nearest existing
convention is the deny-message text itself informally citing
`docs/issue-<n>/...` current-state docs (e.g.
`product-opportunity-solution-tree/hooks/methodology-gate.sh:172`
cites `docs/issue-36/...`). Issue #60's acceptance criterion "point to
the spec condition" is satisfied by extending this existing informal
citation convention consistently to the stderr message, not by inventing
a new spec.json (no such structured spec exists to point at, and
building one is out of scope for a bug fix).

## Related prior/parallel work

`docs/issue-61/proposals/2026-08-09-test-env-resolution-adoption.md`
(phase-1 only, not yet executed) proposes a `SKIP: core plugin
unreachable — unverifiable outside spawn env` / exit-75 convention for
*test-harness* environment-resolution skips — a different call site
(tests detecting an unreachable core plugin) from this issue's *gate
scripts'* production deny messages. Same "silent failure" family, no
file overlap expected beyond both potentially touching
`docs/handbooks/tests.md` — worth a coordination note in the proposal's
rationale, not a merge of scope.

No prior commit addressed stderr-message completeness
(`git log --all --oneline -- '**/methodology-gate.sh'` shows fixes for
different symptoms: sandbox mktemp bug, gate A+ closeout, initial
remediation). `docs/decisions/` is empty.

## Skip-condition check (scout directive)

This is a bugfix (empty-stderr refusal is unambiguously a defect, not a
design choice) — scout sweep skipped per the bugfix skip condition.
