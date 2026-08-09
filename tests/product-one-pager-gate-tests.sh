#!/usr/bin/env bash
# Gate tests for product-one-pager's methodology-gate.sh.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOOKS="$HERE/../product-one-pager/hooks"

# The gate sources gate-lib.sh via CLAUDE_PLUGIN_ROOT_CORE (issue-45
# migration); the harness must resolve it the same way the real runtime
# does, so subprocess runs below can find gate-lib.sh/gate-lib.py.
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
export CLAUDE_PLUGIN_ROOT_CORE

pass=0; fail=0
report() { if [ "$2" = "$1" ]; then pass=$((pass+1)); printf 'ok     %-34s %s\n' "$3" "$2"; else fail=$((fail+1)); printf 'FAIL   %-34s want=%s got=%s\n' "$3" "$1" "$2"; fi; }

SURVEY=docs/issue-7/reports/product-discovery/current-state.md

run_write() { # want name file content [extra_env]
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"; mkdir -p "$td/$(dirname "$3")"
  printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":%s},"cwd":"%s"}' \
    "$3" "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$4")" "$td" \
    | env ${5:-} CLAUDE_PLUGIN_ROOT_CORE="$CLAUDE_PLUGIN_ROOT_CORE" CLAUDE_PROJECT_DIR="$td" /bin/bash "$HOOKS/methodology-gate.sh" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report "$1" "$got" "$2"
}

JTBD='## Current state

Job performer: a support agent.
Job: triage incoming tickets quickly.
Circumstance: during peak-hour ticket floods.
Desired outcome: tickets routed to the right owner within a minute.

No solution named yet.'

run_write allow jtbd-tuple-pass "$SURVEY" "$JTBD"

SOLUTION_FIRST='## Current state

Solution: we will build an AI ticket router.

Job performer: a support agent.
Job: triage incoming tickets quickly.
Circumstance: during peak-hour ticket floods.
Desired outcome: tickets routed to the right owner within a minute.'

run_write deny  solution-before-tuple-deny "$SURVEY" "$SOLUTION_FIRST"

run_write deny  missing-tuple-deny "$SURVEY" "We should probably fix onboarding somehow."

# Malformed stdin: not valid JSON at all.
malformed_stdin_test() { # want payload name
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"; mkdir -p "$td/$(dirname "$SURVEY")"
  printf '%s' "$2" | env CLAUDE_PLUGIN_ROOT_CORE="$CLAUDE_PLUGIN_ROOT_CORE" CLAUDE_PROJECT_DIR="$td" /bin/bash "$HOOKS/methodology-gate.sh" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report deny "$got" "$3"
}
malformed_stdin_test deny 'not json at all' malformed-stdin-not-json-deny
malformed_stdin_test deny '{"tool_name":"Write"' malformed-stdin-truncated-deny
malformed_stdin_test deny '"just a string"' malformed-stdin-non-object-deny
malformed_stdin_test deny '' malformed-stdin-empty-deny

run_write allow unrelated-path-pass "docs/issue-7/reports/verify.md" "anything goes here"

# Kill switch: even malformed/deficient content passes when the gate is off.
killswitch_test() { # want value name
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"; mkdir -p "$td/$(dirname "$SURVEY")"
  printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":"no tuple here"},"cwd":"%s"}' \
    "$SURVEY" "$td" \
    | env PRODUCT_ONE_PAGER_GATE_OFF="$2" CLAUDE_PLUGIN_ROOT_CORE="$CLAUDE_PLUGIN_ROOT_CORE" CLAUDE_PROJECT_DIR="$td" /bin/bash "$HOOKS/methodology-gate.sh" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report "$1" "$got" "$3"
}
killswitch_test allow 1 kill-switch-on-spelling-pass
killswitch_test deny banana kill-switch-unrecognized-value-stays-active-deny

# Edit reconstruction failure: old_string not found in the pre-created file.
edit_recon_failure_test() {
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"; mkdir -p "$td/$(dirname "$SURVEY")"
  printf 'unrelated pre-existing content\n' > "$td/$SURVEY"
  printf '{"tool_name":"Edit","tool_input":{"file_path":"%s","old_string":"this text is not in the file","new_string":"replacement"},"cwd":"%s"}' \
    "$SURVEY" "$td" \
    | env CLAUDE_PLUGIN_ROOT_CORE="$CLAUDE_PLUGIN_ROOT_CORE" CLAUDE_PROJECT_DIR="$td" /bin/bash "$HOOKS/methodology-gate.sh" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report deny "$got" edit-reconstruction-failure-deny
}
edit_recon_failure_test

# --- issue-45 mandatory additions --------------------------------------

# Edit replace_all:true against a multiply-occurring old_string. Fixture:
# "Circumstance: TBD" appears twice; only replacing all occurrences yields a
# complete, well-formed JTBD tuple (replacing only the first would leave a
# stray unresolved "Circumstance: TBD" but our facet check only requires the
# labeled line to be present once — so instead we build the fixture so that
# a first-occurrence-only bug flips the verdict: the FIRST occurrence sits
# inside a decoy pre-heading blurb, and only the SECOND occurrence sits
# under the real JTBD content. If only the first occurrence were replaced
# (bug), the real section keeps "Circumstance: TBD" unresolved --- but
# structurally that's still a labeled line, satisfying tier 1. Instead we
# make old_string's replacement introduce the outcome label itself, so a
# missed replacement means outcome is never labeled.
REPLACE_ALL_BASE='Note: circumstance details pending. See PLACEHOLDER.

Job performer: a support agent.
Circumstance: during peak-hour ticket floods.
PLACEHOLDER

Desired outcome depends on PLACEHOLDER resolution.'

replace_all_edit_case() {
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"; mkdir -p "$td/$(dirname "$SURVEY")"
  printf '%s' "$REPLACE_ALL_BASE" > "$td/$SURVEY"
  payload='{"tool_name":"Edit","tool_input":{"file_path":"'"$SURVEY"'","old_string":"PLACEHOLDER","new_string":"Desired outcome: tickets routed to the right owner within a minute.","replace_all":true},"cwd":"'"$td"'"}'
  printf '%s' "$payload" | env CLAUDE_PLUGIN_ROOT_CORE="$CLAUDE_PLUGIN_ROOT_CORE" CLAUDE_PROJECT_DIR="$td" /bin/bash "$HOOKS/methodology-gate.sh" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report allow "$got" "Edit replace_all:true replaces every occurrence, completing the tuple"
}
replace_all_edit_case

# MultiEdit with 2 edits, one replace_all:true one replace_all:false (or
# default), against multiply-occurring strings. Base has "TBD" appearing
# twice (only replace_all:true resolves both) and "PENDING" appearing twice
# (replace_all:false/default only resolves the first) -- the verdict must
# reflect correct per-edit flag application.
MULTIEDIT_BASE='Job performer: TBD.
Circumstance: TBD.

Desired outcome: PENDING.
Extra note: PENDING.'

multiedit_case() {
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"; mkdir -p "$td/$(dirname "$SURVEY")"
  printf '%s' "$MULTIEDIT_BASE" > "$td/$SURVEY"
  payload='{"tool_name":"MultiEdit","tool_input":{"file_path":"'"$SURVEY"'","edits":[{"old_string":"TBD","new_string":"a support agent during peak-hour ticket floods","replace_all":true},{"old_string":"PENDING","new_string":"tickets routed to the right owner within a minute","replace_all":false}]},"cwd":"'"$td"'"}'
  printf '%s' "$payload" | env CLAUDE_PLUGIN_ROOT_CORE="$CLAUDE_PLUGIN_ROOT_CORE" CLAUDE_PROJECT_DIR="$td" /bin/bash "$HOOKS/methodology-gate.sh" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report allow "$got" "MultiEdit applies replace_all:true and replace_all:false independently, completing the tuple"
}
multiedit_case

# Kill switch set to an unrecognized value (already covered above via
# killswitch_test deny banana ...).

# Absolute file_path and ./-prefixed variant must match the same as relative.
abs_path_case() { # want name file_path_json_expr
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"; mkdir -p "$td/$(dirname "$SURVEY")"
  fp="$3"
  fp="${fp/__ROOT__/$td}"
  printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":"still incomplete"},"cwd":"%s"}' "$fp" "$td" \
    | env CLAUDE_PLUGIN_ROOT_CORE="$CLAUDE_PLUGIN_ROOT_CORE" CLAUDE_PROJECT_DIR="$td" /bin/bash "$HOOKS/methodology-gate.sh" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report "$1" "$got" "$2"
}
abs_path_case deny "absolute file_path resolves to the same survey path as the relative fixture" "__ROOT__/$SURVEY"
abs_path_case deny "./-prefixed file_path resolves to the same survey path as the relative fixture" "./$SURVEY"

# Bash-tool coverage: writing to the survey path via a shell redirect denies
# (fail-closed, cannot verify JTBD facet); an unrelated Bash command allows.
bash_write_case() {
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"; mkdir -p "$td/$(dirname "$SURVEY")"
  printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"cwd":"%s"}' "$3" "$td" \
    | env CLAUDE_PLUGIN_ROOT_CORE="$CLAUDE_PLUGIN_ROOT_CORE" CLAUDE_PROJECT_DIR="$td" /bin/bash "$HOOKS/methodology-gate.sh" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report "$1" "$got" "$2"
}
bash_write_case deny "Bash command redirecting to the survey path denies (cannot verify JTBD facet)" "echo 'no tuple' > docs/issue-7/reports/product-discovery/current-state.md"
bash_write_case allow "Bash command unrelated to the survey path allows" "git status"

# Semantic-upgrade regression pair: incidental substring mentions outside
# any JTBD-labeled section must now DENY (old bare-substring check would
# have false-positive ALLOWed); a cleanly labeled survey must still ALLOW.
INCIDENTAL_MENTIONS='## Notes

For context, see docs/handbooks/circumstance-notes.md. The desired outcome
of that meeting was to align on scope. Ask the performer of the demo for
details.'

run_write deny incidental-substring-mentions-must-now-deny "$SURVEY" "$INCIDENTAL_MENTIONS"

WELL_FORMED_LABELED='## Current state

Performer: a support agent.
Circumstance: during peak-hour ticket floods.
Desired outcome: tickets routed to the right owner within a minute.

No solution named yet.'

run_write allow well-formed-labeled-survey-allows "$SURVEY" "$WELL_FORMED_LABELED"

# missing-core: CLAUDE_PLUGIN_ROOT_CORE points nowhere -> guarded source
# must deny (exit 2), not silently allow (issue-75 fix).
missing_core_test() {
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"; mkdir -p "$td/$(dirname "$SURVEY")"
  printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":%s},"cwd":"%s"}' \
    "$SURVEY" "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$JTBD")" "$td" \
    | env CLAUDE_PLUGIN_ROOT_CORE="$td/no-such-core" CLAUDE_PROJECT_DIR="$td" /bin/bash "$HOOKS/methodology-gate.sh" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report deny "$got" missing-core-denies
}
missing_core_test

printf '\n== %d passed, %d failed ==\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
