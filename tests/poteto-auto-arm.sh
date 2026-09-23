#!/usr/bin/env bash
# Functional test for hooks/poteto-auto-arm.sh. Runs the real hook against real
# stdin payloads, then runs the real hooks/poteto-mode.sh against the state it
# produced, so the two are asserted as one chain rather than in isolation.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARM="$ROOT/hooks/poteto-auto-arm.sh"
PIN="$ROOT/hooks/poteto-mode.sh"
export CLAUDE_CONFIG_DIR="$(mktemp -d)"
CFG="$CLAUDE_CONFIG_DIR/pstack-cc"
SID="test-session-$$"
pass=0; fail=0

start() { printf '{"session_id":%s,"source":"%s"}' "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "${2:-$SID}")" "${1:-startup}" | bash "$ARM" 2>/dev/null; }
turn()  { printf '{"session_id":"%s","prompt":%s}' "$SID" "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1")" | bash "$PIN" 2>/dev/null; }
armed() { [ -f "$CFG/state/$SID.mode" ] && echo yes || echo no; }

eq() { # name, got, want
  if [ "$2" = "$3" ]; then pass=$((pass+1)); printf '  ok    %s\n' "$1"
  else fail=$((fail+1)); printf '  FAIL  %s (want %q, got %q)\n' "$1" "$3" "$2"; fi
}

eq "gate absent leaves no marker"      "$(start; armed)" "no"
eq "gate absent creates no state dir"  "$([ -d "$CFG/state" ] && echo yes || echo no)" "no"

mkdir -p "$CFG"; : > "$CFG/always-on"

eq "gate present arms the session"     "$(start; armed)" "yes"
eq "marker is an empty file"           "$(wc -c < "$CFG/state/$SID.mode" | tr -d ' ')" "0"
eq "SessionStart injects no context"   "$(start)" ""

eq "plain turn now gets the reminder"  "$(turn 'refactor the parser' | grep -c 'poteto-mode is pinned')" "1"
eq "and the playbook instruction"      "$(turn 'refactor the parser' | grep -c 'copy its steps into a todo list verbatim')" "1"

eq "/poteto-off still unpins"          "$(turn '/poteto-off' >/dev/null; armed)" "no"
eq "and the next turn is quiet"        "$(turn 'hello')" ""

start; start resume; start clear
eq "re-arm is idempotent"              "$(find "$CFG/state" -name '*.mode' | wc -l | tr -d ' ')" "1"

: > "$CFG/state/stale.mode"
touch -t "$(python3 -c 'import datetime;print((datetime.datetime.now()-datetime.timedelta(days=8)).strftime("%Y%m%d%H%M"))')" "$CFG/state/stale.mode"
start
eq "prune reaps an 8-day-old marker"   "$([ -e "$CFG/state/stale.mode" ] && echo yes || echo no)" "no"
eq "prune keeps the fresh marker"      "$(armed)" "yes"

eq "traversal session_id is refused"   "$(start startup '../../escaped'; [ -e "$CLAUDE_CONFIG_DIR/../escaped.mode" ] && echo yes || echo no)" "no"

printf 'not json' | bash "$ARM" >/dev/null 2>&1; eq "malformed stdin exits 0" "$?" "0"
printf '' | bash "$ARM" >/dev/null 2>&1;         eq "empty stdin exits 0"     "$?" "0"

rm -rf "$CLAUDE_CONFIG_DIR"
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
