#!/usr/bin/env bash
. "${CLAUDE_PLUGIN_ROOT_CORE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../core" && pwd -P)}/hooks/lib/gate-lib.sh" || { echo "product-one-pager: cannot source gate-lib.sh" >&2; exit 2; }
gate_trap_fail_closed
# product-one-pager methodology gate: fires only on the current-state
# survey write (docs/issue-<n>/reports/product-discovery/current-state.md)
# and checks the JTBD problem-without-solution facet — see
# docs/issue-42/proposals/2026-07-31-methodology-gate-machine.md section 1.
#
# Migrated to the gate-house standard (core issue #72) per issue #45's gate
# A+ remediation: adopts gate-lib.sh/gate-lib.py by reference for the
# fail-closed trap, kill switch, JSON parse, path normalization, and
# Write/Edit/MultiEdit/NotebookEdit reconstruction, rather than hand-rolling
# each. Also fixes a dead ternary in the case-fold of solution markers, and
# upgrades the JTBD-tuple semantic check from bare substring-anywhere-in-
# document matching to a section/adjacency/structure-aware check (issue #45
# requirement #2) so an incidental mention like
# "docs/handbooks/circumstance-notes.md" outside any JTBD-labeled section no
# longer false-positives an ALLOW.
#
# Kill switch: export PRODUCT_ONE_PAGER_GATE_OFF=1 (any other value leaves
# it active, per gate_kill_switch_active's fixed on-spelling set —
# 1/true/yes/on).
set -uo pipefail
gate_kill_switch_active "${PRODUCT_ONE_PAGER_GATE_OFF:-}" || { trap - EXIT; exit 0; }

deny() {
  printf '{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":%s}}\n' \
    "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1" 2>/dev/null || echo '"product-one-pager: refused"')"
  printf '%s\n' "$1" >&2
  exit 2
}

command -v python3 >/dev/null 2>&1 || deny "product-one-pager: refused — python3 unavailable ; required by product-one-pager/hooks/methodology-gate.sh — see docs/handbooks/tests.md"

payload="$(cat 2>/dev/null || true)"
[ -n "$payload" ] || deny "product-one-pager: refused — empty tool-use payload; cannot evaluate the gate on nothing ; required by product-one-pager/hooks/methodology-gate.sh — see docs/handbooks/tests.md"

get_field() {
  printf '%s' "$payload" | python3 -c "
import json, sys
try:
    obj = json.loads(sys.stdin.read())
except Exception:
    print('')
    sys.exit(0)
if not isinstance(obj, dict):
    print('')
    sys.exit(0)
val = obj
for key in sys.argv[1:]:
    if isinstance(val, dict) and key in val:
        val = val[key]
    else:
        print('')
        sys.exit(0)
if isinstance(val, (dict, list)):
    print(json.dumps(val))
elif val is None:
    print('')
else:
    print(val)
" "$@"
}

printf '%s' "$payload" | python3 -c '
import json, sys
try:
    obj = json.loads(sys.stdin.read())
except Exception:
    sys.exit(1)
sys.exit(0 if isinstance(obj, dict) else 1)
' || deny "product-one-pager: refused — the tool-call payload is not a valid JSON object; failing closed ; required by product-one-pager/hooks/methodology-gate.sh — see docs/handbooks/tests.md"

tool_name="$(get_field tool_name)"
file_path="$(get_field tool_input file_path)"
notebook_path="$(get_field tool_input notebook_path)"
command_str="$(get_field tool_input command)"
cwd="$(get_field cwd)"

# Bash-tool write coverage: cannot reconstruct content for a shell-redirected
# write, so fail closed if any path-shaped token in the command looks like
# the survey path.
if [ "$tool_name" = "Bash" ] && [ -n "$command_str" ]; then
  while IFS= read -r tok; do
    [ -n "$tok" ] || continue
    if printf '%s' "$tok" | grep -qE '(^|/)docs/issue-[0-9]+/reports/product-discovery/current-state\.md$'; then
      deny "product-one-pager: refused — a Bash command may write to the current-state survey; this gate cannot verify the JTBD facet on a shell-redirected write — use Write/Edit/MultiEdit instead ; required by product-one-pager/hooks/methodology-gate.sh — see docs/handbooks/tests.md"
    fi
  done <<EOF
$(gate_bash_write_targets "$command_str")
EOF
fi

target_path="$file_path"
is_notebook=0
if [ -z "$target_path" ] && [ -n "$notebook_path" ]; then
  target_path="$notebook_path"
  is_notebook=1
fi
[ "$tool_name" = "NotebookEdit" ] && [ -n "$notebook_path" ] && { target_path="$notebook_path"; is_notebook=1; }

[ -n "$target_path" ] || exit 0

resolve_root() {
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "${CLAUDE_PROJECT_DIR:-}" ]; then
    case "$CLAUDE_PROJECT_DIR" in
      /*) printf '%s' "$CLAUDE_PROJECT_DIR"; return 0 ;;
    esac
  fi
  if [ -n "$cwd" ] && [ -d "$cwd" ]; then
    local top
    top="$(cd "$cwd" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)"
    if [ -n "$top" ]; then
      printf '%s' "$top"
      return 0
    fi
    printf '%s' "$cwd"
    return 0
  fi
  pwd -P
}

root="$(resolve_root)"

POP_PAYLOAD="$payload" POP_ROOT="$root" POP_IS_NOTEBOOK="$is_notebook" GATE_LIB_PY="$GATE_LIB_PY" python3 <<'PY'
import sys as _fc_sys
try:
    import importlib.util, json, os, re, sys

    def deny(m):
        payload = "product-one-pager: refused — " + m
        sys.stderr.write(payload + "\n")
        sys.stdout.write(
            '{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":%s}}\n'
            % json.dumps(payload)
        )
        sys.exit(2)

    _spec = importlib.util.spec_from_file_location("gate_lib", os.environ["GATE_LIB_PY"])
    gate_lib = importlib.util.module_from_spec(_spec)
    _spec.loader.exec_module(gate_lib)

    raw = os.environ.get("POP_PAYLOAD", "")
    ev = gate_lib.gate_parse_json_or_deny(raw, deny)

    tool = ev.get("tool_name")
    if tool not in ("Write", "Edit", "MultiEdit", "NotebookEdit"):
        sys.exit(0)

    ti = ev.get("tool_input")
    if not isinstance(ti, dict):
        deny("tool_input is missing or not a JSON object; the gate cannot judge a write it cannot parse.")

    root = os.path.realpath(os.environ["POP_ROOT"]).replace("\\", "/")
    SURVEY_RE = re.compile(r'(^|.*/)docs/issue-[0-9]+/reports/product-discovery/current-state\.md$')

    is_notebook = os.environ.get("POP_IS_NOTEBOOK") == "1"
    path = ti.get("notebook_path") if (tool == "NotebookEdit" or is_notebook) else ti.get("file_path")
    if not isinstance(path, str) or not path:
        sys.exit(0)

    rel = gate_lib.gate_normalize_path(root, path)
    if rel is None:
        sys.exit(0)  # resolves outside the project root — not this gate's business
    if not SURVEY_RE.match(rel):
        sys.exit(0)  # not this gate's own file — not this gate's business

    current = None
    if tool != "NotebookEdit":
        abs_path = root + "/" + rel if rel else root
        if os.path.isfile(abs_path):
            try:
                with open(abs_path, encoding="utf-8-sig") as fh:
                    current = fh.read(1 << 20)
            except OSError:
                deny("%s exists but cannot be read; failing closed." % rel)

    new_text, ok = gate_lib.gate_reconstruct_write(tool, ti, current)
    if not ok:
        deny(
            "this write targets %s but the gate cannot determine the resulting content "
            "from the tool input (tool=%r); cannot determine resulting content." % (rel, tool)
        )

    # --- facet check: JTBD 4-tuple (performer, circumstance, desired
    # outcome) must be stated before any solution name appears. Tier 1:
    # explicit label lines. Tier 2: section+adjacency (heading/bold-label
    # naming the JTBD facet, with marker word co-occurring in a paragraph of
    # that section). A bare substring match anywhere in the document no
    # longer counts (issue #45 requirement #2).
    text = new_text

    HEADING_RE = re.compile(r'^(#{1,6})\s+(.*)$')
    BOLD_LABEL_RE = re.compile(r'^\*\*([^*]+)\*\*\s*:?\s*$')

    def split_sections(t):
        lines = t.split('\n')
        sections = []
        cur_heading = ''
        cur_lines = []
        for line in lines:
            h = HEADING_RE.match(line)
            b = BOLD_LABEL_RE.match(line)
            if h or b:
                sections.append((cur_heading, '\n'.join(cur_lines)))
                cur_heading = (h.group(2) if h else b.group(1)).strip()
                cur_lines = []
            else:
                cur_lines.append(line)
        sections.append((cur_heading, '\n'.join(cur_lines)))
        return sections

    def paragraphs(body):
        return re.split(r'\n\s*\n', body)

    LABEL_RES = {
        "performer": re.compile(r'^\s*(job\s*performer|performer)\s*:\s*\S', re.IGNORECASE | re.MULTILINE),
        "circumstance": re.compile(r'^\s*circumstance\s*:\s*\S', re.IGNORECASE | re.MULTILINE),
        "outcome": re.compile(r'^\s*(desired\s*outcome|outcome)\s*:\s*\S', re.IGNORECASE | re.MULTILINE),
    }

    def structure_match(t, label_res):
        found = {}
        lines = t.split('\n')
        for idx, line in enumerate(lines):
            for key, pat in label_res.items():
                if key in found:
                    continue
                if pat.search(line):
                    found[key] = idx
        return found

    SECTION_NAME_RE = re.compile(r'(?i)circumstance|job\s*performer|desired\s*outcome|jtbd')
    MARKER_RES = {
        "performer": re.compile(r'(?i)job\s*performer|performer'),
        "circumstance": re.compile(r'(?i)circumstance'),
        "outcome": re.compile(r'(?i)desired\s*outcome|outcome'),
    }

    def section_adjacency_match(t, section_name_re, marker_res):
        found = {}
        pos = 0
        for heading, body in split_sections(t):
            body_start = t.find(body, pos) if body else pos
            if body_start == -1:
                body_start = pos
            if section_name_re.search(heading):
                offset = body_start
                for para in paragraphs(body):
                    para_pos = t.find(para, offset)
                    if para_pos == -1:
                        para_pos = offset
                    for key, pat in marker_res.items():
                        if key in found:
                            continue
                        if pat.search(para):
                            found[key] = para_pos
                    offset = para_pos + len(para)
            pos = body_start + len(body)
        return found

    line_starts = [0]
    for line in text.split('\n'):
        line_starts.append(line_starts[-1] + len(line) + 1)

    tier1 = structure_match(text, LABEL_RES)
    keys = {"performer", "circumstance", "outcome"}

    if keys.issubset(tier1.keys()):
        positions = {k: line_starts[tier1[k]] for k in keys}
        tuple_complete_pos = max(positions.values())
    else:
        tier2 = section_adjacency_match(text, SECTION_NAME_RE, MARKER_RES)
        merged = dict(tier1)
        for k, v in tier2.items():
            if k not in merged:
                merged[k] = v if isinstance(v, int) else v
        # positions from tier1 are line indices; from tier2 are char offsets.
        # Normalize: convert tier1 line indices to char offsets too.
        norm_positions = {}
        for k in keys:
            if k in tier1:
                norm_positions[k] = line_starts[tier1[k]]
            elif k in tier2:
                norm_positions[k] = tier2[k]

        missing = [k for k in ("performer", "circumstance", "outcome") if k not in norm_positions]
        if missing:
            label_map = {"performer": "job-performer", "circumstance": "circumstance", "outcome": "desired-outcome"}
            deny(
                "JTBD tuple element(s) missing: " + ",".join(label_map[m] for m in missing) +
                ". Per docs/issue-36/..., the problem must be stated as a JTBD 4-tuple "
                "(performer, job, circumstance, desired outcome) before any solution name appears."
            )
        tuple_complete_pos = max(norm_positions.values())

    solution_markers = [
        re.compile(r"^\s*solution\s*:", re.MULTILINE),
        re.compile(r"we will build"),
        re.compile(r"we are building"),
        re.compile(r"제안\s*:"),
        re.compile(r"우리는\s*[^\n]*?(만든다|만듭니다|구축한다|구축합니다)"),
    ]

    lowered = text.lower()
    earliest_solution_pos = None
    for pat in solution_markers:
        m = pat.search(lowered)
        if m:
            if earliest_solution_pos is None or m.start() < earliest_solution_pos:
                earliest_solution_pos = m.start()

    if earliest_solution_pos is not None and earliest_solution_pos < tuple_complete_pos:
        deny(
            "a solution name appears before the JTBD tuple is stated. Per docs/issue-36/..., "
            "the JTBD tuple (performer, job, circumstance, desired outcome) must be stated "
            "before any solution name appears."
        )

    sys.exit(0)
except SystemExit:
    raise
except Exception as _fc_e:
    import json as _fc_json
    payload = "product-one-pager: refused — fail-closed: internal error: %r" % (_fc_e,)
    _fc_sys.stdout.write(
        '{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":%s}}\n'
        % _fc_json.dumps(payload)
    )
    _fc_sys.exit(2)
PY
_fc_rc=$?
if [ "$_fc_rc" -ne 0 ] && [ "$_fc_rc" -ne 2 ]; then
  deny "product-one-pager: refused — fail-closed: internal error (judge exited $_fc_rc) ; required by product-one-pager/hooks/methodology-gate.sh — see docs/handbooks/tests.md"
fi
exit "$_fc_rc"
