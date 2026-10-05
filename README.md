# pstack-cc

[pstack](https://github.com/cursor/plugins/tree/main/pstack) by Lauren Tan (@poteto),
adapted for **Claude Code**, with [Matt Pocock's skills](https://github.com/mattpocock/skills)
folded into the same workflow. 68 skills, 24 playbooks, 24 principles, 3 agents.
Works in local sessions and in [cloud sessions](#cloud-sessions).

Upstream is a *Cursor* plugin — it has a `.cursor-plugin/plugin.json` and no Claude Code
manifest anywhere in the repo, so there is nothing to `/plugin install`. This repo is that
plugin, regenerated for Claude Code.

## Not a fork — a generator

The plugin is `plugins/pstack-cc/`. That is all an install copies; the generator, tests and
reference material around it stay in the repo. Its `skills/` and `agents/` are **generated
output. Never hand-edit them.** They are produced by `./import.sh` from two pinned upstream refs,
through:

| Piece | Job |
|---|---|
| `transform/rules.pl` | deterministic substitutions (paths, tool names, model slugs, merge policy) |
| `transform/frontmatter.py` | drops Cursor-only keys, slugs names, hides principles from `/`, preloads poteto-mode into `poteto-agent`, extracts the reminder |
| `transform/readonly.py` | maps Cursor's `readonly` spawn flag onto the `pstack-cc:read-only` agent |
| `overlay/` | whole-file replacements for what a regex cannot fix |
| `own/` | files this port adds that upstream never had (the `read-only` agent); fails if upstream later ships the same path |
| `transform/forbid.txt` | patterns that must **not** survive — a hit fails the build |
| `tests/` | a frontmatter and cross-reference linter, and functional tests for the hooks and cloud-session support |
| `CHANGES.md` | what each update brought; CI fails a plugin change that adds no entry |

To update: bump `UPSTREAM_REF` (pstack) or `MATT_REF` (Matt Pocock's skills) in `import.sh`,
run it, read the diff.

```bash
./import.sh
```

Because the output is regenerated rather than merged, there are **never merge conflicts** —
new upstream skills appear, deleted ones vanish. Four guards make an upstream change loud
instead of silent, and each one fails the build:

| Guard | Catches |
|---|---|
| `transform/forbid.txt` | upstream reintroducing a Cursor dependency (`.cursor/`, a model slug, `--squash`, `generalPurpose`) |
| `transform/audit.py` — dead rules | a rule that fired **zero** times, i.e. upstream reworded the prose it anchors on. Known-zero rules are listed with reasons in `transform/optional-rules.txt` |
| `transform/audit.py` — overlay drift | upstream **rewriting a file `overlay/` replaces**. Without this the override silently wins and you never see their change. Re-accept deliberately: `./import.sh --accept-overlay` |
| `transform/panels.py` | upstream renaming a panel skill, which would drop the cross-vendor section |

Vendor model ids rot on their own schedule (`gemini-2.5-pro` already answers *"no longer
available to new users"*). `panelist doctor` exits non-zero when a keyed vendor has no
working model, so it can be used as a check — an unfunded account is reported separately and
does not count as a failure.

```bash
./plugins/pstack-cc/bin/panelist doctor
```

## Matt Pocock's skills, in the same flow

pstack is strong at building and proving: architect, verify on the real surface,
multi-model review, autonomy. Matt Pocock's skills are strong at deciding what to build with
you: grilling, a glossary and ADRs, specs and tickets. This plugin runs both as one workflow,
split by phase.

| Phase | Who decides | Skills |
|---|---|---|
| Deciding what to build | You. The agent asks, and your confirmation is the gate. | The Deciding playbook: `setup-matt-pocock-skills` once per repo, `grill-with-docs` (`grilling` plus `domain-modeling`), `to-spec`, `to-tickets`, `wayfinder` for work bigger than a session |
| Building an agreed spec or ticket | The agent, autonomously | pstack's Feature and Bug fix playbooks, one ticket at a time in blocking order. The ticket's acceptance criteria are the verify predicate, `tdd` tests at its seams under test, and merging the work closes it. Autopilot-stack when you ask for it. |

Specs and tickets go to the tracker that `/pstack-cc:setup-matt-pocock-skills` records, once per
repo. Choose GitHub issues when it asks; it proposes them for a GitHub remote. In a cloud
session `gh issue` is refused like the rest of GraphQL, and the cloud note points the skills at
the `mcp__github__*` issue tools instead.

**Turn off Matt's own plugin** wherever pstack-cc is on. With both enabled, two `tdd` skills
with opposite stances are live, and his excluded skills come back. In Claude Code, run
`claude plugin disable mattpocock-skills@mattpocock`. In Codex, set
`[plugins."mattpocock-skills@mattpocock"] enabled = false` in `~/.codex/config.toml`.

Matt's repo is a second pinned upstream of the same generator (`MATT_REF` in `import.sh`).
[`transform/mattpocock.tsv`](transform/mattpocock.tsv) classifies every skill his plugin
promotes:

| Role | What happens | Skills |
|---|---|---|
| core | imported, and routed to from `poteto-mode` or the Deciding playbook (`grill-me` is a typed entry point to `grilling`) | grilling, grill-me, grill-with-docs, domain-modeling, codebase-design, improve-codebase-architecture, to-spec, to-tickets, wayfinder, research, diagnosing-bugs, setup-matt-pocock-skills, writing-for-agents, handoff |
| merge | folded into pstack's skill of the same name | tdd: Matt's test-first vertical slices for new behavior plus pstack's regression gate for bugs |
| extra | imported, but nothing routes to them, and they keep Matt's user-only flag | triage, course (Matt's `teach`, renamed because pstack's `teach` is a different job), wizard, to-questionnaire |
| exclude | not imported; pstack covers the job | ask-matt, implement, implement-spec, prototype, code-review, pr, retro, wait-what |

Three more guards fail the build, the same way pstack's do:

| Guard | Catches |
|---|---|
| `transform/mattpocock.py`, manifest check | Matt promoting a skill the manifest does not classify, or removing one it names |
| `transform/mattpocock.py`, edits | an edit to his text no longer matching exactly as often as expected (for example, `wayfinder`'s call to his excluded `prototype` skill now points at the Prototype playbook) |
| `transform/mattpocock.py`, merge rows | a merge row with no `overlay/` SKILL.md, which would ship pstack's skill unmerged |
| `transform/audit.py`, merge drift | Matt rewriting or deleting his `tdd/SKILL.md`, which the merged overlay replaces |

`tests/lint-skills.py` checks every skill named in a Skill-tool call (`Call the Skill tool with
"<name>"`, `the Skill tool twice, for "a" and "b"`) against the skills this plugin ships, and every
link to a sibling `.md` file. It also fails when a skill is user-only in Claude Code but not in
Codex (`agents/openai.yaml`), or the other way round, and when an extra loses Matt's flag.
`tests/mattpocock-guards.sh` breaks each guard in a scratch copy and checks that the build fails.

## Install

```bash
claude plugin marketplace add ~/Developer/pstack-cc
```

```bash
claude plugin install pstack-cc@pstack-cc
```

Restart Claude Code, then `/pstack-cc:setup-pstack` to write your model-role config.

Everything is namespaced (`/pstack-cc:how`, `/pstack-cc:tdd`), so nothing shadows a built-in
or another pack. Upstream marks its skills `disable-model-invocation: true`. Claude Code reads
that flag more strictly than upstream intends: it refuses Claude's own Skill tool call, so
poteto-mode could not route to `/how`, `/why` or a principle skill. The flag is therefore
dropped from every skill except `make-bot-ui` and Matt Pocock's unrouted extras (`triage`,
`course`, `to-questionnaire`), which nothing routes to. The descriptions are explicit ("Use for /how"),
so the skills stay out of unrelated requests. The 24 `principle-*` skills are
`user-invocable: false` instead: other skills route to them, but they stay out of your `/` menu.

Claude Code gives the skill listing 1% of the context window, 30,000 characters on a
1M-context Opus. A listing over that loses descriptions, least-used skills first, and those
skills show by name only. This plugin lists 64 skills in 11,185 characters. With a few other
plugins installed the listing overflows, and a skill reached only by its description, such as
`tdd`, can stop triggering. Add `"skillListingBudgetFraction": 0.013` to
`~/.claude/settings.json`, or disable skills you do not use. `docs/PORT.md` section 9 has the
measurements.

### Updating an install

`plugin.json` deliberately has **no `version`**. Claude Code keys its plugin cache by version,
so a pinned version keeps every install on its first copy until someone remembers to bump the
string. `0.1.0` stayed put through the commit that added `hooks/poteto-auto-arm.sh`, so older
installs never received that hook. Without a version, each commit's SHA is the version and
every push is an update:

```bash
claude plugin marketplace update pstack-cc && claude plugin update pstack-cc@pstack-cc
```

`claude plugin validate` warns about the missing version; that warning is the trade-off.

## Cloud sessions

A cloud session (claude.ai/code, the desktop or mobile app's cloud mode, `claude --cloud`)
starts a fresh container from a fresh clone, so none of the usual install routes reach it.
Each of these was tested in a real cloud session on 2026-10-04, and each failed:

| Route | What happened |
|---|---|
| `enabledPlugins` / `extraKnownMarketplaces` in a repo's `.claude/settings.json` | Ignored by design ([docs](https://code.claude.com/docs/en/cloud-environments#what-carries-over-from-your-setup)). |
| Plugin added to your claude.ai account (**Customize → Plugins**) | Not loaded. Only built-in plugins appear, though account *skills* do sync. |
| Plugin committed under a repo's `.claude/skills/<name>/` | Skipped: "workspace was not trusted", and cloud sessions never show the trust dialog. |
| `CLAUDE_CODE_PLUGIN_DIRS` in a repo's `.claude/settings.json` `env` | Not applied. Plugins load before project settings. |

**What works, on any plan: the cloud environment.** Edit the environment at claude.ai/code
(one time; it then covers every repo you open in that environment):

- **Setup script**: runs before Claude Code starts, and puts the plugin on disk:

  ```bash
  #!/bin/bash
  git clone --depth 1 https://github.com/techRambam/pstack-cc /opt/pstack-cc 2>/dev/null \
    || git -C /opt/pstack-cc pull --ff-only
  ```

- **Environment variable**: tells Claude Code to load it:

  ```text
  CLAUDE_CODE_PLUGIN_DIRS=/opt/pstack-cc/plugins/pstack-cc
  ```

`MEASURED:` a new session then reports `pstack-cc@inline` with all skills, the three agents,
and the budget and cloud notes from its SessionStart hooks. A wrong path shows up in the
session's startup event as `Path not found: <path>`.

The clone needs no credentials because this repository is public. The setup script runs when
the environment's cache is built, so the plugin is a snapshot: it refreshes when you edit the
script or the cache expires after about seven days.

**Team and Enterprise: server-managed settings** are the other route. An Owner adds this at
**Organization settings > Claude Code > Managed settings**, and cloud sessions fetch it before
they install plugins (documented; not tested here, since this account is on a Max plan):

```json
{
  "extraKnownMarketplaces": {
    "pstack-cc": { "source": { "source": "github", "repo": "techRambam/pstack-cc" } }
  },
  "enabledPlugins": { "pstack-cc@pstack-cc": true }
}
```

Once loaded, `plugins/pstack-cc/hooks/cloud-session.sh` (a `SessionStart` hook that only speaks when
`CLAUDE_CODE_REMOTE=true`) tells the model what differs from a laptop, so the generated
skills stay identical to upstream instead of forking for the cloud:

| Local assumption | In a cloud session |
|---|---|
| `gh` with GraphQL (`gh pr view`, `watch-pr`) | The session proxy refuses GraphQL. Use the `mcp__github__*` tools, and `subscribe_pr_activity` in place of polling. `watch-pr` exits 69 with that advice instead of retrying a refusal forever. |
| `~/.claude/pstack-models.md` | Home is discarded with the container. `setup-pstack` writes `.claude/pstack-models.md` in the repo, and the hook copies it home at every session start. Commit it. |
| `~/.claude/.env` for panel keys | Set the keys as environment variables in the cloud environment. `panelist` reads the environment, and it wins over the file. |
| `codex` for OpenAI seats | Not installed. With `OPENAI_API_KEY` set, bare `gpt-*` seats use the OpenAI API instead. |
| `touch ~/.claude/pstack-cc/always-on` | Set `PSTACK_CC_ALWAYS_ON=1` in the environment instead. |
| Built-in browser pane | Not available. Use Playwright; Chromium is preinstalled at `/opt/pw-browsers`. |
| `gt` (Graphite) for `orch` | Not installed, same as the known gap below. |
| Past sessions under `~/.claude/projects` | Only the current session is there, so `recall`, `reflect` and `automate-me` see no earlier sessions. |

Proxy-injected **API credentials** (Pro and Max) never reach the environment, so `panelist`
cannot use them yet. Use environment variables for panel keys.

## Staying inside a subscription's limits

On a Pro or Max plan, pstack's cost is mostly **subagents**: every panel seat, explorer,
investigator and swarm worker is a fresh context that re-reads its files and thinks on its
own. Three controls, in the order they pay off:

1. **Budget** (`/pstack-cc:setup-pstack`): `max`, `balanced` (recommended on a plan), or `lean`.
   It writes each role's model, and its `# budget:` line drives `hooks/budget.sh`, a
   SessionStart hook that caps fan-out: 3 subagents per step on balanced, 2 on lean. It also
   allows one Claude seat per panel and keeps arena, swarm and the autopilots for when you
   name them. **With no config at all, the hook applies `balanced`.** `PSTACK_CC_BUDGET=max`
   turns the caps off.
2. **Non-Claude panel seats.** `gpt-*`, `gemini-*` and `vendor:model` seats run through
   `panelist` and cost nothing against Claude limits. The skills' own default panels now use a
   GPT seat where upstream does, instead of the second Opus seat this port used to put there.
3. **Main session.** Spawns without a `model` inherit the main session's model and effort.
   Per token, Fable 5.1 costs 2.5× Opus 5.5, which costs 2× Sonnet 5.5, which costs 2× Haiku
   4.5. `pstack-cc:read-only` seats pin `effort: high` so they don't inherit `xhigh` or `max`.

Measure instead of guessing. `pstack-usage` reads Claude Code's own transcripts and shows the
share of usage by model, subagent type, effort and session, then says what to change first:

```bash
./plugins/pstack-cc/bin/pstack-usage --days 7
```

It prints token counts and metadata only, never message text. Shares are weighted by API price
ratios: a good proxy for what drains a plan, not an exact meter.

## poteto-mode is sticky here

Cursor pins a mode with `Opt+Enter` and re-injects its `reminder:` every turn. Claude Code
ignores both frontmatter keys, so `hooks/poteto-mode.sh` (a plugin-shipped `UserPromptSubmit`
hook) reproduces it:

| Type | Effect |
|---|---|
| `/poteto-mode <task>` | pins it for the session |
| `/poteto-off` | unpins |
| `/goal <text>` | sets a standing objective (emulates Cursor's `/goal`) |
| `/goal clear` | clears it |

The reminder text is extracted from upstream's own frontmatter at import time, so it tracks
upstream rather than drifting.

Typing `/poteto-mode` in every new session gets old. `hooks/poteto-auto-arm.sh` is a
`SessionStart` hook that pins the mode for you, and it is off until you ask for it:

```bash
touch ~/.claude/pstack-cc/always-on
```

Remove that file to stop arming new sessions. `PSTACK_CC_ALWAYS_ON=1` in the environment
does the same, which is the only form that survives a cloud session's fresh home directory. Only `source=startup` arms, so `/poteto-off`
holds for the rest of the session: `SessionStart` fires again on resume, clear, compact and
fork, and none of those re-pin what you turned off. A forked session starts unpinned for the
same reason.

## Panels stay cross-vendor

Upstream's `arena`, `interrogate`, `swarm` and `architect` draw their adversarial signal from
**model diversity across vendors**, not from assigned personas. Claude Code's `Agent` tool
reaches Anthropic models only, so `bin/panelist` supplies the other seats:

```bash
./plugins/pstack-cc/bin/panelist doctor
```

| Vendor | Route | Models |
|---|---|---|
| Anthropic | native `Agent` tool (`model:`) | `opus`, `sonnet`, `haiku`, `fable` |
| OpenAI | `codex exec`, org ChatGPT auth — **no API key needed** | `gpt-6-astra`, `gpt-5.6-sol`, `gpt-5.6-luna`, `gpt-5.6-terra`, `gpt-5.5` |
| OpenAI (no `codex`) | OpenAI API, `OPENAI_API_KEY` | the same ids; used when `codex` is absent |
| Google | Gemini REST, key from `~/.claude/.env` or the environment | `gemini-3-flash-preview`, `gemini-3.5-flash`, `gemini-2.5-flash`, `gemini-3.1-flash-lite` |

Write one plain JSON Schema and pass it to every seat — `panelist` converts it per vendor,
because OpenAI's strict mode and Gemini's OpenAPI subset disagree about `required` and
`additionalProperties`. Seats are read-only by construction (`codex exec -s read-only`;
Gemini has no tool access).

**Caveat:** Gemini **pro** returns HTTP 429 on the current key, so Google seats are
flash-class — a real third voice, not a peer of an Opus seat. There is no Grok access at all,
and the HuggingFace key in `~/.claude/.env` is dead (401), so no Llama/Qwen/Mistral seat
without a new key.

Live check (costs quota, not run by `import.sh`):

```bash
bash tests/panelist-live.sh
```

Full decision record: [`docs/PORT.md`](docs/PORT.md).

## Licence

Upstream is MIT (`LICENSE.upstream`). This adaptation keeps that licence and attribution.
Matt Pocock's skills are MIT too, and ship with their licence as `LICENSE.mattpocock`.
