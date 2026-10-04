#!/usr/bin/env bash
# poteto-auto-arm.sh — SessionStart hook shipped with the pstack-cc plugin.
#
# hooks/poteto-mode.sh pins poteto-mode by checking for a per-session marker,
# <config>/pstack-cc/state/<session-id>.mode, before it injects anything. That
# marker is written when someone types /poteto-mode, which means every new
# session starts unpinned and the mode has to be re-armed by hand.
#
# This hook writes the marker at session start instead, so poteto-mode is
# pinned from the first turn.
#
# It is OFF unless <config>/pstack-cc/always-on exists or PSTACK_CC_ALWAYS_ON=1,
# because pinning a mode for every session in every repo is a choice the plugin
# should not make on anyone's behalf.
#
#   touch ~/.claude/pstack-cc/always-on   arm every future session
#   rm ~/.claude/pstack-cc/always-on      stop arming them
#   PSTACK_CC_ALWAYS_ON=1                 the same, as an environment variable
#   /poteto-off                           unpin the current session only
#
# The variable exists for cloud sessions, whose home directory is created fresh
# for every session, so a touched file there never reaches the next one. Set it
# in the cloud environment's settings, or in a repo's .claude/settings.json
# "env" block to arm every session in that repo.
#
# ONLY source=startup arms. SessionStart also fires on resume, clear, compact
# and fork, all of which happen inside a session that already has its marker,
# so re-arming there buys nothing and would resurrect a deliberate /poteto-off
# at the next compaction. A forked session starts unpinned as a result; type
# /poteto-mode in it.
#
# It also reaps .mode markers older than 7 days. One is written per session and
# nothing else deletes them.
#
# Any error, or the gate absent, exits 0 silently and changes nothing.
set -uo pipefail

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/pstack-cc"
[ -f "$CFG/always-on" ] || [ "${PSTACK_CC_ALWAYS_ON:-}" = 1 ] || exit 0

read -r -d '' PY <<'PYEOF' || true
import json,sys
try:
    d = json.load(sys.stdin)
    print(d.get("session_id", ""))
    print(d.get("source", ""))
except Exception:
    pass
PYEOF

parsed="$(cat 2>/dev/null | python3 -c "$PY" 2>/dev/null)" || exit 0
sid="$(printf '%s\n' "$parsed" | sed -n '1p')"
src="$(printf '%s\n' "$parsed" | sed -n '2p')"

[ "$src" = startup ] || exit 0
[ -n "$sid" ] || exit 0
case "$sid" in */*|..|.) exit 0 ;; esac

mkdir -p "$CFG/state" 2>/dev/null || exit 0
: > "$CFG/state/$sid.mode" 2>/dev/null || exit 0
find "$CFG/state" -maxdepth 1 -name '*.mode' -mtime +7 -delete 2>/dev/null
exit 0
