#!/usr/bin/env bash
# Functional test for bin/pstack-usage against a synthetic transcript tree:
# deduplication by requestId, model weighting, subagent attribution, the time
# window, and that no message text is ever printed.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/plugins/pstack-cc"
U="$ROOT/bin/pstack-usage"
pass=0; fail=0
eq() { if [ "$2" = "$3" ]; then pass=$((pass+1)); printf '  ok    %s\n' "$1"
       else fail=$((fail+1)); printf '  FAIL  %s (want %q, got %q)\n' "$1" "$3" "$2"; fi; }

T="$(mktemp -d "${TMPDIR:-/tmp}/pstack-test.XXXXXX")" || exit 2; P="$T/projects/-Users-me-app"; mkdir -p "$P/s1/subagents"
now="$(python3 -c 'import datetime;print(datetime.datetime.now(datetime.timezone.utc).isoformat())')"
old="$(python3 -c 'import datetime;print((datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(days=30)).isoformat())')"
turn() { # requestId model output effort timestamp
  printf '{"type":"assistant","requestId":"%s","timestamp":"%s","effort":"%s","message":{"model":"%s","content":[{"type":"text","text":"SECRET-TEXT"}],"usage":{"input_tokens":0,"output_tokens":%s,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' "$1" "$5" "$4" "$2" "$3"; }
{ turn r1 claude-opus-5-5 1000 xhigh "$now"; turn r1 claude-opus-5-5 1000 xhigh "$now"   # same request twice
  turn r2 claude-sonnet-5-5 1000 high "$now"; turn r3 claude-opus-5-5 99999 xhigh "$old"; } > "$P/s1.jsonl"
turn r4 claude-haiku-4-5 2000 high "$now" > "$P/s1/subagents/agent-x.jsonl"
printf '{"agentType":"pstack-cc:read-only"}' > "$P/s1/subagents/agent-x.meta.json"

out="$(CLAUDE_CONFIG_DIR="$T" python3 "$U" --days 7)"
# opus 1000 out * 2 = 2000, sonnet 1000 * 1 = 1000, haiku 2000 * 0.5 = 1000 -> 50/25/25
eq "a repeated requestId counts once"      "$(grep -E '^  opus ' <<<"$out" | awk '{print $2}')" "50.0%"
eq "sonnet weighs half of opus"            "$(grep -E '^  sonnet ' <<<"$out" | awk '{print $2}')" "25.0%"
eq "subagents are attributed by type"      "$(grep -c 'pstack-cc:read-onl' <<<"$out")" "1"
eq "subagent share is reported"            "$(grep -E '^  subagents' <<<"$out" | awk '{print $2}')" "25.0%"
eq "turns outside the window are skipped"  "$(grep -c '99,999' <<<"$out")" "0"
eq "message text is never printed"         "$(grep -c 'SECRET-TEXT' <<<"$out")" "0"
eq "xhigh-heavy spend gets the effort tip" "$(grep -c '/effort high' <<<"$out")" "1"
eq "--project filters"                     "$(CLAUDE_CONFIG_DIR="$T" python3 "$U" --project nomatch | grep -c 'No assistant turns')" "1"

rm -rf "$T"
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
