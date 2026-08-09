#!/usr/bin/env bash
. "${CLAUDE_PLUGIN_ROOT_CORE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../core" && pwd -P)}/hooks/lib/gate-lib.sh" || { echo "product-assumption-mapping: cannot source gate-lib.sh" >&2; exit 2; }
gate_trap_fail_closed
# product-assumption-mapping gate: evidence-citation format + RICE/ICE
# prioritization, fired only on product-discovery proposal writes.
set -uo pipefail
gate_kill_switch_active "${PRODUCT_ASSUMPTION_MAPPING_GATE_OFF:-}" || { trap - EXIT; exit 0; }

payload="$(cat)"

deny() {
  printf '{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":%s}}\n' \
    "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1" 2>/dev/null || echo '"product-assumption-mapping: refused"')"
  printf '%s\n' "$1" >&2
  exit 2
}

command -v python3 >/dev/null 2>&1 || deny "product-assumption-mapping: refused — python3 not available, failing closed. ; required by product-assumption-mapping/hooks/methodology-gate.sh — see docs/handbooks/tests.md"

[ -n "$payload" ] || deny "product-assumption-mapping: refused — empty stdin payload. ; required by product-assumption-mapping/hooks/methodology-gate.sh — see docs/handbooks/tests.md"

# --- Bash-tool coverage: scan command for proposal-path-shaped write targets
bash_cmd="$(printf '%s' "$payload" | python3 -c '
import json, sys
try:
    data = json.loads(sys.stdin.read())
except Exception:
    print("")
    sys.exit(0)
if isinstance(data, dict) and data.get("tool_name") == "Bash":
    ti = data.get("tool_input")
    if isinstance(ti, dict) and isinstance(ti.get("command"), str):
        print(ti["command"])
    else:
        print("")
else:
    print("")
' 2>/dev/null)"

if [ -n "$bash_cmd" ]; then
  for tok in $(gate_bash_write_targets "$bash_cmd"); do
    case "$tok" in
      */docs/issue-*/proposals/*product-discovery*.md|docs/issue-*/proposals/*product-discovery*.md)
        echo "$tok" | grep -Eq 'docs/issue-[0-9]+/proposals/.*product-discovery.*\.md$' && \
          deny "product-assumption-mapping: refused — Bash write to proposal path cannot be verified for evidence-citation/RICE facets."
        ;;
    esac
  done
fi

# --- parse payload + extract fields in one python invocation ---------------
parsed="$(printf '%s' "$payload" | python3 -c '
import importlib.util, os, sys, json
_spec = importlib.util.spec_from_file_location("gate_lib", os.environ["GATE_LIB_PY"])
gate_lib = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(gate_lib)

def deny(msg):
    print("__PARSE_ERROR__")
    sys.exit(0)

raw = sys.stdin.read()
event = gate_lib.gate_parse_json_or_deny(raw, deny)
tool_input = event.get("tool_input")
if not isinstance(tool_input, dict):
    print("__PARSE_ERROR__")
    sys.exit(0)

print("__OK__")
print(json.dumps({
    "tool_name": event.get("tool_name", ""),
    "file_path": tool_input.get("file_path", tool_input.get("notebook_path", "")),
    "cwd": event.get("cwd", ""),
}))
' 2>/dev/null)"

first_line="$(printf '%s\n' "$parsed" | head -n 1)"
[ "$first_line" = "__OK__" ] || deny "product-assumption-mapping: refused — malformed or non-dict tool_input. ; required by product-assumption-mapping/hooks/methodology-gate.sh — see docs/handbooks/tests.md"

fields_json="$(printf '%s\n' "$parsed" | tail -n +2)"
tool_name="$(printf '%s' "$fields_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["tool_name"])')"
file_path="$(printf '%s' "$fields_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["file_path"])')"
cwd="$(printf '%s' "$fields_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["cwd"])')"

# --- resolve project root --------------------------------------------------
_plausible() { [ -n "${1:-}" ] && [ -d "$1" ]; }

root=""
if _plausible "${CLAUDE_PROJECT_DIR:-}"; then
  root="$CLAUDE_PROJECT_DIR"
elif root="$(git -C "${cwd:-.}" rev-parse --show-toplevel 2>/dev/null)"; then
  :
else
  root="${cwd:-$(pwd -P)}"
fi

# --- only this plugin's target surface -------------------------------------
rel_path="$(python3 -c '
import importlib.util, os, sys
_spec = importlib.util.spec_from_file_location("gate_lib", os.environ["GATE_LIB_PY"])
gate_lib = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(gate_lib)
rel = gate_lib.gate_normalize_path(sys.argv[1], sys.argv[2])
print(rel if rel is not None else "")
' "$root" "$file_path")"

echo "$rel_path" | grep -Eq '^docs/issue-[0-9]+/proposals/.*product-discovery.*\.md$' || exit 0

issue_n="$(printf '%s' "$rel_path" | sed -E 's#^docs/issue-([0-9]+)/proposals/.*#\1#')"

# --- order-constraint precondition (copy-identical across the four plugins)
current_state="$root/docs/issue-$issue_n/reports/product-discovery/current-state.md"
[ -f "$current_state" ] || deny "product-assumption-mapping: refused — proposal write precedes its own current-state survey ; required by product-assumption-mapping/hooks/methodology-gate.sh — see docs/handbooks/tests.md"

abs_path="$root/$rel_path"

# --- reconstruct resulting text --------------------------------------------
resulting_text="$(python3 -c '
import importlib.util, json, os, sys
_spec = importlib.util.spec_from_file_location("gate_lib", os.environ["GATE_LIB_PY"])
gate_lib = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(gate_lib)

payload = sys.argv[1]
abs_path = sys.argv[2]

try:
    data = json.loads(payload)
except Exception:
    print("__RECON_ERROR__")
    sys.exit(0)

tool_name = data.get("tool_name", "")
tool_input = data.get("tool_input", {})

def read_current():
    try:
        with open(abs_path, "r") as f:
            return f.read()
    except Exception:
        return None

current = read_current()
new_text, ok = gate_lib.gate_reconstruct_write(tool_name, tool_input, current)
if not ok:
    print("__RECON_ERROR__")
    sys.exit(0)
print("__RECON_OK__")
sys.stdout.write(new_text)
' "$payload" "$abs_path")"

recon_marker="$(printf '%s\n' "$resulting_text" | head -n 1)"
[ "$recon_marker" = "__RECON_OK__" ] || deny "product-assumption-mapping: refused — cannot determine resulting content ; required by product-assumption-mapping/hooks/methodology-gate.sh — see docs/handbooks/tests.md"
body="$(printf '%s\n' "$resulting_text" | tail -n +2)"

# --- facet checks -----------------------------------------------------------
verdict="$(printf '%s' "$body" | python3 -c '
import re, sys

HEADING_RE = re.compile(r"^(#{1,6})\s+(.*)$")
BOLD_LABEL_RE = re.compile(r"^\*\*([^*]+)\*\*\s*:?\s*$")

def split_sections(text):
    lines = text.split("\n")
    sections = []
    cur_heading = ""
    cur_lines = []
    for line in lines:
        h = HEADING_RE.match(line)
        b = BOLD_LABEL_RE.match(line)
        if h or b:
            sections.append((cur_heading, "\n".join(cur_lines)))
            cur_heading = (h.group(2) if h else b.group(1)).strip()
            cur_lines = []
        else:
            cur_lines.append(line)
    sections.append((cur_heading, "\n".join(cur_lines)))
    return sections

text = sys.stdin.read()
lines = text.splitlines()

EVIDENCE_HEADING_RE = re.compile(r"(?i)evidence|citation|assumption|interview")
BULLET_RE = re.compile(r"^\s*[-*]\s")

# map each line index to its enclosing heading (last heading seen above it)
heading_for_line = []
cur_heading = ""
for line in lines:
    h = HEADING_RE.match(line)
    if h:
        cur_heading = h.group(2).strip()
    heading_for_line.append(cur_heading)

# (a) evidence-citation format ----------------------------------------------
citation_lines = []
for idx, line in enumerate(lines):
    if re.search(r"(?i)\b(interview|observation|evidence)\b.{0,40}?\b[0-9]+\b", line):
        anchored = bool(BULLET_RE.match(line)) or bool(EVIDENCE_HEADING_RE.search(heading_for_line[idx]))
        if anchored:
            citation_lines.append(line)

if citation_lines:
    date_re = re.compile(r"(?:\b(19|20)\d{2}\b|\d{4}-\d{2}(?:-\d{2})?)")
    for line in citation_lines:
        has_date = bool(date_re.search(line))
        stripped = date_re.sub("", line)
        stripped = re.sub(r"[0-9]+", "", stripped)
        stripped = re.sub(r"[^A-Za-z가-힣]+", " ", stripped).strip()
        has_paraphrase = len(stripped) >= 8
        if not (has_date and has_paraphrase):
            print("DENY_CITATION")
            sys.exit(0)

# (b) RICE / ICE prioritization ---------------------------------------------
candidate_markers = re.findall(r"(?im)^\s*[-*]\s*.*\b(candidate|opportunity)\b", text)
candidate_count = len(candidate_markers)
explicit = re.search(r"(?i)\b([2-9]|[1-9][0-9]+)\s+(candidates|opportunities)\b", text)
two_plus = candidate_count >= 2 or bool(explicit)

if two_plus:
    reach_unavailable = bool(re.search(r"(?i)reach\s+(data\s+)?unavailable", text))
    has_rice = bool(re.search(r"(?i)\bRICE\b", text)) or bool(
        re.search(r"(?i)reach", text) and re.search(r"(?i)impact", text)
        and re.search(r"(?i)confidence", text) and re.search(r"(?i)effort", text)
    )
    has_ice = bool(re.search(r"(?i)\bICE\b", text))
    flagged_ice = has_ice and reach_unavailable

    if has_rice:
        pass
    elif flagged_ice:
        pass
    elif has_ice and not reach_unavailable:
        print("DENY_UNFLAGGED_ICE")
        sys.exit(0)
    else:
        print("DENY_MISSING_SCORE")
        sys.exit(0)

print("PASS")
')"

case "$verdict" in
  DENY_CITATION)
    deny "product-assumption-mapping: refused — evidence citation missing count/date/paraphrase."
    ;;
  DENY_UNFLAGGED_ICE)
    deny "product-assumption-mapping: refused — unflagged ICE score used where RICE was computable."
    ;;
  DENY_MISSING_SCORE)
    deny "product-assumption-mapping: refused — RICE (or flagged ICE) score missing for compared candidates."
    ;;
esac

exit 0
