#!/usr/bin/env python3
"""Lint every generated SKILL.md and agent against Claude Code's frontmatter rules.

`claude plugin validate` only checks .claude-plugin/marketplace.json -- it never
opens a SKILL.md (MEASURED: four Cursor-only keys reintroduced on a skill still
passed validation). This is the check that actually catches a bad port.
"""
import re, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent / "plugins" / "pstack-cc"
SKILL_OK = {"name", "description", "allowed-tools", "user-invocable",
            "license", "paths", "model", "version", "argument-hint"}
AGENT_OK = {"name", "description", "tools", "disallowedTools", "model", "color",
            "background", "isolation", "permissionMode", "maxTurns", "skills",
            "effort", "memory", "omitClaudeMd"}
# Slash-only on purpose: side effects (it wires a UI that triggers agent runs and holds
# a server-side secret) and no pstack skill routes to it. Every other skill must stay
# invocable by Claude, or the skills that route to it are refused.
SLASH_ONLY_OK = {"make-bot-ui"}
# Matt Pocock's skills that nothing routes to keep his flags (transform/frontmatter.py).
SLASH_ONLY_OK |= {line.split("\t")[2] for line in
                  (ROOT.parent.parent / "transform" / "mattpocock.tsv").read_text().splitlines()
                  if line.startswith("extra\t")}
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
    for k in set(f) - SKILL_OK:
        if k == "disable-model-invocation" and name in SLASH_ONLY_OK:
            continue
        if k == "disable-model-invocation":
            errs.append(f"{rel}: disable-model-invocation makes the Skill tool refuse the call, "
                        f"so other pstack skills cannot route here (transform/frontmatter.py)")
        else:
            errs.append(f"{rel}: unsupported key {k!r}")

agents = sorted((ROOT / "agents").glob("*.md"))
for p in agents:
    rel = p.relative_to(ROOT); f = fm(p)
    if f is None: errs.append(f"{rel}: no YAML frontmatter"); continue
    n = f.get("name", "")
    if not NAME_RE.match(n): errs.append(f"{rel}: agent name {n!r} is not lowercase-hyphen")
    for k in set(f) - AGENT_OK: errs.append(f"{rel}: unsupported agent key {k!r}")

# --- references between skills ----------------------------------------------
# An upstream sync can rename a playbook, reference or skill that another file still
# points at; nothing else notices until an agent follows the dead link mid-task.
# Paths resolve against the referring file's directory, then the skill root (the
# poteto-mode playbooks name scripts/... relative to the skill). Names resolve
# against this plugin's skills and agents.
EXTERNAL = {"skill-creator"}  # anthropic-skills:skill-creator, not ours
PATH_RE = re.compile(r"`((?:\.\./)*(?:playbooks|references|scripts)/[A-Za-z0-9_./-]+)`"
                     r"|\]\(((?:\.\./)*(?:playbooks|references|scripts)/[A-Za-z0-9_./-]+)\)")
NS_RE = re.compile(r"pstack-cc:([a-z0-9-]+)")
# "a **model-invoked** skill" describes a kind of skill, not one by name, so an
# indefinite article in front exempts it.
BOLD_RE = re.compile(r"(?<![Aa] )(?<![Aa]n )\*\*([a-z0-9-]+)\*\* (?:principle )?skill")
# Matt Pocock's skills chain by naming the tool, one name or several in the clause:
# Call the Skill tool with "grilling". / call the Skill tool twice, for "a" and "b".
CALL_RE = re.compile(r"[Ss]kill tool\b[^.\n]*")
QUOTED_RE = re.compile(r"[`\"']([a-z0-9]+(?:-[a-z0-9]+)*)[`\"']")
# A bare link to a file beside the referring one, as Matt's skills write them: [x](tests.md)
SIBLING_RE = re.compile(r"\]\((?:\./)?([A-Za-z0-9_.-]+\.md)\)")
skill_names = {p.parent.name for p in skills}
agent_names = {p.stem for p in agents}
checked = 0
for md in sorted((ROOT / "skills").rglob("*.md")) + agents:
    rel = md.relative_to(ROOT)
    skill_root = ROOT / "skills" / rel.parts[1] if rel.parts[0] == "skills" else md.parent
    text = md.read_text(encoding="utf-8")
    for m in PATH_RE.finditer(text):
        ref = (m.group(1) or m.group(2)).rstrip(".")
        if "<" in ref or "*" in ref: continue
        checked += 1
        if not ((md.parent / ref).exists() or (skill_root / ref).exists()):
            errs.append(f"{rel}: dead reference {ref!r}")
    for m in NS_RE.finditer(text):
        checked += 1
        if m.group(1) not in skill_names | agent_names:
            errs.append(f"{rel}: pstack-cc:{m.group(1)} names no skill or agent in this plugin")
    for m in BOLD_RE.finditer(text):
        n = m.group(1); checked += 1
        if n not in skill_names | EXTERNAL and f"principle-{n}" not in skill_names:
            errs.append(f"{rel}: **{n}** skill does not exist")
    for clause in CALL_RE.finditer(text):
        for n in QUOTED_RE.findall(clause.group(0)):
            checked += 1
            if n not in skill_names:
                errs.append(f"{rel}: calls the Skill tool with {n!r}, which is not a skill in this plugin")
    for m in SIBLING_RE.finditer(text):
        checked += 1
        if not (md.parent / m.group(1)).exists():
            errs.append(f"{rel}: dead link to {m.group(1)!r}")

# --- invocation flags across harnesses ----------------------------------------
# A skill is user-only in Claude Code (disable-model-invocation) exactly when it is in
# Codex (agents/openai.yaml allow_implicit_invocation: false). A routed skill hidden from
# one harness's model has no route there.
def user_only(p):
    return (fm(p) or {}).get("disable-model-invocation", "").strip() == "true"
for p in skills:
    y = p.parent / "agents" / "openai.yaml"
    if not y.exists():
        continue
    codex = "allow_implicit_invocation: false" in y.read_text(encoding="utf-8")
    if codex != user_only(p):
        errs.append(f"{p.relative_to(ROOT)}: user-only in "
                    f"{'Codex but not Claude Code' if codex else 'Claude Code but not Codex'}")

# Matt's unrouted extras keep his flag exactly, whichever way it points.
MATT = ROOT.parent.parent / "upstream-mattpocock"
for line in (ROOT.parent.parent / "transform" / "mattpocock.tsv").read_text().splitlines():
    if not line.startswith("extra\t") or not MATT.exists():
        continue
    _, source, target, _ = line.split("\t")
    if user_only(MATT / source / "SKILL.md") != user_only(ROOT / "skills" / target / "SKILL.md"):
        errs.append(f"skills/{target}/SKILL.md: an extra must keep Matt's disable-model-invocation as he set it")

print(f"linted {len(skills)} skills, {len(agents)} agents, {checked} cross-references")
for e in errs: print("  FAIL " + e)
print(f"\n{len(errs)} problem(s)")
sys.exit(1 if errs else 0)
