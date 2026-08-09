#!/usr/bin/env bash
. "${CLAUDE_PLUGIN_ROOT_CORE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../core" && pwd -P)}/hooks/lib/gate-lib.sh" || { echo "product-hypothesis-testing: cannot source gate-lib.sh" >&2; exit 2; }
gate_trap_fail_closed
# PreToolUse gate for product-hypothesis-testing: pre-registered hypothesis
# discipline. Fires on the phase-1 PROPOSAL write
# (docs/issue-<n>/proposals/*product-discovery*.md) and the phase-2 RECORD
# (docs/issue-<n>/reports/product-discovery.md). Fails closed.
#
# Migrated to the gate-house standard (core issue #72): kill switch now uses
# gate_kill_switch_active's fixed on-spelling set (1/true/yes/on) instead of
# an exact-match "= 1" check that fail-opened on any unrecognized value.
# Also adopts gate_parse_json_or_deny / gate_normalize_path /
# gate_reconstruct_write from core's gate-lib.py, and adds Bash-tool write
# coverage via gate_bash_write_targets.
#
# Fixed a template-less `mktemp` that wrote its inline python payload to a
# scratch file before running it: under a Claude Code sandboxed role session,
# a bare `mktemp` resolved to the platform tmp dir (on macOS, the confstr
# _CS_DARWIN_USER_TEMP_DIR path under /var/folders/.../T) rather than the
# sandbox's own writable $TMPDIR, so the gate's own scratch write was denied
# and it failed closed on every proposal/record write in that plugin,
# regardless of content (found via reasona issue-3, 2026-08-06). No file is
# needed at all — the payload and root now travel via env vars into a
# `python3 <<'PYEOF' … PYEOF` heredoc piped straight to python3's stdin, the
# same pattern the sibling gates (product-one-pager, product-guardrail-
# metrics, product-opportunity-solution-tree) already use.
set -uo pipefail
gate_kill_switch_active "${PRODUCT_HYPOTHESIS_TESTING_GATE_OFF:-}" || { cat >/dev/null 2>&1 || true; trap - EXIT; exit 0; }

deny() {
  printf '{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":%s}}\n' \
    "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1" 2>/dev/null || echo '"product-hypothesis-testing: refused"')"
  printf '%s\n' "$1" >&2
  exit 2
}

trap 'deny "product-hypothesis-testing: refused — gate failed closed on an internal error; required by product-hypothesis-testing/hooks/methodology-gate.sh — see docs/handbooks/tests.md"' ERR

command -v python3 >/dev/null 2>&1 || deny "product-hypothesis-testing: refused — python3 is not available; failing closed; required by product-hypothesis-testing/hooks/methodology-gate.sh — see docs/handbooks/tests.md"

payload="$(cat)"
[ -n "$payload" ] || deny "product-hypothesis-testing: refused — empty stdin payload; required by product-hypothesis-testing/hooks/methodology-gate.sh — see docs/handbooks/tests.md"

# Bash-tool write coverage: scan tool_input.command tokens for a match
# against the proposal/record path patterns before the python payload runs.
bash_cmd="$(printf '%s' "$payload" | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin)
    if isinstance(d, dict) and d.get("tool_name") == "Bash":
        ti = d.get("tool_input")
        if isinstance(ti, dict) and isinstance(ti.get("command"), str):
            print(ti["command"])
except Exception:
    pass' 2>/dev/null)"
if [ -n "$bash_cmd" ]; then
  for tok in $(printf '%s\n' "$bash_cmd" | grep -oE '[[:alnum:]_./~$-]+' || true); do
    if printf '%s' "$tok" | grep -qE 'docs/issue-[0-9]+/proposals/[^/]*product-discovery[^/]*\.md$' \
      || printf '%s' "$tok" | grep -qE 'docs/issue-[0-9]+/reports/product-discovery\.md$'; then
      deny "product-hypothesis-testing: refused — Bash command targets the proposal/record path; failing closed; required by product-hypothesis-testing/hooks/methodology-gate.sh — see docs/handbooks/tests.md"
    fi
  done
fi

# Resolve project root: CLAUDE_PROJECT_DIR (validated) -> git toplevel -> cwd.
root=""
if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "${CLAUDE_PROJECT_DIR:-}" ]; then
  cand="$(cd "$CLAUDE_PROJECT_DIR" 2>/dev/null && pwd -P)"
  cwd_json="$(printf '%s' "$payload" | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin)
    print(d.get("cwd","") if isinstance(d,dict) else "")
except Exception:
    print("")' 2>/dev/null)"
  if [ -n "$cand" ]; then
    if [ -z "$cwd_json" ] || [ "$cand" = "$cwd_json" ] || [[ "$cwd_json" == "$cand"/* ]]; then
      root="$cand"
    fi
  fi
fi
if [ -z "$root" ]; then
  root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
fi
[ -n "$root" ] || root="$(pwd -P)"

result="$(MHT_ROOT="$root" MHT_PAYLOAD="$payload" GATE_LIB_PY="$GATE_LIB_PY" python3 <<'PYEOF'
import importlib.util, os, re, sys

_spec = importlib.util.spec_from_file_location("gate_lib", os.environ["GATE_LIB_PY"])
gate_lib = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gate_lib)

root = os.environ["MHT_ROOT"]
raw = os.environ["MHT_PAYLOAD"]


def deny(msg):
    print("DENY|product-hypothesis-testing: refused — " + msg)
    sys.exit(0)


payload = gate_lib.gate_parse_json_or_deny(raw, deny)

tool_name = payload.get("tool_name", "")
tool_input = payload.get("tool_input", None)
if not isinstance(tool_input, dict):
    deny("malformed or missing tool_input.")

file_path = tool_input.get("file_path", "")
if not file_path and tool_name == "NotebookEdit":
    file_path = tool_input.get("notebook_path", "")
if not file_path:
    print("ALLOW")
    sys.exit(0)

rel_path = gate_lib.gate_normalize_path(root, file_path)
if rel_path is None:
    print("ALLOW")
    sys.exit(0)

proposal_re = re.compile(r'^docs/issue-(\d+)/proposals/[^/]*product-discovery[^/]*\.md$')
record_re = re.compile(r'^docs/issue-(\d+)/reports/product-discovery\.md$')

m_proposal = proposal_re.match(rel_path)
m_record = record_re.match(rel_path)

if not m_proposal and not m_record:
    print("ALLOW")
    sys.exit(0)


def read_current(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return f.read()
    except Exception:
        return None


abs_path = file_path if os.path.isabs(file_path) else os.path.join(root, file_path)
current = read_current(abs_path)
if tool_name == "Write":
    resulting_text, ok = gate_lib.gate_reconstruct_write(tool_name, tool_input, current)
elif tool_name in ("Edit", "MultiEdit"):
    if current is None and tool_name == "Edit" and tool_input.get("old_string", None) == "":
        current = ""
    resulting_text, ok = gate_lib.gate_reconstruct_write(tool_name, tool_input, current)
elif tool_name == "NotebookEdit":
    resulting_text, ok = gate_lib.gate_reconstruct_write(tool_name, tool_input, current)
else:
    resulting_text, ok = None, False

if not ok or resulting_text is None:
    deny("cannot determine resulting content for this write.")

text = resulting_text

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


def has_itwws(t):
    if re.search(r'ITWWS', t, re.IGNORECASE):
        return True
    if re.search(r'if this works we should', t, re.IGNORECASE):
        return True
    if '이게 되면' in t:
        return True
    return False


def has_decision_rule(t):
    # Explicit labeled line, e.g. "Decision rule: go if ..."
    for line in t.split('\n'):
        if re.match(r'^\s*(decision[\s-]?rule)\s*:\s*\S.*\b(go|kill|pivot)\b', line, re.IGNORECASE):
            return True
    # Section/paragraph anchored: a decision-shaped heading whose paragraph
    # both mentions go/kill/pivot AND a threshold/metric word.
    for heading, body in split_sections(t):
        if re.search(r'(?i)decision|verdict|rule|hypothesis', heading):
            for para in paragraphs(body):
                if re.search(r'\b(go|kill|pivot)\b', para, re.IGNORECASE) and \
                   re.search(r'threshold|metric|기준', para, re.IGNORECASE):
                    return True
    return False


def has_threshold_digit(t):
    if re.search(r'\d+\s*%', t):
        return True
    if re.search(r'\d+[^\n]{0,40}(threshold|metric|crosses|넘으면|이상|이하)', t, re.IGNORECASE):
        return True
    if re.search(r'(threshold|metric|crosses|넘으면|이상|이하)[^\n]{0,40}\d+', t, re.IGNORECASE):
        return True
    return False


if m_proposal:
    issue_no = m_proposal.group(1)
    current_state = os.path.join(root, "docs", "issue-%s" % issue_no, "reports", "product-discovery", "current-state.md")
    if not os.path.isfile(current_state):
        deny("proposal write precedes its own current-state survey")

    missing = []
    if not has_threshold_digit(text):
        missing.append("threshold-digit")
    if not has_decision_rule(text):
        missing.append("decision-rule")
    if not has_itwws(text):
        missing.append("itwws")

    if missing:
        deny("proposal missing required element(s): %s" % ", ".join(missing))

    print("ALLOW")
    sys.exit(0)

if m_record:
    lines = text.split("\n")
    adjacency_ok = False
    for i in range(len(lines)):
        window = "\n".join(lines[max(0, i - 3):i + 4])
        if re.search(r'\d', window) and re.search(r'(threshold|기준)', window, re.IGNORECASE):
            adjacency_ok = True
            break
    if not adjacency_ok:
        deny("record does not state the measured value adjacent to its threshold.")

    if not has_itwws(text):
        deny("ITWWS follow-up is missing, or deferred with no stated reason.")

    actioned = False
    for para in paragraphs(text):
        if has_itwws(para) and re.search(r'actioned|진행함', para, re.IGNORECASE):
            actioned = True
            break
    deferred_ok = False
    for m in re.finditer(r'deferred', text, re.IGNORECASE):
        start = text.rfind("\n", 0, m.start()) + 1
        end_candidates = [text.find(c, m.end()) for c in [".", "\n"] if text.find(c, m.end()) != -1]
        end = min(end_candidates) if end_candidates else len(text)
        sentence = text[start:end]
        remainder = sentence.lower().replace("deferred", "", 1).strip(" -—:,")
        if len(remainder) > 8:
            deferred_ok = True
            break

    if not actioned and not deferred_ok:
        deny("ITWWS follow-up is missing, or deferred with no stated reason.")

    print("ALLOW")
    sys.exit(0)

print("ALLOW")
PYEOF
)"

status="${result%%|*}"
if [ "$status" = "DENY" ]; then
  msg="${result#DENY|}"
  deny "$msg"
fi

exit 0
