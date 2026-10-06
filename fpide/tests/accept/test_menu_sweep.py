#!/usr/bin/env python3
"""Sweep of the whole menu bar of fpide: every enabled item of every menu is activated, the
screen is looked at, Esc brings the IDE back. The IDE must stay alive and must not report
"Program generated a signal 11" (the IDE's own SIGSEGV box). It does not judge what each item
shows (test_accept.py does that for the main functions): it is the "nothing crashes" net.
usage: test_menu_sweep.py PATH/TO/fp        (needs tmux)"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from fpide_term import TmuxTerm

SKIP={'Exit','Command shell','Print','Print setup'}
def titles(t):
    out=[]
    for l in t.lines():
        for m in re.finditer(r'[╔┌]═?\[?■?\]?[═─]*\s*([^═─┐╗]{3,40}?)\s*[═─]{2,}',l): out.append(m.group(1).strip())
    return out
t=TmuxTerm(sys.argv[1],env={'TV_FAR2L':'0'})
bad=0
count=0
try:
    open(os.path.join(t.work,'sample.pas'),'w').write("program sample;\nbegin\n  writeln('hello world');\nend.\n")
    t.wait_for('Window  Help')
    t.key('F3'); t.wait_for('Open a file'); t.type('sample.pas'); t.key('Enter'); t.wait_for('sample.pas')
    for hot,name in (('M-f','File'),('M-e','Edit'),('M-s','Search'),('M-r','Run'),('M-c','Compile'),('M-d','Debug'),('M-t','Tools'),('M-o','Options'),('M-w','Window'),('M-h','Help')):
        t.key(hot); t.pump(0.5)
        labels=[r[1] for r in t._menu_rows()]
        t.key('Escape','Escape'); t.pump(0.3)
        for lab in labels:
            base=re.split(r'\s{2,}',lab)[0].rstrip('.►').strip()
            if base in SKIP or not base: continue
            if not t.alive(): break
            before=t.text()
            ok=t.menu(hot,base)
            t.pump(0.7)
            after=t.text()
            ttl=titles(t)
            state='alive' if t.alive() else 'DEAD'
            changed = after!=before
            count+=1
            crashed = ('signal 11' in after) or not t.alive()
            print(('FAIL ' if crashed else 'PASS ')+'%s > %s (%s)'%(name,base[:28],' / '.join(ttl[-2:]) or 'no window'), flush=True)
            if crashed:
                bad+=1
                print('   >>>',after[-400:].replace('\n','|'),'| stderr:',t.stderr()[:200])
            # bring back to a clean state
            for _ in range(4):
                t.key('Escape'); t.pump(0.25)
            if not t.alive(): break
        if not t.alive(): break
finally:
    t.close()
print('%d items, %d crashed'%(count,bad))
sys.exit(1 if bad else 0)
