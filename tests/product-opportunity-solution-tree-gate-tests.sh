#!/usr/bin/env bash
# Gate tests for product-opportunity-solution-tree/hooks/methodology-gate.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOOKS="$HERE/../product-opportunity-solution-tree/hooks"

# The gate sources gate-lib.sh via CLAUDE_PLUGIN_ROOT_CORE (issue-72
# gate-house migration); resolve it the same way the real runtime does so
# subprocess runs below can find gate-lib.sh/gate-lib.py.
# Resolution order and SKIP contract per docs/specs/test-env-resolution.md
# (on-the-record issue #551).
if [ -z "${CLAUDE_PLUGIN_ROOT_CORE:-}" ]; then
  for cand in "$HOME/tokenmaxxxer/tokenmaxxxer-core/core" \
              "$HOME/.claude/plugins/marketplaces/tokenmaxxxer/runs/rulebooks/tokenmaxxxer-core/core"; do
    if [ -s "$cand/hooks/lib/gate-lib.sh" ]; then export CLAUDE_PLUGIN_ROOT_CORE="$cand"; break; fi
  done
fi
if [ -z "${CLAUDE_PLUGIN_ROOT_CORE:-}" ] || [ ! -s "$CLAUDE_PLUGIN_ROOT_CORE/hooks/lib/gate-lib.sh" ]; then
  echo "SKIP: core plugin unreachable — unverifiable outside spawn env" >&2
  exit 75
fi

pass=0; fail=0
report() { if [ "$2" = "$1" ]; then pass=$((pass+1)); printf 'ok     %-38s %s\n' "$3" "$2"; else fail=$((fail+1)); printf 'FAIL   %-38s want=%s got=%s\n' "$3" "$1" "$2"; fi; }

SURVEY=docs/issue-7/reports/product-discovery/current-state.md
PROPOSAL=docs/issue-7/proposals/2026-07-31-product-discovery.md
RECORD=docs/issue-7/reports/product-discovery.md

run_raw() { # want name payload-json envvars...
  local want="$1" name="$2" payload="$3"; shift 3
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"
  mkdir -p "$td/docs/issue-7/reports/product-discovery" "$td/docs/issue-7/proposals"
  printf '%s' "$payload" | env CLAUDE_PROJECT_DIR="$td" CLAUDE_PLUGIN_ROOT_CORE="$CLAUDE_PLUGIN_ROOT_CORE" "$@" /bin/bash "$HOOKS/methodology-gate.sh" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report "$want" "$got" "$name"
}

run() { # want name file content [precreate-current-state:0/1]
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"
  mkdir -p "$td/docs/issue-7/reports/product-discovery" "$td/docs/issue-7/proposals"
  if [ "${5:-0}" = "1" ]; then
    printf 'placeholder current-state\n' > "$td/$SURVEY"
  fi
  printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":%s},"cwd":"%s"}' \
    "$3" "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$4")" "$td" \
    | env CLAUDE_PROJECT_DIR="$td" CLAUDE_PLUGIN_ROOT_CORE="$CLAUDE_PLUGIN_ROOT_CORE" /bin/bash "$HOOKS/methodology-gate.sh" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report "$1" "$got" "$2"
}

SURVEY_OK='Background/context.
JTBD: performer=PM, job=..., circumstance=..., desired outcome=...

Opportunity: reduce churn.
Candidate hypotheses ...'
run allow survey-ost-vocab-pass "$SURVEY" "$SURVEY_OK"

SURVEY_BAD='Background/context.
We think users want a dashboard because it would be nice.'
run deny survey-ost-vocab-missing "$SURVEY" "$SURVEY_BAD"

PROPOSAL_OK='Hypothesis package: named metric X, threshold 10, decision rule go/kill.'
run allow proposal-order-pass "$PROPOSAL" "$PROPOSAL_OK" 1
run deny  proposal-order-deny "$PROPOSAL" "$PROPOSAL_OK" 0

RECORD_OK='Verdict: metric 12 vs threshold 10, go.

Opportunity: promoted (go).'
run allow record-disposition-pass "$RECORD" "$RECORD_OK"

RECORD_BAD='Verdict: metric 12 vs threshold 10, go.
No mention of the tree here.'
run deny record-disposition-deny "$RECORD" "$RECORD_BAD"

# malformed stdin
td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"
printf 'not json' | env CLAUDE_PROJECT_DIR="$td" CLAUDE_PLUGIN_ROOT_CORE="$CLAUDE_PLUGIN_ROOT_CORE" /bin/bash "$HOOKS/methodology-gate.sh" >/dev/null 2>&1
rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
rm -rf "$td"; report deny "$got" malformed-stdin

# malformed JSON: truncated
td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"
printf '{"tool_name":"Write","tool_input":{"file_path":"%s"' "$SURVEY" \
  | env CLAUDE_PROJECT_DIR="$td" CLAUDE_PLUGIN_ROOT_CORE="$CLAUDE_PLUGIN_ROOT_CORE" /bin/bash "$HOOKS/methodology-gate.sh" >/dev/null 2>&1
rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
rm -rf "$td"; report deny "$got" malformed-json-truncated

# malformed JSON: non-object top-level
td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"
printf '"just a string"' \
  | env CLAUDE_PROJECT_DIR="$td" CLAUDE_PLUGIN_ROOT_CORE="$CLAUDE_PLUGIN_ROOT_CORE" /bin/bash "$HOOKS/methodology-gate.sh" >/dev/null 2>&1
rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
rm -rf "$td"; report deny "$got" malformed-json-non-object

# malformed JSON: empty payload
td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"
printf '' \
  | env CLAUDE_PROJECT_DIR="$td" CLAUDE_PLUGIN_ROOT_CORE="$CLAUDE_PLUGIN_ROOT_CORE" /bin/bash "$HOOKS/methodology-gate.sh" >/dev/null 2>&1
rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
rm -rf "$td"; report deny "$got" malformed-json-empty

# unrelated path pass-through
run allow unrelated-path "docs/issue-7/reports/other.md" "hello"

# kill switch: recognized on-value disables the gate
td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"; mkdir -p "$td/docs/issue-7/reports/product-discovery"
printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":"nothing"},"cwd":"%s"}' "$SURVEY" "$td" \
  | env CLAUDE_PROJECT_DIR="$td" CLAUDE_PLUGIN_ROOT_CORE="$CLAUDE_PLUGIN_ROOT_CORE" PRODUCT_OPPORTUNITY_SOLUTION_TREE_GATE_OFF=1 /bin/bash "$HOOKS/methodology-gate.sh" >/dev/null 2>&1
rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
rm -rf "$td"; report allow "$got" kill-switch-on

# kill switch regression: THE bug named in the issue's audit — this exact
# gate used to fail-OPEN (silently disable) on ANY unrecognized value
# (case ... in ""|0|false|no|off) ;; *) exit 0 ;; esac). An unrecognized
# typo like "banana" must now leave the gate ACTIVE (deny bad content),
# not silently disable it.
td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"; mkdir -p "$td/docs/issue-7/reports/product-discovery"
printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":"nothing"},"cwd":"%s"}' "$SURVEY" "$td" \
  | env CLAUDE_PROJECT_DIR="$td" CLAUDE_PLUGIN_ROOT_CORE="$CLAUDE_PLUGIN_ROOT_CORE" PRODUCT_OPPORTUNITY_SOLUTION_TREE_GATE_OFF=banana /bin/bash "$HOOKS/methodology-gate.sh" >/dev/null 2>&1
rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
rm -rf "$td"; report deny "$got" kill-switch-unrecognized-value-stays-active

# Edit reconstruction failure (old_string not present in current file)
td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"
mkdir -p "$td/docs/issue-7/reports"
printf 'existing content\n' > "$td/$RECORD"
printf '{"tool_name":"Edit","tool_input":{"file_path":"%s","old_string":"not present here","new_string":"x"},"cwd":"%s"}' "$RECORD" "$td" \
  | env CLAUDE_PROJECT_DIR="$td" CLAUDE_PLUGIN_ROOT_CORE="$CLAUDE_PLUGIN_ROOT_CORE" /bin/bash "$HOOKS/methodology-gate.sh" >/dev/null 2>&1
rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
rm -rf "$td"; report deny "$got" edit-reconstruction-fail

# Edit with replace_all: true across a multiply-occurring old_string —
# only-first-occurrence would leave a stray non-OST placeholder verdict
# term unreplaced and still fail; full replace_all must fix all instances
# and allow.
td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"
mkdir -p "$td/docs/issue-7/reports"
printf 'Verdict: PLACEHOLDER.\nOpportunity: PLACEHOLDER.\nSecond mention: PLACEHOLDER.\n' > "$td/$RECORD"
printf '{"tool_name":"Edit","tool_input":{"file_path":"%s","old_string":"PLACEHOLDER","new_string":"go","replace_all":true},"cwd":"%s"}' "$RECORD" "$td" \
  | env CLAUDE_PROJECT_DIR="$td" CLAUDE_PLUGIN_ROOT_CORE="$CLAUDE_PLUGIN_ROOT_CORE" /bin/bash "$HOOKS/methodology-gate.sh" >/dev/null 2>&1
rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
rm -rf "$td"; report allow "$got" edit-replace-all-true-full-replacement

# MultiEdit with mixed replace_all true/false in one call.
td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"
mkdir -p "$td/docs/issue-7/reports"
printf 'BADWORD one.\nBADWORD two.\nOpportunity: BADWORD.\n' > "$td/$RECORD"
printf '{"tool_name":"MultiEdit","tool_input":{"file_path":"%s","edits":[{"old_string":"BADWORD","new_string":"promoted","replace_all":true},{"old_string":"Opportunity: promoted.","new_string":"Opportunity: promoted (go).","replace_all":false}]},"cwd":"%s"}' "$RECORD" "$td" \
  | env CLAUDE_PROJECT_DIR="$td" CLAUDE_PLUGIN_ROOT_CORE="$CLAUDE_PLUGIN_ROOT_CORE" /bin/bash "$HOOKS/methodology-gate.sh" >/dev/null 2>&1
rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
rm -rf "$td"; report allow "$got" multiedit-mixed-replace-all

# Absolute file_path matching survey scope
td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"
mkdir -p "$td/docs/issue-7/reports/product-discovery"
abs="$td/$SURVEY"
printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":%s},"cwd":"%s"}' \
  "$abs" "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$SURVEY_OK")" "$td" \
  | env CLAUDE_PROJECT_DIR="$td" CLAUDE_PLUGIN_ROOT_CORE="$CLAUDE_PLUGIN_ROOT_CORE" /bin/bash "$HOOKS/methodology-gate.sh" >/dev/null 2>&1
rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
rm -rf "$td"; report allow "$got" absolute-path-survey

# ./-prefixed file_path variant
td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"
mkdir -p "$td/docs/issue-7/reports/product-discovery"
rel="./$SURVEY"
printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":%s},"cwd":"%s"}' \
  "$rel" "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$SURVEY_OK")" "$td" \
  | env CLAUDE_PROJECT_DIR="$td" CLAUDE_PLUGIN_ROOT_CORE="$CLAUDE_PLUGIN_ROOT_CORE" /bin/bash "$HOOKS/methodology-gate.sh" >/dev/null 2>&1
rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
rm -rf "$td"; report allow "$got" dot-slash-prefixed-path-survey

# Bash-tool coverage: a Bash command writing to the record path must DENY
# (this gate cannot verify the OST facet on a shell-redirected write).
td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"
mkdir -p "$td/docs/issue-7/reports"
printf '{"tool_name":"Bash","tool_input":{"command":"echo hi >> %s"},"cwd":"%s"}' "$RECORD" "$td" \
  | env CLAUDE_PROJECT_DIR="$td" CLAUDE_PLUGIN_ROOT_CORE="$CLAUDE_PLUGIN_ROOT_CORE" /bin/bash "$HOOKS/methodology-gate.sh" >/dev/null 2>&1
rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
rm -rf "$td"; report deny "$got" bash-write-to-record-path-denies

# Bash command not touching survey/proposal/record paths — allow.
td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"
printf '{"tool_name":"Bash","tool_input":{"command":"git status"},"cwd":"%s"}' "$td" \
  | env CLAUDE_PROJECT_DIR="$td" CLAUDE_PLUGIN_ROOT_CORE="$CLAUDE_PLUGIN_ROOT_CORE" /bin/bash "$HOOKS/methodology-gate.sh" >/dev/null 2>&1
rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
rm -rf "$td"; report allow "$got" bash-unrelated-command-allows

# Semantic-upgrade regression pair: false-positive doc — layer words only
# as stray references, with no OST-labeled section — must DENY (closes
# the false-positive class "for background see
# docs/handbooks/outcome-notes.md").
SURVEY_FALSE_POSITIVE='Background.
see docs/handbooks/outcome-notes.md for background; the opportunity here is real.'
run deny survey-semantic-false-positive-denies "$SURVEY" "$SURVEY_FALSE_POSITIVE"

# Semantic-upgrade regression pair: genuinely well-formed survey with
# clean Outcome:/Opportunity: label lines — must ALLOW.
SURVEY_WELL_FORMED='Background.

Outcome: reduce time-to-value.
Opportunity: onboarding friction is high.'
run allow survey-semantic-well-formed-allows "$SURVEY" "$SURVEY_WELL_FORMED"

# missing-core: CLAUDE_PLUGIN_ROOT_CORE points nowhere -> guarded source
# must deny (exit 2), not silently allow (issue-75 fix).
td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"; mkdir -p "$td/docs/issue-7/reports/product-discovery"
printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":"nothing"},"cwd":"%s"}' "$SURVEY" "$td" \
  | env CLAUDE_PROJECT_DIR="$td" CLAUDE_PLUGIN_ROOT_CORE="$td/no-such-core" /bin/bash "$HOOKS/methodology-gate.sh" >/dev/null 2>&1
rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
rm -rf "$td"; report deny "$got" missing-core-denies

# stderr diagnostics: forced-refusal fixtures must write a human-readable
# reason naming the unmet element to stderr, not just the stdout JSON.

# survey missing OST vocabulary -> stderr names "OST branch vocabulary"
td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"
mkdir -p "$td/docs/issue-7/reports/product-discovery" "$td/docs/issue-7/proposals"
stderr="$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":%s},"cwd":"%s"}' \
    "$SURVEY" "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$SURVEY_BAD")" "$td" \
  | env CLAUDE_PROJECT_DIR="$td" CLAUDE_PLUGIN_ROOT_CORE="$CLAUDE_PLUGIN_ROOT_CORE" /bin/bash "$HOOKS/methodology-gate.sh" 2>&1 1>/dev/null)"
rm -rf "$td"
if [ -n "$stderr" ] && printf '%s' "$stderr" | grep -q "OST branch vocabulary"; then got=has-reason; else got=empty-or-missing; fi
report has-reason "$got" survey-ost-vocab-missing-stderr

# empty stdin -> stderr names "empty tool-use payload"
td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"
stderr="$(printf '' \
  | env CLAUDE_PROJECT_DIR="$td" CLAUDE_PLUGIN_ROOT_CORE="$CLAUDE_PLUGIN_ROOT_CORE" /bin/bash "$HOOKS/methodology-gate.sh" 2>&1 1>/dev/null)"
rm -rf "$td"
if [ -n "$stderr" ] && printf '%s' "$stderr" | grep -q "empty tool-use payload"; then got=has-reason; else got=empty-or-missing; fi
report has-reason "$got" empty-stdin-stderr

# no project root determinable -> stderr names "project root"
td="$(cd "$(mktemp -d)" && pwd -P)"
stderr="$(cd "$td" && printf '{"tool_name":"Write","tool_input":{"file_path":"docs/issue-7/reports/product-discovery.md","content":"x"},"cwd":"%s"}' "$td" \
  | env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_ROOT_CORE="$CLAUDE_PLUGIN_ROOT_CORE" /bin/bash "$HOOKS/methodology-gate.sh" 2>&1 1>/dev/null)"
rm -rf "$td"
if [ -n "$stderr" ] && printf '%s' "$stderr" | grep -q "project root"; then got=has-reason; else got=empty-or-missing; fi
report has-reason "$got" no-project-root-stderr

printf '\n== %d passed, %d failed ==\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
