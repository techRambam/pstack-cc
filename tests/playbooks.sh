#!/usr/bin/env bash
# shellcheck disable=SC2016
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN="$ROOT/plugins/pstack-cc"
PB="$PLUGIN/bin/pstack-playbook"
pass=0; fail=0
T="$(mktemp -d "${TMPDIR:-/tmp}/pstack-playbooks.XXXXXX")" && [ -d "$T" ] || { echo "mktemp failed"; exit 2; }
trap 'rm -rf "$T"' EXIT

eq() {
  local name="$1" got="$2" want="$3"
  if [ "$got" = "$want" ]; then pass=$((pass+1)); printf '  ok    %s\n' "$name"
  else fail=$((fail+1)); printf '  FAIL  %s\n        want %q\n        got  %q\n' "$name" "$want" "$got"; fi
}
has() {
  local name="$1" haystack="$2" needle="$3"
  case "$haystack" in *"$needle"*) pass=$((pass+1)); printf '  ok    %s\n' "$name" ;;
  *) fail=$((fail+1)); printf '  FAIL  %s (no %q in:)\n%s\n' "$name" "$needle" "$haystack" ;; esac
}
js() { node --input-type=module -e "import * as m from '$PLUGIN/lib/playbooks.mjs'; const pbs = m.loadPlaybooks('$PLUGIN'); $1"; }

node "$PB" check >/dev/null 2>&1; eq "every playbook holds the invariants" "$?" "0"
node "$PB" check --table > "$T/table.tsv"
if diff -u "$ROOT/tests/playbooks.golden.tsv" "$T/table.tsv"; then eq "derived classes match the golden table" ok ok
else
  eq "derived classes match the golden table" diff ok
  echo "  if the change is intended, regenerate: node plugins/pstack-cc/bin/pstack-playbook check --table > tests/playbooks.golden.tsv"
fi

eq "tags per playbook match the 2026-10-21 table" "$(js '
  const t = pbs.map(p => [p.slug, ...["critical","commit","merge"].map(k => p.steps.filter(s => s.tags.has(k)).map(s => s.n).join(","))].join(":"));
  console.log(t.filter(r => !/^[^:]+:::$/.test(r)).join(" "))')" \
  "authoring-a-skill::1: autonomous-run::3: autopilot-full:4:2: autopilot-stack::1: babysit::5: bug-fix:1,4:3: deciding::3: feature:4,5:4: hillclimb::5: orchestrate::3: pause-safely::3: perf-issue:4:3: prototype:5:3: refactoring:6:5: session-pickup:5:: shipping:1::4 visual-parity:4:3:"

eq "boundaries derive from tags and the Opening a PR sentence" "$(js '
  const at = (i) => i === null ? "-" : i + 1;
  console.log(["feature","refactoring","shipping","investigation","deciding"].map(s => pbs.find(p => p.slug === s))
    .map(p => `${p.slug}:${at(p.commitAt)}/${at(p.pushAt)}/${at(p.mergeAt)}/${p.writes}`).join(" "))')" \
  "feature:4/7/7/true refactoring:5/8/8/true shipping:6/-/4/false investigation:4/-/4/false deciding:3/-/6/true"

plan="$(node "$PB" plan feature)"
eq "plan feature prints the seven steps" "$(printf %s "$plan" | node -e 'const p=JSON.parse(require("fs").readFileSync(0,"utf8"));console.log(p.title, p.steps.length, p.steps[2].steps.length)')" "Feature 7 4"
eq "the Opening a PR step carries the three review sub-steps" \
  "$(printf %s "$plan" | node -e 'const p=JSON.parse(require("fs").readFileSync(0,"utf8"));console.log(p.steps[6].steps.map(s=>s.text).join("|"))')" \
  "/pstack-cc:unslop over the diff|/no-comments|interrogate on the PR diff"
has "a critical step prints with its tags" "$plan" '"[critical] Verify on the matching surface."'
node "$PB" plan no-such-playbook >/dev/null 2>&1; eq "an unknown playbook is refused" "$?" "2"

match() { js "const f = pbs.find(p => p.slug === 'feature'); const s = (text, status = 'done', extra = {}) => ({ text, status, ...extra });
  const steps = $1; const r = m.matchPlan(steps, pbs); console.log(r.ok ? 'ok ' + r.playbook.slug : r.why + (r.step ? ' ' + r.step.n : '') + (r.first ? ' ' + r.first : ''))"; }
FEATURE='f.steps.map(x => s(x.display))'
eq "every playbook step's shortest prefix matches" "$(match "$FEATURE")" "ok feature"
eq "an empty plan is no plan" "$(match '[]')" "no-plan"
eq "a first step naming no playbook" "$(match '[s("Make a plan")]')" "no-playbook Make a plan"
eq "a reworded step is a missing step" "$(match "[...$FEATURE.slice(0, 2), s('Make a checkpoint'), ...$FEATURE.slice(3)]")" "missing-step 3"
eq "task steps may sit between playbook steps" "$(match "[...$FEATURE.slice(0, 3), s('wire the CLI'), ...$FEATURE.slice(3)]")" "ok feature"
eq "the whole step line matches" "$(match "[...$FEATURE.slice(0, 4), s(f.steps[4].prefixes.at(-1)), ...$FEATURE.slice(5)]")" "ok feature"
eq "tags, emphasis and backticks do not count" "$(match "[...$FEATURE.slice(0, 4), s('[critical] **Verify** on the \`matching\` surface.'), ...$FEATURE.slice(5)]")" "ok feature"
eq "curly quotes read as straight ones" "$(match "[...$FEATURE.slice(0, 4), s('Verify on the matching surface. \u201CInconclusive\u201D or wrong-surface is not a pass.'), ...$FEATURE.slice(5)]")" "ok feature"
eq "changed words do not match" "$(match "[...$FEATURE.slice(0, 4), s('Verify on the real surface.'), ...$FEATURE.slice(5)]")" "missing-step 5"
eq "a prefix under five words does not match" "$(js "const b = pbs.find(p => p.slug === 'bug-fix');
  const steps = b.steps.map(x => ({ text: x.display, status: 'done' })); steps[2] = { text: 'Plan the fix.', status: 'done' };
  const r = m.matchPlan(steps, pbs); console.log(r.why, r.step?.n)")" "missing-step 3"

eq "a TodoWrite skip suffix reads as skipped with its reason" "$(js "const f = pbs.find(p => p.slug === 'feature');
  const steps = f.steps.map(x => ({ text: x.display, status: 'done' })); steps[1].text += ' skip: one-file change, no design fork';
  const r = m.matchPlan(steps, pbs); console.log(r.rows[1].status, '|', r.rows[1].reason)")" "skipped | one-file change, no design fork"
eq "skipped review sub-steps reach reviewSkips, interrogate included" "$(js "const f = pbs.find(p => p.slug === 'feature');
  const steps = f.steps.map(x => ({ text: x.display, status: 'done' }));
  steps[6].steps = [{ text: '/pstack-cc:unslop over the diff', status: 'skipped', reason: 'no prose in the diff' },
    { text: '/no-comments', status: 'done' }, { text: 'interrogate on the PR diff', status: 'skipped', reason: 'tiny' }];
  const r = m.matchPlan(steps, pbs); console.log([...r.reviewSkips].map(e => e.join('=')).join(' '))")" "unslop=no prose in the diff interrogate=tiny"
eq "TodoWrite review rows after Opening a PR reach reviewSkips" "$(js "const f = pbs.find(p => p.slug === 'feature');
  const todos = m.planFor(f, { todowrite: true }).todos.map(t => ({ ...t, status: 'completed' }));
  todos.find(t => t.content === '/no-comments').content += ' skip: docs-only diff, no code comments';
  const r = m.matchPlan(m.planStepsFromTodos(todos), pbs); console.log(r.ok, [...r.reviewSkips].map(e => e.join('=')).join(' '))")" "true no-comments=docs-only diff, no code comments"

eq "reasonProblem accepts a real reason" "$(js "console.log(m.reasonProblem('docs-only diff, no comments'))")" "null"
has "reasonProblem refuses a stock phrase" "$(js "console.log(m.reasonProblem('n/a'))")" "stock phrase"
has "reasonProblem refuses a thin reason" "$(js "console.log(m.reasonProblem('not useful'))")" "under three words"

mutant() {
  local name="$1" playbook="$2" sed_expr="$3" want_msg="$4"
  local R="$T/mutant-$pass-$fail"
  mkdir -p "$R/skills/poteto-mode"
  cp -R "$PLUGIN/bin" "$PLUGIN/lib" "$R/"
  cp -R "$PLUGIN/skills/poteto-mode/playbooks" "$R/skills/poteto-mode/"
  sed -i.bak -e "$sed_expr" "$R/skills/poteto-mode/playbooks/$playbook" && rm "$R/skills/poteto-mode/playbooks/$playbook.bak"
  local out rc; out="$(node "$R/bin/pstack-playbook" check 2>&1)"; rc=$?
  if [ "$rc" = 2 ] && [[ "$out" == *"$want_msg"* ]]; then pass=$((pass+1)); printf '  ok    %s\n' "$name"
  else fail=$((fail+1)); printf '  FAIL  %s (rc %s)\n%s\n' "$name" "$rc" "$out"; fi
}
mutant "a second [commit] tag fails the check" feature.md 's/^2\. /2. [commit] /' "2 steps tagged [commit]"
mutant "a second [merge] tag fails the check" shipping.md 's/^5\. /5. [merge] /' "2 steps tagged [merge]"
mutant "a [commit] step after the PR step fails the check" feature.md 's/^2\. \(.*\)$/2. \1 Run **Opening a PR**./; s/^7\. Run \*\*Opening a PR\*\*\./7. Done./' "comes after step 2"
mutant "a review missing from opening-a-pr fails the check" opening-a-pr.md 's/`\/no-comments`/`\/no-comment`/' "no longer names"
mutant "reordered reviews in opening-a-pr fail the check" opening-a-pr.md 's/^\*\*PRs\.\*\* /**PRs.** Start with `interrogate`. /' "no longer names"
mutant "broken numbering fails the load" feature.md 's/^5\. /9. /' "breaks the numbering"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
