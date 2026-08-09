#!/usr/bin/env bash
# Root dispatcher for this repo's real gate suites. Previously referenced
# ../product/hooks/record-fields-gate.sh and trailer-gate.sh, which do not
# exist anywhere in this tree (issue #45 survey §5) — this repo has no
# `product` plugin, only the 5 `product-*` plugins below, each owning its
# own methodology-gate.sh and its own tests/product-*-gate-tests.sh suite.
# This script's only job is to run all 5 as subprocesses, plus core's
# compliance-check.sh against every plugin's hooks/ directory (issue #45
# requirement: catch a future hand-rolled kill-switch/reconstruct drift
# back away from gate-lib.sh, not just fix it once).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd "$HERE/.." && pwd -P)"

# Resolve core's plugin root the same way the gates and their own test
# suites do, so compliance-check.sh below can be found. Resolution order
# and SKIP contract per docs/specs/test-env-resolution.md (on-the-record
# issue #551).
if [ -z "${CLAUDE_PLUGIN_ROOT_CORE:-}" ]; then
  for cand in "$HOME/tokenmaxxxer/tokenmaxxxer-core/core" \
              "$HOME/.claude/plugins/marketplaces/tokenmaxxxer/runs/rulebooks/tokenmaxxxer-core/core" \
              "$ROOT/../tokenmaxxxer-core/core"; do
    if [ -s "$cand/hooks/lib/gate-lib.sh" ]; then export CLAUDE_PLUGIN_ROOT_CORE="$cand"; break; fi
  done
fi
if [ -z "${CLAUDE_PLUGIN_ROOT_CORE:-}" ] || [ ! -s "$CLAUDE_PLUGIN_ROOT_CORE/hooks/lib/gate-lib.sh" ]; then
  echo "SKIP: core plugin unreachable — unverifiable outside spawn env" >&2
  exit 75
fi
export CLAUDE_PLUGIN_ROOT_CORE

plugin_fail=0
plugin_skip=0
suite_count=0

for suite in product-one-pager product-opportunity-solution-tree \
             product-assumption-mapping product-hypothesis-testing \
             product-guardrail-metrics; do
  echo; echo "-- $suite --"
  suite_count=$((suite_count+1))
  bash "$HERE/$suite-gate-tests.sh"
  suite_rc=$?
  if [ "$suite_rc" -eq 75 ]; then
    plugin_skip=$((plugin_skip+1))
  elif [ "$suite_rc" -ne 0 ]; then
    plugin_fail=1
  fi
done

echo; echo "-- compliance-check.sh (core issue #72) --"
compliance_fail=0
for plugin in product-one-pager product-opportunity-solution-tree \
              product-assumption-mapping product-hypothesis-testing \
              product-guardrail-metrics; do
  bash "$CLAUDE_PLUGIN_ROOT_CORE/hooks/tests/compliance-check.sh" "$ROOT/$plugin/hooks" || compliance_fail=1
done

if [ "$plugin_fail" -eq 0 ] && [ "$plugin_skip" -eq "$suite_count" ]; then
  echo "SKIP: core plugin unreachable — unverifiable outside spawn env" >&2
  exit 75
fi

overall_fail=0
[ "$plugin_fail" -eq 0 ] || overall_fail=1
[ "$compliance_fail" -eq 0 ] || overall_fail=1

echo
if [ "$overall_fail" -eq 0 ]; then
  echo "run-gate-tests: all 5 plugin suites + compliance-check.sh passed"
else
  echo "run-gate-tests: FAILURES present (plugin_fail=$plugin_fail compliance_fail=$compliance_fail)" >&2
fi
exit "$overall_fail"
