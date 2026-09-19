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
"""

targets = ["arena", "interrogate", "swarm", "architect"]
done = []
for name in targets:
    p = ROOT / "skills" / name / "SKILL.md"
    if not p.exists():
        print(f"    panels: MISSING skills/{name}/SKILL.md", file=sys.stderr)
        continue
    t = p.read_text(encoding="utf-8")
    if MARK in t:
        t = t[: t.index(MARK)].rstrip() + "\n"
    p.write_text(t.rstrip() + "\n" + SECTION, encoding="utf-8")
    done.append(name)
print(f"    panels: cross-vendor section added to {', '.join(done)}")
