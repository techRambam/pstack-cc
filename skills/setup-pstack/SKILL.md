---
name: setup-pstack
description: Configure pstack-cc's per-role model choices for Claude Code. Writes ~/.claude/pstack-models.md, which arena, interrogate, swarm, architect, how, why and reflect read when present. Use for /setup-pstack, "configure pstack models", or after installing pstack-cc.
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

Run `panelist doctor` before choosing: it reports which models answer right now. Note that
Gemini's **pro** models return HTTP 429 on the current key, so Gemini seats are flash-class —
a useful third voice, not a peer of an Opus seat. Weight them accordingly.

## Steps

### 1. Check for an existing config

Read `~/.claude/pstack-models.md`. If it exists, treat its `# budget` line and role values as
the current choices and edit from there. Otherwise start from the defaults in step 3.

### 2. Ask for a budget

Ask the user which budget they want, with `AskUserQuestion`:

- **max** — `opus` for judgment and the hardest work, `fable` for prose and cross-judging.
- **balanced** — `sonnet` for build roles, `opus` only for judgment and panels.
- **cheap** — `sonnet` throughout, `haiku` for bulk fan-out, `opus` only for a final judge.

### 3. Write the file

Overwrite the whole file so re-runs stay idempotent. Shape:

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
judgment and prose: fable
hardest tasks: opus
how explorer: sonnet
how explainer: fable
why investigators: sonnet
why synthesizer: fable
reflect tooling: opus
reflect judgment, divergent, synthesizer: fable
arena runners: opus, gpt-6-astra, gemini-3-flash-preview, huggingface:Qwen/Qwen3-235B-A22B-Instruct-2507
arena cross-judge pool: opus, gpt-6-astra, gemini-3-flash-preview, openrouter:deepseek/deepseek-v4-flash-0731:free
swarm workers: sonnet
architect runners: opus, gpt-6-astra, gemini-3-flash-preview, openrouter:deepseek/deepseek-v4-flash-0731:free
interrogate reviewers: opus, gpt-6-astra, gemini-3-flash-preview, openrouter:deepseek/deepseek-v4-flash-0731:free
```

Valid model values:

Non-Anthropic models are addressed **`vendor:model`**, because ids collide —
`qwen/qwen3.8-27b` exists on both Groq and OpenRouter.

| Vendor | Values | Dispatch |
|---|---|---|
| Anthropic | `opus`, `sonnet`, `haiku`, `fable`, `inherit` | the `Agent` tool's `model:` |
| OpenAI | `gpt-6-astra`, `gpt-5.6-sol`, `gpt-5.6-luna`, `gpt-5.6-terra`, `gpt-5.5` | `panelist` → `codex exec` |
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

Tell the user the file was written and that skills pick it up on their next invocation. No
restart is needed. Re-running this skill updates it.

### 5. Offer a verification skill (optional)

Check whether the project has a way to drive the real app for proof (a `verify-*` skill, or
an existing harness). If not, offer once: "want a project-local verification skill, so agents
can drive the app the way a user does and prove changes work? I can generate one with
`/pstack-cc:create-verification-skill`." On yes, invoke it. On no, move on without pushing.
