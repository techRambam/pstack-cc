#!/usr/bin/env bash
# The dead-rule audit must keep naming the right rules when rules.pl gains or loses a
# line. optional-rules.txt keys each rule by a substring of its line, so each mutant
# below edits a scratch copy of rules.pl and checks what audit.py reports. Offline:
# the overlay half of the audit reads both upstream clones, so run import.sh first.
#
#   shifted      deleting the first rule still silences the same rules, and a dead rule
#                below the deletion is reported by its own line and text
#   gone         an optional entry whose rule was deleted fails the build
#   ambiguous    an optional entry that two rules contain fails the build
#   stale-ref    a [[cross-reference]] whose rule was deleted fails the build
#
# Every mutant picks its rules from the current rules.pl and optional-rules.txt, so an
# upstream sync that adds, deletes or silences rules leaves this test valid.
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
# Read the scratch root's rules.pl and optional-rules.txt, or edit its rules.pl:
#   first-free     print the first rule that no entry or cross-reference names
#   last-free      print the last such rule
#   entry          print the first optional entry
#   ref            print the first cross-reference
#   line <text>    print the line number of the one rule containing <text>
#   shown <text>   print that rule as audit.py quotes it, cut to 88 characters
#   drop <text>    delete the one rule containing <text>
#   twice <text>   append a second copy of the one rule containing <text>
rules() { python3 - "$R/transform/rules.pl" "$R/transform/optional-rules.txt" "$@" <<'EOF'
import pathlib, re, sys
rules_pl, optional, what, *arg = sys.argv[1:]
path = pathlib.Path(rules_pl)
lines = path.read_text().splitlines(keepends=True)
rules = [(n, l.strip()) for n, l in enumerate(lines, 1) if re.match(r"^s[{/]", l.strip())]
entries, refs = [], []
for l in pathlib.Path(optional).read_text().splitlines():
    l = l.strip()
    if l.startswith("#"):
        refs += re.findall(r"\[\[(.+?)\]\]", l)
    elif l:
        entries.append(l)
free = [t for n, t in rules if not any(k in t for k in entries + refs)]
if arg:
    hits = [(n, t) for n, t in rules if arg[0] in t]
    assert len(hits) == 1, f"{len(hits)} rules contain {arg[0]!r}, expected 1"
    n, text = hits[0]
if what == "first-free": print(free[0])
elif what == "last-free": print(free[-1])
elif what == "entry": print(entries[0])
elif what == "ref": print(refs[0])
elif what == "line": print(n)
elif what == "shown": print(text[:88])
elif what == "drop":
    del lines[n - 1]
    path.write_text("".join(lines))
elif what == "twice":
    path.write_text("".join(lines) + text + "\n")
else: sys.exit(f"rules: unknown command {what}")
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

opt="$(grep -cv '^[[:space:]]*\(#\|$\)' "$REPO/transform/optional-rules.txt")"

fresh; run_audit
check "clean audit passes" 0 "0 dead, $opt marked optional" "$code" "$out"

# Deleting the first rule shifts every line below it; the last free rule then goes dead.
fresh; first="$(rules first-free)"; last="$(rules last-free)"
rules drop "$first"; run_audit "$last"
check "shift: same $opt rules silenced" 1 "1 dead, $opt marked optional" "$code" "$out"
check "shift: dead rule named by its own line" 1 \
  "DEAD RULE rules.pl:$(rules line "$last") fired 0 times -- upstream may have reworded it: $(rules shown "$last")" \
  "$code" "$out"

fresh; key="$(rules entry)"; rules drop "$key"; run_audit
check "deleted optional rule fails" 1 "\`$key\` matches 0 rules" "$code" "$out"

fresh; key="$(rules entry)"; rules twice "$key"; run_audit
check "ambiguous optional key fails" 1 "\`$key\` matches 2 rules" "$code" "$out"

fresh; ref="$(rules ref)"; rules drop "$ref"; run_audit
check "stale cross-reference fails" 1 "cross-reference: \`$ref\` matches 0 rules" "$code" "$out"

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
