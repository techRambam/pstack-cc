#!/usr/bin/env python3
"""Post-import audit: dead rules, and overlay drift.

Two silent-failure modes this closes:

1. DEAD RULE. A rule that fired zero times across the whole corpus is either
   obsolete or -- the dangerous case -- anchored on prose upstream has reworded.
   Either way a human should look. Name the rule in transform/optional-rules.txt
   to say "zero is expected here" with a reason.

2. OVERLAY DRIFT. overlay/ files are whole-file replacements applied with an
   unconditional cp. If upstream rewrites the file an overlay replaces, the overlay
   silently wins and the upstream change is never seen -- which is exactly the drift
   this repo's generator architecture exists to prevent. Each overlay records the
   sha256 of the upstream file it was based on; a mismatch fails the build until a
   human re-reads upstream's version and re-accepts.
"""
import hashlib, pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "upstream" / "pstack"
BASE = ROOT / "overlay" / "UPSTREAM-BASE.sha256"
OPTIONAL = ROOT / "transform" / "optional-rules.txt"
counts_file = pathlib.Path(sys.argv[1])
accept = "--accept-overlay" in sys.argv

problems = []

# --- 1. dead rules -------------------------------------------------------
# Counts are keyed by the rule's line in rules.pl (build-counting-rules.py).
totals = {}
if counts_file.exists():
    for line in counts_file.read_text().splitlines():
        if not line.strip():
            continue
        n, c = line.split("\t")
        totals[int(n)] = totals.get(int(n), 0) + int(c)
rules = {i: l.strip() for i, l in
         enumerate((ROOT/"transform"/"rules.pl").read_text(encoding="utf-8").splitlines(), 1)
         if re.match(r'^s[{/]', l.strip())}

# optional-rules.txt names each rule by a substring of its line, never by position: a
# positional number shifted under every insert or delete above it and silently
# silenced whichever rule moved into the slot. A key must match exactly one rule, and
# so must every [[key]] cross-reference in its comments.
def resolve(key, where):
    hits = [i for i, text in rules.items() if key in text]
    if len(hits) != 1:
        lines = "".join(f"\n      rules.pl:{i}: {rules[i][:88]}" for i in hits)
        problems.append(f"{where}: `{key}` matches {len(hits)} rules in transform/rules.pl, "
                        f"expected exactly 1 -- lengthen the key until one rule contains it, "
                        f"or drop it if that rule is gone.{lines}")
        return None
    return hits[0]

optional = set()
if OPTIONAL.exists():
    for k, line in enumerate(OPTIONAL.read_text(encoding="utf-8").splitlines(), 1):
        line = line.strip()
        where = f"optional-rules.txt:{k}"
        if line.startswith("#"):
            for ref in re.findall(r"\[\[(.+?)\]\]", line):
                resolve(ref, f"{where} cross-reference")
        elif line:
            n = resolve(line, where)
            if n is not None:
                optional.add(n)
dead = sorted(n for n, c in totals.items() if c == 0 and n not in optional)
for n in dead:
    problems.append(f"DEAD RULE rules.pl:{n} fired 0 times -- upstream may have reworded it:\n"
                    f"      {rules.get(n, '?')[:88]}")
live = sum(1 for c in totals.values() if c > 0)
print(f"    rules: {live}/{len(totals)} fired, {len(dead)} dead, {len(optional)} marked optional")

# --- 2. overlay drift ----------------------------------------------------
recorded = {}
if BASE.exists():
    for line in BASE.read_text().splitlines():
        if line.strip() and not line.startswith("#"):
            h, p = line.split(None, 1)
            recorded[p.strip()] = h
current, missing = {}, []
for f in sorted((ROOT/"overlay").rglob("*")):
    if not f.is_file() or f.name == "UPSTREAM-BASE.sha256":
        continue
    rel = str(f.relative_to(ROOT/"overlay"))
    up = SRC / rel
    if not up.exists():
        missing.append(rel)
        continue
    current[rel] = hashlib.sha256(up.read_bytes()).hexdigest()

# A merge row in transform/mattpocock.tsv folds Matt's SKILL.md into an overlay/ file
# the same way, so his version is watched under the same rule, keyed by its path in his
# repo. The overlay's own path above already watches the pstack side.
MATT = ROOT / "upstream-mattpocock"
for line in (ROOT / "transform" / "mattpocock.tsv").read_text().splitlines():
    if not line.startswith("merge\t"):
        continue
    source = line.split("\t")[1]
    up = MATT / source / "SKILL.md"
    if not up.exists():
        missing.append(f"mattpocock/{source}/SKILL.md")
        continue
    current[f"mattpocock/{source}/SKILL.md"] = hashlib.sha256(up.read_bytes()).hexdigest()

# A missing upstream target is fatal in BOTH modes. Overlays are copied BEFORE the
# audit runs, so if upstream deleted a skill an overlay replaces, accepting would
# rewrite the baseline without that path and ship the deleted skill back as if it
# were still upstream's. Accepting is for "upstream changed this file", never for
# "upstream no longer has this file".
if missing:
    for rel in missing:
        if rel.startswith("mattpocock/"):
            problems.append(f"MERGE {rel} no longer exists upstream -- Matt deleted or moved "
                            f"the skill a merge row in transform/mattpocock.tsv folds in. Read "
                            f"his change, then retarget or drop the row and its overlay/.")
            continue
        problems.append(f"OVERLAY {rel} replaces a file that no longer exists upstream -- "
                        f"delete overlay/{rel} or retarget it. --accept-overlay will NOT "
                        f"silence this: the overlay is copied before this audit, so the "
                        f"deleted upstream file would be restored and shipped.")
    print()
    for pr in problems:
        print(f"  !! {pr}")
    sys.exit(1)

if accept:
    lines = ["# sha256 of the UPSTREAM file each overlay/ file replaces, at the ref it was",
             "# based on. Regenerate deliberately with: ./import.sh --accept-overlay",
             "# A mismatch means upstream rewrote a file you override -- read their version",
             "# before re-accepting, or the override silently discards their change."]
    lines += [f"{current[k]}  {k}" for k in sorted(current)]
    BASE.write_text("\n".join(lines) + "\n")
    print(f"    overlay: accepted {len(current)} upstream baseline(s)")
else:
    for rel, h in sorted(current.items()):
        if rel not in recorded:
            problems.append(f"OVERLAY {rel} has no recorded upstream baseline -- run ./import.sh --accept-overlay")
        elif recorded[rel] != h:
            problems.append(
                f"OVERLAY DRIFT {rel}: upstream's version CHANGED since this override was written.\n"
                f"      was {recorded[rel][:16]}  now {h[:16]}\n"
                f"      Read upstream{'-' if rel.startswith('mattpocock/') else '/pstack/'}{rel}, "
                f"fold anything new into the overlay/ file that replaces it,\n"
                f"      then re-accept: ./import.sh --accept-overlay")
    print(f"    overlay: {len(current)} file(s) checked against upstream")

if problems:
    print()
    for p in problems:
        print(f"  !! {p}")
    sys.exit(1)
