#!/usr/bin/env bash
# The dead-rule audit must keep naming the right rules when rules.pl gains or loses a
# line. optional-rules.txt keys each rule by a substring of its line, so each mutant
# below edits a scratch copy of rules.pl and checks what audit.py reports. Offline:
# the overlay half of the audit reads both upstream clones, so run import.sh first.
#
#   shifted      deleting a rule above the optional ones still silences the same rules,
#                and a dead rule below the deletion is reported by its own line and text
#   gone         an optional entry whose rule was deleted fails the build
#   ambiguous    an optional entry that two rules contain fails the build
#   stale-ref    a [[cross-reference]] whose rule was deleted fails the build
# Backticks in the expected texts below are literal, so single quotes are correct.
# shellcheck disable=SC2016
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -d "$REPO/upstream-mattpocock/.git" ] && [ -d "$REPO/upstream/pstack" ] || {
  echo "run ./import.sh first: it clones both upstreams"; exit 2; }
pass=0; fail=0
# Whitespace runs collapse to one space on both sides, so <want text> may span lines of
# the output. grep -F would read a multi-line pattern as alternatives, any one enough.
check() {  # <name> <want exit> <want text> <got exit> <got output>
  local want got
  want="$(printf %s "$3" | tr -s ' \n' '  ')"; got="$(printf %s "$5" | tr -s ' \n' '  ')"
  if [ "$4" = "$2" ] && [[ "$got" == *"$want"* ]]; then
    pass=$((pass+1)); printf '  ok    %s\n' "$1"
  else
    fail=$((fail+1)); printf '  FAIL  %s (want exit %s with %q, got exit %s)\n%s\n' "$1" "$2" "$3" "$4" "$5"
  fi
}

ROOTS=()
trap 'rm -rf ${ROOTS[@]+"${ROOTS[@]}"}' EXIT
# An explicit template: macOS mktemp ignores $TMPDIR without one. An empty R would aim
# every write below at /, so a failed mktemp ends the run.
fresh() {
  R="$(mktemp -d "${TMPDIR:-/tmp}/rule-keys.XXXXXX")" && [ -d "$R" ] || {
    echo "mktemp failed; refusing to build a scratch root"; exit 2; }
  ROOTS+=("$R")
  cp -R "$REPO/transform" "$REPO/overlay" "$R/"
  mkdir -p "$R/upstream"
  ln -s "$REPO/upstream/pstack" "$R/upstream/pstack"
  ln -s "$REPO/upstream-mattpocock" "$R/upstream-mattpocock"
}
# Drop the rules.pl lines containing <text>.
drop() { python3 - "$R/transform/rules.pl" "$1" <<'EOF'
import pathlib, sys
p, text = pathlib.Path(sys.argv[1]), sys.argv[2]
lines = p.read_text().splitlines(keepends=True)
kept = [l for l in lines if text not in l]
assert len(kept) < len(lines), f"no rules.pl line contains {text!r}"
p.write_text("".join(kept))
EOF
}
# A counts file in the format build-counting-rules.py emits: every rule fired once,
# except the optional ones and any line containing one of the arguments.
run_audit() {
  python3 - "$R/transform/rules.pl" "$R/transform/optional-rules.txt" "$@" > "$R/counts" <<'EOF'
import pathlib, re, sys
rules, optional, dead = sys.argv[1], sys.argv[2], sys.argv[3:]
dead += [l.strip() for l in pathlib.Path(optional).read_text().splitlines()
         if l.strip() and not l.strip().startswith("#")]
for n, line in enumerate(pathlib.Path(rules).read_text().splitlines(), 1):
    if re.match(r"^s[{/]", line.strip()):
        print(f"{n}\t{0 if any(d in line for d in dead) else 1}")
EOF
  out="$(python3 "$R/transform/audit.py" "$R/counts" 2>&1)"; code=$?
}

fresh; run_audit
check "clean audit passes" 0 "0 dead, 12 marked optional" "$code" "$out"

fresh; drop 'gpt-5\.6-sol-max'; run_audit 'gh pr merge (\S+) --squash'
check "shift: same 12 rules silenced"   1 "1 dead, 12 marked optional" "$code" "$out"
check "shift: dead rule named by its own line" 1 \
  'DEAD RULE rules.pl:27 fired 0 times -- upstream may have reworded it: s{gh pr merge (\S+) --squash}' \
  "$code" "$out"

fresh; drop 'grok-4\.6-fast'; run_audit
check "deleted optional rule fails" 1 '`grok-4\.6-fast` matches 0 rules' "$code" "$out"

fresh; printf 's{\\bin Cursor\\b}{inside Claude Code}g;\n' >> "$R/transform/rules.pl"; run_audit
check "ambiguous optional key fails" 1 '`\bin Cursor\b` matches 2 rules' "$code" "$out"

fresh; drop 's{\bTask tool\b}'; run_audit
check "stale cross-reference fails" 1 'cross-reference: `\bTask tool\b` matches 0 rules' "$code" "$out"

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
