#!/usr/bin/env python3
"""New(X, Init(args)) -> X := TFoo.Create(args), typed from the declaration of X anywhere in fpide/src.

fpide-class-migrate.py only knows declarations of the file it converts; the dialog code in the
*.inc files uses variables declared in the units that include them. usage: <srcdir> <files...>
Dispose(X, Done) -> X.Free. Ambiguous names are reported, not guessed.
"""
import re, sys
from pathlib import Path

src = Path(sys.argv[1])
alltext = "\n".join(p.read_bytes().decode('utf-8', 'surrogateescape') for p in list(src.glob('*.pas')) + list(src.glob('*.inc')))
pat = re.compile(r"\bNew\(\s*([\w.]+)\s*,\s*(\w+)\s*(\((?:[^()]|\((?:[^()]|\([^()]*\))*\))*\))?\s*\)")
for f in sys.argv[2:]:
    p = Path(f)
    t = p.read_bytes().decode('utf-8', 'surrogateescape')

    def r(m):
        full, ctor, args = m.group(1), m.group(2), m.group(3) or ''
        name = full.split('.')[-1]
        found = re.findall(r"\b%s\s*:\s*(P\w+)\b" % re.escape(name), alltext)
        if not found:
            print('NOTYPE', p.name, full); return m.group(0)
        if len(set(found)) > 1:
            print('AMBIG', p.name, full, sorted(set(found)))
        method = 'Create' if ctor.lower() == 'init' else ctor
        return f"{full} := T{found[0][1:]}.{method}{args}"
    n = pat.sub(r, t)
    n = re.sub(r"\bDispose\(\s*([\w.]+)\s*,\s*Done\s*\)", r"\1.Free", n, flags=re.I)
    if n != t:
        p.write_bytes(n.encode('utf-8', 'surrogateescape'))
        print('converted', p.name)
