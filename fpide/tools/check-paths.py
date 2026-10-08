#!/usr/bin/env python3
"""Counts the places in fpide/src that spell a DOS / Windows path assumption by hand (a ratchet: a number may only fall).
What is counted: a backslash as a char literal, a drive letter prefix ('c:\\...'), a test of a drive letter ([2]=':'),
the mask '*.*' (it misses names without a dot on Unix), COMSPEC, and 'cygdrive'. Lines of comments are skipped.
Most places that are left are inside {$ifndef Unix} / {$ifdef Windows} code or are the second branch of a platform test;
a new one in portable code is a bug on Linux.
usage: tools/check-paths.py [--update]     the baseline is tools/paths-baseline.txt"""
import os, re, sys

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
src = os.path.join(root, 'src')
base = os.path.join(root, 'tools', 'paths-baseline.txt')
pat = re.compile(r"'\\'|'[A-Za-z]:\\|\[2\]\s*=\s*':'|'\*\.\*'|COMSPEC|cygdrive", re.I)
skip = re.compile(r'^\s*(\{|//|\(\*)')
# files that came from other systems and are not built for Unix paths at all
ignore = {'vesa.pas', 'pmode.pas', 'windebug.pas', 'fpcygwin.pas', 'fpmingw.pas'}
counts = {}
for f in sorted(os.listdir(src)):
    if not (f.endswith('.pas') or f.endswith('.inc')) or f in ignore:
        continue
    n = 0
    for line in open(os.path.join(src, f), encoding='utf-8', errors='replace'):
        if skip.match(line):
            continue
        n += len(pat.findall(line))
    if n:
        counts[f] = n
total = sum(counts.values())
if '--update' in sys.argv:
    with open(base, 'w') as fh:
        for f, n in counts.items():
            fh.write('%s %d\n' % (f, n))
    print('baseline', total)
    sys.exit(0)
old = {}
if os.path.exists(base):
    for l in open(base):
        a, b = l.split()
        old[a] = int(b)
bad = [(f, n, old.get(f, 0)) for f, n in counts.items() if n > old.get(f, 0)]
for f, n, o in bad:
    print('FAIL %s: %d hand-spelled DOS path assumptions (the baseline allows %d); use DirSep / AllFilesMask / ExtractFile* and guard what is DOS only' % (f, n, o))
fell = [(f, o, counts.get(f, 0)) for f, o in old.items() if counts.get(f, 0) < o]
for f, o, n in fell:
    print('note %s fell from %d to %d: run tools/check-paths.py --update' % (f, o, n))
print('total %d (baseline %d)' % (total, sum(old.values())))
sys.exit(1 if bad else 0)
