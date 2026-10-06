#!/usr/bin/env python3
"""Insert class casts where FPC reports Pointer (or a base class) assigned/passed as a class.

`object` types were reached through typed pointers (PFoo = ^TFoo), so `P := Coll.At(I)` and
`Foo(Item)` converted implicitly. A class reference needs an explicit cast. This reads an FPC
log and wraps the offending expression in TFoo(...). It patches only the reported lines.
usage: fpide-ptrcast.py <fpc.log> <srcdir>
"""
import re, sys
from pathlib import Path

BASES = r'(?:Pointer|TObject|TStreamable|TView|TGroup|TCollection|TSortedCollection|TStringCollection|TUnsortedStringCollection)'
RX = [
    re.compile(r'^(\w+\.pas)\((\d+),(\d+)\) Error: Incompatible types: got "(%s)" expected "(T\w+)"' % BASES, re.M),
    re.compile(r'^(\w+\.pas)\((\d+),(\d+)\) Error: Incompatible type for arg no\. \d+: Got "(%s)", expected "(T\w+)"' % BASES, re.I | re.M),
]
STOP_KW = re.compile(rb'(?i)(then|do|else|of|to|downto|until|and|or|begin|end)\b')


def expr_end(b, i):
    depth = 0
    n = len(b)
    while i < n:
        c = b[i:i + 1]
        if c == b"'":
            i += 1
            while i < n and b[i:i + 1] != b"'":
                i += 1
        elif c in b'([':
            depth += 1
        elif c in b')]':
            if depth == 0:
                return i
            depth -= 1
        elif depth == 0 and c in b',;':
            return i
        elif depth == 0 and (c.isalpha() or c == b'_') and (i == 0 or not (b[i - 1:i].isalnum() or b[i - 1:i] == b'_')):
            m = STOP_KW.match(b, i)
            if m:
                return i
        elif c == b'{' or b[i:i + 2] == b'//':
            return i
        i += 1
    return n


def expr_start(b, col, is_arg):
    """FPC reports the column of the last factor (the call), not the start of the expression."""
    if not is_arg:
        i = b.rfind(b':=', 0, col + 1)
        if i >= 0:
            s = i + 2
            while b[s:s + 1] == b' ':
                s += 1
            return s
        return col
    depth = 0
    i = col
    while i > 0:
        i -= 1
        c = b[i:i + 1]
        if c in b')]':
            depth += 1
        elif c in b'([':
            if depth == 0:
                return i + 1
            depth -= 1
        elif c == b',' and depth == 0:
            return i + 1
    return col


def main(log, src):
    text = Path(log).read_bytes().decode('utf-8', 'replace')
    hits = {}
    for rx in RX:
        for m in rx.finditer(text):
            hits.setdefault(m.group(1), set()).add((int(m.group(2)), int(m.group(3)), m.group(5), 'arg no' in m.group(0)))
    total = 0
    for f, items in hits.items():
        p = Path(src) / f
        lines = p.read_bytes().split(b'\n')
        for line, col, typ, is_arg in sorted(items, key=lambda x: (x[0], -x[1])):
            b = lines[line - 1]
            s = expr_start(b, col - 1, is_arg)
            e = expr_end(b, s)
            expr = b[s:e].rstrip()
            if not expr or expr.lower().startswith(typ.lower().encode() + b'('):
                continue
            e = s + len(expr)
            lines[line - 1] = b[:s] + typ.encode() + b'(' + expr + b')' + b[e:]
            total += 1
        p.write_bytes(b'\n'.join(lines))
    print(f'ptrcast: {total} casts inserted')


main(sys.argv[1], sys.argv[2])
