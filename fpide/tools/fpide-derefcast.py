#!/usr/bin/env python3
"""Remove `^` after class references (PFoo = TFoo now, so `S^` and `P^.X` are illegal).

FPC reports "Illegal qualifier" at the column right after the `^`. Only lines it names are
patched, and only when the byte before that column is `^`. usage: fpide-derefcast.py <fpc.log> <srcdir>
"""
import re, sys
from pathlib import Path

rx = re.compile(r'^(\w+\.(?:pas|inc))\((\d+),(\d+)\) Error: Illegal qualifier', re.M)
text = Path(sys.argv[1]).read_bytes().decode('utf-8', 'replace')
hits = {}
for m in rx.finditer(text):
    hits.setdefault(m.group(1), set()).add((int(m.group(2)), int(m.group(3))))
total = 0
for f, items in hits.items():
    p = Path(sys.argv[2]) / f
    lines = p.read_bytes().split(b'\n')
    for line, col in sorted(items, key=lambda x: (x[0], -x[1])):
        b = lines[line - 1]
        i = b.rfind(b'^', max(0, col - 5), col)   # the column is after the caret, or after `^ ` before `do`
        if i >= 0:
            lines[line - 1] = b[:i] + b[i + 1:]
            total += 1
    p.write_bytes(b'\n'.join(lines))
print(f'derefcast: removed {total} carets')
