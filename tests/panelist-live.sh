#!/usr/bin/env bash
# LIVE test: real calls to real vendors. Costs org quota, so import.sh does NOT
# run it. Run by hand after changing bin/panelist or when a vendor looks broken.
#
#   bash tests/panelist-live.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/plugins/pstack-cc"
T="$(mktemp -d "${TMPDIR:-/tmp}/pstack-test.XXXXXX")" || exit 2; pass=0; fail=0

cat > "$T/schema.json" <<'EOF'
{"$schema":"http://json-schema.org/draft-07/schema#","type":"object",
 "properties":{"verdict":{"type":"string"},"reason":{"type":"string"},
               "tags":{"type":"array","items":{"type":"string"}}},
 "required":["verdict","reason"],"additionalProperties":false}
EOF
printf 'Is calling sort() twice in a row on the same list a real bug? verdict, reason under 15 words, 1-2 tags.\n' > "$T/p.txt"

try() { # label model
  local out
  out="$(python3 "$ROOT/bin/panelist" run -m "$2" -p "$T/p.txt" --schema "$T/schema.json" 2>&1)"
  if printf '%s' "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["verdict"] and d["reason"]' 2>/dev/null; then
    pass=$((pass+1)); printf '  ok    %-12s %s\n' "$1" "$(printf '%s' "$out" | head -c 70)"
  else
    fail=$((fail+1)); printf '  FAIL  %-12s %s\n' "$1" "$(printf '%s' "$out" | head -c 160)"
  fi
}

echo "live panel round-trips (one plain JSON Schema, converted per vendor):"
try openai     gpt-5.6-sol
try google     gemini-3-flash-preview
try groq       "groq:openai/gpt-oss-120b"
try mistral    "mistral:ministral-8b-latest"
try openrouter "openrouter:deepseek/deepseek-v4-flash-0731:free"
try hf-llama   "huggingface:meta-llama/Llama-3.3-70B-Instruct"
try hf-cohere  "huggingface:CohereLabs/command-a-reasoning-08-2025"

echo; echo "guard rails:"
out="$(python3 "$ROOT/bin/panelist" run -m opus -p "$T/p.txt" 2>&1)"
if printf '%s' "$out" | grep -q 'Agent tool'; then pass=$((pass+1)); printf '  ok    refuses to route an Anthropic model\n'
else fail=$((fail+1)); printf '  FAIL  Anthropic guard: %s\n' "$out"; fi
out="$(python3 "$ROOT/bin/panelist" run -m totally-made-up -p "$T/p.txt" 2>&1)"
if printf '%s' "$out" | grep -q 'unknown model'; then pass=$((pass+1)); printf '  ok    rejects an unknown model\n'
else fail=$((fail+1)); printf '  FAIL  unknown-model guard: %s\n' "$out"; fi

rm -rf "$T"
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
