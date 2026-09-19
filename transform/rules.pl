# Deterministic Cursor -> Claude Code substitutions.
# Applied by import.sh to every generated .md / .ts / .sh file.
# Each rule exists because of a MEASURED hit in upstream; see docs/PORT.md.

# --- paths -------------------------------------------------------------
s{\.cursor/skills/}{.claude/skills/}g;
s{~/\.cursor/projects/}{~/.claude/projects/}g;
s{\.cursor/settings\.json}{.claude/settings.json}g;
s{\.cursor/automations/}{.claude/automations/}g;

# --- subagent / tool names --------------------------------------------
s{\bgeneralPurpose\b}{general-purpose}g;
s{\bAskQuestion\b}{AskUserQuestion}g;
s{`Task` tool}{`Agent` tool}g;
s{\bTask tool\b}{Agent tool}g;
s{\bTask calls\b}{Agent calls}g;
s{\bthe Task\b}{the Agent}g;
s{\bis_background:}{background:}g;

# --- model slugs -> Claude Code model aliases --------------------------
s{\bclaude-opus-5-thinking-xhigh\b}{opus}g;
s{\bclaude-fable-5-1-thinking-max\b}{fable}g;
s{\bgpt-5\.6-sol-max\b}{opus}g;
s{\bgrok-4\.6-fast-xhigh\b}{sonnet}g;
s{\bgrok-4\.6-fast\b}{sonnet}g;

# --- merge policy: the house rule is a merge commit, never a squash ----
s{gh pr merge (\S+) --squash}{gh pr merge $1 --merge}g;
s{origin pr merge (\S+) --squash}{gh pr merge $1 --merge}g;
s{\bsquash-merges\b}{merges (--merge, never --squash)}g;
s{\bsquash it with\b}{land it with}g;

# --- Cursor built-ins -> Claude Code equivalents -----------------------
s{Cursor's built-in for authoring SKILL\.md files}{use the anthropic-skills:skill-creator skill}g;
s{\bthe \*\*create-skill\*\* skill}{the **skill-creator** skill}g;
s{`/create-skill`}{`/anthropic-skills:skill-creator`}g;
s{\bcreate-skill\b}{skill-creator}g;
s{`/loop`}{`/loop`}g;
s{`/deslop`}{`/pstack-cc:unslop`}g;
s{the `deslop` skill from the `cursor-team-kit` plugin}{the **unslop** skill}g;

# --- product names ------------------------------------------------------
s{\bCursor restart\b}{Claude Code restart}g;
s{\bin Cursor\b}{in Claude Code}g;

# --- model-roles config: a Cursor always-applied rule becomes a plain file --
s{~/\.cursor/rules/pstack-models\.mdc}{~/.claude/pstack-models.md}g;

# --- remaining Cursor paths --------------------------------------------
s{~/\.cursor/plugins/}{~/.claude/plugins/}g;
s{\$HOME/\.cursor/projects/\$slug/agent-transcripts}{$HOME/.claude/projects/$slug}g;
s{\.cursor/worktrees/}{.claude/worktrees/}g;
s{~/Library/Application Support/Cursor}{~/Library/Application Support/Claude}g;

# --- cursor-team-kit control skills -> Claude Code tooling ---------------
s{`control-ui` from `cursor-team-kit`}{the built-in browser tools (`mcp__Claude_Browser__*`)}g;
s{`control-cli` from `cursor-team-kit`}{a Bash/tmux driver}g;
s{`control-ui` or `control-cli` from `cursor-team-kit`}{the built-in browser tools or a Bash/tmux driver}g;
s{ from `cursor-team-kit`}{}g;
s{\bcontrol-ui\b}{the built-in browser tools}g;
s{\bcontrol-cli\b}{a Bash/tmux driver}g;

# --- cursor-team-kit, precise forms (must precede the generic rules above on re-run) --
s{`cursor-team-kit` publishes `a Bash/tmux driver` \(CLIs and TUIs\) and `the built-in browser tools` \(browser / Electron / web UIs\)\.}{Claude Code drives browser, Electron and web UIs with the built-in browser tools (`mcp__Claude_Browser__*`), and CLIs or TUIs through Bash (a `tmux` session for anything interactive).}g;
s{ \(from `cursor-team-kit`\)}{}g;
s{`cursor-team-kit`}{Claude Code's own tooling}g;

# --- review-bot marker: accept any bot's stamp, not only Cursor's ---------
s{/CURSOR_AUTOMATION_ID:}{/(?:CURSOR_)?AUTOMATION_ID:}g;
s{"CURSOR_AUTOMATION_ID: }{"AUTOMATION_ID: }g;

# --- poll cadence: watch-pr's default mode is unbounded (--timeout 0) and hits
# --- a remote API, so it takes the 300s floor rather than upstream's 60s.
s{\.option\(\s*"--interval <seconds>",\s*"([^"]*)",\s*"60"}{.option("--interval <seconds>", "$1", "300"}g;
s{\.option\("--interval <seconds>", "poll interval", positiveNumber, 60\)}{.option("--interval <seconds>", "poll interval", positiveNumber, 300)}g;
