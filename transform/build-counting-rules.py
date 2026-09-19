#!/usr/bin/env python3
"""Emit a counting variant of rules.pl.

WHY: a rule in rules.pl anchors on exact upstream prose. When upstream rewords a
sentence the rule silently becomes a no-op -- the build still passes, the port is
quietly wrong, and nothing says so. The forbid gate only catches the subset where a
FORBIDDEN token survives; a reworded sentence that leaves no banned token behind
slips through.

Counting at APPLY time (perl's s///g returns its substitution count) is exact: it
needs no regex translation and is immune to rule ordering, unlike matching patterns
against the raw upstream tree -- several rules deliberately operate on text an
earlier rule produced, and would score zero there while working perfectly.
"""
import pathlib, re, sys

src, dst, counts = sys.argv[1], sys.argv[2], sys.argv[3]
out, n = [], 0
# NOT `my %C` -- perl -p wraps the script body in `while(<>){...}`, so a `my`
# declaration is re-created for every input LINE and the END block sees an empty
# hash. Measured: all 47 rules reported 0 while their substitutions had plainly
# been applied. Package globals survive the loop.
out.append(f'BEGIN {{ $main::CF = "{counts}"; }}\n')
for line in pathlib.Path(src).read_text(encoding="utf-8").splitlines():
    if re.match(r'^s[{/]', line.strip()):
        n += 1
        body = line.rstrip()
        assert body.endswith(";"), f"rule {n} is not a single statement: {body[:60]}"
        out.append(f'$main::C{{{n}}} += {body[:-1]};\n')
    else:
        out.append(line + "\n")
out.append('''
END {
  open(my $fh, ">>", $main::CF) or die;
  print $fh "$_\\t$main::C{$_}\\n" for sort { $a <=> $b } keys %main::C;
  close $fh;
}
''')
pathlib.Path(dst).write_text("".join(out), encoding="utf-8")
print(f"    rules: {n} counted")
