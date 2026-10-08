#!/usr/bin/env python3
"""Acceptance test of fpide on tv3: the IDE is started in a 100x30 terminal and clicked through
(keys only). One check per user-visible function; PASS/FAIL lines, exit status 1 on any FAIL.
usage: test_accept.py PATH/TO/fp        (needs tmux; no network, no root, HOME is a temp dir)

Every step is something done by hand while bringing the port up: the file list of "what works"
is the test list. A check that fails is a bug to fix or a documented limitation (MIGRATION-STATUS.md)."""
import os
import sys
import time

sys.path.insert(0, os.path.dirname(__file__))
from fpide_term import TmuxTerm

fails = 0
count = 0


def find_rtl_units():
    """the directory with the RTL units of the installed FPC (it differs between distributions)"""
    import glob
    for pat in ('/usr/lib/*/fpc/*/units/*/rtl', '/usr/lib/fpc/*/units/*/rtl', '/usr/local/lib/fpc/*/units/*/rtl'):
        found = sorted(glob.glob(pat))
        if found:
            return found[-1]
    return ''


def check(cond, name, term=None):
    global fails, count
    count += 1
    print(('PASS ' if cond else 'FAIL ') + name, flush=True)
    if not cond:
        fails += 1
        if term:
            print(term.text())
            print('stderr:', term.stderr()[:400])


# TV_FAR2L=0: tmux does not answer the far2l terminal queries (clipboard etc.); see MIGRATION-STATUS.md
t = TmuxTerm(sys.argv[1], env={'TV_FAR2L': '0'})
try:
    # --- start ------------------------------------------------------------------------------------
    check(t.wait_for('Window  Help'), 'starts and draws the menu bar', t)
    check(t.alive(), 'is still running after the start', t)
    check('F1 Help' in t.lines()[-1] and 'F9 Make' in t.lines()[-1], 'the status line is on the last row', t)

    # --- menus ------------------------------------------------------------------------------------
    t.key('F10', 'Down')
    check(t.wait_for('New from template...') and t.wait_for('Exit           Alt+X'), 'F10 + Down drops the File menu down', t)
    t.key('Escape', 'Escape')
    check(t.wait_gone('New from template...'), 'Esc closes the menu', t)
    t.key('M-f')
    check(t.wait_for('Save all'), 'Alt+F opens the File menu', t)
    t.key('Escape', 'Escape')
    for hot, item in (('M-e', 'Undo'), ('M-r', 'Run'), ('M-c', 'Compile'), ('M-d', 'Debug'),
                      ('M-t', 'Messages'), ('M-o', 'Compiler'), ('M-w', 'Tile'), ('M-h', 'Contents')):
        t.key(hot)
        check(t.wait_for(item, 3), 'Alt+%s opens a menu with "%s"' % (hot[-1].upper(), item), t)
        t.key('Escape', 'Escape')

    # --- editor: new file, typing -------------------------------------------------------------------
    t.key('M-f', 'Enter')   # File > New
    check(t.wait_for('noname01.pas'), 'File > New opens an edit window', t)
    t.type('program hello;')
    t.key('Enter')
    t.type("var f: text; begin assign(f, 'ran.txt'); rewrite(f); writeln(f, 'ok'); close(f) end.")
    check(t.wait_for("rewrite(f)"), 'typed text appears in the editor', t)
    check('program hello;' in t.text(), 'a semicolon and Enter are typed correctly', t)

    # the Search menu is disabled (skipped) until there is an edit window, as in the original IDE
    t.key('M-s')
    check(t.wait_for('Find...') or t.wait_for('Find'), 'Alt+S opens the Search menu once there is an editor', t)
    t.key('Escape', 'Escape')

    # --- save as ------------------------------------------------------------------------------------
    t.key('F2')
    check(t.wait_for('Save File As'), 'F2 on an unnamed file asks for a name', t)
    t.type('hello.pas')
    t.key('Enter')
    check(t.wait_for('hello.pas'), 'the window is renamed after Save as', t)
    check(os.path.exists(os.path.join(t.work, 'hello.pas')), 'the file was written to disk', t)
    saved = os.path.join(t.work, 'hello.pas')
    check(os.path.exists(saved) and 'rewrite(f)' in open(saved).read(), 'with the typed content', t)

    # --- compile with the external compiler (fpc of the system) ------------------------------------------
    t.key('M-F9')
    check(t.wait_for('Compile successful', 30), 'Alt+F9 runs the external compiler: Compile successful', t)
    check(os.path.exists(os.path.join(t.work, 'hello')), 'the executable was linked', t)
    check(t.alive(), 'is still running after the compile', t)
    t.key('Enter')

    # --- Options > Directories (the unit directories reach the compiler through fp.cfg) -----------------
    check(t.menu('M-o', 'Directories'), 'Options > Directories is found in the menu', t)
    check(t.wait_for('Unit directories:'), 'the Directories dialog opens with its tabs', t)
    rtl = find_rtl_units()
    check(rtl != '', 'the RTL units of FPC are installed (fp-units-rtl)')
    t.type(rtl)
    check(t.wait_for(rtl[-30:]), 'text typed into the unit directories memo appears', t)
    t.key('Tab', 'Enter')
    check(t.wait_gone('Unit directories:'), 'OK closes the dialog', t)

    # --- run ---------------------------------------------------------------------------------------------
    t.key('C-F9')
    ran = os.path.join(t.work, 'ran.txt')
    end = time.time() + 15
    while time.time() < end and not os.path.exists(ran):
        time.sleep(0.2)
    check(os.path.exists(ran), 'Ctrl+F9 runs the program (it wrote ran.txt)', t)
    # on Unix the IDE waits for a key after the program (as the original does): "Press any key to return to IDE"
    check(t.wait_for('Press any key to return to IDE', 10), 'the IDE waits for a key after the program ended', t)
    t.key('Enter')
    check(t.wait_for('F9 Make', 10) and t.alive(), 'the IDE is back after the key', t)
    check(os.path.exists(os.path.join(t.work, '.local/state/fp/fp.dsk')), 'the desktop file was saved before the run', t)

    check(t.alive(), 'no runtime error during the whole run (stderr: %r)' % t.stderr()[:80], t)
finally:
    t.close()

print('%d checks, %d failed' % (count, fails))
sys.exit(1 if fails else 0)
