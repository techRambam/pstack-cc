---
name: interrogate
description: "Use for \"interrogate\", \"adversarial review\", \"multi-model review\", \"challenge this\", \"stress test this code\", \"find blind spots\", or \"tear this apart\". Multiple LLM reviewers challenge changes from independent angles."
---

# Interrogate

Spawn one reviewer per configured model to adversarially review code changes. The adversarial signal comes from model diversity, not assigned personas. The deliverable is a synthesized verdict. Do NOT auto-apply changes.

## Step 1, Scope

Identify what to review from context:

- If the user points at specific files or a diff, use that.
- If on a feature branch, run `git diff main...HEAD` (or the appropriate base branch) for the full changeset.
- If the user's message references recent work, gather the relevant files.

Package the diff or file contents with any surrounding context files the reviewers need to understand the code.

Also collect the repo's coding standards. Search the files tracked at the base you diff against (`git ls-tree -r --name-only <base>`), skipping vendored and generated trees, for every file that documents how the code should be written, such as `CONTRIBUTING.md`, `CODING_STANDARDS.md`, a style guide, or the coding sections of `AGENTS.md` or `CLAUDE.md`. If `CONTRIBUTING.md` or `CODING_STANDARDS.md` exists, it must be on the list. Read each file from the base you diff against (`git show <base>:<path>`), so a change cannot loosen the rules it is judged by. If the diff edits, renames, or deletes one of these files, say so. Package the passages that govern how code is written, each under a heading with its repo-relative path, as the repo standards, or "none found" if the repo has none.

## Step 2, Intent

Before spawning reviewers, state the intent in one clear paragraph from the user's message, commit messages, the PR description if one exists, and the code. If you're unsure about the intent, ask the user before proceeding.

## Step 3, Spawn Reviewers

Launch all reviewers in a single message with the Agent tool, one per entry on the `interrogate reviewers` line in `~/.claude/pstack-models.md`, labeled Reviewer A, B, and so on to match the entry count. If the rule or that line is missing, use the table defaults.

| Subagent | Default model |
|----------|---------------|
| Reviewer A | `opus` |
| Reviewer B | `sonnet` |

Each reviewer gets `subagent_type: "pstack-cc:read-only"` (no edit tools, no `Agent`: it reports and never changes the tree), and `model` set to its configured entry, or its table default when there is no configured line. Omit `model` for an `auto` or `inherit-parent` entry, so that reviewer runs on the parent model.

If the Agent tool rejects a configured entry, run that reviewer on its family's table default and say so. Families go by prefix: `claude-*`. With no family match, use Reviewer A's default. If it rejects a table default, spawn with the closest equivalent from the valid slugs in its error message (prefer the same family and reasoning tier), and open a separate PR to update the default table. Do not block the review on the slug issue. Never treat an alias entry as a rejected slug or apply either fallback to it.

Read `references/reviewer-prompt.md` and fill in the same template for every reviewer, cross-vendor seats included, with the stated intent, the diff or file contents, the repo standards from Step 1, the rubric from `references/rubric.md`, and the code-quality lens from `references/code-quality-review.md`. Pick each subagent's model for the job, per the Subagents section of the **poteto-mode** skill.

## Step 4, Synthesize

As results come back, build a unified picture. Parse every reviewer's findings. Merge findings that describe the same issue differently, and note which models raised each one. Findings two or more models raised independently are the highest signal. Read a lone model's finding, but weight it accordingly. Note disagreements. If one model flags something and another explicitly says the opposite, that is context for the verdict.

## Step 5, Lead Judgment

You are the lead reviewer, a pragmatic senior engineer, not a neutral aggregator. Read `references/lead-judgment.md` for the full framework. Put every finding in one of four buckets, with the model(s) that raised it and a one-line rationale.

- **Act on**. Real issues affecting correctness, security, or maintainability given the actual goals. They would block a real PR.
- **Consider**. Legitimate, but you're not sure they outweigh the cost of addressing them now. Worth the user's attention.
- **Noted**. Technically valid but not actionable. Context-dependent, premature optimization, or low-impact at this stage.
- **Dismissed**. Wrong, nitpicky, or missing context, with a brief reason.

## Output Format

### Intent
> [The stated intent paragraph from Step 2]

### Reviewers
- Reviewer [label]: [model name], [N findings] (one bullet per reviewer)

### Act On
[Each: description, which models raised it, why it matters.]

### Consider
[Each: description, which models raised it, the tradeoff.]

### Noted
[Brief list.]

### Dismissed
[Each with a brief rationale.]

### Agreement Map
[Where models agreed and diverged, and what that pattern tells us.]

## Cross-vendor panelists

This skill's value comes from **model diversity, not personas**. Claude Code's
`Agent` tool reaches Anthropic models only, so a panel built purely from it is
one family wearing different hats — weaker than what this skill assumes.

Use both dispatch routes in the same panel, in parallel:

- **Anthropic seats** → the `Agent` tool with `model:` set to `opus`, `fable`,
  `sonnet` or `haiku`. Never route these through `panelist`. A seat that only reviews
  or judges uses `subagent_type: "pstack-cc:read-only"`, so it cannot edit the tree or
  spawn a fan-out of its own; a seat that writes a candidate keeps `general-purpose`.
- **Other-vendor seats** → Bash, one call per seat:

```bash
${CLAUDE_PLUGIN_ROOT}/bin/panelist run -m gpt-5.6-sol -p /tmp/seat-a.md --schema /tmp/verdict.json
```

```bash
${CLAUDE_PLUGIN_ROOT}/bin/panelist run -m gemini-3-flash-preview -p /tmp/seat-b.md --schema /tmp/verdict.json
```

A `gpt-*`, `gemini-*` or `vendor:model` entry in a model line or a default table
is one of these seats; never pass it to the `Agent` tool's `model`. A seat that must
produce a candidate (an arena runner) returns it as a unified diff or whole files
in its answer, and you write that into the candidate's slot.

Write the seat's prompt to a file and pass `-p`; write one plain JSON Schema and
pass the same `--schema` file to every seat. `panelist` converts it per vendor
(OpenAI strict mode and Gemini's OpenAPI subset disagree about `required` and
`additionalProperties`, so one file cannot satisfy both raw).

`panelist doctor` lists which models answer right now. Reachable today: OpenAI
via the org `codex` CLI (`gpt-6-astra`, `gpt-5.6-sol`, `gpt-5.6-luna`,
`gpt-5.6-terra`, `gpt-5.5`), or via `OPENAI_API_KEY` where `codex` is absent (a
cloud session), and Google's free tier (`gemini-3-flash-preview`,
`gemini-3.5-flash`, `gemini-2.5-flash`, `gemini-3.1-flash-lite`). Gemini **pro**
returns HTTP 429 — free tier is flash-class only, so weight a Gemini seat
accordingly rather than treating it as a peer of an Opus seat.

A fourth route is wired but unkeyed: **OpenRouter**, which reaches many model
*families* through one key (DeepSeek, Qwen, GLM, Nemotron, Gemma, Cohere — 22
free-tier models). Every currently-reachable seat is a GPT, a Gemini or a
Claude, so OpenRouter is where genuinely different architecture would come from.
If `panelist doctor` says NO KEY, note in your verdict table that the panel is
three-vendor rather than four, and carry on.

Seats are read-only by construction: `panelist` runs `codex exec -s read-only`
and Gemini has no tool access at all. A panelist reviews and reports; it never
edits the tree.

Run each seat's Bash call with `run_in_background: true` when it may take more than a few
minutes. A foreground call is killed at 600s, and `panelist`'s own default timeout (540s)
sits just under that so a slow seat reports "timed out" instead of vanishing. Pass `-t` for
longer seats.

**A seat counts only if it delivered.** That means exit status 0, a non-empty
answer, and (under `--schema`) JSON that parses against the schema. Anything else
is a **dropout**: name the seat, its model and the error in the verdict table, and
carry on with the seats you have. Never substitute another model for a dropout
silently, and never let one model fill two seats to keep the count up, because
the panel exists for model diversity. A panel of three that names its missing
fourth is honest; reporting three as if four voted is not.
