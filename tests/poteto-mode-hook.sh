#!/usr/bin/env bash
# Functional test for hooks/poteto-mode.sh. Runs the real hook against real
# stdin payloads and asserts on what it injects.
set -uo pipefail
HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/hooks/poteto-mode.sh"
export CLAUDE_CONFIG_DIR="$(mktemp -d)"
SID="test-session-$$"
pass=0; fail=0

fire() { printf '{"session_id":"%s","prompt":%s}' "$SID" "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1")" | bash "$HOOK" 2>/dev/null; }

check() { # name, expect(has|empty), needle
  local name="$1" mode="$2" needle="${3:-}" out="$4"
  if [ "$mode" = empty ]; then
    if [ -z "$out" ]; then pass=$((pass+1)); printf '  ok    %s\n' "$name"
    else fail=$((fail+1)); printf '  FAIL  %s (expected no output, got: %s)\n' "$name" "$(printf '%s' "$out" | head -1)"; fi
  else
    if printf '%s' "$out" | grep -qF "$needle"; then pass=$((pass+1)); printf '  ok    %s\n' "$name"
    else fail=$((fail+1)); printf '  FAIL  %s (missing %q in: %s)\n' "$name" "$needle" "$(printf '%s' "$out" | head -2)"; fi
  fi
}

check "quiet when nothing armed"        empty ""             "$(fire 'just a normal question')"
check "/poteto-mode arms + injects"     has   "poteto-mode is pinned" "$(fire '/poteto-mode build the thing')"
check "stays armed on a later turn"     has   "poteto-mode is pinned" "$(fire 'ok now do the next bit')"
check "reminder text is upstream's"     has   "Playbook match or rigor needed" "$(fire 'another turn')"
check "playbook instruction present"    has   "copy its steps into a todo list verbatim" "$(fire 'another turn')"
check "/goal stores the objective"      has   "ship the release by friday" "$(fire '/goal ship the release by friday')"
check "goal persists next turn"         has   "Standing goal for this session" "$(fire 'unrelated follow-up')"
check "goal + mode both inject"         has   "poteto-mode is pinned" "$(fire 'unrelated follow-up')"
check "/poteto-off unpins"              empty ""             "$(fire '/poteto-off and /goal clear')"
check "namespaced form arms too"        has   "poteto-mode is pinned" "$(fire '/pstack-cc:poteto-mode do a thing')"
check "goal stayed cleared"             has   "poteto-mode is pinned" "$(fire 'turn')"
out="$(fire 'turn')"; if printf '%s' "$out" | grep -qF "Standing goal"; then fail=$((fail+1)); printf '  FAIL  goal really cleared\n'; else pass=$((pass+1)); printf '  ok    goal really cleared\n'; fi
check "malformed stdin is silent"       empty ""             "$(printf 'not json' | bash "$HOOK" 2>/dev/null)"
check "empty stdin is silent"           empty ""             "$(printf '' | bash "$HOOK" 2>/dev/null)"

rm -rf "$CLAUDE_CONFIG_DIR"
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
