#!/usr/bin/env bash
. "${CLAUDE_PLUGIN_ROOT_CORE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../core" && pwd -P)}/hooks/lib/gate-lib.sh" || { echo "product-guardrail-metrics: cannot source gate-lib.sh" >&2; exit 2; }
gate_trap_fail_closed
# ^ fail-closed trap-at-top, from gate-lib.sh (issue-72): any abnormal
#   termination (failed source, set -u abort, unbound var, etc.) before the
#   verdict logic runs is forced to exit 2 (DENY), since a PreToolUse hook
#   treats any non-2 exit as NON-BLOCKING (fail-OPEN). Installed as the
#   FIRST executable statement, above set -uo pipefail.
#
# PreToolUse gate for product-guardrail-metrics: guardrail non-emptiness at
# registration (phase 1) and guardrail status tracking at measurement time
# (phase 2). Fires on the phase-1 PROPOSAL write
# (docs/issue-<n>/proposals/*product-discovery*.md) and the phase-2 RECORD
# (docs/issue-<n>/reports/product-discovery.md). Also covers a Bash-tool
# write to either path via gate_bash_write_targets. Migrated to the
# gate-house standard (core issue #72) per issue #45's gate A+ remediation
# survey: this gate's deny-JSON shape was already correct and is kept as
# the template the sibling gates standardize onto; the confirmed defect
# here was the exact-match (`= "1"`) kill switch, now gate_kill_switch_active.
# Fails closed.
set -uo pipefail
gate_kill_switch_active "${PRODUCT_GUARDRAIL_METRICS_GATE_OFF:-}" || { trap - EXIT; exit 0; }

deny() {
  printf '{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":%s}}\n' \
    "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1" 2>/dev/null || echo '"product-guardrail-metrics: refused"')"
  printf '%s\n' "$1" >&2
  exit 2
}

trap 'deny "product-guardrail-metrics: refused — gate failed closed on an internal error; required by product-guardrail-metrics/hooks/methodology-gate.sh — see docs/handbooks/tests.md"' ERR

command -v python3 >/dev/null 2>&1 || deny "product-guardrail-metrics: refused — python3 is not available; failing closed; required by product-guardrail-metrics/hooks/methodology-gate.sh — see docs/handbooks/tests.md"

payload="$(cat)"
[ -n "$payload" ] || deny "product-guardrail-metrics: refused — empty stdin payload; required by product-guardrail-metrics/hooks/methodology-gate.sh — see docs/handbooks/tests.md"

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

# Bash-tool write-target scan: a Bash command whose text mentions the
# proposal or record path pattern is denied fail-closed before the Python
# payload runs (gate_bash_write_targets, gate-lib.sh).
bash_cmd="$(printf '%s' "$payload" | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin)
    ti = d.get("tool_input") if isinstance(d, dict) else None
    name = d.get("tool_name") if isinstance(d, dict) else None
    if name == "Bash" and isinstance(ti, dict):
        c = ti.get("command", "")
        print(c if isinstance(c, str) else "")
except Exception:
    print("")' 2>/dev/null)"
if [ -n "$bash_cmd" ]; then
  while IFS= read -r tok; do
    [ -n "$tok" ] || continue
    if [[ "$tok" =~ (^|/)docs/issue-[0-9]+/proposals/[^/]*product-discovery[^/]*\.md$ ]] || \
       [[ "$tok" =~ (^|/)docs/issue-[0-9]+/reports/product-discovery\.md$ ]]; then
      deny "product-guardrail-metrics: refused — a Bash command targets the proposal/record path directly; use Write/Edit/MultiEdit so guardrail fields can be checked; required by product-guardrail-metrics/hooks/methodology-gate.sh — see docs/handbooks/tests.md"
    fi
  done <<< "$(gate_bash_write_targets "$bash_cmd")"
fi

result="$(PGM_PAYLOAD="$payload" PGM_ROOT="$root" GATE_LIB_PY="$GATE_LIB_PY" python3 <<'PYEOF'
import json, os, re, sys

root = os.environ["PGM_ROOT"]

import importlib.util
_spec = importlib.util.spec_from_file_location("gate_lib", os.environ["GATE_LIB_PY"])
gate_lib = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(gate_lib)


def deny(m):
    print("DENY|" + m)
    sys.exit(0)


payload = gate_lib.gate_parse_json_or_deny(os.environ.get("PGM_PAYLOAD", ""), deny)

tool_name = payload.get("tool_name", "")
tool_input = payload.get("tool_input", None)
if not isinstance(tool_input, dict):
    deny("product-guardrail-metrics: refused — malformed or missing tool_input.")

file_path = tool_input.get("file_path", "")
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

abs_path = file_path if os.path.isabs(file_path) else os.path.join(root, file_path)


def read_current(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return f.read()
    except Exception:
        return None


current_content = read_current(abs_path)
resulting_text, ok = gate_lib.gate_reconstruct_write(tool_name, tool_input, current_content)

if not ok or resulting_text is None:
    deny(
        "product-guardrail-metrics: refused — this write targets %s but the "
        "gate cannot determine the resulting content from the tool input "
        "(tool=%r). Write the full document with Write, or use an Edit/MultiEdit "
        "whose old_string matches, so guardrail fields can be checked." % (rel_path, tool_name)
    )

text = resulting_text

GUARDRAIL_RE = re.compile(r'guardrail|가드레일', re.IGNORECASE)
EMPTY_MARKERS = ("none", "n/a", "na", "없음", "tbd")

HEADING_RE = re.compile(r'^(#{1,6})\s+(.*)$')
BOLD_LABEL_RE = re.compile(r'^\*\*([^*]+)\*\*\s*:?\s*$')
GUARDRAIL_HEADING_RE = re.compile(r'guardrail', re.IGNORECASE)
GUARDRAIL_LABEL_LINE_RE = re.compile(r'^\s*(guardrails?\s*(metrics?)?\s*:\s*\S|\*\*guardrails?\*\*)', re.IGNORECASE)


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


def guardrail_present_nonempty(t):
    """A guardrail keyword exists, and at least one occurrence's phrase/line
    does not reduce to an emptiness marker immediately after the keyword."""
    for m in GUARDRAIL_RE.finditer(t):
        end = m.end()
        end_candidates = [t.find(c, end) for c in [".", "\n"] if t.find(c, end) != -1]
        stop = min(end_candidates) if end_candidates else len(t)
        after = t[end:stop]
        after_norm = re.sub(r'^[\s:\-–—]*(metrics|metric|are|is)?[\s:\-–—]*', '', after, flags=re.IGNORECASE)
        after_norm = after_norm.strip().lower()
        first_word = re.split(r'[\s,.;]+', after_norm, maxsplit=1)[0] if after_norm else ""
        if first_word in EMPTY_MARKERS:
            continue
        return True
    return False


def anchored_guardrail_texts(t):
    """Text chunks that are structurally anchored as a guardrail
    declaration: either the whole body under a guardrail-related heading (a
    `## Guardrails` section or a `**Guardrails:**` bold-label line, per
    split_sections), or an individual paragraph that is itself a guardrail
    label-style line. Only these chunks count toward non-emptiness — an
    incidental sentence mentioning "guardrail" anywhere else in the document
    does not."""
    out = []
    for heading, body in split_sections(t):
        heading_matches = bool(GUARDRAIL_HEADING_RE.search(heading)) if heading else False
        if heading_matches:
            out.append(body)
            continue
        for para in paragraphs(body):
            if GUARDRAIL_RE.search(para) and GUARDRAIL_LABEL_LINE_RE.search(para):
                out.append(para)
    return out


def anchored_nonempty(t):
    for chunk in anchored_guardrail_texts(t):
        if GUARDRAIL_RE.search(chunk):
            if guardrail_present_nonempty(chunk):
                return True
            continue
        # Heading-anchored chunk with no explicit "guardrail" word inside
        # the body itself (the keyword lived in the heading/label line) —
        # check the body's content isn't trivially empty/an emptiness
        # marker.
        stripped = chunk.strip()
        if not stripped:
            continue
        first_word = re.split(r'[\s,.;:]+', stripped, maxsplit=1)[0].lower()
        if first_word in EMPTY_MARKERS:
            continue
        return True
    return False


if m_proposal:
    issue_no = m_proposal.group(1)
    current_state = os.path.join(root, "docs", "issue-%s" % issue_no, "reports", "product-discovery", "current-state.md")
    if not os.path.isfile(current_state):
        deny("product-guardrail-metrics: refused — proposal write precedes its own current-state survey")

    if not anchored_nonempty(text):
        deny(
            "product-guardrail-metrics: refused — guardrail metric(s) missing or "
            "empty at proposal time; per docs/issue-36/..., guardrails must be named "
            "non-empty at registration in a structurally anchored guardrail section "
            "or label line, not merely mentioned in passing."
        )

    print("ALLOW")
    sys.exit(0)

if m_record:
    STATUS_RE = re.compile(
        r'\b(not breached|breached|unbreached|held)\b|위반|정상', re.IGNORECASE
    )

    status_ok = False
    if GUARDRAIL_RE.search(text):
        for para in paragraphs(text):
            if GUARDRAIL_RE.search(para) and STATUS_RE.search(para):
                status_ok = True
                break

    if not status_ok:
        deny(
            "product-guardrail-metrics: refused — guardrail status not stated "
            "explicitly at measurement time (silence is not \"assumed fine\")."
        )

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
