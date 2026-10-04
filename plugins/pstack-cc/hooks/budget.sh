#!/usr/bin/env bash
# budget.sh — SessionStart hook shipped with the pstack-cc plugin.
#
# pstack's playbooks fan out: panels of reviewers, swarms of workers, an explorer
# per question. On a subscription plan, subagents are where the usage goes, and
# ~/.claude/pstack-models.md only chooses each subagent's MODEL. It cannot say
# how MANY to spawn. This hook adds the missing half: fan-out caps, injected once
# per session (and again after compaction, which re-fires SessionStart).
#
# Budget, first match wins:
#   PSTACK_CC_BUDGET=max|balanced|lean      environment
#   "# budget: <name>" in ~/.claude/pstack-models.md, else in the repo's
#   .claude/pstack-models.md                written by /pstack-cc:setup-pstack
#   balanced                                when nothing is set
#
# `max` injects nothing: upstream's full fan-out. Any error exits 0 silently.
set -uo pipefail
cat >/dev/null 2>&1 || true

budget="${PSTACK_CC_BUDGET:-}"
if [ -z "$budget" ]; then
  for f in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/pstack-models.md" \
           "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/pstack-models.md"; do
    [ -f "$f" ] || continue
    budget="$(sed -n -E 's/^#[[:space:]]*budget:[[:space:]]*([a-z]+).*/\1/p' "$f" 2>/dev/null | head -1)"
    [ -n "$budget" ] && break
  done
fi
budget="${budget:-balanced}"
# Older configs say "cheap"; it is the same tier as lean.
[ "$budget" = cheap ] && budget=lean

case "$budget" in
  balanced) width=3; seats="at most ONE Anthropic seat (the judgment seat, normally opus); fill the rest with non-Claude seats through panelist, which do not count against Claude plan limits" ;;
  lean)     width=2; seats="no opus seat; one sonnet seat plus non-Claude seats through panelist" ;;
  *)        exit 0 ;;
esac

cat <<NOTE
pstack-cc usage budget: ${budget}. Subagents are where plan usage goes, so these caps override any playbook step that asks for more:
- Fan-out: at most ${width} subagents per step and at most ${width} in flight at once. Need more? Say why in one line first, or run the extra work in a later wave.
- Panels (interrogate, arena, architect): ${seats}. A missing non-Claude seat is a named dropout; do not backfill it with another Claude seat.
- Spawn a subagent only when the work would flood this context (many files, long logs) or needs isolation. A lookup of a few files is cheaper as Read/Grep here.
- Always set \`model\` on a spawn from the role's line in ~/.claude/pstack-models.md; an unset model inherits this session's model. Pure search and listing work runs on haiku.
- Brief with file paths and exact questions, not pasted context: everything in a brief is paid for again in every turn of that subagent.
- arena, swarm, orchestrate and the autopilot playbooks run only when the user names them, not as a step chosen on their behalf.
NOTE
exit 0
