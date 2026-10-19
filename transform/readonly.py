#!/usr/bin/env python3
"""Map upstream's `readonly` spawn flag onto a real Claude Code agent.

Cursor's Task tool takes `readonly: true` (Ask mode: no edits, no MCP) and
`readonly: false` (agent mode). Claude Code's Agent tool has no such parameter,
so a ported `readonly: true` silently spawned a general-purpose agent that could
edit the tree and fan out. own/agents/read-only.md is the real equivalent: the
same tools minus Edit, Write, NotebookEdit and Agent, with MCP intact.

Each spawn spec names `subagent_type` and `readonly` together, so it is rewritten
as one unit here rather than as two rules.pl substitutions. Every pattern has an
expected count per file; a miss fails the import, like a dead rule.
"""
import pathlib, re, sys

PLUGIN = pathlib.Path(__file__).resolve().parent.parent / "plugins" / "pstack-cc"
RO_WHY = "(no edit tools, no `Agent`: it reports and never changes the tree)"
RO_SPEC = f'`subagent_type: "pstack-cc:read-only"` {RO_WHY}'

FIXES = [
    # file, pattern, replacement, expected count
    ("skills/how/SKILL.md", re.compile(
        r"Every spawn is a Task subagent with `subagent_type: general-purpose` and `readonly: true`\."),
     f"Every spawn is an `Agent` subagent with {RO_SPEC}.", 1),
    ("skills/interrogate/SKILL.md", re.compile(
        r"Each reviewer gets `subagent_type: general-purpose`, `readonly: true`, and "),
     f"Each reviewer gets {RO_SPEC}, and ", 1),
    ("skills/arena/SKILL.md", re.compile(r"Spawn one readonly judge subagent on that model\."),
     "Spawn one judge subagent on that model with `subagent_type: \"pstack-cc:read-only\"`.", 1),
    # readonly: false meant "keep MCP". general-purpose already has MCP here.
    ("skills/why/SKILL.md", re.compile(
        r"Every spawn is `general-purpose` with `readonly: false` \(agent mode\)\. \*\*Do not use readonly/Ask mode\.\*\* "
        r"It strips MCP access, which disables the MCP-backed investigators and the synthesizer's citation spot-checks\. "),
     "Every spawn is `general-purpose`, never `pstack-cc:read-only`. Investigators need MCP and Bash, "
     "and the synthesizer's citation spot-checks can need MCP. ", 1),
]

bad = []
for rel, pat, repl, want in FIXES:
    p = PLUGIN / rel
    t = p.read_text(encoding="utf-8")
    t2, n = pat.subn(repl, t)
    if n != want:
        bad.append(f"{rel}: expected {want} match(es) of {pat.pattern[:60]!r}, got {n}")
    p.write_text(t2, encoding="utf-8")
if bad:
    print("    readonly: upstream reworded a spawn spec -- retarget transform/readonly.py:", file=sys.stderr)
    for b in bad: print(f"      {b}", file=sys.stderr)
    sys.exit(1)
print(f"    readonly: {len(FIXES)} spawn specs mapped to pstack-cc:read-only / general-purpose")
