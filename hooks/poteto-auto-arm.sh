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
# It is OFF unless <config>/pstack-cc/always-on exists, because pinning a mode
# for every session in every repo is a choice the plugin should not make on
# anyone's behalf.
#
#   touch ~/.claude/pstack-cc/always-on   arm every future session
#   rm ~/.claude/pstack-cc/always-on      stop arming them
#   /poteto-off                           unpin the current session only
#
# SessionStart does not run again mid-session, so /poteto-off still wins until
# the next session starts.
#
# It also reaps .mode markers older than 7 days. One is written per session and
# nothing else deletes them.
#
# Any error, or the gate absent, exits 0 silently and changes nothing.
set -uo pipefail

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/pstack-cc"
[ -f "$CFG/always-on" ] || exit 0

payload="$(cat 2>/dev/null)" || true
sid="$(printf '%s' "$payload" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin).get("session_id",""))' 2>/dev/null)"
[ -n "$sid" ] || sid="${CLAUDE_SESSION_ID:-${CLAUDE_CODE_SESSION_ID:-}}"
[ -n "$sid" ] || exit 0
case "$sid" in */*|..|.) exit 0 ;; esac

mkdir -p "$CFG/state" 2>/dev/null || exit 0
: > "$CFG/state/$sid.mode" 2>/dev/null || exit 0
find "$CFG/state" -maxdepth 1 -name '*.mode' -mtime +7 -delete 2>/dev/null
exit 0
