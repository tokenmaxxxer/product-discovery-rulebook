# Handbook — tests/

`tests/run-gate-tests.sh` runs each of the five `product-*` methodology
plugins' own gate test suite as a subprocess —
`tests/product-one-pager-gate-tests.sh`,
`tests/product-opportunity-solution-tree-gate-tests.sh`,
`tests/product-assumption-mapping-gate-tests.sh`,
`tests/product-hypothesis-testing-gate-tests.sh`,
`tests/product-guardrail-metrics-gate-tests.sh` — then runs core's
`compliance-check.sh` (from `tokenmaxxxer-core`, issue #72) against each
of the 5 plugins' `hooks/` directories. It no longer references
`record-fields-gate.sh`/`trailer-gate.sh` (issue #45 survey: those files
never existed in this repo; the dispatcher previously pointed at them by
mistake and failed before ever reaching the 5 real suites).

## Run

    bash tests/run-gate-tests.sh

Each plugin's own suite can also be run standalone, e.g.:

    bash tests/product-hypothesis-testing-gate-tests.sh

`CLAUDE_PLUGIN_ROOT_CORE` is auto-detected by `run-gate-tests.sh` and by
each plugin suite (checking `$HOME/tokenmaxxxer/tokenmaxxxer-core/core`
and the marketplace-installed core plugin path) so both the gates
themselves and their test harnesses can locate core's `gate-lib.sh`/
`gate-lib.py`/`compliance-check.sh` without it being set externally in a
dev checkout.

On a plain checkout where none of those candidates resolve to a
non-empty `gate-lib.sh` (no `CLAUDE_PLUGIN_ROOT_CORE` and no sibling core
checkout — e.g. a bare `main` clone), every script in `tests/` that
depends on core SKIPs instead of failing: it prints
`SKIP: core plugin unreachable — unverifiable outside spawn env` to
stderr and exits `75`, a distinct code from a real assertion failure.
`run-gate-tests.sh` propagates the same SKIP verdict for the whole
dispatcher when every sub-suite it ran also SKIPped. This follows the
canonical resolution order and SKIP contract landed at
`docs/specs/test-env-resolution.md` (on-the-record issue #551);
`tests/deny-only-check.sh` and `tests/parse-check.sh` have no core
dependency and are unaffected.

## Coverage

- Each `product-*` plugin's `methodology-gate.sh` sources core's
  `gate-lib.sh`/`gate-lib.py` by reference (issue #45/#72): fail-closed
  EXIT trap, `gate_kill_switch_active` (unrecognized value stays
  active), `gate_parse_json_or_deny`, `gate_normalize_path`,
  `gate_reconstruct_write` (Write/Edit/MultiEdit/NotebookEdit, honoring
  each edit's own `replace_all`), and `gate_bash_write_targets` for
  Bash-tool write-target coverage.
- Each plugin's own adopted-methodology facet from `docs/issue-36`'s
  norms (JTBD tuple, OST vocabulary/disposition, evidence-citation +
  RICE/ICE, hypothesis package + verdict-adjacency + ITWWS, guardrail
  non-emptiness + status) is checked with section/adjacency/structure
  discipline: an explicit `label: value` line first, else a marker word
  required to co-occur with its value inside a paragraph under a
  heading that itself names the facet — never a bare keyword match
  anywhere in the document (issue #45).
- The shared cross-plugin order-constraint (proposal write must not
  precede its own current-state survey), fail-closed behavior on
  malformed JSON, and each plugin's own kill switch.
- Mandatory per-gate cases (issue #45 / gate-house-standard.md): Edit
  `replace_all: true` against a multiply-occurring string, MultiEdit
  with mixed `replace_all`, 3 malformed-JSON sub-cases, kill switch set
  to an unrecognized value, absolute + `./`-prefixed path matching, a
  Bash-tool write reaching the same target a Write call would, and a
  semantic-upgrade regression pair (false-positive-that-must-now-deny /
  well-formed-that-must-still-allow) per facet.
- `compliance-check.sh` (core issue #72), run against each plugin's
  `hooks/` directory: flags a hand-rolled kill switch or a hand-rolled
  `Edit`/`MultiEdit` reconstruction that bypasses `gate_lib`, catching a
  future drift back to the pre-issue-45 shape.

Add a case here whenever a gate's decision boundary changes (e.g. a new
required section, a new plugin facet, a new mandatory case group).
