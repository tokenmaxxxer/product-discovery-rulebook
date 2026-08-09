#!/usr/bin/env bash
# product-assumption-mapping gate, exercised as a real subprocess.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOOKS="$HERE/../product-assumption-mapping/hooks"

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

TARGET=docs/issue-77/proposals/2026-07-28-product-discovery.md
CURRENT_STATE=docs/issue-77/reports/product-discovery/current-state.md

LAST_STDERR=""
run_payload() {
  # $1=want $2=name $3=payload-json $4=cwd-dir $5..=extra env assignments (VAR=VAL)
  want="$1"; name="$2"; payload="$3"; cwd_dir="$4"; shift 4
  LAST_STDERR="$(printf '%s' "$payload" | env CLAUDE_PROJECT_DIR="$cwd_dir" CLAUDE_PLUGIN_ROOT_CORE="$CLAUDE_PLUGIN_ROOT_CORE" "$@" /bin/bash "$HOOKS/methodology-gate.sh" 2>&1 1>/dev/null)"
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  report "$want" "$got" "$name"
}

# Assert the last run_payload call's captured stderr is non-empty and names
# the unmet element (forced-refusal fixtures only).
check_stderr_nonempty() {
  name="$1"
  if [ -n "$LAST_STDERR" ]; then
    pass=$((pass+1)); printf 'ok     %-34s stderr-non-empty\n' "$name"
  else
    fail=$((fail+1)); printf 'FAIL   %-34s want=non-empty-stderr got=empty\n' "$name"
  fi
}

# run want name content [skip_current_state]
run() {
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"
  mkdir -p "$td/$(dirname "$TARGET")"
  if [ "${4:-}" != "skip" ]; then
    mkdir -p "$td/$(dirname "$CURRENT_STATE")"
    echo "survey" > "$td/$CURRENT_STATE"
  fi
  payload="$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":%s},"cwd":"%s"}' \
    "$TARGET" "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$3")" "$td")"
  run_payload "$1" "$2" "$payload" "$td"
  rm -rf "$td"
}

ZERO_CITATION='# Proposal
No citations here at all, just prose about the idea.'
run allow citation-zero-pass "$ZERO_CITATION"

BAD_CITATION='# Proposal
- Evidence: 3 interviews said users like it.'
run deny citation-missing-date "$BAD_CITATION"
check_stderr_nonempty citation-missing-date-stderr

GOOD_CITATION='# Proposal
- Evidence: 3 interviews, approx 2026-06, paraphrase: users struggle with onboarding.'
run allow citation-good-pass "$GOOD_CITATION"

RICE_GOOD='# Proposal
- candidate A
- candidate B
RICE: Reach 100, Impact 3, Confidence 80, Effort 2 for A.
RICE: Reach 50, Impact 2, Confidence 70, Effort 1 for B.'
run allow rice-required-pass "$RICE_GOOD"

RICE_MISSING='# Proposal
- candidate A
- candidate B
No scoring here.'
run deny rice-required-deny "$RICE_MISSING"
check_stderr_nonempty rice-required-deny-stderr

ICE_FLAGGED='# Proposal
- candidate A
- candidate B
Reach data unavailable, so ICE score used: Impact 3, Confidence 80, Effort 2 for A.
ICE: Impact 2, Confidence 70, Effort 1 for B, reach unavailable.'
run allow ice-flagged-pass "$ICE_FLAGGED"

ICE_UNFLAGGED='# Proposal
- candidate A
- candidate B
ICE: Impact 3, Confidence 80, Effort 2 for A.
ICE: Impact 2, Confidence 70, Effort 1 for B.'
run deny ice-unflagged-deny "$ICE_UNFLAGGED"

# order constraint: current-state.md absent
run deny order-constraint-deny "$ZERO_CITATION" skip
check_stderr_nonempty order-constraint-deny-stderr
run allow order-constraint-pass "$ZERO_CITATION"

# --- semantic-upgrade regression pair: citation anchoring -------------------
# A bare narrative sentence mentioning "interview" + a number with no
# bullet/heading anchor and no date/paraphrase: unanchored logic would
# recognize it as a citation line and DENY (missing date); anchored logic
# excludes it from citation recognition entirely, and since no other facet
# fires, the verdict is ALLOW.
FALSE_POSITIVE_NARRATIVE='# Proposal
We spoke with the team during interview 5 about roadmap plans in passing.'
run allow citation-anchor-excludes-unanchored-line "$FALSE_POSITIVE_NARRATIVE"

# Well-formed bulleted evidence citation under an "## Evidence" heading -> ALLOW
WELL_FORMED_UNDER_HEADING='## Evidence
- interview 5, 2026-06-01, paraphrase: users abandon onboarding at step 3.'
run allow citation-anchor-allows-heading-bullet "$WELL_FORMED_UNDER_HEADING"

# Same anchor, but missing date -> DENY (still enforced once anchored)
BAD_UNDER_HEADING='## Evidence
- interview 5, users abandon onboarding at step 3, no date given here.'
run deny citation-anchor-denies-heading-bullet-missing-date "$BAD_UNDER_HEADING"

# --- malformed stdin: truncated, non-object top-level, empty payload -------
td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"
run_payload deny malformed-json-truncated-deny '{"tool_name":"Write","tool_in' "$td"
check_stderr_nonempty malformed-json-truncated-stderr
rm -rf "$td"

td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"
run_payload deny malformed-json-nonobject-deny '["not", "an", "object"]' "$td"
check_stderr_nonempty malformed-json-nonobject-stderr
rm -rf "$td"

td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"
run_payload deny malformed-json-empty-deny '' "$td"
check_stderr_nonempty malformed-json-empty-stderr
rm -rf "$td"

# unrelated path pass-through
td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"
run_payload allow unrelated-path-pass "$(printf '{"tool_name":"Write","tool_input":{"file_path":"src/app.py","content":"x"},"cwd":"%s"}' "$td")" "$td"
rm -rf "$td"

# kill switch: recognized on-value disables
td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"
mkdir -p "$td/$(dirname "$TARGET")"
payload="$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":%s},"cwd":"%s"}' \
  "$TARGET" "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$RICE_MISSING")" "$td")"
run_payload allow kill-switch-on-value-pass "$payload" "$td" PRODUCT_ASSUMPTION_MAPPING_GATE_OFF=1
rm -rf "$td"

# kill switch: unrecognized garbage value -> gate stays ACTIVE (this content
# would deny: 2 candidates with no RICE/ICE score)
td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"
mkdir -p "$td/$(dirname "$TARGET")" "$td/$(dirname "$CURRENT_STATE")"
echo "survey" > "$td/$CURRENT_STATE"
payload="$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":%s},"cwd":"%s"}' \
  "$TARGET" "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$RICE_MISSING")" "$td")"
run_payload deny kill-switch-garbage-value-stays-active "$payload" "$td" PRODUCT_ASSUMPTION_MAPPING_GATE_OFF=banana
rm -rf "$td"

# Edit reconstruction failure (old_string not present in current file)
td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"
mkdir -p "$td/$(dirname "$TARGET")" "$td/$(dirname "$CURRENT_STATE")"
echo "survey" > "$td/$CURRENT_STATE"
echo "existing content" > "$td/$TARGET"
payload="$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s","old_string":"does-not-exist","new_string":"x"},"cwd":"%s"}' "$TARGET" "$td")"
run_payload deny edit-recon-failure-deny "$payload" "$td"
rm -rf "$td"

# Edit with replace_all: true against a multiply-occurring old_string
td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"
mkdir -p "$td/$(dirname "$TARGET")" "$td/$(dirname "$CURRENT_STATE")"
echo "survey" > "$td/$CURRENT_STATE"
cat > "$td/$TARGET" <<'EOF'
# Proposal
XX
- candidate A
- candidate B
XX
EOF
NEWBLOCK='RICE: Reach 100, Impact 3, Confidence 80, Effort 2 for A/B.'
payload="$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s","old_string":"XX","new_string":%s,"replace_all":true},"cwd":"%s"}' \
  "$TARGET" "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$NEWBLOCK")" "$td")"
run_payload allow edit-replace-all-true-pass "$payload" "$td"
rm -rf "$td"

# MultiEdit with mixed replace_all true/false in one call
td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"
mkdir -p "$td/$(dirname "$TARGET")" "$td/$(dirname "$CURRENT_STATE")"
echo "survey" > "$td/$CURRENT_STATE"
cat > "$td/$TARGET" <<'EOF'
# Proposal
PLACEHOLDER
- candidate A
- candidate B
PLACEHOLDER
TAILMARK
EOF
payload="$(python3 -c '
import json, sys
target_rel, cwd_dir = sys.argv[1], sys.argv[2]
edits = [
    {"old_string": "PLACEHOLDER", "new_string": "RICE: Reach 10, Impact 1, Confidence 50, Effort 1 for X.", "replace_all": True},
    {"old_string": "TAILMARK", "new_string": "RICE: Reach 20, Impact 2, Confidence 60, Effort 2 for Y.", "replace_all": False},
]
print(json.dumps({"tool_name": "MultiEdit", "tool_input": {"file_path": target_rel, "edits": edits}, "cwd": cwd_dir}))
' "$TARGET" "$td")"
run_payload allow multiedit-mixed-replace-all-pass "$payload" "$td"
rm -rf "$td"

# Absolute file_path matching proposal scope
td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"
mkdir -p "$td/$(dirname "$TARGET")" "$td/$(dirname "$CURRENT_STATE")"
echo "survey" > "$td/$CURRENT_STATE"
payload="$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/%s","content":%s},"cwd":"%s"}' \
  "$td" "$TARGET" "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$ZERO_CITATION")" "$td")"
run_payload allow absolute-path-pass "$payload" "$td"
rm -rf "$td"

# ./-prefixed file_path variant
td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"
mkdir -p "$td/$(dirname "$TARGET")" "$td/$(dirname "$CURRENT_STATE")"
echo "survey" > "$td/$CURRENT_STATE"
payload="$(printf '{"tool_name":"Write","tool_input":{"file_path":"./%s","content":%s},"cwd":"%s"}' \
  "$TARGET" "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$ZERO_CITATION")" "$td")"
run_payload allow dot-prefixed-path-pass "$payload" "$td"
rm -rf "$td"

# Bash tool writing to proposal path -> DENY (new Bash-write coverage)
td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"
mkdir -p "$td/$(dirname "$TARGET")" "$td/$(dirname "$CURRENT_STATE")"
echo "survey" > "$td/$CURRENT_STATE"
payload="$(printf '{"tool_name":"Bash","tool_input":{"command":"echo hi > %s"},"cwd":"%s"}' "$TARGET" "$td")"
run_payload deny bash-write-proposal-path-deny "$payload" "$td"
rm -rf "$td"

# Bash tool, unrelated command -> ALLOW
td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"
payload="$(printf '{"tool_name":"Bash","tool_input":{"command":"git status"},"cwd":"%s"}' "$td")"
run_payload allow bash-unrelated-command-pass "$payload" "$td"
rm -rf "$td"

# missing-core: CLAUDE_PLUGIN_ROOT_CORE points nowhere -> guarded source
# must deny (exit 2), not silently allow (issue-75 fix).
td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"
mkdir -p "$td/$(dirname "$TARGET")" "$td/$(dirname "$CURRENT_STATE")"
echo "survey" > "$td/$CURRENT_STATE"
payload="$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":%s},"cwd":"%s"}' \
  "$TARGET" "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$ZERO_CITATION")" "$td")"
run_payload deny missing-core-denies "$payload" "$td" CLAUDE_PLUGIN_ROOT_CORE="$td/no-such-core"
rm -rf "$td"

printf '\n== %d passed, %d failed ==\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
