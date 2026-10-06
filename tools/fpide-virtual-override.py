#!/usr/bin/env python3
"""A `virtual` method that redeclares a virtual/override ancestor method becomes `override`.

With `object` types, repeating a method as `virtual` in a descendant reused the VMT slot. With
classes it creates a new slot and hides the ancestor's method (the ancestor's code is then
called through the base class: e.g. an abstract method). Ancestors are looked up across all the
given files (fpide/src, fpide/compat, tv/src). usage: <rewrite-dir> <extra-ancestor-dirs...>
"""
import re, sys
from pathlib import Path

CLS = re.compile(r'(?im)^[ \t]*(T\w+)[ \t]*=[ \t]*class[ \t]*(?:\([ \t]*(\w+)[ \t]*(?:,[^)]*)?\))?[ \t]*$|^[ \t]*(T\w+)[ \t]*=[ \t]*class[ \t]*\([ \t]*(\w+)')
METH = re.compile(r'(?is)^\s*(?:class\s+)?(procedure|function|destructor|constructor)\s+(\w+)')


DIRECTIVES = {'virtual', 'override', 'abstract', 'overload', 'reintroduce', 'cdecl', 'stdcall', 'register', 'inline', 'dynamic', 'message', 'deprecated', 'platform', 'static'}


def class_bodies(text):
    """yield (name, parent, body_start, body_end) for every `TFoo = class(TBar)` ... `end;`"""
    for m in re.finditer(r'(?im)^[ \t]*(T\w+)[ \t]*=[ \t]*class[ \t]*\([ \t]*(\w+)[^)]*\)', text):
        start = m.end()
        # body ends at the first `end;` at line start (indented members never use a bare end;)
        e = re.search(r'(?im)^[ \t]*end[ \t]*;', text[start:])
        if e:
            yield m.group(1), m.group(2), start, start + e.start()


def members(body):
    """split a class body into statements at ';' outside parentheses/comments, with offsets"""
    out, depth, i, last = [], 0, 0, 0
    while i < len(body):
        c = body[i]
        if c == '{':
            j = body.find('}', i); i = j if j >= 0 else len(body)
        elif body.startswith('(*', i):
            j = body.find('*)', i); i = j + 1 if j >= 0 else len(body)
        elif body.startswith('//', i):
            j = body.find('\n', i); i = j if j >= 0 else len(body)
        elif c == "'":
            j = body.find("'", i + 1); i = j if j >= 0 else len(body)
        elif c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
        elif c == ';' and depth == 0:
            seg = body[last:i + 1]
            word = re.match(r'\s*(\w+)', re.sub(r'\{[^}]*\}', '', seg))
            if out and word and word.group(1).lower() in DIRECTIVES:
                out[-1] = (out[-1][0], i + 1)      # `virtual;` etc. belong to the declaration before
            else:
                out.append((last, i + 1))
            last = i + 1
        i += 1
    return out


def scan(paths):
    info = {}   # class(lower) -> (parent(lower), {method(lower): kind})
    for p in paths:
        t = p.read_bytes().decode('utf-8', 'surrogateescape')
        for name, parent, s, e in class_bodies(t):
            meth = {}
            for a, b in members(t[s:e]):
                st = t[s + a:s + b]
                m = METH.match(re.sub(r'\{[^}]*\}', '', st))
                if not m:
                    continue
                low = st.lower()
                kind = 'override' if re.search(r'\boverride\s*;', low) else 'virtual' if re.search(r'\bvirtual\s*;', low) else None
                if kind:
                    meth[m.group(2).lower()] = kind
            info[name.lower()] = (parent.lower(), meth)
    return info


def ancestor_virtual(info, cls, meth):
    seen = set()
    c = info.get(cls, (None, {}))[0]
    while c and c not in seen:
        seen.add(c)
        if meth in info.get(c, (None, {}))[1]:
            return True
        c = info.get(c, (None, {}))[0]
    return False


def main():
    rewrite = Path(sys.argv[1])
    allp = list(rewrite.glob('*.pas')) + list(rewrite.glob('*.inc'))
    for d in sys.argv[2:]:
        allp += list(Path(d).glob('*.pas'))
    info = scan(allp)
    total = 0
    for p in list(rewrite.glob('*.pas')) + list(rewrite.glob('*.inc')):
        t = p.read_bytes().decode('utf-8', 'surrogateescape')
        edits = []
        for name, parent, s, e in class_bodies(t):
            for a, b in members(t[s:e]):
                st = t[s + a:s + b]
                m = METH.match(re.sub(r'\{[^}]*\}', '', st))
                if not m or m.group(1).lower() == 'constructor':
                    continue
                mv = re.search(r'\bvirtual\b(\s*;)', st, re.I)
                if mv and ancestor_virtual(info, name.lower(), m.group(2).lower()) and 'abstract' not in st.lower():
                    edits.append((s + a + mv.start(), s + a + mv.start() + 7))
        edits = sorted(set(edits))   # {$ifdef} variants of one class share a body
        if edits:
            for a, b in sorted(edits, reverse=True):
                t = t[:a] + 'override' + t[b:]
            p.write_bytes(t.encode('utf-8', 'surrogateescape'))
            total += len(edits)
            print(f'{p.name}: {len(edits)}')
    print(f'virtual-override: {total} methods')


main()
