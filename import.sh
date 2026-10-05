#!/usr/bin/env bash
# Regenerate pstack-cc from upstream pstack.
#
# This is the ONLY way skills/ and agents/ are produced. Never hand-edit them:
# edit transform/rules.pl (deterministic substitutions) or overlay/ (whole-file
# replacements for things a regex cannot fix), then re-run.
#
# Updating to a newer upstream:  edit UPSTREAM_REF, run, read the diff.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPSTREAM_REPO="https://github.com/cursor/plugins.git"
UPSTREAM_REF="e43c7ee26e0038c6c1fa8380dd34ce86ff94cb2a"
SRC="$ROOT/upstream/pstack"
# The installable plugin. Everything else in this repo (transform/, tests/, docs/,
# reference/) is the generator and stays out of every install.
PLUGIN="$ROOT/plugins/pstack-cc"

ACCEPT=""
for a in "$@"; do [ "$a" = "--accept-overlay" ] && ACCEPT="--accept-overlay"; done

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mFAIL:\033[0m %s\n' "$*" >&2; exit 1; }

# --- 1. fetch upstream at the pinned ref --------------------------------
if [ ! -d "$ROOT/upstream/.git" ]; then
  log "cloning upstream"
  git clone --filter=blob:none --sparse -q "$UPSTREAM_REPO" "$ROOT/upstream"
  git -C "$ROOT/upstream" sparse-checkout set pstack
fi
git -C "$ROOT/upstream" fetch -q origin "$UPSTREAM_REF" 2>/dev/null || git -C "$ROOT/upstream" fetch -q origin
git -C "$ROOT/upstream" checkout -q "$UPSTREAM_REF"
log "upstream at $(git -C "$ROOT/upstream" rev-parse --short HEAD)"
[ -d "$SRC" ] || die "no pstack/ at that ref"

# --- 2. clean copy ------------------------------------------------------
log "copying skills/ agents/"
rm -rf "$PLUGIN/skills" "$PLUGIN/agents"
cp -R "$SRC/skills" "$PLUGIN/skills"
cp -R "$SRC/agents" "$PLUGIN/agents"
cp "$SRC/LICENSE" "$ROOT/LICENSE.upstream"
cp "$SRC/LICENSE" "$PLUGIN/LICENSE"

# Reference material: upstream's own guide, and the benny automation sources.
# Not skills (nothing under reference/ is discovered), so they are exempt from
# the forbid gate and keep their Cursor references as historical record.
rm -rf "$ROOT/reference"
mkdir -p "$ROOT/reference"
cp -R "$SRC/docs/guide" "$ROOT/reference/upstream-guide"
cp -R "$SRC/automations/benny" "$ROOT/reference/benny"
cp "$SRC/README.md" "$ROOT/reference/upstream-README.md"

# --- 3. deterministic substitutions ------------------------------------
log "applying transform/rules.pl"
COUNTS="$(mktemp)"; RULES_C="$(mktemp)"
trap 'rm -f "$COUNTS" "$RULES_C"' EXIT
python3 "$ROOT/transform/build-counting-rules.py" "$ROOT/transform/rules.pl" "$RULES_C" "$COUNTS"
find "$PLUGIN/skills" "$PLUGIN/agents" -type f \
  \( -name '*.md' -o -name '*.ts' -o -name '*.mjs' -o -name '*.sh' -o -name '*.json' \) \
  -print0 | xargs -0 perl -pi "$RULES_C"

# --- 4. frontmatter normalisation --------------------------------------
log "normalising frontmatter"
python3 "$ROOT/transform/frontmatter.py" "$PLUGIN/skills" "$PLUGIN/agents"

log "wiring cross-vendor panels"
python3 "$ROOT/transform/panels.py"
log "mapping readonly spawns"
python3 "$ROOT/transform/readonly.py" || die "readonly mapping failed (see above)"

# --- 5. overlay (hand-written replacements win) -------------------------
if [ -d "$ROOT/overlay" ] && [ -n "$(find "$ROOT/overlay" -type f -print -quit)" ]; then
  log "applying overlay/"
  # -not -name UPSTREAM-BASE.sha256: that manifest lives under overlay/ but is
  # METADATA, not an override. Copying it would drop an untracked
  # UPSTREAM-BASE.sha256 at the repo root on every import while still reporting
  # "clean" -- measured: exactly that file turned up at the root and was first
  # mistaken for a stray.
  (cd "$ROOT/overlay" && find . -type f -not -name UPSTREAM-BASE.sha256 -print0) | \
    while IFS= read -r -d '' f; do
      mkdir -p "$PLUGIN/$(dirname "${f#./}")"
      cp "$ROOT/overlay/${f#./}" "$PLUGIN/${f#./}"
      printf '    overlay: %s\n' "${f#./}"
    done
fi

# --- 5b. own/: files this port adds that upstream never had -----------------
# overlay/ only REPLACES upstream files (audit.py fails an overlay with no upstream
# counterpart). A file that exists only here lives in own/ instead, and the reverse
# guard applies: if upstream later ships the same path, that is a collision to
# resolve by hand, not something to overwrite silently.
if [ -d "$ROOT/own" ]; then
  log "applying own/"
  while IFS= read -r -d '' f; do
    rel="${f#./}"
    [ -e "$SRC/$rel" ] && die "own/$rel now exists upstream too -- move it to overlay/ or rename it"
    mkdir -p "$PLUGIN/$(dirname "$rel")"
    cp "$ROOT/own/$rel" "$PLUGIN/$rel"
    printf '    own: %s\n' "$rel"
  done < <(cd "$ROOT/own" && find . -type f -print0)
fi

log "auditing rule coverage + overlay drift"
python3 "$ROOT/transform/audit.py" "$COUNTS" $ACCEPT || die "audit failed (see above)"

# --- 6. forbid check: nothing Cursor-only may survive -------------------
log "checking for surviving Cursor dependencies"
EXEMPT="$ROOT/transform/allow-cursor.txt"
hits=0
while IFS= read -r pat; do
  [ -z "$pat" ] && continue
  # -e: without it a pattern starting with "-" (--squash) is parsed as an option,
  # and grep exits 2 having searched nothing. Exit 1 is "no match"; 2 is an error.
  rc=0
  matches="$(grep -rEn -e "$pat" "$PLUGIN/skills" "$PLUGIN/agents")" || rc=$?
  [ "$rc" -le 1 ] || die "grep failed on forbid pattern '$pat' (exit $rc)"
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    file="${line%%:*}"
    rel="${file#"$ROOT"/}"
    if [ -f "$EXEMPT" ] && grep -qxF "$rel" "$EXEMPT"; then continue; fi
    # A blockquoted "ported from upstream" note may name what it replaced.
    content="${line#*:}"; content="${content#*:}"
    case "$content" in [[:space:]]*\>*|\>*) continue ;; esac
    printf '  \033[1;33m%s\033[0m  %s\n' "$pat" "$rel"
    hits=$((hits+1))
  done <<< "$matches"
done < "$ROOT/transform/forbid.txt"

echo
log "generated $(find "$PLUGIN/skills" -name SKILL.md | wc -l | tr -d ' ') skills, $(find "$PLUGIN/agents" -name '*.md' | wc -l | tr -d ' ') agents"
if [ "$hits" -gt 0 ]; then
  die "$hits unported Cursor reference(s) above. Fix transform/rules.pl or add an overlay/, or exempt the path in transform/allow-cursor.txt with a reason in docs/PORT.md."
fi

# --- 7. lint + functional tests ----------------------------------------
log "linting generated skills/agents"
python3 "$ROOT/tests/lint-skills.py" || die "lint failed"
log "testing the stickiness hook"
bash "$ROOT/tests/poteto-mode-hook.sh" >/dev/null || die "hook tests failed"
bash "$ROOT/tests/poteto-auto-arm.sh" >/dev/null || die "auto-arm tests failed"
log "testing cloud-session support"
bash "$ROOT/tests/cloud-session.sh" >/dev/null || die "cloud-session tests failed"
log "testing the budget hook and usage report"
bash "$ROOT/tests/budget.sh" >/dev/null || die "budget tests failed"
bash "$ROOT/tests/pstack-usage.sh" >/dev/null || die "pstack-usage tests failed"
log "clean"
