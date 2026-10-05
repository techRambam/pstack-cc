#!/usr/bin/env python3
"""Post-import audit: dead rules, and overlay drift.

Two silent-failure modes this closes:

1. DEAD RULE. A rule that fired zero times across the whole corpus is either
   obsolete or -- the dangerous case -- anchored on prose upstream has reworded.
   Either way a human should look. List a rule number in transform/optional-rules.txt
   to say "zero is expected here" with a reason.

2. OVERLAY DRIFT. overlay/ files are whole-file replacements applied with an
   unconditional cp. If upstream rewrites the file an overlay replaces, the overlay
   silently wins and the upstream change is never seen -- which is exactly the drift
   this repo's generator architecture exists to prevent. Each overlay records the
   sha256 of the upstream file it was based on; a mismatch fails the build until a
   human re-reads upstream's version and re-accepts.
"""
import hashlib, pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "upstream" / "pstack"
BASE = ROOT / "overlay" / "UPSTREAM-BASE.sha256"
OPTIONAL = ROOT / "transform" / "optional-rules.txt"
counts_file = pathlib.Path(sys.argv[1])
accept = "--accept-overlay" in sys.argv

problems = []

# --- 1. dead rules -------------------------------------------------------
totals = {}
if counts_file.exists():
    for line in counts_file.read_text().splitlines():
        if not line.strip():
            continue
        n, c = line.split("\t")
        totals[int(n)] = totals.get(int(n), 0) + int(c)
optional = set()
if OPTIONAL.exists():
    for line in OPTIONAL.read_text().splitlines():
        line = line.split("#")[0].strip()
        if line.isdigit():
            optional.add(int(line))
dead = sorted(n for n, c in totals.items() if c == 0 and n not in optional)
rules = [l for l in (ROOT/"transform"/"rules.pl").read_text().splitlines()
         if l.strip().startswith("s{")]
for n in dead:
    text = rules[n-1][:88] if n-1 < len(rules) else "?"
    problems.append(f"DEAD RULE {n} fired 0 times -- upstream may have reworded it:\n      {text}")
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
