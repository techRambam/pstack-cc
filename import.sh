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
UPSTREAM_REF="032be146865d973682535de75f2287da438550bf"
SRC="$ROOT/upstream/pstack"

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
rm -rf "$ROOT/skills" "$ROOT/agents"
cp -R "$SRC/skills" "$ROOT/skills"
cp -R "$SRC/agents" "$ROOT/agents"
cp "$SRC/LICENSE" "$ROOT/LICENSE.upstream"

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
find "$ROOT/skills" "$ROOT/agents" -type f \
  \( -name '*.md' -o -name '*.ts' -o -name '*.mjs' -o -name '*.sh' -o -name '*.json' \) \
  -print0 | xargs -0 perl -pi "$RULES_C"

# --- 4. frontmatter normalisation --------------------------------------
log "normalising frontmatter"
python3 "$ROOT/transform/frontmatter.py" "$ROOT/skills" "$ROOT/agents"

log "wiring cross-vendor panels"
python3 "$ROOT/transform/panels.py"

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
      mkdir -p "$ROOT/$(dirname "${f#./}")"
      cp "$ROOT/overlay/${f#./}" "$ROOT/${f#./}"
      printf '    overlay: %s\n' "${f#./}"
    done
fi

log "auditing rule coverage + overlay drift"
python3 "$ROOT/transform/audit.py" "$COUNTS" $ACCEPT || die "audit failed (see above)"

# --- 6. forbid check: nothing Cursor-only may survive -------------------
log "checking for surviving Cursor dependencies"
EXEMPT="$ROOT/transform/allow-cursor.txt"
hits=0
while IFS= read -r pat; do
  [ -z "$pat" ] && continue
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    file="${line%%:*}"
    rel="${file#$ROOT/}"
    if [ -f "$EXEMPT" ] && grep -qxF "$rel" "$EXEMPT"; then continue; fi
    # A blockquoted "ported from upstream" note may name what it replaced.
    content="${line#*:}"; content="${content#*:}"
    case "$content" in [[:space:]]*\>*|\>*) continue ;; esac
    printf '  \033[1;33m%s\033[0m  %s\n' "$pat" "$rel"
    hits=$((hits+1))
  done < <(grep -rEn "$pat" "$ROOT/skills" "$ROOT/agents" 2>/dev/null || true)
done < "$ROOT/transform/forbid.txt"

echo
log "generated $(find "$ROOT/skills" -name SKILL.md | wc -l | tr -d ' ') skills, $(find "$ROOT/agents" -name '*.md' | wc -l | tr -d ' ') agents"
if [ "$hits" -gt 0 ]; then
  die "$hits unported Cursor reference(s) above. Fix transform/rules.pl or add an overlay/, or exempt the path in transform/allow-cursor.txt with a reason in docs/PORT.md."
fi

# --- 7. lint + functional tests ----------------------------------------
log "linting generated skills/agents"
python3 "$ROOT/tests/lint-skills.py" || die "lint failed"
log "testing the stickiness hook"
bash "$ROOT/tests/poteto-mode-hook.sh" >/dev/null || die "hook tests failed"
log "clean"
