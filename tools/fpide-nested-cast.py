#!/usr/bin/env python3
"""Patch ForEach/FirstThat/LastThat(@Nested) call sites reported by FPC as incompatible.

tv3 declares the callbacks as nested procvars over `Pointer`; IDE callbacks take a typed
class (TSymbol, ...). Both are one machine word, so a cast is exact (tested). Reads an FPC
log, patches only the lines it names. usage: fpide-nested-cast.py <fpc.log> <srcdir>
"""
import re, sys
from pathlib import Path

log, src = Path(sys.argv[1]), Path(sys.argv[2])
rx = re.compile(r'^(\w+\.(?:pas|inc))\((\d+),\d+\) Error: Incompatible type for arg no\. \d+: Got "<(?:address of|procedure variable type of) '
                r'(procedure|function)\([^"]*? is nested[^"]*", expected "<procedure variable type of '
                r'(procedure|function)\(Pointer\)[^"]*is nested', re.M)
n = 0
for m in rx.finditer(log.read_bytes().decode('utf-8', 'replace')):
    f, line, kind = m.group(1), int(m.group(2)), m.group(4)
    cast = 'TNestedActionProc' if kind == 'procedure' else 'TNestedTestProc'
    p = src / f
    lines = p.read_bytes().decode('utf-8', 'surrogateescape').split('\n')
    new = re.sub(r'\b(ForEach|FirstThat|LastThat)\(\s*(@[\w.]+)\s*\)', rf'\1({cast}(\2))', lines[line - 1])
    if new != lines[line - 1]:
        lines[line - 1] = new
        p.write_bytes('\n'.join(lines).encode('utf-8', 'surrogateescape'))
        n += 1
print(f'nested-cast: patched {n} call sites')
