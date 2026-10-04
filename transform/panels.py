#!/usr/bin/env python3
"""Append the cross-vendor panelist section to the four panel skills.

pstack's arena / interrogate / swarm / architect were built on panels drawn
from several model VENDORS -- interrogate/SKILL.md: "The adversarial signal
comes from model diversity, not assigned personas." Claude Code's Agent tool
reaches only Anthropic models, so without a way out of the family those skills
lose the property they exist for. bin/panelist is that way out; this step tells
the skills it exists.

Idempotent: re-running replaces the section rather than stacking copies.
"""
import pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
MARK = "## Cross-vendor panelists"

SECTION = """
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
"""

targets = ["arena", "interrogate", "swarm", "architect"]
done, missing = [], []
for name in targets:
    p = ROOT / "plugins" / "pstack-cc" / "skills" / name / "SKILL.md"
    if not p.exists():
        # A warn-and-continue here meant an upstream RENAME silently dropped the
        # cross-vendor section from a panel skill, leaving it telling the agent to
        # use Anthropic-only seats. Fail instead.
        missing.append(name)
        continue
    t = p.read_text(encoding="utf-8")
    if MARK in t:
        t = t[: t.index(MARK)].rstrip() + "\n"
    p.write_text(t.rstrip() + "\n" + SECTION, encoding="utf-8")
    done.append(name)
if missing:
    print(f"    panels: MISSING upstream skill(s): {', '.join(missing)} -- renamed or removed "
          f"upstream. Retarget transform/panels.py before shipping.", file=sys.stderr)
    sys.exit(1)
print(f"    panels: cross-vendor section added to {', '.join(done)}")
