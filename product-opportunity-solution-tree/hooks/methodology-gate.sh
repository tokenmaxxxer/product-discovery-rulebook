#!/usr/bin/env bash
. "${CLAUDE_PLUGIN_ROOT_CORE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../core" && pwd -P)}/hooks/lib/gate-lib.sh" || { echo "product-opportunity-solution-tree: cannot source gate-lib.sh" >&2; exit 2; }
gate_trap_fail_closed
# PreToolUse gate (Write|Edit|MultiEdit|NotebookEdit|Bash) — the
# opportunity-solution-tree (OST) facet of the product-discovery
# methodology set, migrated to the gate-house standard (core issue #72)
# per docs/issue-45/... gate A+ remediation.
#
# This plugin fires on three of its own surfaces:
#   (a) survey  — docs/issue-<n>/reports/product-discovery/current-state.md
#                 must name the relevant OST branch in OST's own
#                 four-layer vocabulary (outcome / opportunity / candidate
#                 solutions / discriminating assumption test), via the
#                 section/adjacency/structure tiers below (not a bare
#                 substring-anywhere-in-document check).
#   (b) proposal — docs/issue-<n>/proposals/*product-discovery*.md must
#                 not be written before the current-state survey exists
#                 on disk. This is the only check this plugin runs on the
#                 proposal surface — no OST-vocabulary check applies
#                 there; that is this plugin's own facet only on (a)/(c).
#   (c) record  — docs/issue-<n>/reports/product-discovery.md must state
#                 a disposition (pruned/promoted/kill/go/pivot) plus a
#                 layer name, in that same vocabulary.
#
# Kill switch: export PRODUCT_OPPORTUNITY_SOLUTION_TREE_GATE_OFF=1
set -uo pipefail
gate_kill_switch_active "${PRODUCT_OPPORTUNITY_SOLUTION_TREE_GATE_OFF:-}" || { trap - EXIT; exit 0; }

role="${CLAUDE_ROLE:-product-opportunity-solution-tree}"
deny() {
  printf '%s\n' "$1" >&2
  printf '{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":%s}}\n' \
    "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1" 2>/dev/null || echo '"product-opportunity-solution-tree: refused"')"
  exit 2
}

command -v python3 >/dev/null 2>&1 || deny "product-opportunity-solution-tree: refused — methodology-gate.sh requires python3, which is not on PATH; denying rather than guessing. ; required by product-opportunity-solution-tree/hooks/methodology-gate.sh — see docs/handbooks/tests.md"

payload="$(cat 2>/dev/null || true)"
[ -n "$payload" ] || deny "product-opportunity-solution-tree: refused — empty tool-use payload on stdin; cannot evaluate the methodology gate. ; required by product-opportunity-solution-tree/hooks/methodology-gate.sh — see docs/handbooks/tests.md"

_target="$(printf '%s' "$payload" | python3 -c '
import json,sys
try: e=json.loads(sys.stdin.read())
except Exception: sys.exit(0)
ti=e.get("tool_input") if isinstance(e,dict) else None
if isinstance(ti,dict):
    for k in ("file_path","notebook_path"):
        v=ti.get(k)
        if isinstance(v,str) and v: print(v); break
' 2>/dev/null || true)"

_tool_name="$(printf '%s' "$payload" | python3 -c '
import json,sys
try: e=json.loads(sys.stdin.read())
except Exception: sys.exit(0)
if isinstance(e,dict):
    v=e.get("tool_name")
    if isinstance(v,str): print(v)
' 2>/dev/null || true)"

_command="$(printf '%s' "$payload" | python3 -c '
import json,sys
try: e=json.loads(sys.stdin.read())
except Exception: sys.exit(0)
ti=e.get("tool_input") if isinstance(e,dict) else None
if isinstance(ti,dict):
    v=ti.get("command")
    if isinstance(v,str): print(v)
' 2>/dev/null || true)"

_plausible() { [ -n "$1" ] && [ -d "$1" ] && { [ -e "$1/.git" ] || [ -f "$1/docs/specs/role-handoff-contract.md" ]; }; }
_under() {
  [ -z "$2" ] && return 0
  python3 -c '
import os,posixpath,sys
r,t=sys.argv[1],sys.argv[2]
try: rr=posixpath.normpath(os.path.realpath(r).replace("\\","/"))
except Exception: sys.exit(1)
n=t.replace("\\","/"); a=n if posixpath.isabs(n) else posixpath.join(rr,n)
a=posixpath.normpath(a); real=posixpath.normpath(os.path.realpath(a).replace("\\","/"))
sys.exit(0 if (real==rr or real.startswith(rr+"/")) else 1)
' "$1" "$2"
}

root=""
if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && _plausible "$CLAUDE_PROJECT_DIR" && _under "$CLAUDE_PROJECT_DIR" "$_target"; then
  root="$(cd "$CLAUDE_PROJECT_DIR" 2>/dev/null && pwd -P)"
fi
if [ -z "$root" ]; then
  d="$_target"; [ -n "$d" ] || d="$(pwd -P)"; [ -d "$d" ] || d="$(dirname "$d")"
  root="$(git -C "$d" rev-parse --show-toplevel 2>/dev/null || true)"
fi
[ -z "$root" ] && root="$(git -C "$(pwd -P)" rev-parse --show-toplevel 2>/dev/null || true)"
[ -z "$root" ] && deny "product-opportunity-solution-tree: refused — no project root could be determined; failing closed (methodology check cannot run). ; required by product-opportunity-solution-tree/hooks/methodology-gate.sh — see docs/handbooks/tests.md"

# Bash-tool coverage: scan tool_input.command for path-shaped tokens that
# hit the survey/proposal/record patterns before invoking the python
# payload (gate_bash_write_targets, from gate-lib.sh). A shell-redirected
# write cannot be reconstructed by this gate, so any hit fails closed.
if [ "$_tool_name" = "Bash" ] && [ -n "$_command" ]; then
  while IFS= read -r tok; do
    [ -n "$tok" ] || continue
    case "$tok" in
      *reports/product-discovery/current-state.md|*reports/product-discovery.md|*proposals/*product-discovery*.md)
        deny "product-opportunity-solution-tree: refused — a Bash command may write to $tok; this gate cannot verify the OST facet on a shell-redirected write."
        ;;
    esac
  done < <(gate_bash_write_targets "$_command")
fi

PG_PAYLOAD="$payload" PG_ROOT="$root" \
python3 <<'PY'
import sys as _fc_sys  # fail-closed-on-internal-error
try:
    import importlib.util, os, posixpath, re, sys

    _spec = importlib.util.spec_from_file_location("gate_lib", os.environ["GATE_LIB_PY"])
    gate_lib = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(gate_lib)

    def deny(m):
        sys.stderr.write("product-opportunity-solution-tree: refused — %s\n" % m)
        import json as _json
        print(_json.dumps({"hookSpecificOutput": {"permissionDecision": "deny",
              "permissionDecisionReason": "product-opportunity-solution-tree: refused — %s" % m}}))
        sys.exit(2)

    raw = os.environ.get("PG_PAYLOAD", "")
    ev = gate_lib.gate_parse_json_or_deny(raw, deny)

    tool = ev.get("tool_name")
    ti = ev.get("tool_input")
    if not isinstance(ti, dict):
        deny("tool_input is missing or not a JSON object; the gate cannot judge a write it cannot parse (methodology).")

    root = posixpath.normpath(os.environ["PG_ROOT"].replace("\\", "/"))
    SURVEY_RE = re.compile(r'^docs/issue-[0-9]+/reports/product-discovery/current-state\.md$')
    PROPOSAL_RE = re.compile(r'^docs/issue-[0-9]+/proposals/.*product-discovery.*\.md$', re.I)
    RECORD_RE = re.compile(r'^docs/issue-[0-9]+/reports/product-discovery\.md$')

    path = None
    if tool in ("Write", "Edit", "MultiEdit"):
        p = ti.get("file_path")
        if isinstance(p, str) and p:
            path = p
    elif tool == "NotebookEdit":
        p = ti.get("notebook_path")
        if isinstance(p, str) and p:
            path = p
    if path is None:
        sys.exit(0)

    rel = gate_lib.gate_normalize_path(root, path)
    if rel is None:
        sys.exit(0)

    is_survey = bool(SURVEY_RE.match(rel))
    is_proposal = bool(PROPOSAL_RE.match(rel))
    is_record = bool(RECORD_RE.match(rel))

    if not (is_survey or is_proposal or is_record):
        sys.exit(0)  # not an OST methodology write surface — not this gate's business

    # --- proposal path: order-constraint only, no vocabulary check here ---
    if is_proposal:
        parts = rel.split("/")
        issue_seg = parts[1] if len(parts) > 1 else None
        survey_abs = posixpath.join(root, "docs", issue_seg, "reports", "product-discovery", "current-state.md") if issue_seg else None
        if not survey_abs or not os.path.isfile(survey_abs):
            deny(
                "proposal write precedes its own current-state survey "
                "(missing docs/%s/reports/product-discovery/current-state.md). "
                "Per docs/issue-36/..., the current-state survey must exist before "
                "any product-discovery proposal is written." % (issue_seg or "issue-<n>")
            )
        sys.exit(0)  # order gate satisfied; this plugin has no other proposal obligation

    # --- survey/record paths: reconstruct resulting content ---
    r = posixpath.join(root, rel) if rel else root
    current = None
    if os.path.isfile(r):
        try:
            with open(r, encoding="utf-8-sig") as fh:
                current = fh.read(1 << 20)
        except OSError:
            deny("%s exists but cannot be read; failing closed on methodology." % rel)

    new_text, ok = gate_lib.gate_reconstruct_write(tool, ti, current)
    if not ok or new_text is None:
        deny(
            "this write targets %s but the gate cannot determine the resulting content "
            "from the tool input (tool=%r). Write the full document with Write, or use an "
            "Edit/MultiEdit whose old_string matches, so the methodology fields can be "
            "checked." % (rel, tool)
        )

    # --- section/adjacency/structure tiered vocabulary check ---
    HEADING_RE = re.compile(r'^(#{1,6})\s+(.*)$')
    BOLD_LABEL_RE = re.compile(r'^\*\*([^*]+)\*\*\s*:?\s*$')

    def split_sections(text):
        lines = text.split('\n')
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

    LABEL_LINE_RE = re.compile(
        r'(?im)^\s*(outcome|opportunity|candidate solution(?:s)?|discriminating assumption test)\s*:\s*\S'
    )
    SECTION_NAME_RE = re.compile(
        r'(?i)outcome|opportunity|candidate solution|discriminating assumption test|\bost\b'
    )
    OST_LAYER_PATTERNS = {
        "outcome": re.compile(r'(?i)\boutcome\b'),
        "opportunity": re.compile(r'(?i)\bopportunity\b'),
        "candidate_solution": re.compile(r'(?i)\bcandidate solution(?:s)?\b'),
        "discriminating_assumption_test": re.compile(r'(?i)\bdiscriminating assumption test\b'),
    }

    def section_adjacency_match(text, section_name_re, marker_res):
        found = set()
        for heading, body in split_sections(text):
            if not section_name_re.search(heading):
                continue
            for para in paragraphs(body):
                for key, pat in marker_res.items():
                    if pat.search(para):
                        found.add(key)
        return found

    def ost_layer_named(text):
        # Tier 1: explicit label line.
        if LABEL_LINE_RE.search(text):
            return True
        # Tier 2: section + adjacency.
        found = section_adjacency_match(text, SECTION_NAME_RE, OST_LAYER_PATTERNS)
        return bool(found)

    low = new_text.lower()

    def has_any(*needles):
        return any(nd in low for nd in needles)

    if is_survey:
        if not ost_layer_named(new_text):
            deny(
                "OST branch vocabulary missing. Per docs/issue-36/..., the current-state "
                "survey must name the relevant branch (outcome/opportunity/candidate "
                "solutions/discriminating assumption test) in OST's own vocabulary, in a "
                "labeled section (not a stray mention elsewhere in the document)."
            )
        sys.exit(0)

    if is_record:
        verdict_named = has_any("pruned", "promoted", "kill", "go", "pivot")
        if not (ost_layer_named(new_text) and verdict_named):
            deny(
                "record is missing an OST branch disposition (pruned/promoted, in OST "
                "vocabulary) in a labeled section."
            )
        sys.exit(0)

    sys.exit(0)
except Exception as _fc_e:  # fail-closed-on-internal-error
    _fc_sys.stderr.write("methodology-gate.sh: fail-closed: internal error: %r\n" % (_fc_e,))
    _fc_sys.exit(2)
PY
_fc_rc=$?  # fail-closed-on-internal-error
if [ "$_fc_rc" -ne 0 ] && [ "$_fc_rc" -ne 2 ]; then
  deny "product-opportunity-solution-tree: refused — fail-closed: internal error (judge exited $_fc_rc)"
fi
exit "$_fc_rc"
