---
name: swarm
description: "Fan out N parallel workers, drain them, and return one report. Use for /swarm, 'swarm this', or parallel coverage, races, gauntlets, and exploration."
disable-model-invocation: true
---

# Swarm

Fan out N parallel cloud workers. They may cover separate slices, race the same brief, or mix both. The parent waits, aggregates, and returns one report.

## Start

Open a todolist with one entry per phase before launching anything.

1. Frame
2. Fan out
3. Aggregate
4. Report

## Phase A: Frame

1. State the done predicate and the artifact or report the swarm must return.
2. Choose the shape. Partition into slices, race N workers on identical briefs, or mix both. For a race or mixed shape, declare `first pass`, `rank all`, or `best-of` before spawning.
3. Set N from the user or derive it from the shape. N is total workers, not the cloud concurrency limit.
4. Pick the worker model from `swarm workers` in `~/.claude/pstack-models.md` when present. Otherwise use `sonnet`. For a model race, name each arm's model up front.
5. Give each worker its own writable output when it writes.

## Phase B: Fan out

Spawn all N workers in one message with `subagent_type: general-purpose`, `environment: "cloud"`, `run_in_background: true`, and the configured model. Use `environment: "local"` only when the worker needs access to something on the user's computer.

When a worker must start from a non-default pushed branch, pass `cloud_base_branch`.

Every brief stands alone. Include the goal, scope, exact slice or race arm, how to verify, and what to report. Reports use `PASS`, `ISSUES`, or `BLOCKED` with evidence.

If a worker drops out, proceed with N-1 and note it.

## Phase C: Aggregate

Read the terminal results. For coverage, every required slice needs a result. For a race, apply the selection rule declared up front. Use first pass, rank all, or best-of. Do not paste raw worker dumps.

Keep a compact result table, one-line evidenced issues, and explicit gaps or dropouts.

## Phase D: Report

Return one consolidated in-chat report with the table, issue one-liners, gaps or dropouts, and the race rule when used.

## Cross-vendor panelists

This skill's value comes from **model diversity, not personas**. Claude Code's
`Agent` tool reaches Anthropic models only, so a panel built purely from it is
one family wearing different hats — weaker than what this skill assumes.

Use both dispatch routes in the same panel, in parallel:

- **Anthropic seats** → the `Agent` tool with `model:` set to `opus`, `fable`,
  `sonnet` or `haiku`. Never route these through `panelist`.
- **Other-vendor seats** → Bash, one call per seat:

```bash
${CLAUDE_PLUGIN_ROOT}/bin/panelist run -m gpt-5.6-sol -p /tmp/seat-a.md --schema /tmp/verdict.json
```

```bash
${CLAUDE_PLUGIN_ROOT}/bin/panelist run -m gemini-3-flash-preview -p /tmp/seat-b.md --schema /tmp/verdict.json
```

Write the seat's prompt to a file and pass `-p`; write one plain JSON Schema and
pass the same `--schema` file to every seat. `panelist` converts it per vendor
(OpenAI strict mode and Gemini's OpenAPI subset disagree about `required` and
`additionalProperties`, so one file cannot satisfy both raw).

`panelist doctor` lists which models answer right now. Reachable today: OpenAI
via the org `codex` CLI (`gpt-6-astra`, `gpt-5.6-sol`, `gpt-5.6-luna`,
`gpt-5.6-terra`, `gpt-5.5`) and Google's free tier (`gemini-3-flash-preview`,
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

If a seat errors, say so in the verdict table and carry on with the seats you
have. A panel of three that names its missing fourth is honest; silently
reporting three as if four voted is not.
