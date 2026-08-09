#!/usr/bin/env bash
# Gate tests for product-guardrail-metrics: guardrail non-emptiness at
# registration (proposal path) and guardrail status tracking at measurement
# time (record path). Migrated to exercise the gate-house-standard
# (core issue #72) gate script, which sources core/hooks/lib/gate-lib.sh via
# CLAUDE_PLUGIN_ROOT_CORE.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOOKS="$HERE/../product-guardrail-metrics/hooks"

# The gate sources gate-lib.sh via CLAUDE_PLUGIN_ROOT_CORE; resolve it the
# same way the real runtime does so subprocess runs below can find
# gate-lib.sh/gate-lib.py (precedent: accessibility-rulebook's
# run-methodology-gate-tests.sh).
# Resolution order and SKIP contract per docs/specs/test-env-resolution.md
# (on-the-record issue #551).
if [ -z "${CLAUDE_PLUGIN_ROOT_CORE:-}" ]; then
  for cand in "$HERE/../core" \
              "$HOME/tokenmaxxxer/tokenmaxxxer-core/core" \
              "$HOME/.claude/plugins/marketplaces/tokenmaxxxer/runs/rulebooks/tokenmaxxxer-core/core"; do
    if [ -s "$cand/hooks/lib/gate-lib.sh" ]; then export CLAUDE_PLUGIN_ROOT_CORE="$cand"; break; fi
  done
fi
if [ -z "${CLAUDE_PLUGIN_ROOT_CORE:-}" ] || [ ! -s "$CLAUDE_PLUGIN_ROOT_CORE/hooks/lib/gate-lib.sh" ]; then
  echo "SKIP: core plugin unreachable — unverifiable outside spawn env" >&2
  exit 75
fi

pass=0; fail=0
report() { if [ "$2" = "$1" ]; then pass=$((pass+1)); printf 'ok     %-34s %s\n' "$3" "$2"; else fail=$((fail+1)); printf 'FAIL   %-34s want=%s got=%s\n' "$3" "$1" "$2"; fi; }

PROPOSAL=docs/issue-7/proposals/2026-07-28-product-discovery.md
RECORD=docs/issue-7/reports/product-discovery.md

run() { # want name gate file content [with_current_state]
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"
  mkdir -p "$td/$(dirname "$4")"
  if [ "${6:-1}" = "1" ]; then
    mkdir -p "$td/docs/issue-7/reports/product-discovery"
    echo "current state" > "$td/docs/issue-7/reports/product-discovery/current-state.md"
  fi
  printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":%s},"cwd":"%s"}' \
    "$4" "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$5")" "$td" \
    | env CLAUDE_PROJECT_DIR="$td" CLAUDE_PLUGIN_ROOT_CORE="$CLAUDE_PLUGIN_ROOT_CORE" /bin/bash "$HOOKS/$3" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report "$1" "$got" "$2"
}

run_raw() { # want name payload [env...]
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"
  mkdir -p "$td/docs/issue-7/proposals" "$td/docs/issue-7/reports/product-discovery"
  echo "current state" > "$td/docs/issue-7/reports/product-discovery/current-state.md"
  printf '%s' "$3" | env CLAUDE_PROJECT_DIR="$td" CLAUDE_PLUGIN_ROOT_CORE="$CLAUDE_PLUGIN_ROOT_CORE" "${4:-}" /bin/bash "$HOOKS/methodology-gate.sh" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report "$1" "$got" "$2"
}

# --- proposal path -----------------------------------------------------
run deny order-constraint-missing methodology-gate.sh "$PROPOSAL" 'Guardrail: signup-error-rate must stay under 2%.' 0
run allow order-constraint-present methodology-gate.sh "$PROPOSAL" 'Guardrail: signup-error-rate must stay under 2%.' 1
run allow guardrail-present methodology-gate.sh "$PROPOSAL" 'Guardrail metric: p95 latency must stay under 200ms.' 1
run deny  guardrail-absent methodology-gate.sh "$PROPOSAL" 'We believe X; we will know when conversion crosses 5%.' 1
run deny  guardrail-none-suffixed methodology-gate.sh "$PROPOSAL" 'Guardrail metrics: none.' 1
run deny  guardrail-tbd-suffixed methodology-gate.sh "$PROPOSAL" 'Guardrail: TBD' 1

# --- record path ---------------------------------------------------------
run allow status-word-present methodology-gate.sh "$RECORD" 'Measured value 6% vs threshold 5%.

Guardrail: signup-error-rate held at 1.2%, not breached.' 1
run deny  status-missing methodology-gate.sh "$RECORD" 'Measured value 6% vs threshold 5%.

Guardrail: signup-error-rate.' 1
run deny  status-guardrail-absent methodology-gate.sh "$RECORD" 'Measured value 6% vs threshold 5%. Kill per rule.' 1

# --- semantic-upgrade regression pair: guardrail-anchoring ---------------
run deny  guardrail-unanchored-mention methodology-gate.sh "$PROPOSAL" 'Our guardrail thinking evolved over several meetings and remains an open question.' 1
run allow guardrail-labeled-real methodology-gate.sh "$PROPOSAL" 'Some context about the feature.

**Guardrails:**
signup-error-rate must stay under 2%; p95 latency must stay under 200ms.' 1

# --- shared mechanics ------------------------------------------------------
malformed() {
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"
  printf 'not json' | env CLAUDE_PROJECT_DIR="$td" CLAUDE_PLUGIN_ROOT_CORE="$CLAUDE_PLUGIN_ROOT_CORE" /bin/bash "$HOOKS/methodology-gate.sh" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report deny "$got" malformed-stdin-notjson
}
malformed

truncated_json() {
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"
  printf '{"tool_name":"Write","tool_input":{"file_path":"x.md","content":"y"' \
    | env CLAUDE_PROJECT_DIR="$td" CLAUDE_PLUGIN_ROOT_CORE="$CLAUDE_PLUGIN_ROOT_CORE" /bin/bash "$HOOKS/methodology-gate.sh" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report deny "$got" malformed-stdin-truncated
}
truncated_json

nonobject_json() {
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"
  printf '["not","an","object"]' \
    | env CLAUDE_PROJECT_DIR="$td" CLAUDE_PLUGIN_ROOT_CORE="$CLAUDE_PLUGIN_ROOT_CORE" /bin/bash "$HOOKS/methodology-gate.sh" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report deny "$got" malformed-stdin-nonobject
}
nonobject_json

empty_payload() {
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"
  printf '' \
    | env CLAUDE_PROJECT_DIR="$td" CLAUDE_PLUGIN_ROOT_CORE="$CLAUDE_PLUGIN_ROOT_CORE" /bin/bash "$HOOKS/methodology-gate.sh" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report deny "$got" malformed-stdin-empty
}
empty_payload

run allow unrelated-path methodology-gate.sh "docs/issue-7/reports/verify.md" "x" 1

killswitch() {
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"; mkdir -p "$td/docs/issue-7/proposals"
  printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":"no guardrail here"},"cwd":"%s"}' \
    "$PROPOSAL" "$td" \
    | env CLAUDE_PROJECT_DIR="$td" CLAUDE_PLUGIN_ROOT_CORE="$CLAUDE_PLUGIN_ROOT_CORE" PRODUCT_GUARDRAIL_METRICS_GATE_OFF=1 /bin/bash "$HOOKS/methodology-gate.sh" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report allow "$got" kill-switch-on
}
killswitch

killswitch_unrecognized() {
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"; mkdir -p "$td/docs/issue-7/proposals"
  printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":"no guardrail here"},"cwd":"%s"}' \
    "$PROPOSAL" "$td" \
    | env CLAUDE_PROJECT_DIR="$td" CLAUDE_PLUGIN_ROOT_CORE="$CLAUDE_PLUGIN_ROOT_CORE" PRODUCT_GUARDRAIL_METRICS_GATE_OFF=banana /bin/bash "$HOOKS/methodology-gate.sh" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report deny "$got" kill-switch-unrecognized-stays-active
}
killswitch_unrecognized

editfail() {
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"
  mkdir -p "$td/docs/issue-7/proposals" "$td/docs/issue-7/reports/product-discovery"
  echo "current state" > "$td/docs/issue-7/reports/product-discovery/current-state.md"
  echo "existing content" > "$td/$PROPOSAL"
  printf '{"tool_name":"Edit","tool_input":{"file_path":"%s","old_string":"nonexistent-text","new_string":"Guardrail: x"},"cwd":"%s"}' \
    "$PROPOSAL" "$td" \
    | env CLAUDE_PROJECT_DIR="$td" CLAUDE_PLUGIN_ROOT_CORE="$CLAUDE_PLUGIN_ROOT_CORE" /bin/bash "$HOOKS/methodology-gate.sh" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report deny "$got" edit-reconstruction-fail
}
editfail

edit_replace_all() {
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"
  mkdir -p "$td/docs/issue-7/reports/product-discovery"
  printf 'Guardrail: TBD\n\nGuardrail: TBD\n' > "$td/$RECORD"
  printf '{"tool_name":"Edit","tool_input":{"file_path":"%s","old_string":"Guardrail: TBD","new_string":"Guardrail: signup-error-rate held at 1.2%%, not breached.","replace_all":true},"cwd":"%s"}' \
    "$RECORD" "$td" \
    | env CLAUDE_PROJECT_DIR="$td" CLAUDE_PLUGIN_ROOT_CORE="$CLAUDE_PLUGIN_ROOT_CORE" /bin/bash "$HOOKS/methodology-gate.sh" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report allow "$got" edit-replace-all-multi-occurrence
}
edit_replace_all

multiedit_mixed() {
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"
  mkdir -p "$td/docs/issue-7/reports/product-discovery"
  printf 'Measured value 6%% vs threshold 5%%.\n\nGuardrail: PLACEHOLDER\n\nGuardrail: PLACEHOLDER\n' > "$td/$RECORD"
  edits='[{"old_string":"Guardrail: PLACEHOLDER","new_string":"Guardrail: signup-error-rate held at 1.2%, not breached.","replace_all":false},{"old_string":"Guardrail: PLACEHOLDER","new_string":"Guardrail: latency held, not breached.","replace_all":false}]'
  printf '{"tool_name":"MultiEdit","tool_input":{"file_path":"%s","edits":%s},"cwd":"%s"}' \
    "$RECORD" "$edits" "$td" \
    | env CLAUDE_PROJECT_DIR="$td" CLAUDE_PLUGIN_ROOT_CORE="$CLAUDE_PLUGIN_ROOT_CORE" /bin/bash "$HOOKS/methodology-gate.sh" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report allow "$got" multiedit-mixed-replace-all
}
multiedit_mixed

abs_path_test() {
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"
  mkdir -p "$td/docs/issue-7/reports/product-discovery"
  printf '{"tool_name":"Write","tool_input":{"file_path":"%s/%s","content":"Measured value 6%% vs threshold 5%%.\\n\\nGuardrail: signup-error-rate held at 1.2%%, not breached."},"cwd":"%s"}' \
    "$td" "$RECORD" "$td" \
    | env CLAUDE_PROJECT_DIR="$td" CLAUDE_PLUGIN_ROOT_CORE="$CLAUDE_PLUGIN_ROOT_CORE" /bin/bash "$HOOKS/methodology-gate.sh" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report allow "$got" absolute-file-path
}
abs_path_test

dotslash_path_test() {
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"
  mkdir -p "$td/docs/issue-7/reports/product-discovery"
  printf '{"tool_name":"Write","tool_input":{"file_path":"./%s","content":"Measured value 6%% vs threshold 5%%.\\n\\nGuardrail: signup-error-rate held at 1.2%%, not breached."},"cwd":"%s"}' \
    "$RECORD" "$td" \
    | env CLAUDE_PROJECT_DIR="$td" CLAUDE_PLUGIN_ROOT_CORE="$CLAUDE_PLUGIN_ROOT_CORE" /bin/bash "$HOOKS/methodology-gate.sh" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report allow "$got" dotslash-file-path
}
dotslash_path_test

bash_write_deny() {
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"
  mkdir -p "$td/docs/issue-7/reports"
  printf '{"tool_name":"Bash","tool_input":{"command":"echo hi >> docs/issue-7/reports/product-discovery.md"},"cwd":"%s"}' \
    "$td" \
    | env CLAUDE_PROJECT_DIR="$td" CLAUDE_PLUGIN_ROOT_CORE="$CLAUDE_PLUGIN_ROOT_CORE" /bin/bash "$HOOKS/methodology-gate.sh" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report deny "$got" bash-write-to-record-path
}
bash_write_deny

bash_unrelated_allow() {
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"
  printf '{"tool_name":"Bash","tool_input":{"command":"ls -la docs/"},"cwd":"%s"}' \
    "$td" \
    | env CLAUDE_PROJECT_DIR="$td" CLAUDE_PLUGIN_ROOT_CORE="$CLAUDE_PLUGIN_ROOT_CORE" /bin/bash "$HOOKS/methodology-gate.sh" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report allow "$got" bash-unrelated-command
}
bash_unrelated_allow

missing_core() {
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"; mkdir -p "$td/docs/issue-7/proposals"
  printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":"Guardrail: signup-error-rate must stay under 2%%."},"cwd":"%s"}' \
    "$PROPOSAL" "$td" \
    | env CLAUDE_PROJECT_DIR="$td" CLAUDE_PLUGIN_ROOT_CORE="$td/no-such-core" /bin/bash "$HOOKS/methodology-gate.sh" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report deny "$got" missing-core-denies
}
missing_core

printf '\n== %d passed, %d failed ==\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
