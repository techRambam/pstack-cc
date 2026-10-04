#!/usr/bin/env bash
# poteto-mode.sh — UserPromptSubmit hook shipped with the pstack-cc plugin.
#
# Replaces two Cursor mechanisms Claude Code has no equivalent for:
#
#   1. `mode: true` + `reminder:` in poteto-mode's frontmatter. In Cursor,
#      Opt+Enter pins a skill as a Custom Mode and its reminder is re-injected
#      on every turn. Claude Code ignores both keys, so the skill would apply
#      to exactly one turn and then be forgotten.
#   2. Cursor's built-in `/goal`, a persistent cross-turn objective that the
#      autopilot and multi-phase-plan playbooks depend on.
#
# Both are emulated here with per-session state plus this hook's stdout, which
# Claude Code injects as context.
#
# Arming is automatic: typing /poteto-mode (or /pstack-cc:poteto-mode) arms it
# for the rest of the session, which is the closest thing to Opt+Enter that
# needs no cooperation from the model.
#
#   /poteto-mode ...   arm         /poteto-off        disarm
#   /goal <text>       set goal    /goal clear        clear goal
#
# Any error, or nothing armed, exits 0 silently and injects nothing.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/pstack-cc/state"

payload="$(cat 2>/dev/null)" || exit 0
[ -n "$payload" ] || exit 0

read -r -d '' PY <<'PYEOF' || true
import json,sys
try:
    d = json.load(sys.stdin)
    print(d.get("session_id", ""))
    print(d.get("prompt", "")[:8000].replace("\n", " "))
except Exception:
    pass
PYEOF

parsed="$(printf '%s' "$payload" | python3 -c "$PY" 2>/dev/null)" || exit 0
sid="${CLAUDE_SESSION_ID:-$(printf '%s\n' "$parsed" | sed -n '1p')}"
prompt="$(printf '%s\n' "$parsed" | sed -n '2p')"
[ -n "$sid" ] || exit 0
mkdir -p "$STATE" 2>/dev/null || exit 0

mode_f="$STATE/$sid.mode"
goal_f="$STATE/$sid.goal"

# --- state transitions --------------------------------------------------
if printf '%s' "$prompt" | grep -Eq '(^|[[:space:]])/(pstack-cc:)?poteto-off([[:space:]]|$)'; then
  rm -f "$mode_f"
elif printf '%s' "$prompt" | grep -Eq '(^|[[:space:]])/(pstack-cc:)?poteto-mode([[:space:]]|$)'; then
  : > "$mode_f"
fi

if printf '%s' "$prompt" | grep -Eq '(^|[[:space:]])/goal[[:space:]]+clear([[:space:]]|$)'; then
  rm -f "$goal_f"
elif printf '%s' "$prompt" | grep -Eq '(^|[[:space:]])/goal[[:space:]]'; then
  printf '%s' "$prompt" \
    | sed -E 's!.*(^|[[:space:]])/goal[[:space:]]+!!' \
    | cut -c1-2000 > "$goal_f"
fi

# --- injection ----------------------------------------------------------
out=""
if [ -f "$goal_f" ] && [ -s "$goal_f" ]; then
  out+="Standing goal for this session (pstack-cc /goal). It does not expire when a turn ends; "
  out+="re-read it before deciding you are done:"$'\n'
  out+="  $(cat "$goal_f")"$'\n'
fi
if [ -f "$mode_f" ]; then
  reminder="$(cat "$HERE/reminder.txt" 2>/dev/null)"
  [ -n "$reminder" ] || reminder="New task? Playbook match or rigor needed -> apply /poteto-mode. Casual turn or user opts out -> don't."
  [ -n "$out" ] && out+=$'\n'
  out+="poteto-mode is pinned for this session (pstack-cc). $reminder"$'\n'
  out+="Match the task to a playbook in the poteto-mode skill and copy its steps into a todo list verbatim before any task-specific todos. Type /poteto-off to unpin."
fi

[ -n "$out" ] || exit 0
printf '%s\n' "$out"
