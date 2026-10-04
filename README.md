# pstack-cc

[pstack](https://github.com/cursor/plugins/tree/main/pstack) by Lauren Tan (@poteto),
adapted for **Claude Code**. 50 skills, 23 playbooks, 24 principles, 2 agents.
Works in local sessions and in [cloud sessions](#cloud-sessions).

Upstream is a *Cursor* plugin — it has a `.cursor-plugin/plugin.json` and no Claude Code
manifest anywhere in the repo, so there is nothing to `/plugin install`. This repo is that
plugin, regenerated for Claude Code.

## Not a fork — a generator

`skills/` and `agents/` are **generated output. Never hand-edit them.** They are produced by
`./import.sh` from a pinned upstream ref, through:

| Piece | Job |
|---|---|
| `transform/rules.pl` | deterministic substitutions (paths, tool names, model slugs, merge policy) |
| `transform/frontmatter.py` | drops Cursor-only keys, slugs names, extracts the poteto-mode reminder |
| `overlay/` | whole-file replacements for what a regex cannot fix |
| `transform/forbid.txt` | patterns that must **not** survive — a hit fails the build |
| `tests/` | a frontmatter linter and functional tests for the hooks and cloud-session support |

To update: bump `UPSTREAM_REF` in `import.sh`, run it, read the diff.

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
./bin/panelist doctor
```

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
dropped from every skill except `make-bot-ui`. The descriptions are explicit ("Use for /how"),
so the skills stay out of unrelated requests.

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
starts a fresh container from a fresh clone. It **ignores** plugins a repository enables in
`.claude/settings.json` and plugins in your local user settings
([docs](https://code.claude.com/docs/en/cloud-environments#what-carries-over-from-your-setup)),
so the `Install` steps above do nothing there. Two routes work:

**Any plan: load the plugin from a directory.** In the cloud environment's settings at
claude.ai/code, add a setup script that clones the plugin, and an environment variable that
points Claude Code at it:

```bash
git clone --depth 1 https://github.com/techRambam/pstack-cc /opt/pstack-cc
```

```text
CLAUDE_CODE_PLUGIN_DIRS=/opt/pstack-cc
```

The plugin then loads as `pstack-cc@inline`, with its skills, agents, hooks and `bin/`. The
setup script runs when the environment's cache is built, so the clone is a snapshot. It
refreshes when you edit the script or the cache expires after about seven days. This
repository is private, so the clone needs read access from the environment. If it fails,
use the route below or make the repository public; upstream is MIT.

**Team and Enterprise: server-managed settings.** An Owner adds this at
**Organization settings > Claude Code > Managed settings**. Cloud sessions fetch it before
they install plugins:

```json
{
  "extraKnownMarketplaces": {
    "pstack-cc": { "source": { "source": "github", "repo": "techRambam/pstack-cc" } }
  },
  "enabledPlugins": { "pstack-cc@pstack-cc": true }
}
```

Once loaded, `hooks/cloud-session.sh` (a `SessionStart` hook that only speaks when
`CLAUDE_CODE_REMOTE=true`) tells the model what differs from a laptop, so the fifty generated
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
./bin/panelist doctor
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
