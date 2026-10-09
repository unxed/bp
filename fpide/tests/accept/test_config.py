#!/usr/bin/env python3
"""Where fpide keeps the files of the user: fp.ini and fp.cfg in $XDG_CONFIG_HOME/fp, the desktop fp.dsk in
$XDG_STATE_HOME/fp, nothing in the current directory; the files of ~/.fp are taken over on the first start; the next
start in the same directory brings back the windows and the breakpoints.
usage: test_config.py PATH/TO/fp        (needs tmux; HOME and the XDG directories are temp dirs)"""
import os
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.dirname(__file__))
from fpide_term import TmuxTerm

fails = 0
count = 0


def check(cond, name, term=None):
    global fails, count
    count += 1
    print(('PASS ' if cond else 'FAIL ') + name, flush=True)
    if not cond:
        fails += 1
        if term:
            print(term.text())
            print('stderr:', term.stderr()[:400])


def leave(t):
    t.key('M-x')
    return t.wait_until(lambda: not t.alive(), 8) and 'EXIT=0' in t.stderr()


# a first start: the files are made in the XDG directories
t = TmuxTerm(sys.argv[1], env={'TV_FAR2L': '0'})
try:
    conf = os.path.join(t.work, '.config', 'fp')
    state = os.path.join(t.work, '.local', 'state', 'fp')
    with open(os.path.join(t.work, 'hello.pas'), 'w') as f:
        f.write("program hello;\nbegin\nend.\n")
    check(t.wait_for('Window  Help'), 'the IDE starts', t)
    t.key('F3'); t.wait_for('Open a file'); t.type('hello.pas'); t.key('Enter')
    t.wait_for('program hello')
    t.key('M-F9')                           # a compile writes the switches (fp.cfg) for the compiler
    check(t.wait_for('Compile successful', 30), 'a file is compiled', t)
    t.key('Enter')
    check(os.path.isfile(os.path.join(conf, 'fp.cfg')), 'fp.cfg is written into $XDG_CONFIG_HOME/fp', t)
    check(leave(t), 'Alt+X leaves the IDE', t)
    check(os.path.isfile(os.path.join(conf, 'fp.ini')), 'fp.ini is written into $XDG_CONFIG_HOME/fp', t)
    check(os.path.isfile(os.path.join(state, 'fp.dsk')), 'fp.dsk is written into $XDG_STATE_HOME/fp', t)
    left = [n for n in ('fp.ini', 'fp.cfg', 'fp.dsk') if os.path.exists(os.path.join(t.work, n))]
    check(not left, 'nothing is written into the current directory: %r' % left, t)
    check(not os.path.exists(os.path.join(t.work, '.fp')), 'no ~/.fp is made', t)
finally:
    t.close()

# the desktop and the breakpoints come back on the next start in the same directory
t = TmuxTerm(sys.argv[1], env={'TV_FAR2L': '0'})
work = t.work
try:
    with open(os.path.join(work, 'hello.pas'), 'w') as f:
        f.write("program hello;\nbegin\n  writeln(1);\nend.\n")
    check(t.wait_for('Window  Help'), 'the IDE starts (desktop)', t)
    t.key('F3'); t.wait_for('Open a file'); t.type('hello.pas'); t.key('Enter')
    check(t.wait_for('program hello'), 'hello.pas is opened', t)
    t.key('Down', 'Down')
    check(t.wait_until(lambda: t.indicator() == (3, 1)), 'the cursor is on line 3: %r' % (t.indicator(),), t)
    check(t.menu('M-d', 'Breakpoint', exact=True), 'Debug > Breakpoint sets a breakpoint on line 3', t)
    t.pump(0.3)
    check(leave(t), 'Alt+X leaves the IDE (desktop)', t)
finally:
    t.stop()
t = TmuxTerm(sys.argv[1], env={'TV_FAR2L': '0'}, work=work)
try:
    check(t.wait_for('Window  Help'), 'the IDE starts again in the same directory', t)
    check(t.wait_for('hello.pas') and 'program hello' in t.text(), 'the window of hello.pas is back', t)
    check('never started' not in t.text(), 'no question about a config file of this directory', t)
    check('noname' not in t.text(), 'no empty file is opened beside it', t)
    check(t.wait_until(lambda: t.indicator() == (3, 1)), 'the cursor is back on line 3: %r' % (t.indicator(),), t)
    t.menu('M-d', 'Breakpoint List')
    check(t.wait_for('Breakpoint list', 3) and t.wait_for('hello.pas:3', 3), 'the breakpoint on hello.pas:3 is back', t)
finally:
    t.close()

# a start with the files of an older version in ~/.fp: they are copied into the new places
home = tempfile.mkdtemp(prefix='fpide-home-')
old = os.path.join(home, '.fp')
os.makedirs(old)
files = {'fp.ini': '[Misc]\nComment=old ini\n', 'fp.cfg': '# old switches\n', 'fp.dir': '[Misc]\nComment=old dir\n'}
for name, text in files.items():
    with open(os.path.join(old, name), 'w') as f:
        f.write(text)
with open(os.path.join(old, 'fp.dsk'), 'wb') as f:
    f.write(b'not a desktop')
t = TmuxTerm(sys.argv[1], env={'TV_FAR2L': '0', 'HOME': home})
try:
    conf = os.path.join(t.work, '.config', 'fp')
    state = os.path.join(t.work, '.local', 'state', 'fp')
    check(t.wait_for('Window  Help'), 'the IDE starts with a ~/.fp', t)
    for name, text in files.items():
        p = os.path.join(conf, name)
        check(os.path.isfile(p) and open(p).read() == text, '%s of ~/.fp is copied into $XDG_CONFIG_HOME/fp' % name, t)
    p = os.path.join(state, 'fp.dsk')
    check(os.path.isfile(p) and open(p, 'rb').read() == b'not a desktop', 'fp.dsk of ~/.fp is copied into $XDG_STATE_HOME/fp', t)
    check(open(os.path.join(old, 'fp.ini')).read() == files['fp.ini'], '~/.fp is left as it was', t)
    check(t.alive(), 'is still running', t)
finally:
    t.close()
    shutil.rmtree(home, ignore_errors=True)

print('%d checks, %d failed' % (count, fails))
sys.exit(1 if fails else 0)
