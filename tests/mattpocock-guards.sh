#!/usr/bin/env bash
# Each guard on the Matt Pocock import must FAIL the build when its one condition is
# broken, and only then. Offline: it works on a scratch copy of transform/, overlay/ and
# both upstream clones, so run it after import.sh has cloned them.
#
# A mutant per guard, each built in a fresh scratch root:
#   unclassified    Matt's plugin.json promotes a skill the manifest does not name
#   vanished        the manifest names a skill Matt's plugin no longer promotes
#   collision       a core target already exists among pstack's generated skills
#   merge-overwrite a merged skill's extra file would overwrite a pstack file
#   reworded        an EDITS anchor no longer matches upstream's text
#   tdd-drift       Matt rewrites the tdd SKILL.md the merged overlay replaces
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -d "$REPO/upstream-mattpocock/.git" ] && [ -d "$REPO/upstream/pstack" ] || {
  echo "run ./import.sh first: it clones both upstreams"; exit 2; }
pass=0; fail=0
check() {  # <name> <want exit> <want text> <got exit> <got output>
  if [ "$4" = "$2" ] && grep -qF -- "$3" <<<"$5"; then
    pass=$((pass+1)); printf '  ok    %s\n' "$1"
  else
    fail=$((fail+1)); printf '  FAIL  %s (want exit %s with %q, got exit %s)\n%s\n' "$1" "$2" "$3" "$4" "$5"
  fi
}

# A root in the state mattpocock.py runs in: pstack's skills copied, Matt's not yet.
# An explicit template: macOS mktemp ignores $TMPDIR without one. An empty R would aim
# every write below at /, so a failed mktemp ends the run.
fresh() {
  R="$(mktemp -d "${TMPDIR:-/tmp}/mattpocock-guards.XXXXXX")" && [ -d "$R" ] || {
    echo "mktemp failed; refusing to build a scratch root"; exit 2; }
  mkdir -p "$R/plugins/pstack-cc"
  cp -R "$REPO/transform" "$REPO/overlay" "$R/"
  cp -R "$REPO/upstream-mattpocock" "$R/upstream-mattpocock"
  mkdir -p "$R/upstream"; ln -s "$REPO/upstream/pstack" "$R/upstream/pstack"
  cp -R "$REPO/upstream/pstack/skills" "$R/plugins/pstack-cc/skills"
}
run_import() { out="$(python3 "$R/transform/mattpocock.py" 2>&1)"; code=$?; }
run_audit()  { : > "$R/counts"; out="$(python3 "$R/transform/audit.py" "$R/counts" 2>&1)"; code=$?; }
promote() { python3 - "$R/upstream-mattpocock/.claude-plugin/plugin.json" "$1" "$2" <<'EOF'
import json, sys
p, op, skill = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(p))
d["skills"] = d["skills"] + [skill] if op == "add" else [s for s in d["skills"] if s != skill]
json.dump(d, open(p, "w"), indent=2)
EOF
}

fresh; run_import
check "clean import passes"   0 "18 imported, 1 merged" "$code" "$out"
run_audit
check "clean audit passes"    0 "overlay:" "$code" "$out"

fresh; promote add ./skills/engineering/brand-new; run_import
check "unclassified promoted skill fails" 1 "promotes skills/engineering/brand-new" "$code" "$out"

fresh; promote remove ./skills/engineering/wizard; run_import
check "vanished manifest skill fails"     1 "no longer promotes. Read upstream" "$code" "$out"

fresh; mkdir "$R/plugins/pstack-cc/skills/grilling"; run_import
check "collision with a pstack skill fails" 1 "would land on skills/grilling" "$code" "$out"

fresh; touch "$R/plugins/pstack-cc/skills/tdd/tests.md"; run_import
check "merge overwriting a pstack file fails" 1 "tests.md would overwrite" "$code" "$out"

fresh; sed -i.bak 's/by calling the Skill tool with "prototype"/by invoking "prototype"/' \
  "$R/upstream-mattpocock/skills/engineering/wayfinder/SKILL.md"; run_import
check "reworded edit anchor fails"        1 "matched 0 time(s), expected 1" "$code" "$out"

fresh; printf '\n- A new upstream rule.\n' >> "$R/upstream-mattpocock/skills/engineering/tdd/SKILL.md"; run_audit
check "drift in Matt's tdd fails the audit" 1 "OVERLAY DRIFT mattpocock/skills/engineering/tdd/SKILL.md" "$code" "$out"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
