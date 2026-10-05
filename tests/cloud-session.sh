#!/usr/bin/env bash
# Functional test for pstack-cc's cloud-session support: hooks/cloud-session.sh,
# the PSTACK_CC_ALWAYS_ON gate in hooks/poteto-auto-arm.sh, the watch-pr cloud
# guard, and bin/panelist's environment keys. Offline: nothing here touches the
# network.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/plugins/pstack-cc"
HOOK="$ROOT/hooks/cloud-session.sh"
ARM="$ROOT/hooks/poteto-auto-arm.sh"
pass=0; fail=0

eq() { # name, got, want
  if [ "$2" = "$3" ]; then pass=$((pass+1)); printf '  ok    %s\n' "$1"
  else fail=$((fail+1)); printf '  FAIL  %s (want %q, got %q)\n' "$1" "$3" "$2"; fi
}

CFG="$(mktemp -d "${TMPDIR:-/tmp}/pstack-test.XXXXXX")" || exit 2; PROJ="$(mktemp -d "${TMPDIR:-/tmp}/pstack-test.XXXXXX")" || exit 2
cloud() { printf '{"session_id":"s","source":"startup"}' \
  | env -u OPENAI_API_KEY CLAUDE_CODE_REMOTE=true CLAUDE_CONFIG_DIR="$CFG" CLAUDE_PROJECT_DIR="$PROJ" "$@" bash "$HOOK" 2>/dev/null; }

eq "local session prints nothing"      "$(printf '{}' | env -u CLAUDE_CODE_REMOTE bash "$HOOK")" ""
eq "local session exits 0"             "$(printf '{}' | env -u CLAUDE_CODE_REMOTE bash "$HOOK" >/dev/null; echo $?)" "0"
eq "cloud session injects the notes"   "$(cloud | grep -c 'cloud session')" "1"
eq "names the GraphQL refusal"         "$(cloud | grep -c 'mcp__github__')" "1"
eq "names the plugin's script root"    "$(cloud | grep -c "$ROOT/skills/poteto-mode")" "1"
eq "no repo config: says how to make one" "$(cloud | grep -c 'setup-pstack writes .claude/pstack-models.md')" "1"
eq "no repo config: writes nothing"    "$([ -e "$CFG/pstack-models.md" ] && echo yes || echo no)" "no"

mkdir -p "$PROJ/.claude"; printf 'swarm workers: haiku\n' > "$PROJ/.claude/pstack-models.md"
eq "repo config is reported as copied" "$(cloud | grep -c 'copied from the repo')" "1"
eq "and lands in the home config"      "$(cat "$CFG/pstack-models.md")" "swarm workers: haiku"
printf 'swarm workers: opus\n' > "$CFG/pstack-models.md"
eq "an existing home config is kept"   "$(cloud >/dev/null; cat "$CFG/pstack-models.md")" "swarm workers: opus"

eq "key names are listed"              "$(cloud GEMINI_API_KEY=x | grep -c 'environment: GEMINI_API_KEY')" "1"
eq "key values are never printed"      "$(cloud GEMINI_API_KEY=sekrit-value | grep -c sekrit-value)" "0"
eq "no keys says none"                 "$(cloud | grep -c 'environment: none')" "1"
printf 'not json' | CLAUDE_CODE_REMOTE=true CLAUDE_CONFIG_DIR="$CFG" bash "$HOOK" >/dev/null 2>&1
eq "malformed stdin exits 0"           "$?" "0"

# --- auto-arm: the environment-variable gate --------------------------------
ACFG="$(mktemp -d "${TMPDIR:-/tmp}/pstack-test.XXXXXX")" || exit 2
arm() { printf '{"session_id":"envsid","source":"%s"}' "${1:-startup}" | CLAUDE_CONFIG_DIR="$ACFG" "${@:2}" bash "$ARM"; }
eq "auto-arm: no file, no var: off"    "$(arm startup env -u PSTACK_CC_ALWAYS_ON; [ -f "$ACFG/pstack-cc/state/envsid.mode" ] && echo yes || echo no)" "no"
eq "auto-arm: var=0 stays off"         "$(arm startup env PSTACK_CC_ALWAYS_ON=0; [ -f "$ACFG/pstack-cc/state/envsid.mode" ] && echo yes || echo no)" "no"
eq "auto-arm: var=1 arms"              "$(arm startup env PSTACK_CC_ALWAYS_ON=1; [ -f "$ACFG/pstack-cc/state/envsid.mode" ] && echo yes || echo no)" "yes"
rm -f "$ACFG/pstack-cc/state/envsid.mode"
eq "auto-arm: var=1 still skips compact" "$(arm compact env PSTACK_CC_ALWAYS_ON=1; [ -f "$ACFG/pstack-cc/state/envsid.mode" ] && echo yes || echo no)" "no"

# --- watch-pr guard -----------------------------------------------------------
if command -v bun >/dev/null 2>&1; then
  WP="$ROOT/skills/poteto-mode/scripts/watch-pr/watch-pr"
  CLAUDE_CODE_REMOTE=true bun "$WP" --status-only >/dev/null 2>&1
  eq "watch-pr exits 69 in a cloud session" "$?" "69"
  eq "watch-pr names the replacement"   "$(CLAUDE_CODE_REMOTE=true bun "$WP" 2>&1 | grep -c subscribe_pr_activity)" "1"
else
  printf '  skip  watch-pr guard (no bun)\n'
fi

# --- panelist: keys from the environment ----------------------------------------
PL="$ROOT/bin/panelist"
PCFG="$(mktemp -d "${TMPDIR:-/tmp}/pstack-test.XXXXXX")" || exit 2
nocodex() { env PATH="/usr/bin:/bin" CLAUDE_CONFIG_DIR="$PCFG" "$@"; }
# load_env() without running the CLI: panelist is a script, not a module.
gemkey() { nocodex "$@" python3 -c "
src = open('$PL').read().split('\np = argparse.ArgumentParser')[0]
ns = {}; exec(compile(src, 'panelist', 'exec'), ns); print(ns['load_env']().get('GEMINI_API_KEY'))"; }
eq "panelist: no codex, no key: clear error" \
   "$(echo hi | nocodex env -u OPENAI_API_KEY python3 "$PL" run -m gpt-5.5 -p - 2>&1 | grep -c 'codex CLI not on PATH, and no OPENAI_API_KEY')" "1"
eq "panelist: missing key names the environment" \
   "$(echo hi | nocodex env -u GEMINI_API_KEY -u GOOGLE_API_KEY python3 "$PL" run -m gemini-2.5-flash -p - 2>&1 | grep -c 'or the environment')" "1"
eq "panelist: env key beats .env file" \
   "$(printf 'GEMINI_API_KEY=from-file\n' > "$PCFG/.env"; gemkey env GEMINI_API_KEY=from-env)" "from-env"
eq "panelist: .env file still read" \
   "$(gemkey env -u GEMINI_API_KEY)" "from-file"

rm -rf "$CFG" "$PROJ" "$ACFG" "$PCFG"
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
