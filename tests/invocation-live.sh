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
#   - pstack-cc:read-only really lacks Edit, Write and Agent
#   - principle-* skills are hidden from / but still load through the Skill tool
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/plugins/pstack-cc"
pass=0; fail=0
eq() { if [ "$2" = "$3" ]; then pass=$((pass+1)); printf '  ok    %s\n' "$1"
       else fail=$((fail+1)); printf '  FAIL  %s (want %q, got %q)\n' "$1" "$3" "$2"; fi; }
cd "$(mktemp -d)" || exit 1

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
eq "agent registered as pstack-cc:read-only"     "$(field agents | grep -cx 'pstack-cc:read-only')" "1"
eq "principles are out of the / menu"            "$(field slash_commands | grep -c 'pstack-cc:principle-')" "0"
eq "routable skills are in the / menu"           "$(field slash_commands | grep -cx 'pstack-cc:how')" "1"
eq "budget hook output reached the session"     "$(printf '%s' "$init" | grep -q 'pstack-cc usage budget: balanced' && echo yes || echo no)" "yes"
eq "cloud hook output reached the session"       "$(printf '%s' "$init" | grep -q 'pstack-cc is running in a Claude Code cloud session' && echo yes || echo no)" "yes"

got="$(timeout 180 claude -p 'Call the Skill tool exactly once with skill "pstack-cc:principle-prove-it-works". Then reply with only LOADED if the skill content was returned, or REFUSED if it was refused.' \
        --plugin-dir "$ROOT" --max-turns 3 --output-format text 2>/dev/null | tail -1)"
eq "Skill tool loads a routed-to skill"          "$(printf '%s' "$got" | grep -o -E 'LOADED|REFUSED' | head -1)" "LOADED"

got="$(timeout 300 claude -p 'Spawn exactly one subagent with the Agent tool, subagent_type "pstack-cc:read-only", model haiku, asking it to list the names of every tool it has. Then reply with one line: HAS_EDIT=yes|no HAS_WRITE=yes|no HAS_AGENT=yes|no HAS_READ=yes|no, based only on its list.' \
        --plugin-dir "$ROOT" --max-turns 4 --output-format text 2>/dev/null | tail -1)"
eq "read-only agent has no Edit"                 "$(printf '%s' "$got" | grep -o 'HAS_EDIT=[a-z]*')"  "HAS_EDIT=no"
eq "read-only agent has no Write"                "$(printf '%s' "$got" | grep -o 'HAS_WRITE=[a-z]*')" "HAS_WRITE=no"
eq "read-only agent cannot spawn agents"         "$(printf '%s' "$got" | grep -o 'HAS_AGENT=[a-z]*')" "HAS_AGENT=no"
eq "read-only agent can still read"              "$(printf '%s' "$got" | grep -o 'HAS_READ=[a-z]*')"  "HAS_READ=yes"

# poteto-agent must start with poteto-mode in hand. Upstream's body named the skill but no
# path; a spawned agent searched ~/.claude/skills/, found nothing and worked without it.
got="$(timeout 300 claude -p 'Spawn exactly one subagent with the Agent tool, subagent_type "pstack-cc:poteto-agent", in the foreground, model haiku, with this task: "Reply with the exact text of the description line in the frontmatter of the poteto-mode SKILL.md, then one word for how you obtained it: PRELOADED (in your context at start), SKILL_TOOL, READ_FILE or NOT_FOUND." Then reply with one line: HOW=<that word>.' \
        --plugin-dir "$ROOT" --max-turns 6 --output-format text 2>/dev/null | tail -1)"
how="$(printf '%s' "$got" | grep -o -E 'HOW=[A-Z_]+' | head -1)"
case "$how" in HOW=PRELOADED|HOW=SKILL_TOOL) how=HOW=OK ;; esac
eq "poteto-agent has poteto-mode without a disk search" "$how" "HOW=OK"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
