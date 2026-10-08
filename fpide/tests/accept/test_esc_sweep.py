#!/usr/bin/env python3
"""Esc sweep of fpide (navigation guidelines of vtui: Esc closes the dialog): every item of the menu bar that ends in "..." (it opens a dialog) is
activated and one Esc is sent; the screen has to be what it was before. Items that open a window and not a dialog are told apart by the title of
the new window (the lists below).
usage: test_esc_sweep.py PATH/TO/fp        (needs tmux)"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from fpide_term import TmuxTerm

# these open a window (not a modal dialog) or leave the IDE: Esc is not expected to restore the screen
SKIP = {'Exit', 'Command shell', 'Print', 'Print setup', 'List', 'Help', 'Files', 'Contents', 'Index', 'Topic search'}
t = TmuxTerm(sys.argv[1], env={'TV_FAR2L': '0'})
bad = 0
count = 0
try:
    open(os.path.join(t.work, 'sample.pas'), 'w').write("program sample;\nbegin\n  writeln('hello world');\nend.\n")
    t.wait_for('Window  Help')
    t.key('F3'); t.wait_for('Open a file'); t.type('sample.pas'); t.key('Enter'); t.wait_for('sample.pas')
    for hot, name in (('M-f', 'File'), ('M-e', 'Edit'), ('M-s', 'Search'), ('M-r', 'Run'), ('M-c', 'Compile'), ('M-d', 'Debug'), ('M-t', 'Tools'),
                      ('M-o', 'Options'), ('M-w', 'Window'), ('M-h', 'Help')):
        t.key(hot)
        t.pump(0.5)
        labels = [r[1] for r in t._menu_rows()]
        t.key('Escape', 'Escape')
        t.pump(0.3)
        for lab in labels:
            if not lab.rstrip().endswith('...') and '...' not in re.split(r'\s{2,}', lab)[0]:
                continue
            base = re.split(r'\s{2,}', lab)[0].rstrip('.►').strip()
            if base in SKIP or not base:
                continue
            before = t.text()
            t.menu(hot, base)
            t.pump(0.7)
            opened = t.text() != before
            t.key('Escape')
            t.pump(0.5)
            after = t.text()
            count += 1
            ok = after == before
            print(('PASS ' if ok else 'FAIL ') + '%s > %s: Esc %s' % (name, base[:30], 'restores the screen' if ok else 'leaves something open' + ('' if opened else ' (it did not open?)')), flush=True)
            if not ok:
                bad += 1
                print(after)
                for _ in range(4):
                    t.key('Escape')
                    t.pump(0.25)
finally:
    t.close()
print('%d dialogs, %d not closed by Esc' % (count, bad))
sys.exit(1 if bad else 0)
