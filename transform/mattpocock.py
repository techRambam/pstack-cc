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
import json, pathlib, shutil, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "upstream-mattpocock"
PLUGIN = ROOT / "plugins" / "pstack-cc"
MANIFEST = ROOT / "transform" / "mattpocock.tsv"

# (target file under plugins/pstack-cc, old text, new text, expected matches).
# Each edit exists because the text it replaces points at a skill this port excludes or renames.
EDITS = [
    ("skills/wayfinder/SKILL.md",
     'by calling the Skill tool with "prototype"',
     "by following the Prototype playbook of the **poteto-mode** skill", 1),
    ("skills/course/SKILL.md", "name: teach", "name: course", 1),
    ("skills/course/agents/openai.yaml", 'display_name: "Teach"', 'display_name: "Course"', 1),
]


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

    for rel, old, new, want in EDITS:
        p = PLUGIN / rel
        text = p.read_text(encoding="utf-8") if p.exists() else ""
        got = text.count(old)
        if got != want:
            problems.append(f"edit on {rel} matched {got} time(s), expected {want}: {old!r}. "
                            f"Upstream reworded it; read their version and update EDITS.")
            continue
        p.write_text(text.replace(old, new), encoding="utf-8")

    shutil.copy2(SRC / "LICENSE", PLUGIN / "LICENSE.mattpocock")
    excluded = sum(r["role"] == "exclude" for r in rows)
    print(f"    mattpocock: {imported} imported, {merged} merged, {excluded} excluded, "
          f"{len(EDITS)} edits")
    return problems


if __name__ == "__main__":
    problems = main()
    for p in problems:
        print(f"  !! {p}")
    sys.exit(1 if problems else 0)
