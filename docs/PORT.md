# Port record — pstack (Cursor) → pstack-cc (Claude Code)

Upstream: `cursor/plugins` @ `e43c7ee26e0038c6c1fa8380dd34ce86ff94cb2a`, `pstack/` only.
Every decision below is implemented in `transform/` or `overlay/`, never by hand-editing
generated output.

## 1. Packaging

| Upstream | Here | Note |
|---|---|---|
| `.cursor-plugin/plugin.json` | `.claude-plugin/plugin.json` + `marketplace.json` | The upstream repo has **no** `.claude-plugin/` and no `marketplace.json`, so there was nothing to install. |
| `displayName`, `logo`, `category`, `tags`, `skills`, `agents` keys | dropped | `MEASURED:` not present in any real Claude Code `plugin.json` on this machine; `skills/` and `agents/` are auto-discovered. `category`/`tags` are marketplace-entry keys and moved there. |
| — | `hooks/hooks.json` | `MEASURED:` auto-discovered, not referenced from `plugin.json` (same as superpowers 6.3.0). |
| plugin at the repo root (`source: "./"`) | `plugins/pstack-cc/` | An install copies the plugin directory, and at the root that meant `transform/`, `tests/`, `docs/` and `reference/` (images included) went into every cache. `MEASURED:` a marketplace install from the new layout contains only `LICENSE`, `agents`, `bin`, `hooks`, `skills`. |
| `"version": "0.1.0"` | no `version` | `MEASURED:` the install reports `Version: 7ed20aaed090`, the commit SHA, so every push is an update. A changelog (`CHANGES.md`, enforced in CI) replaces the version as the record. |
| — | `own/agents/read-only.md` | Cursor's `readonly: true` spawn flag has no Claude Code parameter; the agent (no Edit/Write/NotebookEdit/Agent) is the equivalent. `transform/readonly.py` rewrites the five spawn specs, failing on any count mismatch. |

**`claude plugin validate` does not check SKILL.md.** `MEASURED:` reintroducing `mode`,
`icon`, `color` and `reminder` on a skill still passed validation. `tests/lint-skills.py`
is the check that actually catches a bad port; `import.sh` runs it and fails on any problem.

## 2. Frontmatter

Dropped from `poteto-mode` (Cursor-only, no Claude Code meaning): `mode`, `icon`, `color`,
`reminder`. `reminder` is not discarded — it is extracted to `hooks/reminder.txt` and used by
the stickiness hook, so it tracks upstream.

Names slugged to lowercase-hyphen: `Poteto Mode` → `poteto-mode`, `Make Bot UI` →
`make-bot-ui`, `Comment Sicko` → `comment-sicko`. `is_background:` → `background:`.
Plugin agents are dispatched by their namespaced name, `pstack-cc:poteto-agent` and
`pstack-cc:comment-sicko`. An earlier version of this record claimed the `no-comments`
reference was slugged. It was not: it still spawned `subagent_type: "Comment Sicko"`, which
resolves to nothing. The forbid gate now rejects the bare and display forms.

**`disable-model-invocation` is dropped**, except on `make-bot-ui`. An earlier version kept it
on 49 skills on the theory that it only kept them out of automatic routing. In Claude Code it
does more than that: when Claude calls a skill that carries it, the Skill tool **refuses** the
call ([docs](https://code.claude.com/docs/en/skills)). Upstream's skills invoke one another:
poteto-mode routes to `how`, `why`, `arena` and the principle skills, and the pinned reminder
says "apply /poteto-mode". Every one of those calls was being refused. The descriptions are
explicit ("Use for /how"), so the skills don't trigger on unrelated requests. `make-bot-ui`
keeps the flag because it has side effects and nothing routes to it. `tests/lint-skills.py`
fails on the key anywhere else.

Kept unchanged: `paths`, which means the same thing here.

## 3. Mechanisms with no Claude Code equivalent — what replaced them

| Cursor mechanism | Replacement |
|---|---|
| `mode: true` + `reminder:` (Custom Mode pinning via `Opt+Enter`) | `hooks/poteto-mode.sh`, a plugin-shipped `UserPromptSubmit` hook. Typing `/poteto-mode` arms it for the session; `/poteto-off` disarms. 14 functional tests in `tests/`. |
| `/goal` (persistent cross-turn objective) | Same hook. `/goal <text>` stores it per session and re-injects every turn; `/goal clear` clears. Needed by `autopilot-*` and `multi-phase-plan`. |
| `~/.cursor/rules/pstack-models.mdc` (`alwaysApply: true`) | `~/.claude/pstack-models.md`, a plain file each skill reads explicitly — which is how the skills were already written (*"when present … otherwise the table defaults"*). Written by `/pstack-cc:setup-pstack`. |
| Cursor built-in `create-skill` | `anthropic-skills:skill-creator`. |
| `cursor-team-kit`'s `control-ui` / `control-cli` | The built-in browser tools (`mcp__Claude_Browser__*`) and Bash/tmux. |
| `/deslop` (`cursor-team-kit`) | `/pstack-cc:unslop`, which is the same job and ships here. |
| `~/.cursor/projects/<slug>/agent-transcripts/`, "named in the system prompt" | `~/.claude/projects/<slug>/<session-id>.jsonl`, with subagents under `<session-id>/subagents/`. `MEASURED:` the slug keeps its leading dash (`-home-user-pstack-cc`), and no system prompt names the directory, so the skills now say how to build it, and SKILL.md files name `${CLAUDE_SESSION_ID}.jsonl`. |
| `~/.cursor/plugins/` | `~/.claude/plugins/`. |
| Cursor cloud agents (`environment: "cloud"`, `cloud_base_branch`, the Cursor dashboard) | A background `Agent` with `isolation: "worktree"`. This is not a drop-in replacement for one VM per PR, so `orchestrate` and both `autopilot-*` playbooks are still **the least faithful part of this port**. |
| `readonly: false` ("agent mode", so MCP stays available) | Dropped. Claude Code subagents get MCP tools without a flag. |
| A skill read by name ("Read the `poteto-mode` skill's `SKILL.md`"), which Cursor resolves through `.cursor/skills/` | `poteto-agent` preloads `pstack-cc:poteto-mode` through `skills:` frontmatter, and its body names the Skill tool as the fallback and forbids a disk search. `MEASURED:` a poteto-agent spawned 2026-09-28 from a copy without the preload looked for `~/.claude/skills/poteto-mode/SKILL.md`, found nothing, and worked without the skill. A plugin skill has no fixed path, so the Skill tool is the one route that always resolves. |

## 4. Model slugs

Upstream's slugs map to Claude Code aliases. The rules match every effort suffix, so an
upstream budget change (`-max` → `-medium`) maps instead of leaking:

| Upstream | Here |
|---|---|
| `claude-opus-5-5-{max,xhigh,high,medium,low}` | `opus` |
| `gpt-5.6-sol-max` | `gpt-5.6-sol`, a `panelist` seat (was `opus`; reflect's tooling reviewer, which needs files and MCP, stays `opus`) |
| `grok-4.7-{…}-fast` | `sonnet` |
| `claude-fable-5-1-thinking-*`, `grok-4.6-fast*` | `fable`, `sonnet` (pre-`e43c7ee`; kept so a return maps) |

At `e43c7ee` upstream moved every Fable role (judgment, prose, explainer, synthesizer) to Opus
5.5, so `setup-pstack`'s defaults follow: those roles are `opus` here too.

**Recovered, not lost.** `arena`, `interrogate`, `swarm` and `architect` were built on
*cross-vendor* panels — `interrogate/SKILL.md` says the adversarial signal comes from model
diversity, not assigned personas. Claude Code's `Agent` tool reaches only Anthropic models,
so `bin/panelist` adds the other vendors and the default panels in `setup-pstack` are mixed
again: `opus, fable, gpt-6-astra, gemini-3-flash-preview`.

| Vendor | Route | Auth | `MEASURED:` status |
|---|---|---|---|
| Anthropic | `Agent` tool | native | opus / sonnet / haiku / fable |
| OpenAI | `codex exec -s read-only` | org ChatGPT sign-in (`~/.codex/auth.json`, `auth_mode` set, API-key slot empty) | `gpt-6-astra`, `gpt-5.6-sol` answered; `gpt-5.6-luna`, `gpt-5.6-terra`, `gpt-5.5` listed |
| Google | Gemini REST `v1beta` | `GEMINI_API_KEY` from `~/.claude/.env` | flash-class answered; **pro = HTTP 429** |
| Meta/Qwen/Mistral | HuggingFace router | `HUGGINGFACE_API_KEY` | **dead — 401 on every model** |
| xAI | — | — | no access at all |

Three gotchas, each cost a real debugging round and each is now encoded in `bin/panelist`:

1. **`codex exec` hangs forever under an agent harness** unless stdin is `/dev/null`. It
   appends piped stdin as a `<stdin>` block when a prompt is also given, and the harness's
   stdin never closes.
2. **`codex exec` can exit 0 after the API rejected the request** (an `invalid_json_schema`
   400 still returned status 0, leaving `-o` empty). Falling back to stdout there would
   return the whole transcript as if it were the model's answer, so `panelist` treats an
   empty `-o` under `--schema` as a failure.
3. **The vendors' schema dialects are mirror images.** OpenAI strict mode demands every
   `properties` key appear in `required` plus `additionalProperties: false`; Gemini rejects
   `additionalProperties` outright and takes only an OpenAPI-3.0 subset. `panelist` converts
   a plain JSON Schema per vendor so callers write one file.

Also worth knowing for any shell caller: **zsh parses `$m:generateContent` as a parameter
modifier** and silently mangles the URL to `models/5-flashnerateContent`. Brace it (`${m}`).

## 5. House-rule adaptations

| Change | Reason |
|---|---|
| `gh pr merge … --squash` → `--merge` (`shipping.md:11`, `autopilot-full.md:9`, `multi-phase-plan.md:132`) | A squash rewrites the branch's commits into one new commit on the base, so a branch you keep working on conflicts by *unrelated history* on its next PR. Merge commits only. |
| `watch-pr` default `--interval` 60 → 300 | Its default mode is unbounded (`--timeout 0`) and hits a remote API. 300s is the floor for an unbounded poll. Override per-run if you need faster. |
| Bugbot marker regex widened to `(?:CURSOR_)?AUTOMATION_ID:` | Works with any review bot that stamps an id, not only Cursor's. The rest of `bugbot-triage.md` is a rubric and is harness-independent. |

## 6. Known gaps — not solved, stated plainly

- **`orch/store.ts` hard-requires Graphite (`gt`).** `graphiteFrontier()` and
  `graphitePullRequest()` shell out to it; without `gt` the orchestrator computes no frontier.
  Rewriting them against `gh` is unstarted work.
- **`make-bot-ui`** was entirely Grok Bot / Cursor Automations (`api2.cursor.sh`,
  `update_state`, `SendToUser`). Rewritten onto published Artifacts and headless `claude -p`.
  The security posture is upstream's, unchanged; the mechanism is new and **untested**.
- **benny** (`reference/benny/`) needs Cursor Automations and is kept as reference only. Its
  operational discipline — immutable thread coordinates, coordinator is the only poster,
  children forbidden every write tool, fail closed — is harness-independent and worth reading
  before building any equivalent on GitHub Actions.
- **`worktree-cleanup` / `worktree-audit.sh`** work, but their liveness signal was Cursor
  transcript mtime plus pinned sidebar chats. If you already have a heartbeat-based sweeper,
  prefer it — `worktree-cleanup.md:9` does `git worktree remove --force` plus `rm -rf`.
- **`worktree-audit.sh` is BSD-only.** It uses `stat -f` and `date -r <epoch>`, which mean
  something else on GNU/Linux, so its AGE and LAST_CHAT columns are wrong there. Worktree
  cleanup does not apply in a cloud container anyway.
- **Nothing here has been run inside a live Claude Code session yet.** The generator, linter
  and hook tests all pass; skill *behaviour* under the real harness is unverified until the
  plugin is installed and used.

## 7. Cloud sessions

`MEASURED` in real cloud sessions (2026-10-04). These do **not** load a plugin there:
- repo `enabledPlugins`
- a plugin on the claude.ai account (account skills sync, plugins don't)
- a plugin under `.claude/skills/<name>/` ("workspace was not trusted")
- `CLAUDE_CODE_PLUGIN_DIRS` in a repo's settings `env`

What does load one is the environment: a setup script that clones the (public) repo to
`/opt/pstack-cc`, plus `CLAUDE_CODE_PLUGIN_DIRS=/opt/pstack-cc/plugins/pstack-cc` as an
environment variable. The startup event then lists `pstack-cc@inline` with every skill, the
three agents and both SessionStart notes. Steps are in the README.

What differs inside one, all `MEASURED:` in a cloud container:

| Fact | Consequence | Handled by |
|---|---|---|
| `gh pr list` → HTTP 403 "GitHub GraphQL is not available from Claude Code sessions"; `gh api repos/…` works | `watch-pr` and every `gh pr …` line in the playbooks fail; `watch-pr`'s errors are retryable, so it would poll forever | `overlay/…/watch-pr/watch-pr` exits 69 when `CLAUDE_CODE_REMOTE=true`; `hooks/cloud-session.sh` points at `mcp__github__*` and `subscribe_pr_activity` |
| `codex`, `gt` absent | OpenAI seats crashed with an uncaught `FileNotFoundError` | `panelist` returns a clean error, or uses the OpenAI API when `OPENAI_API_KEY` is set |
| `$HOME` is fresh per session | `~/.claude/.env`, `~/.claude/pstack-models.md` and `~/.claude/pstack-cc/always-on` never persist | keys from the environment; repo `.claude/pstack-models.md` copied home by the hook; `PSTACK_CC_ALWAYS_ON=1` |
| No desktop browser pane; Chromium at `/opt/pw-browsers` | `mcp__Claude_Browser__*` references dead | the hook names Playwright |

The skills themselves are **not** rewritten for the cloud. One `SessionStart` note costs a few
hundred tokens once per session and keeps fifty generated files identical to upstream; forking
them would turn every upstream sync into a merge. `tests/cloud-session.sh` covers the hook,
the auto-arm variable, the `watch-pr` guard and `panelist`'s key lookup, offline.

## 8. The forbid gate

`transform/forbid.txt` lists patterns that must not survive into `skills/` or `agents/`:
`.cursor/`, `cursor-agent`, `CURSOR_*`, `cursor-team-kit`, `pstack-models.mdc`,
`api2.cursor.sh`, every model slug, `generalPurpose`, `--squash`, `is_background`.

A hit fails `import.sh` with a non-zero exit. Blockquoted port notes are exempt, so a
`> **Ported from upstream.**` paragraph may name what it replaced without tripping the gate.
That exemption is scoped to blockquotes deliberately — exempting whole files would let a real
regression through.

## 9. Second upstream: Matt Pocock's skills

Upstream: `mattpocock/skills` @ `4588b32ecab9ecc9fc8cc6b6c5e7d675b6004b0d`, the skills its
`.claude-plugin/plugin.json` promotes. `transform/mattpocock.tsv` classifies each one, and
`transform/mattpocock.py` imports them after pstack's Cursor rules and before frontmatter
normalisation.

**The split is by phase (user decision, 2026-10-05).** Matt's skills ask the human and wait
for confirmation; pstack's proceed and report. Both stances are right in their own phase.
Deciding what to build belongs to the human, so grilling's confirmation is the gate there.
Building an agreed spec or ticket is the agent's, so pstack's autonomy applies. The router
half lives in three `transform/rules.pl` lines on `poteto-mode` and the Bug fix playbook, so
the dead-rule audit catches an upstream reword of their anchors.

| Conflict found in the overlap map | Resolution |
|---|---|
| Both packs ship `tdd`, with opposite stances (opt-in regression gate vs test-first features) | Merged in `overlay/skills/tdd/SKILL.md`. Seams are agreed while deciding and taken from the ticket while building; the agent never stops to ask for them. Matt's `tests.md` and `mocking.md` ship beside it. Both upstream versions are drift-watched. |
| Both packs ship `teach` for different jobs | Matt's is imported as `course`. |
| Matt's `prototype` puts UI variants on the real route; the Prototype playbook keeps sketches out of production source | `prototype` excluded. `wayfinder`'s call to it now points at the playbook (an asserted edit in `mattpocock.py`). |
| Matt's `pr` template and the Opening a PR playbook prescribe different PR bodies | `pr` excluded. |
| Matt's `code-review` clashes with the built-in `code-review` by name | Excluded. `interrogate` and `blast-radius` review here. |
| `unslop` would strip the emoji markers and coined terms ("frontier", "tracer bullet") Matt's templates depend on | The prose trigger in `poteto-mode` now says grilling rounds, specs, tickets and glossaries keep their own skills' templates and terms. |
| Matt's user-only skills (`disable-model-invocation`) cannot be routed to | Dropped on the core skills, as for pstack's own. Kept on the extras (`triage`, `course`, `to-questionnaire`), which nothing routes to. |
| `pr` carries a `metadata` key, which a plugin skill may not have | Dropped by `transform/frontmatter.py`, nested lines included. The credit ships in the skill's `CREDITS.md`. |

**Known gaps.**
- `budget.sh` caps fan-out at 3 subagents per step on `balanced`. That cap also applies to
  Matt's design-it-twice (3 or more subagents) and to grilling's fact-finding subagents.
- `setup-matt-pocock-skills` and its dependents name `/setup-matt-pocock-skills` without the
  `pstack-cc:` prefix. `UNVERIFIED:` whether a bare slash name resolves to a plugin skill;
  the Skill tool loads it either way.
- Codex reads this plugin through its own marketplace entry. Matt's per-skill
  `agents/openai.yaml` files ship unchanged, so his skills keep their Codex metadata.
  pstack's skills have none.
