#!/usr/bin/env bash
# shellcheck disable=SC2016
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN="$ROOT/plugins/pstack-cc"
RC="$PLUGIN/bin/pstack-receipt"
pass=0; fail=0
T="$(mktemp -d "${TMPDIR:-/tmp}/pstack-receipts.XXXXXX")" && [ -d "$T" ] || { echo "mktemp failed"; exit 2; }
trap 'rm -rf "$T"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
mkdir -p "$T/bin"
cat > "$T/bin/gh" <<'EOF'
#!/usr/bin/env bash
[ "${GH_FAIL:-}" = 1 ] && { echo "HTTP 404: Not Found" >&2; exit 1; }
[ "$1 $2" = "pr view" ] || { echo "unexpected gh call: $*" >&2; exit 1; }
printf '%s\n' "$GH_PR_JSON"
EOF
chmod +x "$T/bin/gh"
export PATH="$T/bin:$PATH"

expect() {
  local name="$1" want_rc="$2" want="$3" dir="$4"; shift 4
  local out rc; out="$(cd "$dir" && node "$RC" "$@" 2>&1)"; rc=$?
  if [ "$rc" = "$want_rc" ] && [[ "$out" == *"$want"* ]]; then pass=$((pass+1)); printf '  ok    %s\n' "$name"
  else fail=$((fail+1)); printf '  FAIL  %s (want rc %s with %q, got rc %s)\n%s\n' "$name" "$want_rc" "$want" "$rc" "$out"; fi
}
quiet() { local out; out="$(cd "$W" && node "$RC" "$@" 2>&1)" || { echo "setup step failed: pstack-receipt $*"; echo "$out"; exit 2; }; }

n=0
fixture_repo_with_uncommitted_work() {
  n=$((n+1)); W="$T/repo-$n"; mkdir -p "$W/src" "$W/tests"
  git -C "$W" init -q -b main
  for f in README.md src/x.ts src/y.ts src/z.ts tests/t.ts; do printf 'line one of %s\nline two\n' "$f" > "$W/$f"; done
  git -C "$W" add -A && git -C "$W" commit -qm base
  git -C "$W" checkout -qb feat/x
  echo "implementation" >> "$W/src/x.ts"
}
edit() { for f in "$@"; do echo "edit $RANDOM" >> "$W/$f"; done; }
commit() { git -C "$W" commit -qam "${1:-work}"; }

s2() { quiet begin unslop; }
s3() { edit README.md; quiet finish unslop; }
s4() { commit "implementation"; }
s5() { quiet begin no-comments; }
s6() { edit src/x.ts src/y.ts; quiet finish no-comments --summary "6 kills in 2 files" --deletions 6; }
s7() { commit "drop comments"; }
s8() { quiet begin interrogate; quiet finish interrogate --seat opus=delivered --seat sonnet=delivered --seat gpt-5.6-sol=dropout:timeout --act-on src/x.ts; }
s9() { edit src/x.ts "$@"; commit "fix the finding"; }

fixture_repo_with_uncommitted_work; s2; s3; s4; s5; s6; s7; s8; s9
expect "worked example: the chain covers the pushed code" 0 "chain        ok" "$W" status
expect "worked example: the push head passes too" 0 "chain        ok" "$W" status --rev HEAD
EXAMPLE="$W"

fixture_repo_with_uncommitted_work; s2; s3; s4; s5; s6; s7; s8; s9 src/z.ts
expect "variant a: an edit outside the Act on files is a tail" 2 "edits after interrogate touch src/z.ts, but its Act on findings cite src/x.ts" "$W" status
expect "variant a: a tail reruns every review" 2 "Rerun in order: unslop, no-comments, interrogate." "$W" status

fixture_repo_with_uncommitted_work; s2; s3; s4; edit tests/t.ts; commit "fix a test"; s5; s6; s7; s8; s9
expect "variant b: an edit between two reviews is a gap" 2 "edits between unslop and no-comments touch tests/t.ts, which unslop never saw" "$W" status

fixture_repo_with_uncommitted_work; s2; s3; s4; s5; s6; s7; s8; s9; s5; edit src/y.ts; quiet finish no-comments --summary "1 kill" --deletions 1; commit "rerun"
expect "variant c: rerunning a middle review opens a gap before it" 2 "edits between unslop and no-comments touch src/x.ts" "$W" status
expect "variant c: and asks for every review again" 2 "Rerun in order: unslop, no-comments, interrogate." "$W" status

fixture_repo_with_uncommitted_work; s2; s3; s4; s5; s6; s7; s8; s9
git -C "$W" checkout -q main && echo new > "$W/other.txt" && git -C "$W" add other.txt && git -C "$W" commit -qm "main moves"
git -C "$W" checkout -q feat/x && git -C "$W" rebase -q main
expect "variant d: a rebase onto a newer base is a tail" 2 "edits after interrogate touch other.txt" "$W" status

fixture_repo_with_uncommitted_work; echo "notes" > "$W/scratch.txt"; s2; s3; s4; s5; s6; s7; s8; s9
expect "variant e: the work tree still holds the untracked file" 0 "chain        ok" "$W" status
expect "variant e: the pushed head does not, so it is a tail" 2 "edits after interrogate touch scratch.txt" "$W" status --rev HEAD

fixture_repo_with_uncommitted_work; s2; s3; s4; s5; s6; s7
expect "a missing interrogate reruns only interrogate when nothing moved" 2 "there is no interrogate receipt for this branch. Rerun in order: interrogate." "$W" status
eq_js() {
  local name="$1" script="$2" want="$3"
  local got; got="$(cd "$W" && node --input-type=module -e "import { receiptState } from '$PLUGIN/lib/receipts.mjs'; $script")"
  if [ "$got" = "$want" ]; then pass=$((pass+1)); printf '  ok    %s\n' "$name"
  else fail=$((fail+1)); printf '  FAIL  %s (want %q, got %q)\n' "$name" "$want" "$got"; fi
}
eq_js "interrogate in the skipped set still counts as missing" \
  "const s = receiptState({ cwd: process.cwd(), skipped: ['unslop', 'interrogate'] }); console.log(s.chain.problem.kind, s.chain.problem.step)" \
  "missing interrogate"
expect "status refuses to skip interrogate" 2 "interrogate cannot be skipped" "$W" status --skip interrogate

fixture_repo_with_uncommitted_work; s5; s6; s7; s8
expect "a plan-skipped unslop drops out of the chain" 0 "chain        ok" "$W" status --skip unslop
expect "without the skip, unslop is missing" 2 "there is no unslop receipt" "$W" status

fixture_repo_with_uncommitted_work
expect "finish without begin is refused" 2 "no begin for unslop in this worktree on feat/x" "$W" finish unslop
quiet begin interrogate; edit src/y.ts
expect "finish interrogate after the tree moved is refused" 2 "the tree changed during the interrogate run (src/y.ts)" "$W" finish interrogate --seat opus=delivered
quiet begin interrogate
expect "finish interrogate with no delivered seat is refused" 2 "no seat delivered" "$W" finish interrogate --seat opus=dropout:timeout --seat sonnet=dropout:429
expect "finish interrogate with no seat is refused" 2 "needs one --seat" "$W" finish interrogate
expect "a malformed seat is refused" 2 "must read <model>=delivered" "$W" finish interrogate --seat opus
expect "an act-on path outside the worktree is refused" 2 "is outside the worktree" "$W" finish interrogate --seat opus=delivered --act-on ../elsewhere.ts
quiet begin no-comments
expect "finish no-comments without a summary is refused" 2 "needs --summary" "$W" finish no-comments
expect "a deletion count that is not a number is refused" 2 "is not a count" "$W" finish no-comments --summary x --deletions six
expect "there is no skip verb" 2 "Mark the review's sub-step skipped in the plan" "$W" skip no-comments --reason "docs only change"
expect "an unknown step is refused" 2 'unknown review step "lint"' "$W" begin lint
expect "an unknown flag is refused" 2 "unknown flag --force" "$W" begin unslop --force x
expect "a base that names no commit is refused" 2 "--base nowhere names no commit" "$W" begin unslop --base nowhere
mkdir -p "$T/plain"
expect "outside a git work tree is refused" 2 "is not inside a git work tree" "$T/plain" begin unslop
git -C "$W" checkout -q --detach
expect "a detached HEAD is refused" 2 "HEAD is detached" "$W" begin unslop
git -C "$W" checkout -q feat/x

fixture_repo_with_uncommitted_work; quiet begin unslop; quiet begin unslop
eq_js "begin twice leaves one open record" "import fs from 'node:fs'; console.log(fs.readdirSync('.git/pstack-receipts/feat%2Fx/open').length)" "1"
quiet finish unslop; quiet begin unslop; quiet finish unslop
eq_js "the same receipt written twice is one file" "import fs from 'node:fs'; console.log(fs.readdirSync('.git/pstack-receipts/feat%2Fx').filter(f => f.startsWith('unslop.')).length)" "1"

W="$EXAMPLE"
HEAD_OID="$(git -C "$W" rev-parse HEAD)"
pr_json() { printf '{"number":12,"headRefName":"feat/x","headRefOid":"%s","baseRefName":"main"}' "$1"; }
export GH_PR_JSON; GH_PR_JSON="$(pr_json "$HEAD_OID")"
expect "status before a verdict says none" 0 "verdict      none" "$W" status
expect "a verdict on the PR's own branch is refused" 2 "the PR's own branch" "$W" verdict PASS --pr 12 --by "sonnet verifier" --ran "ran the CLI"
git -C "$W" worktree add -q --detach "$T/verify" "$HEAD_OID~1"
expect "a verdict off the PR head is refused" 2 "but PR #12's head is" "$T/verify" verdict PASS --pr 12 --by "sonnet verifier" --ran "ran the CLI"
git -C "$T/verify" checkout -q --detach "$HEAD_OID"
expect "a verdict that is not PASS, PASS+NOTES or FAIL is refused" 2 "verdict must be one of" "$T/verify" verdict OK --pr 12 --by v --ran r
expect "a verdict without --by is refused" 2 "needs --by" "$T/verify" verdict PASS --pr 12 --ran r
GH_FAIL=1 expect "a gh failure is refused" 2 '`gh pr view 12` failed' "$T/verify" verdict PASS --pr 12 --by v --ran r
expect "a verifier at the PR head records its verdict" 0 "verdict PASS+NOTES for PR #12 written" "$T/verify" verdict PASS+NOTES --pr 12 --by "sonnet verifier" --ran "ran status in the example repo"
expect "status reads the verdict" 0 "verdict      PASS+NOTES for PR #12 by sonnet verifier" "$W" status

BEFORE_WS="$(git -C "$W" diff main HEAD | git patch-id --stable | cut -d' ' -f1)"
sed -i.bak '$s/$/ /' "$W/src/y.ts" && rm "$W/src/y.ts.bak" && commit "trailing space"
AFTER_WS="$(git -C "$W" diff main HEAD | git patch-id --stable | cut -d' ' -f1)"
if [ "$BEFORE_WS" = "$AFTER_WS" ]; then pass=$((pass+1)); echo "  ok    the next case is whitespace-only: --stable would keep the verdict"
else fail=$((fail+1)); echo "  FAIL  the whitespace commit changed the --stable patch id, so it tests nothing"; fi
expect "a whitespace-only commit makes the verdict stale" 2 "verdict      stale" "$W" status

NEW_OID="$(git -C "$W" rev-parse HEAD)"; GH_PR_JSON="$(pr_json "$NEW_OID")"
git -C "$T/verify" checkout -q --detach "$NEW_OID"
expect "a FAIL verdict records" 0 "verdict FAIL for PR #12 written" "$T/verify" verdict FAIL --pr 12 --by "sonnet verifier" --ran "drove it"
expect "status reports the FAIL" 2 "verdict      FAIL for PR #12" "$W" status
expect "a later PASS for the same patch wins" 0 "verdict PASS for PR #12 written" "$T/verify" verdict PASS --pr 12 --by "opus verifier" --ran "drove it again"
expect "a repeated FAIL, word for word, records again" 0 "verdict FAIL for PR #12 written" "$T/verify" verdict FAIL --pr 12 --by "sonnet verifier" --ran "drove it"
expect "status reports the repeated FAIL as the newest" 2 "verdict      FAIL for PR #12" "$W" status
expect "a repeated PASS, word for word, records again" 0 "verdict PASS for PR #12 written" "$T/verify" verdict PASS --pr 12 --by "opus verifier" --ran "drove it again"
expect "PASS, FAIL, PASS ends at PASS" 2 "verdict      PASS for PR #12 by opus verifier" "$W" status
git -C "$W" checkout -q main && echo unrelated > "$W/unrelated.txt" && git -C "$W" add unrelated.txt && git -C "$W" commit -qm "main moves"
git -C "$W" checkout -q feat/x && git -C "$W" rebase -q main
expect "a rebase that keeps the patch keeps the verdict" 2 "verdict      PASS for PR #12 by opus verifier" "$W" status

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
