# Changes

Newest first. The plugin has no version number (see README, "Updating an install"), so
entries are keyed by pull request. CI fails a pull request that changes anything under
`plugins/` without adding a line here, so every install-visible change is recorded.

## Unreleased
- The forbid gate's `--squash` check now runs. `import.sh` passed each pattern to grep bare, so `--squash` was parsed as an option, grep exited 2, and `2>/dev/null || true` hid it. Patterns now go in with `-e`, and a grep error fails the import. With the gate live, the `squash-merges` rewrite in the poteto-mode playbooks says "never a squash" instead of naming the `--squash` flag it forbids.
- Matt Pocock's skills join the plugin as a second pinned upstream (`mattpocock/skills` @ `4588b32`), split by phase: his skills decide what to build with you (`grill-with-docs`, `grilling`, `domain-modeling`, `to-spec`, `to-tickets`, `wayfinder`), and pstack's playbooks build it autonomously. `poteto-mode` routes to them. 18 skills imported: 14 core, 4 unrouted extras (`triage`, `course`, `wizard`, `to-questionnaire`). 8 excluded where pstack covers the job. `transform/mattpocock.tsv` records each decision.
- `tdd` merges both packs: test-first vertical slices for new behavior, the regression gate for bugs. Seams come from the spec or ticket while building, never from a mid-build question.
- The Bug fix playbook builds a hard bug's feedback loop with `diagnosing-bugs` before hypothesising.
- New Deciding playbook (`playbooks/deciding.md`): setup, grilling, spec, tickets, then stop. Building a ticket fetches it through the tracker that setup recorded (`docs/agents/issue-tracker.md`), verifies against its acceptance criteria, tests at its seams under test, and closes it on merge (`Closes #<n>` on GitHub or GitLab, `Status: resolved` on local markdown). A ticket queue goes to Feature per ticket; Autopilot-stack only when named.
- Matt's skills name each other by their registered command (`/pstack-cc:setup-matt-pocock-skills`, not `/setup-matt-pocock-skills`, which no plugin registers). The lint fails on a bare one.
- Codex: the routed skills drop `allow_implicit_invocation: false` along with the Claude flag, so Codex shows them to its model. The extras keep both.
- Build guards: an unclassified Matt skill, a reworded or over-matched edit anchor, a merge row without its overlay, or a change to his `tdd` fails `import.sh`; `tests/mattpocock-guards.sh` proves each fires. The lint checks Skill-tool calls, sibling links, and that a skill is user-only in both harnesses or neither.
- Tests: every scratch dir now uses an explicit `mktemp` template and exits if it fails. On macOS without one, `mktemp` fails in a sandbox and several tests wrote to `/`.
- `poteto-agent` now says how to load poteto-mode: it is preloaded, and otherwise the agent's first action is the Skill tool with `pstack-cc:poteto-mode`. Upstream's pathless "read the SKILL.md" sent a spawned agent looking in `~/.claude/skills/`, where a plugin skill never is. Principle leaves load the same way. `tests/invocation-live.sh` checks, from the spawned agent's own transcript, that it has the skill and searched no disk.
- README: the cloud-session install route that actually works (environment setup script plus `CLAUDE_CODE_PLUGIN_DIRS`), with the four routes that were tested and failed.

## techRambam/pstack-cc#4 (2026-10-04)

**Cloud sessions**
- `hooks/cloud-session.sh` (SessionStart, cloud only) tells the model what differs from a laptop and copies the repo's `.claude/pstack-models.md` home.
- `watch-pr` exits 69 in a cloud session instead of retrying a refused GraphQL call forever.
- `panelist` reads keys from the environment and falls back to the OpenAI API without `codex`.
- `PSTACK_CC_ALWAYS_ON=1` arms auto-arm.
- The README documents the install routes that work in a cloud session.

**Routing and agents**
- `disable-model-invocation` is dropped (it made the Skill tool refuse every routed call), except on `make-bot-ui`.
- The 24 `principle-*` skills are `user-invocable: false`: hidden from the `/` menu, still invocable by Claude.
- Agents are dispatched as `pstack-cc:poteto-agent` and `pstack-cc:comment-sicko`.
- `poteto-agent` preloads `pstack-cc:poteto-mode`.
- New `pstack-cc:read-only` agent (no edit tools, no `Agent`) replaces Cursor's `readonly: true` for `how` explorers, `interrogate` reviewers and the `arena` judge.
- Panel seats count only when they deliver; a failed seat is a named dropout and is never silently replaced.

**Paths and Cursor leftovers**
- Transcript paths match Claude Code's real layout.
- `check-plan` runs from the skill directory.
- `environment: "cloud"`, `readonly`, `cloud_base_branch`, `mcps/`, and Cursor's built-in `skill-creator`, babysit and `/loop` are ported.

**Upstream sync**
- Upstream `032be14` → `e43c7ee` adds `correct`, `benchmark-checklist` and `principle-explain-the-number`.
- Model slugs move to `claude-opus-5-5-*` and `grok-4.7-*-fast`.

**Packaging**
- The plugin moves to `plugins/pstack-cc/`, so installs no longer copy the generator, tests or reference material.
- `plugin.json` has no `version`, so every commit is an update. `0.1.0` had kept installs on their first copy.

**Plan limits**
- `hooks/budget.sh` (SessionStart) caps fan-out by budget (balanced: 3 per step and one Claude seat per panel; lean: 2) and defaults to balanced with no config.
- `/pstack-cc:setup-pstack` offers max, balanced and lean presets with relative costs.
- Upstream's GPT panel seat is a GPT seat again (via `panelist`) instead of a second Opus.
- `pstack-cc:read-only` runs at `effort: high`.
- `bin/pstack-usage` reports where plan usage went: by model, subagent type, effort and session.

**Tooling**
- New `own/` holds port-only files, guarded against upstream collisions.
- Lint now checks cross-references between skills.
- CI runs `import.sh`, a regenerate-and-diff check, `bun test`, `shellcheck`, `actionlint`, and this changelog check.
- `panelist`'s default timeout is 540s, so it reports its own timeout before Bash's 600s kill.

## techRambam/pstack-cc#3 (2026-09-23)
- `hooks/poteto-auto-arm.sh`: an opt-in SessionStart hook pins poteto-mode for new sessions.
- It arms only on `source=startup`, so `/poteto-off` holds through compaction.

## techRambam/pstack-cc#2 (2026-09-20)
- Fixed three holes in the update guards, all found by Codex review: `panelist doctor` passed with every Gemini model dead, `--accept-overlay` restored a deleted upstream skill, and an overlay manifest leaked to the repo root.

## techRambam/pstack-cc#1 (2026-09-19)
- Upstream updates now fail loudly: an overlay-drift guard, a dead-rule audit, and a panel-rename guard.
- `panelist doctor` exits non-zero when a keyed vendor is dead.

## Initial port (2026-09-19)
- pstack at `032be14`, generated for Claude Code by `import.sh`.
- Sticky poteto-mode and `/goal` via a UserPromptSubmit hook.
- Cross-vendor panels via `bin/panelist`.
