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

# A second tree: context per call, which idle-gap writes count as an expired cache, a workflow agent.
Q="$T/q/projects/-Users-me-app"; W="$Q/s2/subagents/workflows/wf_1"; mkdir -p "$W"
gap="$(python3 -c 'import datetime;print((datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(minutes=10)).isoformat())')"
cached() { # requestId cache_read cache_creation timestamp
  printf '{"type":"assistant","requestId":"%s","timestamp":"%s","message":{"model":"claude-sonnet-5-5","usage":{"input_tokens":0,"output_tokens":0,"cache_read_input_tokens":%s,"cache_creation_input_tokens":%s}}}\n' "$1" "$4" "$2" "$3"; }
{ cached q1 200000 0 "$gap"; cached q2 0 300000 "$now"; } > "$Q/s2.jsonl"   # main session: not counted
{ cached y1 1000 0 "$gap"; cached y2 0 40000 "$now"; } > "$W/agent-y.jsonl"     # expired: counted
{ cached z1 1000 0 "$gap"; cached z2 100000 40000 "$now"; } > "$W/agent-z.jsonl" # cache still read: growth
printf '{"agentType":"pstack-cc:poteto-agent"}' > "$W/agent-y.meta.json"
out="$(CLAUDE_CONFIG_DIR="$T/q" python3 "$U" --days 7)"
eq "context per call is averaged"            "$(grep -E '^  in main sessions' <<<"$out" | awk '{print $5}')" "250k"
eq "p90 is the 90th-percentile call"         "$(grep -E '^  in main sessions' <<<"$out" | awk '{print $6}')" "300k"
eq "only an expired subagent cache counts"   "$(grep -c 'idle gap: 1 call,' <<<"$out")" "1"
eq "a large context gets the compaction tip" "$(grep -c 'autoCompactWindow' <<<"$out")" "1"
eq "idle rewrites get the cache TTL tip"     "$(grep -c 'subagentPromptCacheTtl' <<<"$out")" "1"
eq "workflow agents are attributed"          "$(grep -c 'pstack-cc:poteto-a' <<<"$out")" "1"

# A third tree: a 1-hour cache write costs 2x input, a 5-minute one 1.25x.
R="$T/r/projects/-Users-me-app"; mkdir -p "$R/s3/subagents"; : > "$R/s3.jsonl"
written() { # ttl
  printf '{"type":"assistant","requestId":"w-%s","timestamp":"%s","message":{"model":"claude-sonnet-5-5","usage":{"input_tokens":0,"output_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":100000,"cache_creation":{"ephemeral_%s_input_tokens":100000}}}}\n' "$1" "$now" "$1"; }
written 1h > "$R/s3/subagents/agent-h.jsonl"; printf '{"agentType":"hour"}' > "$R/s3/subagents/agent-h.meta.json"
written 5m > "$R/s3/subagents/agent-f.jsonl"; printf '{"agentType":"five"}' > "$R/s3/subagents/agent-f.meta.json"
out="$(CLAUDE_CONFIG_DIR="$T/r" python3 "$U" --days 7)"
eq "a 1-hour cache write weighs 2x input"    "$(grep -E '^  hour ' <<<"$out" | awk '{print $2}')" "61.5%"

rm -rf "$T"
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
