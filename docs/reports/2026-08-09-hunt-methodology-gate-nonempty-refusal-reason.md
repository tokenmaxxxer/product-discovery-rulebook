---
proposal: docs/issue-60/proposals/2026-08-09-methodology-gate-nonempty-refusal-reason.md
---

# Hunt record — methodology-gate-nonempty-refusal-reason

## after-proposal — stance 0: assume the gate just touched is bypassable — find the bypass

Verdict: FINDING — product-assumption-mapping/hooks/methodology-gate.sh has no `trap ... ERR` and no `set -e` (only `set -uo pipefail`), so a bare `python3 -c ...` crash inside any of its ungated command substitutions (e.g. lines 79-81, 96-102, 115-146, 153+) never reaches `deny()` at all — the script falls through toward `exit 0` (ALLOW), not a "deny with empty reason." The proposal's planned fix (mirror `deny()`'s reason to stderr, plus "any inline denial code path that bypasses it, e.g. the ERR traps in product-hypothesis-testing and product-guardrail-metrics") never mentions that product-assumption-mapping has no ERR trap/`-e` to begin with, so patching `deny()` alone leaves this file's crash paths completely unaddressed post-fix — worse than issue #60's symptom (empty-reason refusal), this is a silent fail-OPEN.
Kind: composition
Seed: docs/issue-60/proposals/2026-08-09-methodology-gate-nonempty-refusal-reason.md (phase-1 proposal, no code changed yet); compared against product-assumption-mapping/hooks/methodology-gate.sh, product-hypothesis-testing/hooks/methodology-gate.sh, product-guardrail-metrics/hooks/methodology-gate.sh
cap_seconds: 120
tier: default
diff_stat_lines: approximately 209 (2 new docs files)
started_at: 2026-08-09T00:00:00Z
ended_at: 2026-08-09T00:45:00Z

### Reproduce
Confirmed the real file's guard structure by direct grep (run from repo root):

grep -n pattern-for-set-and-ERR-trap against the three files: product-assumption-mapping/hooks/methodology-gate.sh, product-hypothesis-testing/hooks/methodology-gate.sh, product-guardrail-metrics/hooks/methodology-gate.sh

Result: product-assumption-mapping/hooks/methodology-gate.sh line 6 has `set -uo pipefail` only; it has no ERR trap line anywhere in the file. product-hypothesis-testing (line 27 set, line 36 trap) and product-guardrail-metrics (line 21 set, line 30 trap) both additionally have a `trap 'deny "..."' ERR` line that product-assumption-mapping lacks entirely.

Then a minimal script reproducing the exact control-flow shape used at product-assumption-mapping/hooks/methodology-gate.sh lines 79-81 (a bare `python3 -c` json-key access, no try/except around it, no ERR trap, no `-e`, same `deny()` shape as the real file) was written to a scratch file and executed:

Script body:
```
#!/usr/bin/env bash
set -uo pipefail
deny() { printf 'DENY-CALLED: %s\n' "$1"; exit 2; }
fields_json='{"not_tool_name":"Write"}'
tool_name="$(printf '%s' "$fields_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["tool_name"])')"
echo "reached-after-python-crash: tool_name=[$tool_name]"
echo "ALLOW"
exit 0
```

Run: `bash repro.sh; echo "EXIT:$?"`

### Observed
```
Traceback (most recent call last):
  File "<string>", line 1, in <module>
KeyError: 'tool_name'
reached-after-python-crash: tool_name=[]
ALLOW
EXIT:0
```
`deny()` was never called; the script printed `ALLOW` and exited 0 despite the python subprocess crashing with an uncaught exception mid-evaluation — the same control-flow shape (`set -uo pipefail`, no ERR trap, no `-e`) that product-assumption-mapping/hooks/methodology-gate.sh actually uses at its own bare `python3 -c` call sites.

### Expected
Any internal-error crash in the judge should fail closed and call `deny()` with a diagnosable reason (as the sibling files' ERR trap already does), not silently fall through toward an allow-shaped exit. Since the proposal's write set for this file only adds `>&2` inside `deny()`, and this crash path never reaches `deny()`, the "every refusal carries a non-empty reason" acceptance criterion is unmet for this specific bypass — because there is no refusal to begin with, the check is silently skipped rather than failing closed with a message.
