---
name: setup-pstack
description: Configure pstack-cc's per-role model choices for Claude Code. Writes ~/.claude/pstack-models.md (or the repo's .claude/pstack-models.md in a cloud session), which arena, interrogate, swarm, architect, how, why and reflect read when present. Use for /setup-pstack, "configure pstack models", or after installing pstack-cc.
---

# Setup pstack-cc

Write `~/.claude/pstack-models.md`, a plain config file that sets pstack's model per role.
Skills read it when present and fall back to their own defaults when it is absent.

> **Ported from upstream.** Cursor's version wrote `~/.cursor/rules/pstack-models.mdc` with
> `alwaysApply: true`, so the mapping was injected into every turn. Claude Code has no
> always-applied rule format, so this is an ordinary file that each skill reads explicitly —
> which is how the skills were already written (`when present ... otherwise use the table
> defaults`). No behaviour is lost.

## Panels are cross-vendor again

Upstream drew its panels from several model vendors — the adversarial signal came from
architectural diversity, not from prompts. Claude Code's `Agent` tool reaches only Anthropic
models, so `bin/panelist` supplies the rest: OpenAI through the org `codex` CLI, Google
through the Gemini free tier. A panel therefore mixes two dispatch routes, and the model
lines below may name models from any of the three vendors.

Run `panelist doctor` before choosing: it reports which models answer right now. `panelist`
reads keys from `~/.claude/.env` and from the environment, so in a cloud session the keys
are environment variables set in the cloud environment's settings; nothing in the
container's home directory survives the session. A cloud container also has no `codex` CLI,
so there OpenAI seats need `OPENAI_API_KEY` (bare `gpt-*` ids fall back to the API route). Note that
Gemini's **pro** models return HTTP 429 on the current key, so Gemini seats are flash-class —
a useful third voice, not a peer of an Opus seat. Weight them accordingly.

## Steps

### 1. Check for an existing config

Pick the target file first:

- **Local session** → `~/.claude/pstack-models.md`.
- **Cloud session** (`CLAUDE_CODE_REMOTE` is `true`) → `.claude/pstack-models.md` at the
  repository root. The container's home directory is discarded when the session ends, so a
  file written there is lost. pstack-cc's SessionStart hook copies the repo file to
  `~/.claude/pstack-models.md` at the start of every cloud session, so the skills that read
  the home path find it.

Read the target. If it exists, treat its `# budget` line and role values as the current
choices and edit from there. A line whose role is not in step 3, such as `how critics`, is
from a retired role. Drop it. Otherwise start from the defaults in step 3.

### 2. Ask for a budget

On a subscription plan (Pro, Max), most usage goes to **subagents**: every panel seat,
explorer, investigator and swarm worker is a fresh context that re-reads its files and thinks
on its own. The budget sets two things: each role's model (this file), and the fan-out caps
that pstack-cc's `budget.sh` SessionStart hook injects (it reads the `# budget:` line).

Relative cost per token, Sonnet 5.5 = 1: **Fable 5.1 = 5, Opus 5.5 = 2, Sonnet 5.5 = 1,
Haiku 4.5 = 0.5**. A `gpt-*`, `gemini-*` or `vendor:model` seat runs through `panelist` and
costs **nothing** against Claude plan limits (it uses that vendor's quota instead).

Ask the user which budget they want, with `AskUserQuestion`. Recommend **balanced** for a
subscription plan:

- **max**: upstream's full fan-out, `opus` on every build and judgment role. Fastest way
  through a plan's limits; for API billing or a short, high-stakes run.
- **balanced** (recommended): `opus` only where a judgment is made (synthesizers, the
  explainer, the one Claude seat per panel); `sonnet` builds; panels are filled with
  non-Claude seats; at most 3 subagents per step.
- **lean**: `sonnet` for judgment, `haiku` for search and bulk work, no `opus` seat on panels,
  at most 2 subagents per step. Noticeably weaker on hard design and review calls.

| Role | max | balanced | lean |
|---|---|---|---|
| feature, refactoring / bug-fix / perf-issue / hillclimb | `opus` | `sonnet` | `sonnet` |
| judgment and prose | `opus` | `opus` | `sonnet` |
| hardest tasks | `opus` | `opus` | `opus` |
| how explorer | `sonnet` | `sonnet` | `haiku` |
| how explainer | `opus` | `opus` | `sonnet` |
| why investigators | `sonnet` | `sonnet` | `haiku` |
| why synthesizer | `opus` | `opus` | `sonnet` |
| reflect tooling | `opus` | `sonnet` | `sonnet` |
| reflect judgment, divergent, synthesizer | `opus` | `opus` | `sonnet` |
| arena runners | `opus`, `opus`, `gpt-6-astra`, `gemini-3-flash-preview` | `opus`, `sonnet`, `gpt-6-astra` | `sonnet`, `gpt-6-astra` |
| arena cross-judge pool | `opus`, `gpt-6-astra`, `gemini-3-flash-preview` | `gpt-6-astra`, `gemini-3-flash-preview`, `opus` | `gpt-6-astra`, `gemini-3-flash-preview` |
| swarm workers | `sonnet` | `sonnet` | `haiku` |
| architect runners | `opus`, `opus`, `gpt-6-astra`, `gemini-3-flash-preview` | `opus`, `gpt-6-astra`, `gemini-3-flash-preview` | `sonnet`, `gpt-6-astra`, `gemini-3-flash-preview` |
| interrogate reviewers | `opus`, `opus`, `gpt-6-astra`, `gemini-3-flash-preview` | `opus`, `gpt-6-astra`, `gemini-3-flash-preview` | `sonnet`, `gpt-6-astra`, `gemini-3-flash-preview` |

`panelist doctor` (see "Panels are cross-vendor again" above) says which non-Claude seats answer.
Replace any that don't with another vendor that does; never with a second Claude seat, which is
exactly the spend the budget avoids.

Two settings outside this file matter as much:

- **The main session's model and effort.** A role set to `inherit-parent` or `auto`, and any
  spawn that omits `model`, runs on the main session's model. Keep the main session on Opus
  (`/model`), not Fable, and at `/effort high` for routine work.
- **Measure before tuning further.** `${CLAUDE_PLUGIN_ROOT}/bin/pstack-usage` reads Claude
  Code's own transcripts and shows the share of usage by model, subagent type, effort and
  session, plus what to change first.

### 3. Write the file

Overwrite the whole file so re-runs stay idempotent. Write the chosen budget's column from the
table above. The `# budget:` line is required: `budget.sh` reads it to set the fan-out caps.
Shape, for balanced:

```
# pstack-cc model configuration. One line per role.
# Delete a line to fall back to the skill's own default.
# `inherit-parent` or `auto`: run on the parent chat's model (omit the Agent tool's `model`).
# Panels list several models; each entry is one subagent.
# budget: balanced

feature, refactoring: sonnet
bug-fix: sonnet
perf-issue: sonnet
hillclimb: sonnet
judgment and prose: opus
hardest tasks: opus
how explorer: sonnet
how explainer: opus
why investigators: sonnet
why synthesizer: opus
reflect tooling: sonnet
reflect judgment, divergent, synthesizer: opus
arena runners: opus, sonnet, gpt-6-astra
arena cross-judge pool: gpt-6-astra, gemini-3-flash-preview, opus
swarm workers: sonnet
architect runners: opus, gpt-6-astra, gemini-3-flash-preview
interrogate reviewers: opus, gpt-6-astra, gemini-3-flash-preview
```

Valid model values:

Non-Anthropic models are addressed **`vendor:model`**, because ids collide —
`qwen/qwen3.8-27b` exists on both Groq and OpenRouter.

| Vendor | Values | Dispatch |
|---|---|---|
| Anthropic | `opus`, `sonnet`, `haiku`, `fable`, `inherit` | the `Agent` tool's `model:` |
| OpenAI | `gpt-6-astra`, `gpt-5.6-sol`, `gpt-5.6-luna`, `gpt-5.6-terra`, `gpt-5.5` | `panelist` → `codex exec`, or the OpenAI API (`OPENAI_API_KEY`) when `codex` is absent |
| Google | `gemini-3-flash-preview`, `gemini-3.5-flash`, `gemini-2.5-flash`, `gemini-3.1-flash-lite` | `panelist` → Gemini REST |
| Groq | `groq:openai/gpt-oss-120b`, `groq:qwen/qwen3.8-27b` | `panelist` |
| Mistral | `mistral:ministral-8b-latest`, `mistral:open-mistral-nemo`, `mistral:ministral-3b-latest` | `panelist` |
| OpenRouter | `openrouter:deepseek/…`, `openrouter:google/gemma-…`, `openrouter:nvidia/nemotron-…`, `openrouter:z-ai/glm-…` | `panelist` |
| HuggingFace | `huggingface:meta-llama/…`, `huggingface:Qwen/…`, `huggingface:CohereLabs/…`, `huggingface:deepseek-ai/…` — 139 models, widest family spread | `panelist` |

> Not reachable today: **Cerebras** and **DeepSeek-direct** both answer
> `payment_required` / `Insufficient Balance` — their free tiers need billing
> set up. **xAI/Grok** has no access at all.

> **Ported from upstream.** Never write a Cursor slug here — `grok-4.6-fast-xhigh`,
> `gpt-5.6-sol-max` and `claude-opus-5-thinking-xhigh` resolve nowhere on any of the three
> vendors above. There is no Grok access at all on this setup.

### 4. Confirm

Tell the user the file was written, and list each line step 1 dropped. Skills pick the file up
on their next invocation. No restart is needed. Re-running this skill updates it.

In a cloud session, also copy the file to `~/.claude/pstack-models.md` so this session uses
it now, and tell the user to commit `.claude/pstack-models.md`. A cloud session's work is
lost unless it is committed and pushed.

### 5. Offer a verification skill (optional)

Check whether the project has a way to drive the real app for proof (a `verify-*` skill, or
an existing harness). If not, offer once: "want a project-local verification skill, so agents
can drive the app the way a user does and prove changes work? I can generate one with
`/pstack-cc:create-verification-skill`." On yes, invoke it. On no, move on without pushing.
