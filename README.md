# pstack-cc

[pstack](https://github.com/cursor/plugins/tree/main/pstack) by Lauren Tan (@poteto),
adapted for **Claude Code**. 47 skills, 23 playbooks, 23 principles, 2 agents.

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
| `tests/` | a frontmatter linter and functional tests for the hooks |

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
or another pack. 46 of 47 skills ship `disable-model-invocation: true` exactly as upstream
does, so they are slash-only and cannot compete with your other skills for routing.

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

Remove that file to stop arming new sessions. `/poteto-off` still unpins the session you are
in, because `SessionStart` does not run again mid-session.

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
| Google | Gemini REST, key from `~/.claude/.env` | `gemini-3-flash-preview`, `gemini-3.5-flash`, `gemini-2.5-flash`, `gemini-3.1-flash-lite` |

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
