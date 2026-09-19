#!/usr/bin/env python3
"""Lint every generated SKILL.md and agent against Claude Code's frontmatter rules.

`claude plugin validate` only checks .claude-plugin/marketplace.json -- it never
opens a SKILL.md (MEASURED: four Cursor-only keys reintroduced on a skill still
passed validation). This is the check that actually catches a bad port.
"""
import re, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
SKILL_OK = {"name", "description", "disable-model-invocation", "allowed-tools",
            "license", "paths", "model", "version"}
AGENT_OK = {"name", "description", "tools", "disallowedTools", "model", "color",
            "background", "isolation", "permissionMode", "maxTurns", "skills",
            "effort", "memory", "omitClaudeMd"}
NAME_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")

def fm(p):
    t = p.read_text(encoding="utf-8")
    if not t.startswith("---\n"): return None
    e = t.find("\n---\n", 4)
    if e == -1: return None
    d, key = {}, None
    for line in t[4:e].split("\n"):
        m = re.match(r"^([A-Za-z_-]+):\s*(.*)$", line)
        if m: key = m.group(1); d[key] = m.group(2)
        elif key and line.startswith(("  ", "\t")): d[key] += " " + line.strip()
    return d

errs = []
skills = sorted((ROOT / "skills").rglob("SKILL.md"))
for p in skills:
    rel = p.relative_to(ROOT); f = fm(p)
    if f is None: errs.append(f"{rel}: no YAML frontmatter"); continue
    name = f.get("name", "")
    if not name: errs.append(f"{rel}: missing name")
    elif not NAME_RE.match(name): errs.append(f"{rel}: name {name!r} is not lowercase-hyphen")
    elif name != p.parent.name: errs.append(f"{rel}: name {name!r} != directory {p.parent.name!r}")
    d = f.get("description", "")
    if not d: errs.append(f"{rel}: missing description")
    elif len(d) > 1536: errs.append(f"{rel}: description {len(d)} chars > 1536")
    for k in set(f) - SKILL_OK: errs.append(f"{rel}: unsupported key {k!r}")

agents = sorted((ROOT / "agents").glob("*.md"))
for p in agents:
    rel = p.relative_to(ROOT); f = fm(p)
    if f is None: errs.append(f"{rel}: no YAML frontmatter"); continue
    n = f.get("name", "")
    if not NAME_RE.match(n): errs.append(f"{rel}: agent name {n!r} is not lowercase-hyphen")
    for k in set(f) - AGENT_OK: errs.append(f"{rel}: unsupported agent key {k!r}")

print(f"linted {len(skills)} skills, {len(agents)} agents")
for e in errs: print("  FAIL " + e)
print(f"\n{len(errs)} problem(s)")
sys.exit(1 if errs else 0)
