#!/usr/bin/env python3
"""Map upstream's `readonly` spawn flag onto a real Claude Code agent.

Cursor's Task tool takes `readonly: true` (Ask mode: no edits, no MCP) and
`readonly: false` (agent mode). Claude Code's Agent tool has no such parameter,
so a ported `readonly: true` silently spawned a general-purpose agent that could
edit the tree and fan out. own/agents/read-only.md is the real equivalent: the
same tools minus Edit, Write, NotebookEdit and Agent, with MCP intact.

The spawn specs span lines (`subagent_type`, then `model`, then `readonly`), so
this is a multi-line rewrite rather than a rules.pl substitution. Every pattern
has an expected count per file; a miss fails the import, like a dead rule.
"""
import pathlib, re, sys

PLUGIN = pathlib.Path(__file__).resolve().parent.parent / "plugins" / "pstack-cc"
RO = "`pstack-cc:read-only` (no edit tools, no `Agent`: it reports and never changes the tree)"

SPEC = re.compile(r"- `subagent_type`: `general-purpose`\n(- `model`: [^\n]*\n)- `readonly`: `true`\n")
FIXES = [
    # file, pattern, replacement, expected count
    ("skills/how/SKILL.md", SPEC, rf"- `subagent_type`: {RO}\n\1", 3),
    ("skills/interrogate/SKILL.md", SPEC, rf"- `subagent_type`: {RO}\n\1", 1),
    ("skills/arena/SKILL.md", re.compile(r"Spawn one readonly judge subagent on that model\."),
     "Spawn one judge subagent on that model with `subagent_type: \"pstack-cc:read-only\"`.", 1),
    # readonly: false meant "keep MCP". general-purpose already has MCP here.
    ("skills/why/SKILL.md", re.compile(
        r"- `readonly`: `false` \(agent mode\)\. \*\*Do not use readonly/Ask mode\.\*\* It strips MCP access, "
        r"which disables MCP-backed investigators entirely\. "),
     "- Keep `general-purpose`, not `pstack-cc:read-only`: investigators need MCP and Bash. ", 1),
    ("skills/why/SKILL.md", re.compile(
        r"- `readonly`: `false` \(agent mode\)\. The synthesizer's quality check spot-verifies citations, "
        r"which can require MCP access\. Readonly/Ask mode strips MCPs and defeats that\."),
     "- Keep `general-purpose`: the synthesizer's quality check spot-verifies citations, which can require MCP access.", 1),
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
