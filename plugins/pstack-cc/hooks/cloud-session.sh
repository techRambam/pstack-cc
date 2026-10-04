#!/usr/bin/env bash
# cloud-session.sh — SessionStart hook shipped with the pstack-cc plugin.
#
# pstack's skills and playbooks assume a durable local machine: a home directory
# that persists, an authenticated `gh`, the codex and gt CLIs, a desktop browser
# pane. A Claude Code cloud session (CLAUDE_CODE_REMOTE=true) has none of them.
# Rewriting fifty generated skills for that would fork them from upstream, so
# this hook tells the model once, at session start, what differs here and what
# to use instead. Claude Code adds a SessionStart hook's stdout to the context.
#
# It also copies the repo's .claude/pstack-models.md to ~/.claude/pstack-models.md
# when the home copy is missing, because a cloud container's home starts empty
# and the skills read the home path.
#
# Local sessions: exits 0 silently and changes nothing. Any error: same.
set -uo pipefail

[ "${CLAUDE_CODE_REMOTE:-}" = true ] || exit 0
cat >/dev/null 2>&1 || true

ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
HOME_CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
REPO_MODELS="${CLAUDE_PROJECT_DIR:-$PWD}/.claude/pstack-models.md"

models="none: /pstack-cc:setup-pstack writes .claude/pstack-models.md in the repo; commit it."
if [ -f "$HOME_CFG/pstack-models.md" ]; then
  # shellcheck disable=SC2088  # display text for the model, not a path to expand
  models="~/.claude/pstack-models.md is present."
elif [ -f "$REPO_MODELS" ] && mkdir -p "$HOME_CFG" 2>/dev/null \
     && cp "$REPO_MODELS" "$HOME_CFG/pstack-models.md" 2>/dev/null; then
  models="copied from the repo's .claude/pstack-models.md to ~/.claude/pstack-models.md."
fi

missing=""
for t in codex gt; do command -v "$t" >/dev/null 2>&1 || missing+="${missing:+, }$t"; done

keys=""
for k in OPENAI_API_KEY GEMINI_API_KEY GOOGLE_API_KEY OPENROUTER_API_KEY GROQ_API_KEY \
         MISTRAL_API_KEY CEREBRAS_API_KEY DEEPSEEK_API_KEY HUGGINGFACE_API_KEY; do
  [ -n "${!k:-}" ] && keys+="${keys:+, }$k"
done

browser="drive web UIs with Playwright"
[ -d /opt/pw-browsers ] && browser+=" (Chromium is at /opt/pw-browsers; do not run playwright install)"

# shellcheck disable=SC2016  # the backticks below are markdown for the model, not commands
cat <<NOTE
pstack-cc is running in a Claude Code cloud session. Where a pstack skill or playbook assumes a local machine, use these instead:
- GitHub: the session proxy refuses GraphQL, so \`gh pr view|list|checks|status\` and \`gh api graphql\` fail; plain \`gh api\` REST calls may work. Use the mcp__github__* tools for PRs, reviews and CI. \`scripts/watch-pr/watch-pr\` exits 69 here: to babysit or ship a PR, subscribe to its activity (subscribe_pr_activity) and let events wake the session rather than polling.
- Plugin scripts: poteto-mode's \`scripts/...\` paths are relative to $ROOT/skills/poteto-mode, so run them by absolute path. panelist is $ROOT/bin/panelist.
- Not installed: ${missing:-nothing missing}.$( [[ "$missing" == *gt* ]] && printf ' Without gt, `orch frontier set` cannot compute a frontier.' )$( [[ "$missing" == *codex* ]] && printf ' Without codex, OpenAI panel seats need OPENAI_API_KEY.' )
- Panel keys in the environment: ${keys:-none}. A seat whose key is missing errors; name it in the verdict table and carry on.
- Browser: there is no built-in browser pane here; $browser.
- Ephemeral: the container and its home directory are discarded when the session ends. Commit and push anything worth keeping. ~/.claude/projects holds only this session, so recall, reflect and automate-me see no earlier sessions. Worktree cleanup does not apply.
- Model roles: $models
NOTE
exit 0
