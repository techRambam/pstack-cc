---
name: architect
description: "Sketch types, signatures, and module structure before code, then stay in the loop while implementation fills in. Use for /architect, 'architect this', 'design this', or non-trivial work where jumping to code would lock in the wrong shape."
---

# Architect

Design before implementing. Sketch types, function signatures, class shapes, and module boundaries with `not implemented` bodies and pseudocode. Synthesize across multiple model perspectives, then fill in code against the chosen sketch. If implementation proves the sketch wrong, throw it out and redesign.

## Start

Open a todolist with one entry per phase before starting.

1. Ground
2. Sketch
3. Agree
4. Implement
5. Scrap

## Phase A: Ground the problem

Build a real mental model of every system the new code touches. Run the **how** skill over the relevant subsystems.

Naming a file isn't grounding. Produce the traced model `how` prescribes. If the design redefines ownership or layering, also run the **why** skill on the existing shape so the rationale becomes a constraint, not a guess.

Skip Phase A only when the work is genuinely greenfield with no surrounding system to integrate.

## Phase B: Sketch

Run the **arena** skill with the design-sketch task and the Phase A grounding artifacts. Pass `references/runner-prompt.md` as each runner's prompt. Each candidate produces a design package shaped per `references/rationale-template.md`.

Take the runners from the `architect runners` line in `~/.claude/pstack-models.md`, in place of the `arena runners` line. If the rule or that line is missing, use `opus`, `gpt-5.6-sol`, `sonnet`. Alias and rejected entries follow the runner rules in the **arena** skill's Phase A.

Design it twice. Require at least two structurally distinct candidates before synthesis, even when the first looks sufficient. This is the **exhaust-the-design-space** principle skill made concrete. Whole-shape alternatives, not point fixes inside one shape.

Screen every candidate against [`references/design-red-flags.md`](references/design-red-flags.md) before synthesis. Assume the next contributor is an agent that sees only the files it opened, copies the nearest example, and takes the shortest path that compiles. Prefer the design where a change that looks right from one file is right for the whole repo.

Compare viable candidates on interface depth. Prefer the design that hides more complexity behind a smaller, simpler public surface. A rich interface can keep call chains short by concentrating capability instead of scattering it across layers.

Arena returns one synthesized design package. The synthesis decision populates the rationale's "Synthesis decision" section.

## Phase C: Agree (opt-in)

Default: proceed directly to implementation with the synthesized design. No human checkpoint.

Opt in to a checkpoint when the invoker explicitly asks: "/architect with checkpoint," "stop and show me before implementing," or similar. Then surface the synthesized design and pause for sign-off.

The synthesis can ship as its own commit either way, as the "scaffold first" mode of the **foundational-thinking** principle skill. Planned and scoped breakage during fill-in is fine, per the **outcome-oriented-execution** principle skill. For adversarial pressure on the design before implementing, run the **interrogate** skill on the synthesized sketch.

If the human pushes back on the shape (in a checkpoint or after the fact), treat that as Phase A evidence. Re-ground and re-run Phase B before writing more code.

## Phase D: Implement against the sketch

Replace `not implemented` bodies with code, pseudocode with logic. The synthesized sketch is the contract.

Deviations from the sketch are signal worth surfacing, not friction to absorb silently. If a function needs a parameter the sketch didn't anticipate, ask whether the sketch was wrong, the requirement was missed, or the implementation is overreaching.

## Phase E: Scrap when the architecture is wrong

If implementation keeps producing friction the sketch can't absorb, throw the sketch out. Don't bolt fixes onto a wrong design, per the **redesign-from-first-principles** and **fix-root-causes** principle skills.

The signal is a *pattern*, not single instances. Tells:

- The same shape of workaround appearing repeatedly across unrelated code.
- Multiple unrelated edge cases that all need special-case branches.
- Types that need escape hatches (`any`, casts, optional fields always set in practice) to compile.
- The "we need a lock" reflex when the sketch said the state wasn't shared.
- Callers having to know the abstraction's internal rules to use it.
- Two or more independent Phase D deviations of the same shape across the implementation.

Use judgment. A few edge cases don't condemn an architecture. Some problems are legitimately complex. Complexity in the data is not complexity in the design.

When you scrap:

1. Re-run the **how** skill over what's been built.
2. Redesign as if the new constraints had been day-one assumptions, per redesign-from-first-principles.
3. Subtract before adding, per the **subtract-before-you-add** principle skill. The new sketch should be smaller than the old one before it grows.
4. Return to Phase B and re-run arena.

## Outputs

The caller's usage is written first and the type sketch derived from it. One file with new types and signatures for small changes. Module map plus type definitions for larger work. The rationale ships alongside, shaped per `references/rationale-template.md`, including the usage sketch and the synthesis decision.

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
