#!/usr/bin/env bash
# Live check that the plugin loads and routes the way the skills assume, through
# a real `claude -p --plugin-dir` session. Costs a little model quota, so it is
# NOT run by import.sh -- run it after an upstream bump or a frontmatter change.
#
# What it pins down, each measured once and each a past bug:
#   - plugin agents register as pstack-cc:<name>, so skills must dispatch that name
#   - the Skill tool can load a skill another skill routes to; with upstream's
#     disable-model-invocation it refused ("cannot be used with Skill tool")
#   - the cloud-session SessionStart hook runs and reaches the context
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0; fail=0
eq() { if [ "$2" = "$3" ]; then pass=$((pass+1)); printf '  ok    %s\n' "$1"
       else fail=$((fail+1)); printf '  FAIL  %s (want %q, got %q)\n' "$1" "$3" "$2"; fi; }
cd "$(mktemp -d)"

init="$(CLAUDE_CODE_REMOTE=true timeout 120 claude -p "say ok" --plugin-dir "$ROOT" --max-turns 1 \
          --output-format stream-json --verbose 2>/dev/null)"
field() { printf '%s\n' "$init" | python3 -c '
import json,sys
for l in sys.stdin:
    try: d=json.loads(l)
    except Exception: continue
    if d.get("type")=="system" and d.get("subtype")=="init":
        print("\n".join(d.get(sys.argv[1]) or [])); break' "$1"; }
eq "agent registered as pstack-cc:poteto-agent"  "$(field agents | grep -cx 'pstack-cc:poteto-agent')" "1"
eq "agent registered as pstack-cc:comment-sicko" "$(field agents | grep -cx 'pstack-cc:comment-sicko')" "1"
eq "cloud hook output reached the session"       "$(printf '%s' "$init" | grep -q 'pstack-cc is running in a Claude Code cloud session' && echo yes || echo no)" "yes"

got="$(timeout 180 claude -p 'Call the Skill tool exactly once with skill "pstack-cc:principle-prove-it-works". Then reply with only LOADED if the skill content was returned, or REFUSED if it was refused.' \
        --plugin-dir "$ROOT" --max-turns 3 --output-format text 2>/dev/null | tail -1)"
eq "Skill tool loads a routed-to skill"          "$(printf '%s' "$got" | grep -o -E 'LOADED|REFUSED' | head -1)" "LOADED"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
