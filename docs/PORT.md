# Port record — pstack (Cursor) → pstack-cc (Claude Code)

Upstream: `cursor/plugins` @ `032be146865d973682535de75f2287da438550bf`, `pstack/` only.
Every decision below is implemented in `transform/` or `overlay/`, never by hand-editing
generated output.

## 1. Packaging

| Upstream | Here | Note |
|---|---|---|
| `.cursor-plugin/plugin.json` | `.claude-plugin/plugin.json` + `marketplace.json` | The upstream repo has **no** `.claude-plugin/` and no `marketplace.json`, so there was nothing to install. |
| `displayName`, `logo`, `category`, `tags`, `skills`, `agents` keys | dropped | `MEASURED:` not present in any real Claude Code `plugin.json` on this machine; `skills/` and `agents/` are auto-discovered. `category`/`tags` are marketplace-entry keys and moved there. |
| — | `hooks/hooks.json` | `MEASURED:` auto-discovered, not referenced from `plugin.json` (same as superpowers 6.3.0). |

**`claude plugin validate` does not check SKILL.md.** `MEASURED:` reintroducing `mode`,
`icon`, `color` and `reminder` on a skill still passed validation. `tests/lint-skills.py`
is the check that actually catches a bad port; `import.sh` runs it and fails on any problem.

## 2. Frontmatter

Dropped from `poteto-mode` (Cursor-only, no Claude Code meaning): `mode`, `icon`, `color`,
`reminder`. `reminder` is not discarded — it is extracted to `hooks/reminder.txt` and used by
the stickiness hook, so it tracks upstream.

Names slugged to lowercase-hyphen: `Poteto Mode` → `poteto-mode`, `Make Bot UI` →
`make-bot-ui`, `Comment Sicko` → `comment-sicko` (and the reference at
`no-comments/SKILL.md`). `is_background:` → `background:`.

Kept unchanged: `disable-model-invocation` (46 skills) and `paths` — both are supported here
with the same meaning. This is why the pack is slash-only and cannot degrade skill routing.

## 3. Mechanisms with no Claude Code equivalent — what replaced them

| Cursor mechanism | Replacement |
|---|---|
| `mode: true` + `reminder:` (Custom Mode pinning via `Opt+Enter`) | `hooks/poteto-mode.sh`, a plugin-shipped `UserPromptSubmit` hook. Typing `/poteto-mode` arms it for the session; `/poteto-off` disarms. 14 functional tests in `tests/`. |
| `/goal` (persistent cross-turn objective) | Same hook. `/goal <text>` stores it per session and re-injects every turn; `/goal clear` clears. Needed by `autopilot-*` and `multi-phase-plan`. |
| `~/.cursor/rules/pstack-models.mdc` (`alwaysApply: true`) | `~/.claude/pstack-models.md`, a plain file each skill reads explicitly — which is how the skills were already written (*"when present … otherwise the table defaults"*). Written by `/pstack-cc:setup-pstack`. |
| Cursor built-in `create-skill` | `anthropic-skills:skill-creator`. |
| `cursor-team-kit`'s `control-ui` / `control-cli` | The built-in browser tools (`mcp__Claude_Browser__*`) and Bash/tmux. |
| `/deslop` (`cursor-team-kit`) | `/pstack-cc:unslop`, which is the same job and ships here. |
| `~/.cursor/projects/<slug>/agent-transcripts/` | `~/.claude/projects/<slug>/`. |
| `~/.cursor/plugins/` | `~/.claude/plugins/`. |
| Cursor cloud agents (`environment: "cloud"`) | Left as prose. Nearest equivalents are an `Agent` with `isolation: "worktree"` and a cloud session; neither is a drop-in, so the playbooks that assume one VM per PR (`orchestrate`, both `autopilot-*`) are **the least faithful part of this port**. |

## 4. Model slugs

Upstream's 69 slug references across 15 files map to Claude Code aliases:

| Upstream | Here |
|---|---|
| `claude-opus-5-thinking-xhigh` | `opus` |
| `claude-fable-5-1-thinking-max` | `fable` |
| `gpt-5.6-sol-max` | `opus` |
| `grok-4.6-fast-xhigh` | `sonnet` |

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
- **Nothing here has been run inside a live Claude Code session yet.** The generator, linter
  and hook tests all pass; skill *behaviour* under the real harness is unverified until the
  plugin is installed and used.

## 7. The forbid gate

`transform/forbid.txt` lists patterns that must not survive into `skills/` or `agents/`:
`.cursor/`, `cursor-agent`, `CURSOR_*`, `cursor-team-kit`, `pstack-models.mdc`,
`api2.cursor.sh`, every model slug, `generalPurpose`, `--squash`, `is_background`.

A hit fails `import.sh` with a non-zero exit. Blockquoted port notes are exempt, so a
`> **Ported from upstream.**` paragraph may name what it replaced without tripping the gate.
That exemption is scoped to blockquotes deliberately — exempting whole files would let a real
regression through.
