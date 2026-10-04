#!/usr/bin/env python3
"""Normalise pstack frontmatter for Claude Code.

Claude Code rejects unknown keys in a PLUGIN skill's frontmatter, and requires
agent/skill names to be lowercase-and-hyphens. Cursor allows both. One key means
something stricter here than upstream intends, so it goes too (see DROP).

Side effect: poteto-mode's `reminder:` is extracted to hooks/reminder.txt so the
stickiness hook injects upstream's own wording and picks up changes on re-import.
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

def slug(v):
    return re.sub(r"[^a-z0-9]+", "-", v.strip().lower()).strip("-")

def split_fm(text):
    if not text.startswith("---\n"):
        return None, text
    end = text.find("\n---\n", 4)
    if end == -1:
        return None, text
    return text[4:end], text[end + 5:]

changed = dropped = renamed = 0
reminder = None

for base in sys.argv[1:]:
    for p in sorted(pathlib.Path(base).rglob("*.md")):
        raw = p.read_text(encoding="utf-8")
        fm, body = split_fm(raw)
        if fm is None:
            continue
        out, touched = [], False
        for line in fm.split("\n"):
            m = re.match(r"^([A-Za-z_-]+):\s*(.*)$", line)
            if not m:
                out.append(line)
                continue
            key, val = m.group(1), m.group(2)
            if key == "reminder" and "poteto-mode" in str(p):
                reminder = val.strip().strip('"').strip("'")
            if key in DROP:
                touched = True
                dropped += 1
                continue
            if key == "name":
                s = slug(val)
                if s != val.strip():
                    line = f"name: {s}"
                    touched = True
                    renamed += 1
            out.append(line)
        if touched:
            p.write_text("---\n" + "\n".join(out) + "\n---\n" + body, encoding="utf-8")
            changed += 1

if reminder:
    (ROOT / "hooks").mkdir(exist_ok=True)
    (ROOT / "hooks" / "reminder.txt").write_text(reminder + "\n", encoding="utf-8")
    print(f"    reminder extracted -> hooks/reminder.txt")

print(f"    frontmatter: {changed} files, {dropped} keys dropped, {renamed} names slugged")
