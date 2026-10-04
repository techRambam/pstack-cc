#!/usr/bin/env bash
# Functional test for hooks/budget.sh: where the budget comes from, what each
# tier injects, and that max stays silent.
set -uo pipefail
HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/plugins/pstack-cc/hooks/budget.sh"
pass=0; fail=0
eq() { if [ "$2" = "$3" ]; then pass=$((pass+1)); printf '  ok    %s\n' "$1"
       else fail=$((fail+1)); printf '  FAIL  %s (want %q, got %q)\n' "$1" "$3" "$2"; fi; }
CFG="$(mktemp -d)"; PROJ="$(mktemp -d)"
run() { printf '{"source":"startup"}' | env -u PSTACK_CC_BUDGET CLAUDE_CONFIG_DIR="$CFG" CLAUDE_PROJECT_DIR="$PROJ" "$@" bash "$HOOK" 2>/dev/null; }

eq "no config defaults to balanced"     "$(run | grep -c 'usage budget: balanced')" "1"
eq "balanced caps fan-out at 3"         "$(run | grep -c 'at most 3 subagents per step')" "1"
eq "balanced allows one Anthropic seat" "$(run | grep -c 'at most ONE Anthropic seat')" "1"
mkdir -p "$PROJ/.claude"; printf '# budget: lean\n' > "$PROJ/.claude/pstack-models.md"
eq "repo config is read"                "$(run | grep -c 'usage budget: lean')" "1"
eq "lean caps fan-out at 2"             "$(run | grep -c 'at most 2 subagents per step')" "1"
printf '# pstack-cc model configuration\n# budget: max\n' > "$CFG/pstack-models.md"
eq "home config wins over the repo's"   "$(run)" ""
eq "env wins over both"                 "$(run env PSTACK_CC_BUDGET=balanced | grep -c 'usage budget: balanced')" "1"
printf '# budget: cheap\n' > "$CFG/pstack-models.md"
eq "older 'cheap' reads as lean"        "$(run | grep -c 'usage budget: lean')" "1"
eq "unknown budget injects nothing"     "$(run env PSTACK_CC_BUDGET=weird)" ""
printf 'not json' | bash "$HOOK" >/dev/null 2>&1; eq "malformed stdin exits 0" "$?" "0"
rm -rf "$CFG" "$PROJ"
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
