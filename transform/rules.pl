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
s{\bclaude-opus-5-5-(?:max|xhigh|high|medium|low)\b}{opus}g;
s{\bclaude-fable-5-1-thinking-(?:max|xhigh|high|medium|low)\b}{fable}g;
s{\bgpt-5\.6-sol-max\b}{gpt-5.6-sol}g;
s{\bgrok-4\.7-(?:max|xhigh|high|medium|low)-fast\b}{sonnet}g;
s{\bgrok-4\.6-fast\b}{sonnet}g;

# --- merge policy: the house rule is a merge commit, never a squash ----
s{gh pr merge (\S+) --squash}{gh pr merge $1 --merge}g;
s{origin pr merge (\S+) --squash}{gh pr merge $1 --merge}g;
s{\bsquash-merges\b}{merges (--merge, never a squash)}g;
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
s{\$HOME/\.cursor/projects/\$slug/agent-transcripts}{\$HOME/.claude/projects/\$slug}g;
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
# --- and the parseArgs defaults test asserts that same default, or `bun test` fails.
s{^(\s+)interval: 60,$}{${1}interval: 300,};
# --- multi-phase-plan names check-plan by its path in UPSTREAM's monorepo, which exists
# --- nowhere here. Same base as every other poteto-mode script: the skill directory.
s{node pstack/skills/poteto-mode/scripts/check-plan\.mjs}{node scripts/check-plan.mjs}g;
# --- since #422 upstream names the model rule bare, without its ~/.cursor/rules/ path.
s{the `pstack-models\.mdc` rule}{`~/.claude/pstack-models.md`}g;

# --- plugin agents are namespaced <plugin>:<agent>; a bare or display name does not resolve.
s{subagent_type: "Comment Sicko"}{subagent_type: "pstack-cc:comment-sicko"}g;
s{subagent_type: "poteto-agent"}{subagent_type: "pstack-cc:poteto-agent"}g;
s{Spawn `Task` with}{Spawn an `Agent` with}g;
s{`Task`}{`Agent`}g;

# --- Cursor agent parameters with no Claude Code meaning. Claude Code subagents get
# --- MCP tools by default, so "agent mode" needs no flag; a separate cloud VM per
# --- worker becomes a separate worktree.
s{, agent mode \(`readonly: false`\)}{}g;
s{, agent mode \(readonly strips MCP\)}{}g;
s{`environment: "cloud"`}{`isolation: "worktree"`}g;
s{When a worker must start from a non-default pushed branch, pass `cloud_base_branch`\.}{When a worker must start from a non-default pushed branch, name the branch in its brief so it checks that branch out first.}g;
s{the cloud agent's status}{the background agent's status}g;

# --- transcripts: Claude Code keeps ~/.claude/projects/<slug>/<session-id>.jsonl with
# --- subagents under <session-id>/subagents/. There is no agent-transcripts/ level, the
# --- slug keeps its leading dash, and no system prompt names the directory.
s{`~/\.claude/projects/<slug>/agent-transcripts/<uuid>/<uuid>\.jsonl`, where `<slug>` is the workspace path with the leading slash dropped and each "/" turned into "-" \(so `/Users/you/proj` becomes `Users-you-proj`\)}{`~/.claude/projects/<slug>/<session-id>.jsonl`, with subagents under `<session-id>/subagents/`, where `<slug>` is the workspace path with every character that is not a letter or digit turned into "-" (so `/Users/you/proj` becomes `-Users-you-proj`)}g;
s{The system prompt names (?:the active|the) workspace's `agent-transcripts/` directory\. Use (?:only )?that path\.}{The active workspace's transcripts, `<transcripts>` below, are in `~/.claude/projects/<slug>/`, where `<slug>` is the workspace path with every character that is not a letter or digit turned into "-". This session's own file there is `\${CLAUDE_SESSION_ID}.jsonl`. Use only that directory.}g;
s{<agent-transcripts>}{<transcripts>}g;
s{`agent-transcripts/` directory \(the system prompt names (?:the|this) path}{transcript directory, `~/.claude/projects/<slug>/` (`<slug>` is the workspace path with every character that is not a letter or digit turned into "-"}g;
s{local transcripts under `agent-transcripts/`}{local transcripts under `~/.claude/projects/`}g;
s{# Transcripts dir: ~/\.claude/projects/<slugified-repo-path>/agent-transcripts\.}{# Transcripts dir: ~/.claude/projects/<slug>, every non-alphanumeric byte -> "-".};
s{sed 's#\^/##; s#/#-#g'}{sed 's#[^A-Za-z0-9]#-#g'};

# --- remaining Cursor built-ins.
s{Cursor's built-in `skill-creator` skill}{the `anthropic-skills:skill-creator` skill}g;
s{Cursor's built-in `skill-creator`}{the `anthropic-skills:skill-creator` skill}g;
s{Cursor's built-in babysit skill}{any other installed babysit skill}g;
s{Cursor's `/loop` command \(a built-in, not a pstack skill\)}{Claude Code's `/loop` skill (a built-in, not a pstack skill)}g;
s{list the available MCPs from the Cursor environment\. Use the available-tools map when present\. Otherwise inspect the `mcps/` directory Cursor exposes for enabled MCP servers\.}{list the MCP servers connected to this session: their tools are named `mcp__<server>__<tool>`, and deferred ones are found with ToolSearch.}g;
s{each a Cursor cloud agent,}{each a background `Agent` in its own worktree,}g;
s{One Cursor cloud agent per PR}{One background `Agent` per PR, in its own worktree,}g;
s{with Cursor's `/loop` command}{with Claude Code's `/loop` skill}g;
s{the background agent's status in the Cursor dashboard}{the background agent's last output}g;

# --- upstream's GPT panel seat is a GPT seat again, through bin/panelist, instead of
# --- a second opus: same model diversity upstream designed, and it does not count
# --- against Claude plan limits. reflect's tooling reviewer needs files and MCP,
# --- which a panelist seat does not have, so that one stays an Anthropic agent.
s{\| `reflect tooling` \| `gpt-5\.6-sol` \|}{| `reflect tooling` | `opus` |}g;

# --- poteto-agent: upstream says "Read the `poteto-mode` skill's SKILL.md" with no path,
# --- which in Cursor resolves through .cursor/skills/. A plugin skill here has no fixed
# --- path, and a poteto-agent spawned 2026-09-28 looked for ~/.claude/skills/poteto-mode/,
# --- found nothing and worked without it. Name the Skill tool, the one route that resolves.
s{Read the `poteto-mode` skill's `SKILL\.md` in full before doing any work, including its inline Principles index\. Navigate to a leaf `principle-\*` skill whenever you apply that principle\.}{Before any work, read the `pstack-cc:poteto-mode` skill's `SKILL.md` in full, including its inline Principles index. This agent's `skills:` frontmatter preloads it; if its text is not already in your context, your first action is to invoke the Skill tool with `pstack-cc:poteto-mode`. Never look for it on disk: a plugin's skills are not under `~/.claude/skills/`, and searching there finds nothing. Whenever you apply a principle, load its leaf `principle-*` skill the same way, through the Skill tool with the `pstack-cc:` prefix (for example `pstack-cc:principle-prove-it-works`).}g;

# --- Matt Pocock's skills (transform/mattpocock.tsv): one workflow, split by phase ---
# User decision 2026-10-05: grill while deciding WHAT to build, autonomous while building
# it, GitHub issues as the record. These lines are the router's half of that; the skills
# themselves are imported by transform/mattpocock.py.
s{^(- Nontrivial change, architecture decision, or "are we sure\?" → the \*\*how\*\* skill\.)$}{$1\n- Deciding what to build (a new idea, a fuzzy feature, scope or naming still open, no agreed spec or ticket) → the Deciding playbook (`playbooks/deciding.md`). This phase is the human's. Ask, and treat grilling's confirmation as the gate. Facts stay yours to find.\n- Building from an agreed spec or ticket → the Feature or Bug fix playbook, autonomous from here. Fetch the ticket the way `docs/agents/issue-tracker.md` says (on GitHub, `gh issue view <n> --comments`). Its acceptance criteria are the verify predicate. The work closes the ticket on merge, never before. On GitHub or GitLab, put `Closes #<n>` in the PR or MR body. On local markdown, set the ticket file's `Status:` to `resolved` in the same commit. Don't re-grill what the spec settled. Test at the seams under test the ticket names, else its parent spec's, with the **tdd** skill. A queue of tickets → Feature per ticket in blocking order. Autopilot-stack only when the user names it.\n- An unfamiliar external API, library, or standard → the **research** skill, which saves a cited note in the repo. Questions about this codebase stay with **how** and **why**.\n- Module depth, seams, or where an interface belongs → the **codebase-design** skill for the shared vocabulary. Hunting refactor candidates across a codebase → the **improve-codebase-architecture** skill.\n- Handing work to another harness or directory on this machine → the **handoff** skill. For a person, or from a cloud session, post the handoff as a comment on the tracker issue instead. Resuming here later is Pause safely.}g;
s{^(- Any prose surface → the \*\*unslop\*\* skill\..*\(use the anthropic-skills:skill-creator skill\)\.)$}{$1 What goes into an agent-facing doc, and where, follows the **writing-for-agents** skill. Grilling rounds, specs, tickets, and glossaries keep the templates and terms their own skills define.}g;
s{(If it won't reproduce directly, synthesize the trigger, tighten conditions, or instrument until it fires\.)}{$1 For a hard or flaky bug, build the feedback loop with the **diagnosing-bugs** skill (its loop and reproduce phases) before forming hypotheses.}g;
s{^(- \*\*Feature\.\*\* New or changed behavior, built from a named data shape\. `playbooks/feature\.md`\.)$}{- **Deciding what to build.** No agreed spec or ticket yet, and scope, naming, or behavior still open. Grill the human, record the glossary and decisions, publish a spec and tickets. Runs before Feature. `playbooks/deciding.md`.\n$1}g;
