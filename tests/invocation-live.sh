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
#   - Matt Pocock's skills: core and extras register, excluded ones do not, a bare name
#     resolves, and an unrouted extra keeps its slash-only flag
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/plugins/pstack-cc"
pass=0; fail=0
# Model replies are searched whole, never by their last line: a reply that adds a note after
# its answer (MEASURED 2026-10-05: a machine hook refused haiku and the model appended why)
# would otherwise read as no answer at all. The last match wins.
# Every raw reply is kept, so a failure can be read instead of guessed at.
keep() { printf '%s\n' "$got" > "$SCRATCH/$1.txt"; }
pick() { printf '%s\n' "$1" | grep -o -E "$2" | tail -1; }
eq() { if [ "$2" = "$3" ]; then pass=$((pass+1)); printf '  ok    %s\n' "$1"
       else fail=$((fail+1)); printf '  FAIL  %s (want %q, got %q)\n' "$1" "$3" "$2"; fi; }
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/pstack-test.XXXXXX")" || exit 2; cd "$SCRATCH" || exit 2
# macOS ships no `timeout` (MEASURED 2026-10-05: neither timeout nor gtimeout on PATH), and
# a missing one made every call below print nothing, so every check failed or, worse, passed
# vacuously on an empty menu. perl's alarm survives the exec and is everywhere.
tmo() { if command -v timeout >/dev/null 2>&1; then timeout "$@"; else perl -e 'alarm shift; exec @ARGV or die "exec: $!\n"' "$@"; fi; }

init="$(CLAUDE_CODE_REMOTE=true tmo 120 claude -p "say ok" --plugin-dir "$ROOT" --max-turns 1 \
          --output-format stream-json --verbose 2>/dev/null)"
field() { printf '%s\n' "$init" | python3 -c '
import json,sys
for l in sys.stdin:
    try: d=json.loads(l)
    except Exception: continue
    if d.get("type")=="system" and d.get("subtype")=="init":
        print("\n".join(d.get(sys.argv[1]) or [])); break' "$1"; }
# Every check below reads this init event. Without it they compare against nothing.
[ -n "$(field slash_commands)" ] || { echo "  FAIL  claude -p produced no init event; nothing below would be measured"; exit 1; }
eq "agent registered as pstack-cc:poteto-agent"  "$(field agents | grep -cx 'pstack-cc:poteto-agent')" "1"
eq "agent registered as pstack-cc:comment-sicko" "$(field agents | grep -cx 'pstack-cc:comment-sicko')" "1"
eq "agent registered as pstack-cc:read-only"     "$(field agents | grep -cx 'pstack-cc:read-only')" "1"
eq "principles are out of the / menu"            "$(field slash_commands | grep -c 'pstack-cc:principle-')" "0"
eq "routable skills are in the / menu"           "$(field slash_commands | grep -cx 'pstack-cc:how')" "1"
eq "budget hook output reached the session"     "$(printf '%s' "$init" | grep -q 'pstack-cc usage budget: balanced' && echo yes || echo no)" "yes"
eq "cloud hook output reached the session"       "$(printf '%s' "$init" | grep -q 'pstack-cc is running in a Claude Code cloud session' && echo yes || echo no)" "yes"

# Matt Pocock's skills (transform/mattpocock.tsv): core and extras register, excluded ones do not.
eq "Matt's core skill in the / menu"             "$(field slash_commands | grep -cx 'pstack-cc:grill-with-docs')" "1"
eq "Matt's teach ships renamed as course"        "$(field slash_commands | grep -cx 'pstack-cc:course')" "1"
# Registered first: the refusal check below also reads REFUSED when triage is missing.
eq "extra triage is registered"                  "$(field slash_commands | grep -cx 'pstack-cc:triage')" "1"
eq "excluded ask-matt is absent"                 "$(field slash_commands | grep -cx 'pstack-cc:ask-matt')" "0"
eq "excluded pr is absent"                       "$(field slash_commands | grep -cx 'pstack-cc:pr')" "0"

# His skills chain with a BARE name ("Call the Skill tool with \"grilling\""); it must resolve
# to this plugin's skill. A core skill lost its user-only flag so the router can call it; an
# extra kept it, so the Skill tool must still refuse it.
got="$(tmo 180 claude -p 'Call the Skill tool exactly once with skill "grilling" (no prefix). Then reply with only LOADED if the skill content was returned, or REFUSED if it was refused or not found.' \
        --plugin-dir "$ROOT" --max-turns 3 --output-format text 2>/dev/null)"
keep bare-grilling
eq "a bare Matt skill name loads"                "$(pick "$got" 'LOADED|REFUSED')" "LOADED"
got="$(tmo 180 claude -p 'Call the Skill tool exactly once with skill "pstack-cc:to-spec". Then reply with only LOADED if the skill content was returned, or REFUSED if it was refused.' \
        --plugin-dir "$ROOT" --max-turns 3 --output-format text 2>/dev/null)"
keep to-spec
eq "a routed Matt skill loads"                   "$(pick "$got" 'LOADED|REFUSED')" "LOADED"
got="$(tmo 180 claude -p 'Call the Skill tool exactly once with skill "pstack-cc:triage". Then reply with only LOADED if the skill content was returned, or REFUSED if it was refused.' \
        --plugin-dir "$ROOT" --max-turns 3 --output-format text 2>/dev/null)"
keep triage
eq "an unrouted extra stays slash-only"          "$(pick "$got" 'LOADED|REFUSED')" "REFUSED"

got="$(tmo 180 claude -p 'Call the Skill tool exactly once with skill "pstack-cc:principle-prove-it-works". Then reply with only LOADED if the skill content was returned, or REFUSED if it was refused.' \
        --plugin-dir "$ROOT" --max-turns 3 --output-format text 2>/dev/null)"
keep principle
eq "Skill tool loads a routed-to skill"          "$(pick "$got" 'LOADED|REFUSED')" "LOADED"

got="$(tmo 300 claude -p 'Spawn exactly one subagent with the Agent tool, subagent_type "pstack-cc:read-only", model haiku, asking it to list the names of every tool it has. Then reply with one line: HAS_EDIT=yes|no HAS_WRITE=yes|no HAS_AGENT=yes|no HAS_READ=yes|no, based only on its list.' \
        --plugin-dir "$ROOT" --max-turns 4 --output-format text 2>/dev/null)"
keep read-only
eq "read-only agent has no Edit"                 "$(pick "$got" 'HAS_EDIT=[a-z]+')"  "HAS_EDIT=no"
eq "read-only agent has no Write"                "$(pick "$got" 'HAS_WRITE=[a-z]+')" "HAS_WRITE=no"
eq "read-only agent cannot spawn agents"         "$(pick "$got" 'HAS_AGENT=[a-z]+')" "HAS_AGENT=no"
eq "read-only agent can still read"              "$(pick "$got" 'HAS_READ=[a-z]+')"  "HAS_READ=yes"

# poteto-agent must start with poteto-mode in hand. Upstream's body named the skill but no
# path; a spawned agent searched ~/.claude/skills/, found nothing and worked without it.
# Judged from the subagent's own transcript, not its answer: the preload shows up as an
# injected <command-name>pstack-cc:poteto-mode</command-name> turn, the fallback as a Skill
# call. A search is the failure that bug produced: looking under a skills/ dir that is not
# this plugin's, or a broad find/Glob/ls for it. Reading the plugin's own copy to quote it,
# and the handback that carries the answer, both name poteto-mode and are neither
# (MEASURED 2026-10-05: a preloaded agent grepped its own SKILL.md and read as SEARCHED).
out="$(tmo 300 claude -p 'Spawn exactly one subagent with the Agent tool, subagent_type "pstack-cc:poteto-agent", model haiku, with this task: "Reply with the text of the first second-level (##) heading in the poteto-mode SKILL.md." Wait for its result, then reply with that heading only.' \
        --plugin-dir "$ROOT" --max-turns 10 --output-format stream-json --verbose 2>/dev/null)"
sid="$(printf '%s\n' "$out" | python3 -c '
import json,sys
for l in sys.stdin:
    try: d=json.loads(l)
    except Exception: continue
    if d.get("subtype")=="init": print(d["session_id"]); break')"
sub="$(find ~/.claude/projects -path "*${sid:-none}/subagents/*.jsonl" 2>/dev/null | head -1)"
how="$(python3 - "$sub" "$ROOT" <<'EOF' 2>/dev/null
import json,re,sys
loaded=searched=False
plugin=sys.argv[2]
for l in open(sys.argv[1]):
    d=json.loads(l); c=(d.get("message") or {}).get("content")
    for x in c if isinstance(c,list) else []:
        if x.get("type")=="text" and "<command-name>pstack-cc:poteto-mode</command-name>" in x["text"]: loaded=True
        if x.get("type")!="tool_use" or x["name"]=="SubagentHandback": continue
        if x["name"]=="Skill" and x["input"].get("skill")=="pstack-cc:poteto-mode": loaded=True; continue
        s=json.dumps(x["input"]).replace(plugin, "<plugin>")
        if "poteto-mode" not in s: continue
        if re.search(r"(?<!<plugin>/)skills/poteto-mode", s) or x["name"] in ("Glob","LS") or re.search(r"\b(find|ls|locate)\b", s): searched=True
print("LOADED" if loaded and not searched else "SEARCHED" if searched else "MISSING")
EOF
)"
eq "poteto-agent has poteto-mode without a disk search" "$how" "LOADED"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || printf 'raw replies: %s\n' "$SCRATCH"
[ "$fail" -eq 0 ]
