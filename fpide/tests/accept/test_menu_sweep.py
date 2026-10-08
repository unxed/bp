#!/usr/bin/env python3
"""Sweep of the whole menu bar of fpide: every enabled item of every menu is activated, the
screen is looked at, Esc brings the IDE back. The IDE must stay alive and must not report
"Program generated a signal 11" (the IDE's own SIGSEGV box). It does not judge what each item
shows (test_accept.py does that for the main functions): it is the "nothing crashes" net.
The items are dealt to the workers: -j N runs N copies of the IDE side by side (each its own tmux server
and HOME), --part K/N takes the K-th of N parts of the items (for a CI matrix).
usage: test_menu_sweep.py PATH/TO/fp [-j N] [--part K/N]        (needs tmux)"""
import argparse
import os
import re
import sys
import threading

sys.path.insert(0, os.path.dirname(__file__))
from fpide_term import TmuxTerm

SKIP = {'Exit', 'Command shell', 'Print', 'Print setup'}
MENUS = (('M-f', 'File'), ('M-e', 'Edit'), ('M-s', 'Search'), ('M-r', 'Run'), ('M-c', 'Compile'), ('M-d', 'Debug'),
         ('M-t', 'Tools'), ('M-o', 'Options'), ('M-w', 'Window'), ('M-h', 'Help'))


def titles(t):
    out = []
    for l in t.lines():
        for m in re.finditer(r'[╔┌]═?\[?■?\]?[═─]*\s*([^═─┐╗]{3,40}?)\s*[═─]{2,}', l):
            out.append(m.group(1).strip())
    return out


def start(fp):
    """the IDE with sample.pas open"""
    t = TmuxTerm(fp, env={'TV_FAR2L': '0'})
    open(os.path.join(t.work, 'sample.pas'), 'w').write("program sample;\nbegin\n  writeln('hello world');\nend.\n")
    t.wait_for('Window  Help')
    t.key('F3'); t.wait_for('Open a file'); t.type('sample.pas'); t.key('Enter'); t.wait_for('sample.pas')
    return t


def items(t):
    """[(hotkey, menu, item)] of the whole menu bar, in the order of the menus"""
    out = []
    for hot, name in MENUS:
        t.key(hot); t.pump(0.5)
        labels = [r[1] for r in t._menu_rows()]
        t.key('Escape', 'Escape'); t.pump(0.3)
        for lab in labels:
            base = re.split(r'\s{2,}', lab)[0].rstrip('.►').strip()
            if base and base not in SKIP:
                out.append((hot, name, base))
    return out


def sweep(fp, work, results):
    """activates the items of `work` [(index, (hotkey, menu, item))] in one IDE; results[index] = (crashed, line)"""
    t = start(fp)
    try:
        for i, (hot, name, base) in work:
            if not t.alive():
                results[i] = (True, 'FAIL %s > %s (not run: the IDE is dead)' % (name, base[:28]))
                continue
            t.menu(hot, base)
            t.pump(0.7)
            after = t.text()
            ttl = titles(t)
            crashed = ('signal 11' in after) or not t.alive()
            line = ('FAIL ' if crashed else 'PASS ') + '%s > %s (%s)' % (name, base[:28], ' / '.join(ttl[-2:]) or 'no window')
            if crashed:
                line += '\n   >>> ' + after[-400:].replace('\n', '|') + ' | stderr: ' + t.stderr()[:200]
            results[i] = (crashed, line)
            # bring back to a clean state
            for _ in range(4):
                t.key('Escape'); t.pump(0.25)
    finally:
        t.close()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('fp')
    ap.add_argument('-j', type=int, default=8, help='copies of the IDE side by side')
    ap.add_argument('--part', default='1/1', help='K/N: the K-th of N parts of the items')
    a = ap.parse_args()
    k, n = (int(x) for x in a.part.split('/'))
    t = start(a.fp)
    try:
        everything = items(t)
    finally:
        t.close()
    mine = [(i, it) for i, it in enumerate(everything) if i % n == k - 1]
    jobs = max(1, min(a.j, len(mine)))
    results = {}
    threads = [threading.Thread(target=sweep, args=(a.fp, mine[w::jobs], results)) for w in range(jobs)]
    for th in threads:
        th.start()
    for th in threads:
        th.join()
    bad = 0
    for i, (hot, name, base) in mine:
        crashed, line = results.get(i, (True, 'FAIL %s > %s (not run)' % (name, base[:28])))
        print(line)
        bad += crashed
    print('%d items, %d crashed (part %s, %d of %d items, -j %d)' % (len(mine), bad, a.part, len(mine), len(everything), jobs))
    sys.exit(1 if bad or not mine else 0)


main()
