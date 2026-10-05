#!/usr/bin/env python3
"""Import Matt Pocock's skills into the generated plugin, as transform/mattpocock.tsv says.

Runs after pstack's skills are copied and rewritten, so pstack's Cursor rules never touch
Matt's text. Fails, rather than guessing, when:
  - Matt's plugin promotes a skill the manifest does not classify, or the manifest names
    a skill that no longer exists upstream
  - an imported skill would land on a directory pstack already generated
  - a merged skill's extra files would overwrite a pstack file
  - an edit below no longer matches upstream's text exactly as often as expected
"""
import json, pathlib, re, shutil, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "upstream-mattpocock"
PLUGIN = ROOT / "plugins" / "pstack-cc"
MANIFEST = ROOT / "transform" / "mattpocock.tsv"

# (target file under plugins/pstack-cc, old text, new text, expected matches).
# Each edit exists because the text it replaces points at a skill this port excludes or
# renames, or because the phase split needs a slot his templates lack.
EDITS = [
    # His prototype skill is excluded. The playbook keeps the sketch out of production
    # source; the map's ticket is HITL, so the human still picks the direction.
    ("skills/wayfinder/SKILL.md",
     'by calling the Skill tool with "prototype"',
     "by building a throwaway per the Prototype playbook of the **poteto-mode** skill, "
     "committed to a throwaway branch that the ticket links. The human picks the direction, "
     "and nothing is handed to Feature from inside the map", 1),
    ("skills/course/SKILL.md", "name: teach", "name: course", 1),
    ("skills/course/agents/openai.yaml", 'display_name: "Teach"', 'display_name: "Course"', 1),
    ("skills/tdd/agents/openai.yaml", 'short_description: "Test-driven red-green-refactor"',
     'short_description: "Test-first slices and regression tests"', 1),
    # Seams are agreed while deciding and read while building (tdd), so the spec and both
    # ticket templates carry them.
    ("skills/to-spec/SKILL.md", "- Which modules will be tested\n",
     "- Which modules will be tested, and the seams agreed with the user in step 2. "
     "The build phase tests at these.\n", 1),
    ("skills/to-tickets/SKILL.md", "**Status:** ready-for-agent",
     "**Seams under test:** the seams from the spec's Testing Decisions that this ticket's "
     "tests sit at, or \"None named\".\n\n**Status:** ready-for-agent", 1),
    ("skills/to-tickets/SKILL.md", "## Acceptance criteria\n\n- [ ] Criterion 1",
     "## Seams under test\n\nThe seams from the parent spec's Testing Decisions that this "
     "ticket's tests sit at, or \"None named\".\n\n## Acceptance criteria\n\n- [ ] Criterion 1", 1),
]

# Codex's counterpart of disable-model-invocation. Routed skills drop the Claude flag
# (transform/frontmatter.py), so they drop this one too, or Codex never shows them to the
# model and the router's targets do not exist there. Extras keep both.
CODEX_USER_ONLY = "allow_implicit_invocation: false"
CODEX_IMPLICIT = "allow_implicit_invocation: true"


def bare_slash(rows):
    """`/name` for an imported skill, by its upstream or target name, as a command and not a path.

    Shared with tests/lint-skills.py, so the rewrite and the check can never disagree on what
    a bare mention is. Returns (pattern, {name: target})."""
    names = {}
    for r in rows:
        if r["role"] != "exclude":
            names[pathlib.PurePath(r["source"]).name] = r["target"]
            names[r["target"]] = r["target"]
    alt = "|".join(sorted(map(re.escape, names), key=len, reverse=True))
    return re.compile(r"(?<![\w:./-])/(" + alt + r")(?![\w/-])"), names


def manifest():
    rows = []
    for line in MANIFEST.read_text().splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        role, source, target, reason = line.split("\t")
        rows.append({"role": role, "source": source, "target": target, "reason": reason})
    return rows


def main():
    problems = []
    rows = manifest()
    promoted = {p.removeprefix("./") for p in
                json.loads((SRC / ".claude-plugin" / "plugin.json").read_text())["skills"]}
    listed = {r["source"] for r in rows}
    for s in sorted(promoted - listed):
        problems.append(f"Matt's plugin now promotes {s}, which transform/mattpocock.tsv does not "
                        f"classify. Read it, then add a core, extra, merge or exclude row.")
    for s in sorted(listed - promoted):
        problems.append(f"transform/mattpocock.tsv names {s}, which Matt's plugin no longer "
                        f"promotes. Read upstream's change, then drop or retarget the row.")
    if problems:
        return problems

    imported = merged = 0
    for r in rows:
        src, dst = SRC / r["source"], PLUGIN / "skills" / r["target"]
        if r["role"] in ("core", "extra"):
            if dst.exists():
                problems.append(f"{r['source']} would land on skills/{r['target']}, which pstack "
                                f"already generated. Make it a merge row or rename its target.")
                continue
            shutil.copytree(src, dst)
            imported += 1
        elif r["role"] == "merge":
            if not dst.exists():
                problems.append(f"merge row {r['source']}: pstack has no skills/{r['target']} to merge into")
                continue
            if not (ROOT / "overlay" / "skills" / r["target"] / "SKILL.md").exists():
                problems.append(f"merge row {r['source']}: no overlay/skills/{r['target']}/SKILL.md "
                                f"replaces both packs' SKILL.md, so pstack's would ship unmerged")
                continue
            for f in sorted(src.rglob("*")):
                rel = f.relative_to(src)
                if f.is_dir() or rel == pathlib.Path("SKILL.md"):
                    continue
                if (dst / rel).exists():
                    problems.append(f"merge row {r['source']}: {rel} would overwrite pstack's "
                                    f"skills/{r['target']}/{rel}")
                    continue
                (dst / rel).parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(f, dst / rel)
            merged += 1
        elif r["role"] != "exclude":
            problems.append(f"unknown role {r['role']!r} for {r['source']}")
            continue
        yaml = dst / "agents" / "openai.yaml"
        if r["role"] in ("core", "merge") and yaml.exists():
            text = yaml.read_text(encoding="utf-8")
            yaml.write_text(text.replace(CODEX_USER_ONLY, CODEX_IMPLICIT), encoding="utf-8")

    for rel, old, new, want in EDITS:
        p = PLUGIN / rel
        text = p.read_text(encoding="utf-8") if p.exists() else ""
        got = text.count(old)
        if got != want:
            problems.append(f"edit on {rel} matched {got} time(s), expected {want}: {old!r}. "
                            f"Upstream reworded it; read their version and update EDITS.")
            continue
        p.write_text(text.replace(old, new), encoding="utf-8")

    # His skills name each other as `/name`, but a plugin registers only `/pstack-cc:name`
    # (MEASURED 2026-10-05: the init event's slash_commands has no bare entries), so a user
    # told to run `/setup-matt-pocock-skills` finds nothing. Name each imported skill as
    # registered, under its target name. tests/lint-skills.py fails on any bare one left,
    # backticked or not.
    bare, renamed = bare_slash(rows)
    rewrites = 0
    for r in rows:
        if r["role"] == "exclude":
            continue
        for f in (PLUGIN / "skills" / r["target"]).rglob("*.md"):
            text = f.read_text(encoding="utf-8")
            new_text, n = bare.subn(lambda m: f"/pstack-cc:{renamed[m.group(1)]}", text)
            if n:
                f.write_text(new_text, encoding="utf-8")
                rewrites += n

    shutil.copy2(SRC / "LICENSE", PLUGIN / "LICENSE.mattpocock")
    excluded = sum(r["role"] == "exclude" for r in rows)
    print(f"    mattpocock: {imported} imported, {merged} merged, {excluded} excluded, "
          f"{len(EDITS)} edits, {rewrites} slash names namespaced")
    return problems


if __name__ == "__main__":
    problems = main()
    for p in problems:
        print(f"  !! {p}")
    sys.exit(1 if problems else 0)
