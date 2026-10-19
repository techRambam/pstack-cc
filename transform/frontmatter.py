#!/usr/bin/env python3
"""Normalise pstack frontmatter for Claude Code.

Claude Code rejects unknown keys in a PLUGIN skill's frontmatter, and requires
agent/skill names to be lowercase-and-hyphens. Cursor allows both. One key means
something stricter here than upstream intends, so it goes too (see DROP).
"""
import re, sys, pathlib

DROP = {"mode", "icon", "color", "reminder"}          # Cursor-only skill keys
# Same key, different meaning. In Claude Code it does not just keep a skill out of
# automatic routing: the Skill tool REFUSES the call, so poteto-mode could not route
# to /how, /why, /arena or a principle skill, and the pinned reminder ("apply
# /poteto-mode") could not be acted on. Upstream's skills invoke one another, so the
# key goes. Their descriptions are explicit ("Use for /how"), which keeps them from
# triggering on unrelated requests.
DROP |= {"disable-model-invocation"}
ROOT = pathlib.Path(__file__).resolve().parent.parent
# Matt's skills that nothing in pstack routes to keep his own invocation flags: the
# routing argument above is the only reason to drop them, and it does not apply.
KEEP_FLAGS = {line.split("\t")[2] for line in
              (ROOT / "transform" / "mattpocock.tsv").read_text().splitlines()
              if line.startswith("extra\t")}

def slug(v):
    return re.sub(r"[^a-z0-9]+", "-", v.strip().lower()).strip("-")

def split_fm(text):
    if not text.startswith("---\n"):
        return None, text
    end = text.find("\n---\n", 4)
    if end == -1:
        return None, text
    return text[4:end], text[end + 5:]

# Agents that start with a skill already in context, via Claude Code's `skills:`
# frontmatter (a list of namespaced plugin skill names). poteto-agent's own body
# says to read poteto-mode's SKILL.md in full before any work; preloading makes
# that structural instead of an instruction a fresh agent can skip.
PRELOAD = {"poteto-agent": ["pstack-cc:poteto-mode"]}

# Tools that load up front and that only the main conversation uses. Deferred tools cost
# nothing until searched, so only up-front ones belong here. A spawned agent re-reads every
# loaded schema on every call, and these cost 19k tokens per call (55k vs 36k at spawn,
# measured 2026-10-13). Each agent in DENY gets them appended to its own disallowedTools.
MAIN_THREAD_ONLY = ["Artifact", "Workflow", "ScheduleWakeup", "ReadNotifications", "ListAgents",
                    "SendUserFile", "SuggestPluginInstall", "SuggestSkills", "SearchPlugins",
                    "ReportFindings", "mcp__claude-code-remote", "mcp__visualize",
                    "mcp__Claude_Code_iOS_Simulator", "mcp__ccd_session", "mcp__terminal"]
DENY = {"poteto-agent": MAIN_THREAD_ONLY, "read-only": MAIN_THREAD_ONLY}

# Keys added to an agent that lacks them; an upstream value that differs fails the import.
# A builder waits on test runs and CI past the 5-minute subagent cache, so it keeps 1h.
AGENT_KEYS = {"poteto-agent": {"effort": ["effort: high"],
                               "experimental": ["experimental:", "  cacheTtl: 1h"]}}

# Claude Code lists every skill's description in 1% of the context window, in characters
# (30,000 on a 1M-context Opus), and drops descriptions past that (docs/PORT.md section 9).
# Upstream's principle descriptions spent a fifth of that. Nothing finds a principle by its
# description: poteto-mode's Principles index says when each applies and loads it by name.
PRINCIPLE_DESCRIPTION = '"poteto-mode principle"'

changed = dropped = renamed = 0

for base in sys.argv[1:]:
    for p in sorted(pathlib.Path(base).rglob("*.md")):
        raw = p.read_text(encoding="utf-8")
        fm, body = split_fm(raw)
        if fm is None:
            continue
        principle = p.name == "SKILL.md" and p.parent.name.startswith("principle-")
        out, touched, dropping = [], False, False
        for line in fm.split("\n"):
            m = re.match(r"^([A-Za-z_-]+):\s*(.*)$", line)
            if dropping and not m:
                continue        # a dropped key's value: nested, blank, or `- ` list lines
            dropping = False
            if not m:
                out.append(line)
                continue
            key, val = m.group(1), m.group(2)
            if key == "disable-model-invocation" and p.parent.name in KEEP_FLAGS:
                out.append(line)
                continue
            if key in DROP:
                touched = dropping = True
                dropped += 1
                continue
            if key == "description" and principle:
                out.append(f"description: {PRINCIPLE_DESCRIPTION}")
                touched = dropping = True
                continue
            if key == "name":
                s = slug(val)
                if s != val.strip():
                    line = f"name: {s}"
                    touched = True
                    renamed += 1
            out.append(line)
        # Principles are background knowledge other skills route to ("apply the
        # **prove-it-works** principle skill"), not commands: hide them from the
        # `/` menu. Claude can still invoke them, which is the whole point.
        if principle and not any(l.startswith("user-invocable:") for l in out):
            out.append("user-invocable: false")
            touched = True
        agent = p.parent.name == "agents" and p.stem in PRELOAD
        if agent and not any(l.startswith("skills:") for l in out):
            out += ["skills:"] + [f"  - {s}" for s in PRELOAD[p.stem]]
            touched = True
        for key, lines in (AGENT_KEYS.get(p.stem, {}) if p.parent.name == "agents" else {}).items():
            if not any(l.startswith(f"{key}:") for l in out):
                out += lines
                touched = True
            elif not all(l in out for l in lines):
                sys.exit(f"{p}: upstream now sets {key}:, which transform/frontmatter.py also adds")
        if p.parent.name == "agents" and p.stem in DENY:
            i = next((n for n, l in enumerate(out) if l.startswith("disallowedTools:")), None)
            have = [] if i is None else [t.strip() for t in out[i].split(":", 1)[1].split(",") if t.strip()]
            tools = have + [t for t in DENY[p.stem] if t not in have]
            if tools != have:
                line = "disallowedTools: " + ", ".join(tools)
                if i is None:
                    out.append(line)
                else:
                    out[i] = line
                touched = True
        if touched:
            p.write_text("---\n" + "\n".join(out) + "\n---\n" + body, encoding="utf-8")
            changed += 1

print(f"    frontmatter: {changed} files, {dropped} keys dropped, {renamed} names slugged")
