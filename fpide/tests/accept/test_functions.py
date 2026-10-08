#!/usr/bin/env python3
"""Integration test of fpide on tv3: the functions of the IDE are exercised one by one through the keyboard
(a tmux terminal, see fpide_term.py), the way they were clicked through by hand: the editor (typing, undo/redo,
clipboard, selection), Search (find, find again, replace, go to line), Window (tile, cascade, next, zoom, close all),
Tools (calculator, ASCII table), Options dialogs, Help, the file dialogs, the compiler (error messages with
positions, jump to the error, a good build) and Run.
usage: test_functions.py PATH/TO/fp [section ...]     sections: edit search window tools options files compile golang debuggo unicode templates clipboard syscb debug browser longlines misc mouse ux paths exit
Prints PASS/FAIL per check, exit status 1 on any FAIL. Needs tmux, fpc (the IDE runs the compiler of the system)."""
import datetime
import os
import re
import subprocess
import sys
import time

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


def editor_lines(t):
    """the text of the active edit window (the one with the double frame): the cells between its borders"""
    lines = t.lines()
    top = x0 = x1 = None
    for i, l in enumerate(lines):
        if '╔' in l and '╗' in l:
            top, x0, x1 = i, l.index('╔'), l.rindex('╗')
            break
    if top is None:
        return []
    out = []
    for l in lines[top + 1:]:
        if len(l) <= x0 or l[x0] not in '║└':
            break
        if l[x0] == '└':
            break
        out.append(l[x0 + 1:x1].rstrip(' ▲▓▼■▒░'))
    return out


def new_file(t, name=None):
    """File > New; the menu is retried once if the window did not come (a dialog may have been in the way)"""
    for _ in range(2):
        before = t.text().count('noname')
        t.menu('M-f', 'New', exact=True)    # the menu remembers the item chosen last: go to "New" by name
        if t.wait_until(lambda: t.text().count('noname') > before, 3):
            return True
        close_dialogs(t, 3)
    return False


def type_lines(t, *lines):
    for i, l in enumerate(lines):
        t.type(l)
        if i < len(lines) - 1:
            t.key('Enter')


def menu(t, hot, item, exact=False):
    ok = t.menu(hot, item, exact=exact)
    t.pump(0.4)
    return ok


def close_dialogs(t, n=3):
    for _ in range(n):
        t.key('Escape')
        t.pump(0.15)


def run(fp, only):
    t = TmuxTerm(fp, env={'TV_FAR2L': '0'})
    try:
        t.wait_for('Window  Help')
        for name, fn in SECTIONS:
            if only and name not in only:
                continue
            print('--- %s' % name, flush=True)
            close_all(t)
            fn(t)
            if not t.alive():
                check(False, 'the IDE died in section %s: %s' % (name, t.stderr()[:200]))
                break
            # a clean desktop for the next section: close every window without saving
            close_all(t)
        check(t.alive(), 'the IDE is still running at the end (stderr: %r)' % t.stderr()[:80], t)
    finally:
        t.close()


def close_all(t):
    """Window > Close all; every "Save?" box (Yes / No / Cancel) is answered No"""
    close_dialogs(t)
    for _ in range(8):
        if not menu(t, 'M-w', 'Close all'):
            break
        t.pump(0.4)
        answered = False
        for _ in range(8):
            txt = t.text()
            if 'Yes' in txt and 'No' in txt and 'Cancel' in txt:
                t.key('n')
                answered = True
                t.pump(0.3)
            else:
                break
        close_dialogs(t, 1)
        if not answered:
            break


# ---------------------------------------------------------------------------------------------------------
def section_edit(t):
    check(new_file(t), 'File > New opens an edit window', t)
    type_lines(t, 'hello world', 'second line')
    check(editor_lines(t)[:2] == ['hello world', 'second line'], 'typed text is in the editor: %r' % editor_lines(t)[:2], t)
    check(t.indicator() == (2, 12), 'the indicator follows the typing (2:12): %r' % (t.indicator(),), t)

    # cursor keys
    t.key('C-PPage')
    check(t.indicator() == (1, 1), 'Ctrl+PgUp goes to the start of the text, 1:1', t)
    t.key('End')
    check(t.indicator() == (1, 12), 'End goes to the end of the line (1:12)', t)
    t.key('Down', 'Home')
    check(t.indicator() == (2, 1), 'Down, Home: 2:1', t)
    t.key('C-NPage')
    check(t.indicator() == (2, 12), 'Ctrl+PgDn goes to the end of the text, 2:12', t)

    # delete and backspace
    t.key('BSpace', 'BSpace')
    check(editor_lines(t)[1] == 'second li', 'Backspace deletes the char before the cursor: %r' % editor_lines(t)[1], t)
    t.key('Left', 'Delete')
    check(editor_lines(t)[1] == 'second l', 'Delete deletes the char under the cursor: %r' % editor_lines(t)[1], t)

    # undo / redo (Edit menu)
    check(menu(t, 'M-e', 'Undo'), 'Edit > Undo is enabled')
    check(editor_lines(t)[1] == 'second li', 'Undo brings the deleted char back: %r' % editor_lines(t)[1], t)
    check(menu(t, 'M-e', 'Redo'), 'Edit > Redo is enabled after an undo')
    check(editor_lines(t)[1] == 'second l', 'Redo deletes it again: %r' % editor_lines(t)[1], t)

    # select all, copy, paste
    check(menu(t, 'M-e', 'Select All'), 'Edit > Select All')
    check(menu(t, 'M-e', 'Copy', exact=True), 'Edit > Copy is enabled for a selection')
    t.key('C-NPage', 'Enter')
    check(menu(t, 'M-e', 'Paste', exact=True), 'Edit > Paste is enabled after a copy')
    got = editor_lines(t)
    check(got[:4] == ['hello world', 'second l', 'hello world', 'second l'], 'Paste inserts the copied text: %r' % got[:5], t)
    t.key('C-NPage', 'Enter')
    t.key('C-v')
    check('\n'.join(editor_lines(t)).count('hello world') == 3, 'Ctrl+V pastes too: %r' % editor_lines(t)[:8], t)

    # cut and paste back, then clear, on a fresh window
    new_file(t)
    type_lines(t, 'one', 'two', 'three')
    t.key('C-PPage', 'S-Down')
    check(menu(t, 'M-e', 'Cut'), 'Edit > Cut is enabled for a selection')
    check(editor_lines(t)[:2] == ['two', 'three'], 'Cut removes the selection: %r' % editor_lines(t)[:3], t)
    check(menu(t, 'M-e', 'Paste', exact=True), 'Edit > Paste after the cut')
    check(editor_lines(t)[:3] == ['one', 'two', 'three'], 'Paste puts it back: %r' % editor_lines(t)[:3], t)
    menu(t, 'M-e', 'Unselect')
    t.key('C-PPage', 'S-Down')
    check(menu(t, 'M-e', 'Clear'), 'Edit > Clear is enabled for a selection')
    check(editor_lines(t)[:2] == ['two', 'three'], 'Clear removes the selected text: %r' % editor_lines(t)[:3], t)
    check(menu(t, 'M-e', 'Select All'), 'Select All again')
    check(menu(t, 'M-e', 'Unselect'), 'Edit > Unselect')
    check(menu(t, 'M-e', 'Show clipboard'), 'Edit > Show clipboard')
    check(t.wait_for('Clipboard') and 'one' in t.text(), 'the clipboard window holds the cut text', t)
    t.key('Escape')


def section_search(t):
    new_file(t)
    type_lines(t, 'line 0 foo bar', 'line 1 foo bar', 'line 2 foo bar', 'line 3 foo bar', 'line 4 foo bar')
    t.key('C-PPage')
    check(menu(t, 'M-s', 'Find', exact=True), 'Search > Find...')
    check(t.wait_for('Text to find') and t.wait_for('Case sensitive'), 'the Find dialog opens with its options', t)
    t.type('foo')          # the word under the cursor is preselected: typing replaces it
    t.key('Enter')
    check(t.wait_gone('Text to find'), 'OK closes the Find dialog', t)
    check(t.wait_until(lambda: t.indicator() == (1, 11)), 'Find puts the cursor after the first "foo" (1:11): %r' % (t.indicator(),), t)
    check(menu(t, 'M-s', 'Search again'), 'Search > Search again')
    check(t.wait_until(lambda: t.indicator() == (2, 11)), 'Search again goes to the next one (2:11): %r' % (t.indicator(),), t)

    # not found: a message, and the IDE goes on
    menu(t, 'M-s', 'Find', exact=True)
    t.wait_for('Text to find')
    t.type('nothing-like-this')
    t.key('Enter')
    check(t.wait_for('not found') or t.wait_for('Search string'), 'a missing string is reported', t)
    t.key('Enter')
    close_dialogs(t, 1)

    check(menu(t, 'M-s', 'Go to line'), 'Search > Go to line number...')
    check(t.wait_for('Goto line'), 'the Goto line dialog opens', t)
    t.type('4')
    t.key('Enter')
    check(t.wait_until(lambda: t.indicator() and t.indicator()[0] == 4), 'Go to line 4: the cursor is on line 4 (%r)' % (t.indicator(),), t)

    # replace, answering the prompt with Yes for every occurrence
    t.key('C-PPage')
    check(menu(t, 'M-s', 'Replace'), 'Search > Replace...')
    check(t.wait_for('New text'), 'the Replace dialog opens', t)
    t.type('bar')
    t.key('Tab')
    t.type('QUX')
    t.key('Tab', 'Tab', 'Tab', 'Tab', 'Tab', 'Tab')    # to the "Change all" button
    t.key('Enter')
    answered = 0
    for _ in range(8):
        if t.wait_for('Replace this occurrence', 2):
            t.key('y')
            answered += 1
            t.pump(0.3)
        else:
            break
    check(answered == 5, 'the replace prompt came for each of the 5 lines (%d)' % answered, t)
    got = editor_lines(t)
    check(got[:5] == ['line %d foo QUX' % i for i in range(5)], 'every "bar" is now "QUX": %r' % got[:5], t)


def section_window(t):
    new_file(t); t.type('aaa')
    new_file(t); t.type('bbb')
    check('aaa' in t.text() or 'bbb' in t.text(), 'two windows are open', t)
    check(menu(t, 'M-w', 'Tile'), 'Window > Tile is enabled with windows open')
    txt = t.text()
    check('aaa' in txt and 'bbb' in txt, 'tiled windows show both texts', t)
    check(menu(t, 'M-w', 'Cascade'), 'Window > Cascade')
    check(menu(t, 'M-w', 'Next'), 'Window > Next')
    t.pump(0.3)
    check(editor_lines(t)[:1] in (['aaa'], ['bbb']), 'Next activates a window: %r' % editor_lines(t)[:1], t)
    first = editor_lines(t)[:1]
    check(menu(t, 'M-w', 'Previous'), 'Window > Previous')
    check(editor_lines(t)[:1] != first, 'Previous goes back to the other window', t)
    check(menu(t, 'M-w', 'Zoom'), 'Window > Zoom')
    check(t.wait_for('╔') , 'a zoomed window fills the desktop', t)
    check(menu(t, 'M-w', 'Zoom'), 'Window > Zoom again restores')
    check(menu(t, 'M-w', 'List'), 'Window > List...')
    check(t.wait_for('noname0'), 'the window list shows the windows', t)
    close_dialogs(t)
    check(menu(t, 'M-w', 'Close all'), 'Window > Close all')
    check(t.wait_for('Save') or t.wait_gone('aaa'), 'Close all asks about the modified windows', t)
    t.key('n')
    t.pump(0.3)
    t.key('n')
    t.pump(0.3)
    check(t.wait_gone('noname0', 4) or 'noname0' not in t.text(), 'all windows are closed', t)


def section_tools(t):
    check(menu(t, 'M-t', 'Calculator'), 'Tools > Calculator')
    check(t.wait_for('Calculator'), 'the calculator opens', t)

    def disp():
        L = t.lines()
        i = [k for k, l in enumerate(L) if 'Calculator' in l][0]
        # the display row between the calculator's own borders (the desktop shows through on both sides)
        m = re.search(r'║([^║]*)║', L[i + 2])
        return m.group(1).strip() if m else ''

    t.type('7*6=')
    check(t.wait_until(lambda: disp() == '42', 4), 'the calculator computes 7*6 = 42 (shows %r)' % disp(), t)
    t.type('c')
    t.type('2^10=')
    check(t.wait_until(lambda: disp() == '1024', 4), 'and 2^10 = 1024 (shows %r)' % disp(), t)
    t.type('c9')
    t.type('_')
    check(t.wait_until(lambda: disp() == '-9', 4), 'the sign key negates (shows %r)' % disp(), t)
    check('±' in t.text(), 'the sign button is drawn as ±', t)
    t.key('Escape', 'Escape')
    check(t.wait_gone('Calculator'), 'Esc closes the calculator', t)

    check(menu(t, 'M-t', 'Ascii table'), 'Tools > Ascii table')
    check(t.wait_for('ASCII Table') and 'Char: #0' in t.text(), 'the ASCII table opens', t)
    t.key('Escape')
    close_dialogs(t, 1)


def section_options(t):
    for item, title in (('Mode', 'Switches Mode'), ('Compiler', 'Compiler'), ('Memory sizes', 'Memory sizes'),
                        ('Linker', 'Linker'), ('Debugger', 'Debugging'), ('Directories', 'Unit directories'),
                        ('Browser', 'Browser Options'), ('Tools', 'Program titles')):
        check(menu(t, 'M-o', item), 'Options > %s...' % item)
        check(t.wait_for(title, 4), 'the %s dialog shows "%s"' % (item, title), t)
        t.key('Escape')
        t.pump(0.3)
        check(t.wait_gone(title, 3), 'Esc closes it', t)
    # Environment submenu
    check(menu(t, 'M-o', 'Environment'), 'Options > Environment')
    check(t.wait_for('Preferences') and 'Desktop' in t.text() and 'Keyboard' in t.text(), 'it has Preferences, Editor, Desktop, Keyboard & mouse', t)
    close_dialogs(t, 3)


def section_files(t):
    open(os.path.join(t.work, 'sample.pas'), 'w').write("program sample;\nbegin\n  writeln('hello world');\nend.\n")
    t.key('F3')
    check(t.wait_for('Open a file'), 'F3 opens the Open dialog', t)
    check('sample.pas' in t.text(), 'the file list shows sample.pas', t)
    check(str(datetime.date.today().year) in t.text(), 'with a date of this year (not 2033)', t)
    t.type('sample.pas')
    t.key('Enter')
    check(t.wait_for('sample.pas') and "writeln('hello world')" in t.text(), 'the file is opened in an edit window', t)
    # modify and save with F2
    t.key('C-NPage')
    t.type('{ added }')
    t.key('F2')
    t.pump(0.8)
    check('{ added }' in open(os.path.join(t.work, 'sample.pas')).read(), 'F2 saves the file to disk', t)
    # Save as
    check(menu(t, 'M-f', 'Save as'), 'File > Save as...')
    check(t.wait_for('Save File As'), 'the Save File As dialog opens', t)
    t.type('copy.pas')
    t.key('Enter')
    t.pump(0.8)
    check(os.path.exists(os.path.join(t.work, 'copy.pas')), 'Save as writes the new file', t)
    check('copy.pas' in t.text(), 'the window is renamed', t)
    # Change dir
    check(menu(t, 'M-f', 'Change dir'), 'File > Change dir...')
    check(t.wait_for('Change Directory'), 'the Change Directory dialog opens', t)
    t.key('Escape')
    # File > New from template
    check(menu(t, 'M-f', 'New from template'), 'File > New from template...')
    check(t.wait_for('Information') or t.wait_for('template'), 'the template list opens', t)
    close_dialogs(t)


def section_compile(t):
    with open(os.path.join(t.work, 'bad.pas'), 'w') as f:
        f.write("program bad;\nvar a: integer;\nbegin\n  a := b;\n  c := 1;\nend.\n")
    t.key('F3'); t.wait_for('Open a file'); t.type('bad.pas'); t.key('Enter')
    check(t.wait_for('bad.pas'), 'bad.pas is opened', t)
    t.key('M-F9')
    check(t.wait_for('Compile failed', 30), 'Alt+F9 (external fpc) reports a failed compile', t)
    t.key('Enter')
    check(t.wait_for('Compiler Messages', 5), 'the Compiler Messages window shows up', t)
    txt = t.text()
    check('bad.pas(4,8) Error: Identifier not found "b"' in txt or 'Identifier not found "b"' in txt, 'the first error is listed with its text', t)
    check('Identifier not found "c"' in txt, 'and the second one', t)
    # Enter on a message jumps to the source line
    t.key('Enter')
    t.pump(0.8)
    check(t.wait_until(lambda: t.cursor()[0] == 5), 'Enter on the first message puts the cursor on line 4 (cursor row %r)' % (t.cursor(),), t)
    # fix the program and build it
    new_file(t)
    type_lines(t, 'program good;', "begin writeln('hi') end.")
    t.key('F2'); t.wait_for('Save File As'); t.type('good.pas'); t.key('Enter'); t.pump(0.8)
    t.key('F9')
    check(t.wait_for('Compile successful', 30), 'F9 builds a good program: Compile successful', t)
    check(os.path.exists(os.path.join(t.work, 'good')), 'the executable exists', t)
    t.key('Enter')
    t.key('C-F9')
    check(t.wait_for('Press any key to return to IDE', 15), 'Ctrl+F9 runs it and the user screen waits for a key', t)
    t.key('Enter')
    check(t.wait_for('F9 Make', 10) and t.alive(), 'the IDE comes back after the key', t)


def section_golang(t):
    """Go through the go tool: a bad file shows the position of the error, a good one is built and run"""
    import shutil
    if shutil.which('go') is None:
        print('SKIP go is not installed')
        return
    with open(os.path.join(t.work, 'bad.go'), 'w') as f:
        f.write('package main\n\nfunc main() {\n\tx := undefinedName\n}\n')
    t.key('F3'); t.wait_for('Open a file'); t.type('bad.go'); t.key('Enter')
    check(t.wait_for('bad.go'), 'bad.go is opened', t)
    t.key('M-F9')
    check(t.wait_for('Compile failed', 60), 'Alt+F9 (go vet) reports a failed compile', t)
    t.key('Enter')
    check(t.wait_for('Compiler Messages', 5), 'the Compiler Messages window shows up', t)
    check('undefined: undefinedName' in t.text(), 'the error of go is listed with its text', t)
    t.key('Enter')
    t.pump(0.8)
    check(t.wait_until(lambda: t.cursor()[0] == 5), 'Enter on the message puts the cursor on line 4 (cursor row %r)' % (t.cursor(),), t)
    with open(os.path.join(t.work, 'hello.go'), 'w') as f:
        f.write('package main\n\nimport "fmt"\n\nfunc main() {\n\tfmt.Println("hi from go")\n}\n')
    t.key('F3'); t.wait_for('Open a file'); t.type('hello.go'); t.key('Enter')
    check(t.wait_for('hello.go'), 'hello.go is opened', t)
    t.key('F9')
    check(t.wait_for('Compile successful', 90), 'F9 builds a good Go program: Compile successful', t)
    check(os.path.exists(os.path.join(t.work, 'hello')), 'the executable exists', t)
    t.key('Enter')
    t.key('C-F9')
    check(t.wait_for('hi from go', 15), 'Ctrl+F9 runs it', t)
    t.key('Enter')
    check(t.wait_for('F9 Make', 10) and t.alive(), 'the IDE comes back after the key', t)
    # go test through Compile > Test
    os.remove(os.path.join(t.work, 'bad.go'))          # it would break the package
    with open(os.path.join(t.work, 'go.mod'), 'w') as f:
        f.write('module example.com/acc\n\ngo 1.20\n')
    with open(os.path.join(t.work, 'hello_test.go'), 'w') as f:
        f.write('package main\n\nimport "testing"\n\nfunc TestOne(t *testing.T) {\n\tt.Errorf("deliberate failure")\n}\n')
    t.key('M-c')                                          # the Compile menu
    t.pump(0.4)
    t.key('Down', 'Down', 'Down', 'Enter')                # Compile, Make, Build, Test
    check(t.wait_for('Compile failed', 120), 'Compile > Test runs go test and the failing test fails', t)
    t.key('Enter')
    check(t.wait_for('deliberate failure', 5), 'the message of the failed test is listed', t)
    # a new Go file starts with the template; Tools > Format Go file runs gofmt
    t.key('Escape'); t.pump(0.4)                         # leave the window of messages
    t.key('F3')
    check(t.wait_for('Open a file', 5), 'the Open dialog is shown after the messages', t)
    t.type('fresh.go'); t.key('Enter')
    check(t.wait_for('fresh.go', 10), 'fresh.go is opened', t)
    check(t.wait_for('fmt.Println("hello")', 5), 'a Go file that does not exist yet starts with the template', t)
    check('package main' in t.text() and 'fmt.Println' in t.text(), 'the template has the package and a call', t)
    with open(os.path.join(t.work, 'ugly.go'), 'w') as f:
        f.write('package main\nfunc  ugly( ){ }\n')
    t.key('F3'); t.wait_for('Open a file'); t.type('ugly.go'); t.key('Enter')
    check(t.wait_for('ugly.go', 5), 'ugly.go is opened', t)
    menu(t, 'M-t', 'Format Go file')
    check(t.wait_for('func ugly() {', 15), 'Tools > Format Go file runs gofmt and the editor shows the result', t)
    with open(os.path.join(t.work, 'ugly.go')) as f:
        check('func ugly() {' in f.read(), 'the file on disk is formatted', t)


def go_line_colors(t, marker, n=14):
    """like line_colors, for the window of a Go program found by a text on its first line"""
    for top, l in enumerate(t.lines()):
        if marker in l:
            return t.row_backgrounds(l.index(marker) + 2)[top:top + n]
    return [None] * n


def section_debuggo(t):
    """the Go debugger (Delve): a breakpoint, Run stops on it, F8 steps over, F7 steps into, F4 runs to the cursor,
    Continue runs to the end and shows the output; Program reset ends a session"""
    import shutil
    dlv = shutil.which('dlv') or os.path.expanduser('~/go/bin/dlv')
    if shutil.which('go') is None or not os.path.exists(dlv):
        print('SKIP go or dlv is not installed')
        return
    src = ['package main  // dbgo', '', 'import "fmt"', '', 'func add(a, b int) int {', '\treturn a + b', '}', '',
           'func main() {', '\tx := 20', '\ty := add(x, 22)', '\tfmt.Println("sum", y)', '\tfmt.Println("done")', '}']
    # the golang section leaves a go.mod: with it the whole package would be built (hello.go has a main of its own)
    if os.path.exists(os.path.join(t.work, 'go.mod')):
        os.remove(os.path.join(t.work, 'go.mod'))
    with open(os.path.join(t.work, 'dbgo.go'), 'w') as f:
        f.write('\n'.join(src) + '\n')
    t.key('F3'); t.wait_for('Open a file'); t.type('dbgo.go'); t.key('Enter')
    check(t.wait_for('dbgo.go'), 'dbgo.go is opened', t)
    t.key('C-Home', *(['Down'] * 10), 'Home')
    check(t.wait_until(lambda: t.indicator() == (11, 1)), 'the cursor is on line 11 (y := add): %r' % (t.indicator(),), t)
    menu(t, 'M-d', 'Breakpoint')
    t.pump(0.4)
    plain = go_line_colors(t, '// dbgo')
    check(plain[10] != plain[9], 'the breakpoint line is painted', t)
    t.menu('M-r', 'Run', exact=True)
    check(t.wait_until(lambda: go_line_colors(t, '// dbgo')[10] != plain[10], 90),
          'Run starts Delve and stops at the breakpoint: line 11 is painted as the debugger row', t)
    check(t.alive(), 'the IDE is alive while the program is stopped', t)
    t.key('F8')
    check(t.wait_until(lambda: go_line_colors(t, '// dbgo')[11] not in (plain[11], None) and go_line_colors(t, '// dbgo')[10] == plain[10]
                       or t.indicator()[0] == 12, 30), 'F8 steps over the call: the cursor moves to line 12: %r' % (t.indicator(),), t)
    check(t.indicator()[0] == 12, 'the stop is on line 12: %r' % (t.indicator(),), t)
    # F7 on line 12 (fmt.Println) goes into library code, so test F7 on the call instead: Program reset and begin again with F7
    menu(t, 'M-r', 'Program reset')
    t.pump(1)
    check(t.alive(), 'Program reset ends the session', t)
    t.key('F7')
    check(t.wait_until(lambda: t.indicator()[0] == 9, 90), 'F7 without a session starts it and stops in main (line 9): %r' % (t.indicator(),), t)
    t.key('F8', 'F8')
    check(t.wait_until(lambda: t.indicator()[0] == 11, 30), 'two steps over: line 11: %r' % (t.indicator(),), t)
    t.key('F7')
    check(t.wait_until(lambda: t.indicator()[0] == 5, 30), 'F7 on the call goes into add (line 5): %r' % (t.indicator(),), t)
    t.key('F8', 'F8')                 # add's statement, then back in main
    t.pump(1.5)
    check(t.wait_until(lambda: t.indicator()[0] in (11, 12), 30), 'stepping over the end of add returns to main: %r' % (t.indicator(),), t)
    # run to the cursor: line 13
    t.key('C-Home', *(['Down'] * 12), 'Home')
    t.key('F4')
    check(t.wait_until(lambda: go_line_colors(t, '// dbgo')[12] != plain[12], 30), 'F4 runs to the cursor: line 13 is the debugger row: %r' % (t.indicator(),), t)
    # continue to the end: the output of the program and the exit code
    t.menu('M-r', 'Continue', exact=True)
    check(t.wait_for('Program exited with', 30) and 'exitcode = 0' in t.text(), 'Continue runs to the end: "Program exited with exitcode = 0"', t)
    check('done' in t.text(), 'the output of the program is shown', t)
    t.key('Enter')
    check(t.wait_gone('Program exited', 3) and t.alive(), 'the IDE is back in control after the program ends', t)
    t.key('M-r'); t.pump(0.4)
    names = [r[1] for r in t._menu_rows()]
    t.key('Escape')
    check(names and names[0].startswith('Run'), 'the first Run item is Run again after the end: %r' % (names[:1],), t)
    close_all(t)


def section_unicode(t):
    new_file(t)
    t.type('Привет, мир! ünï 日本語 ─│┌')
    t.key('Enter')
    t.type('abc')
    t.pump(0.5)
    check(t.wait_for('Привет, мир!'), 'Cyrillic is typed and shown', t)
    check('ünï' in t.text(), 'Latin accents are shown', t)
    check('日本語' in t.text(), 'CJK is shown', t)
    check('─│┌' in t.text(), 'box drawing characters typed by the user are shown', t)
    check(editor_lines(t)[1] == 'abc', 'the line after Enter starts with its first typed character: %r' % editor_lines(t)[1], t)
    t.key('F2'); t.wait_for('Save File As'); t.type('u.pas'); t.key('Enter'); t.pump(1)
    data = open(os.path.join(t.work, 'u.pas'), 'rb').read()
    check(data == 'Привет, мир! ünï 日本語 ─│┌\nabc'.encode('utf-8'), 'the file is saved as UTF-8: %r' % data[:50], t)
    # cursor movement by characters; the hardware cursor counts the cells (a CJK character is two)
    t.key('C-PPage', 'Right', 'Right', 'Right')
    check(t.indicator() == (1, 4), 'three Right keys: column 4 (%r)' % (t.indicator(),), t)
    check(t.cursor() == (2, 4), 'the cursor is after three Cyrillic letters (%r)' % (t.cursor(),), t)
    for _ in range(13):
        t.key('Right')
    # columns: Привет,_мир!_ünï_ = 16 characters, then 日本語
    t.key('Right')
    check(t.indicator() == (1, 18), 'column 18 is in front of the first CJK character? (%r)' % (t.indicator(),), t)
    t.key('Right', 'Right')
    c = t.cursor()
    check(c[1] == 1 + 17 + 4, 'after two CJK characters the cursor is 4 cells on: %r' % (c,), t)
    t.key('End')
    check(t.indicator() == (1, 25), 'End: after the last character (%r)' % (t.indicator(),), t)
    t.key('BSpace')
    check('─│' in t.text() and '─│┌' not in t.text(), 'Backspace removes one character (not one byte)', t)

    # Delete on a multi-byte character, overwrite mode
    t.key('Home', 'Delete')
    check(editor_lines(t)[0].startswith('ривет'), 'Delete removes the whole first character: %r' % editor_lines(t)[0][:8], t)
    t.type('П')
    check(editor_lines(t)[0].startswith('Привет'), 'a typed Cyrillic capital goes in: %r' % editor_lines(t)[0][:8], t)
    t.key('Insert')           # overwrite mode
    t.type('Ж')
    check(editor_lines(t)[0].startswith('Жривет') or editor_lines(t)[0].startswith('ПЖивет') or editor_lines(t)[0].startswith('ПЖривет') is False,
          'overwrite replaces a character: %r' % editor_lines(t)[0][:8], t)
    t.key('Insert')
    t.key('Home')

    # word moves over Cyrillic
    t.key('C-Home')
    t.key('C-Right')
    ind = t.indicator()
    check(ind is not None and ind[1] > 1, 'Ctrl+Right moves over a Cyrillic word (%r)' % (ind,), t)

    # selection, copy and paste of UTF-8 text
    t.key('C-PPage', 'Down', 'End')      # end of line 2 ("abc")
    t.key('C-PPage')
    t.key('S-End')
    menu(t, 'M-e', 'Copy', exact=True)
    t.key('C-NPage', 'Enter')
    menu(t, 'M-e', 'Paste', exact=True)
    lines = editor_lines(t)
    check(len(lines) >= 3 and lines[2] == lines[0], 'the first line copied and pasted keeps all its characters: %r' % lines[:4], t)

    # search: case-insensitive for Cyrillic; replace with a Cyrillic text
    t.key('C-PPage')
    menu(t, 'M-s', 'Find', exact=True)
    t.wait_for('Text to find')
    t.type('ЖИВЕТ')
    t.key('Enter')
    check(t.wait_gone('Text to find') and t.wait_until(lambda: t.indicator() == (1, 7)), 'the search is case-insensitive for Cyrillic: %r' % (t.indicator(),), t)
    t.key('C-PPage')
    menu(t, 'M-s', 'Replace')
    t.wait_for('New text')
    t.type('мир')
    t.key('Tab')
    t.type('дом')
    t.key('Tab', 'Tab', 'Tab', 'Tab', 'Tab', 'Tab')
    t.key('Enter')
    for _ in range(4):
        if t.wait_for('Replace this occurrence', 2):
            t.key('y')
            t.pump(0.3)
    check('дом' in '\n'.join(editor_lines(t)), 'a Cyrillic word is replaced by another: %r' % editor_lines(t)[:3], t)

    # undo of typed unicode
    new_file(t)
    t.type('жук')
    menu(t, 'M-e', 'Undo')
    check(editor_lines(t)[0] != 'жук', 'undo takes the typed text back: %r' % editor_lines(t)[0], t)
    menu(t, 'M-e', 'Redo')
    check(editor_lines(t)[0] == 'жук', 'redo puts it back: %r' % editor_lines(t)[0], t)

    # reopen
    close_all(t)
    t.key('F3'); t.wait_for('Open a file'); t.type('u.pas'); t.key('Enter')
    check(t.wait_for('Привет, мир!'), 'the saved file is read back as UTF-8', t)


def line_colors(t, n=8):
    """the background colour of the first n lines of the program text on screen (the debugger row and a breakpoint
    row stand out); the window is found by its first line, wherever it is"""
    for top, l in enumerate(t.lines()):
        if 'program dbgt;' in l:
            return t.row_backgrounds(l.index('program dbgt;') + 2)[top:top + n]
    return [None] * n


def section_templates(t):
    """File > New from template (the .pt files next to the executable) and Tools > Grep (an external grep over the sources)"""
    menu(t, 'M-f', 'New from template')
    check(t.wait_for('Available templates', 5), 'File > New from template lists the templates', t)
    txt = t.text()
    check(all(n in txt for n in ('Gplprog', 'Gplunit', 'Program', 'Unit')), 'all four templates are there', t)
    t.key('Enter')
    check(t.wait_for('Fill in template parameter', 5), 'a template asks for its parameters', t)
    for _ in range(8):
        if not t.wait_for('Fill in template parameter', 1):
            break
        t.key('Enter')
        t.pump(0.3)
    check('program' in t.text().lower() and 'BEGIN' in t.text(), 'the template becomes a new source: %r' % editor_lines(t)[:2], t)
    close_all(t)

    with open(os.path.join(t.work, 'a.pas'), 'w') as f:
        f.write('program a;\nbegin\n  writeln(1);\nend.\n')
    with open(os.path.join(t.work, 'b.pas'), 'w') as f:
        f.write('unit b;\ninterface\nimplementation\nend.\n')
    t.menu('M-t', 'Grep', exact=True)
    check(t.wait_for('Grep arguments', 5), 'Tools > Grep asks for the arguments', t)
    t.key('End'); t.key(*['BSpace'] * 30); t.type('writeln'); t.key('Enter')
    check(t.wait_for('a.pas(3)', 8) and 'b.pas' not in t.text().split('Messages')[-1], 'grep lists the line that matches (and only that file)', t)


def section_clipboard(t):
    """the clipboard: a paste after a two-byte last character, one Cut/Copy/Paste in the menu, the system clipboard (OSC 52) on Copy"""

    # a selection that ends at the end of a line with a multi-byte last character: Paste appends, nothing is split
    new_file(t)
    t.type('Привет мир')
    t.key('Home', 'Right', 'Right', 'Right', 'S-End')
    menu(t, 'M-e', 'Copy', exact=True)
    t.key('End')
    menu(t, 'M-e', 'Paste', exact=True)
    check(editor_lines(t)[0] == 'Привет мирвет мир', 'a paste after the last character (two bytes) keeps it whole: %r' % editor_lines(t)[0], t)

    # one clipboard in the menu: no second pair of "to System / from System" items
    t.key('M-e')
    check('to System' not in t.text() and 'from System' not in t.text(), 'Edit has Cut/Copy/Paste only (no system-clipboard duplicates)', t)
    t.key('Escape', 'Escape')

    # the terminal's own clipboard (OSC 52) gets what Copy copies
    subprocess.call(['tmux', 'set-option', '-g', 'set-clipboard', 'on'])
    t.key('Home', 'S-End')
    menu(t, 'M-e', 'Copy', exact=True)
    t.pump(0.5)
    buf = subprocess.run(['tmux', 'show-buffer'], capture_output=True, text=True).stdout
    check(buf == 'Привет мирвет мир', 'Edit > Copy sets the system clipboard (OSC 52): %r' % buf, t)


def section_syscb(t):
    """the system clipboard through a program (a fake xsel on PATH, as tvision does): Copy writes it, a change made by
    another program is what Paste takes, a bracketed paste is inserted as it is in one undo step"""
    import os, stat
    d = os.path.join(t.work, 'bin')
    os.makedirs(d, exist_ok=True)
    store = os.path.join(t.work, 'clip.txt')
    with open(os.path.join(d, 'xsel'), 'w') as f:
        f.write('#!/bin/sh\ncase "$*" in *--input*) cat > %s;; *--output*) cat %s 2>/dev/null;; esac\n' % (store, store))
    os.chmod(os.path.join(d, 'xsel'), 0o755)
    t2 = TmuxTerm(t.binary, env={'TV_FAR2L': '0', 'PATH': d + ':/usr/local/bin:/usr/bin:/bin', 'DISPLAY': ':99'})
    try:
        t2.wait_for('Window  Help')
        new_file(t2)
        t2.type('Привет')
        t2.key('Home', 'S-End')
        menu(t2, 'M-e', 'Copy', exact=True)
        t2.pump(0.5)
        got = open(store, encoding='utf-8').read() if os.path.exists(store) else None
        check(got == 'Привет', 'Edit > Copy writes the system clipboard through xsel: %r' % got, t2)
        # another program changes the clipboard: Paste takes that
        with open(store, 'w', encoding='utf-8') as f:
            f.write('снаружи\nвторая')
        t2.key('C-NPage', 'Enter')
        menu(t2, 'M-e', 'Paste', exact=True)
        check(t2.wait_until(lambda: editor_lines(t2)[1:3] == ['снаружи', 'вторая'], 4),
              'Edit > Paste takes what another program put on the system clipboard: %r' % editor_lines(t2)[:4], t2)
        # no change since: Paste takes the clipboard window (the same text again)
        t2.key('C-NPage', 'Enter')
        menu(t2, 'M-e', 'Paste', exact=True)
        check('\n'.join(editor_lines(t2)).count('снаружи') == 2, 'a second Paste inserts it again: %r' % editor_lines(t2)[:6], t2)
        # the terminal pastes (bracketed paste): as it is, no auto indent, one undo step
        t2.key('C-NPage', 'Enter')
        t2.paste('  begin\n      x := 1;\n\tend;')
        lines = editor_lines(t2)
        i = lines.index('  begin') if '  begin' in lines else -1
        check(i >= 0 and lines[i + 1] == '      x := 1;' and lines[i + 2].strip() == 'end;' and lines[i + 2].startswith(' '),
              'a bracketed paste is inserted as it is (no auto indent): %r' % lines[:8], t2)
        menu(t2, 'M-e', 'Undo', exact=True)
        lines = editor_lines(t2)
        check('  begin' not in lines and not any('x := 1' in l or 'end;' in l for l in lines[5:]),
              'Undo takes the whole paste back in one step: %r' % lines[:8], t2)
    finally:
        t2.close()


def section_debug(t):
    """the debugger: a breakpoint, Run stops on it (gdb runs the program), the call stack, stepping, a watch, Continue to the end"""
    new_file(t)
    type_lines(t, 'program dbgt;', 'var i,s: integer;', 'begin', 's:=0;', 'for i:=1 to 3 do', 's:=s+i;', 'writeln(s);', 'end.')
    t.key('F2'); t.wait_for('Save File As'); t.type('dbgt.pas'); t.key('Enter'); t.pump(0.8)
    t.key('C-Home', 'Down', 'Down', 'Down', 'Down', 'Down', 'Home')
    check(t.wait_until(lambda: t.indicator() == (6, 1)), 'the cursor is on the line to stop at: %r' % (t.indicator(),), t)
    menu(t, 'M-d', 'Breakpoint')
    menu(t, 'M-d', 'Breakpoint List')
    check(t.wait_for('Breakpoint list', 3) and 'dbgt.pas' in t.text(), 'Debug > Breakpoint adds a breakpoint to the list', t)
    t.key('Escape'); t.pump(0.3)             # closes the breakpoint list window
    plain = line_colors(t)                   # line 6 is painted as a breakpoint now
    # Run builds with symbols and starts gdb; the program stops at the breakpoint
    t.menu('M-r', 'Run', exact=True)
    check(t.wait_until(lambda: line_colors(t)[5] != plain[5], 45), 'Run stops at the breakpoint: line 6 is painted as the debugger row', t)
    shown = False
    for _ in range(3):                       # the IDE may still be busy with the stop: ask again
        close_dialogs(t, 1)
        menu(t, 'M-d', 'Call stack')
        shown = t.wait_for('dbgt.pas(6) main()', 4)
        if shown:
            break
    check(shown, 'Debug > Call stack shows main() on line 6', t)
    t.key('Escape'); t.pump(0.3)
    # Step over executes the line: s becomes 1
    t.key('F8')
    check(t.wait_until(lambda: line_colors(t)[5] == plain[5] and line_colors(t)[4] != plain[4], 10), 'F8 moves the debugger row off the breakpoint line (to line 5, the loop)', t)
    menu(t, 'M-d', 'Add Watch')
    t.wait_for('Expression to watch')
    t.type('s'); t.key('Enter'); t.pump(0.8)
    menu(t, 'M-d', 'Watches')
    check(t.wait_for('s = 1', 5), 'the watch shows s = 1 after the first step', t)
    t.key('Escape'); t.pump(0.3)
    # Continue until the program ends
    for _ in range(6):
        if 'Program exited' in t.text():
            break
        t.menu('M-r', 'Continue', exact=True)
        t.pump(1.5)
    check(t.wait_for('Program exited with', 8) and 'exitcode = 0' in t.text(), 'Run/Continue lets the program finish: "Program exited with exitcode = 0"', t)
    t.key('Enter')
    check(t.wait_gone('Program exited', 3) and t.alive(), 'the IDE is back in control after the program ends', t)

    # a program that reads: it runs on a terminal of its own, which the IDE relays (the keys reach it, nothing
    # of gdb is printed over the screen)
    close_all(t)
    new_file(t)
    type_lines(t, 'program rd;', 'var s: string;', 'begin', "write('name? ');", 'readln(s);', "writeln('hello ', s);", 'end.')
    t.key('F2'); t.wait_for('Save File As'); t.type('rd.pas'); t.key('Enter'); t.pump(0.8)
    t.key('C-Home', 'Down', 'Down', 'Down', 'Down', 'Down', 'Home')
    menu(t, 'M-d', 'Breakpoint')
    t.menu('M-r', 'Run', exact=True)
    check(t.wait_until(lambda: 'GDB Version' in t.text() and 'name?' in t.text(), 45), 'a debugged program shows its output on the user screen', t)
    check('controlling terminal' not in t.text() and 'GDB:' not in t.text().replace('GDB Version', ''),
          'no gdb warning is printed on the user screen', t)
    t.type('abc')
    check(t.wait_for('name? abc', 5), 'the typed text is echoed on the user screen (the keys are relayed)', t); t.key('Enter')
    check(t.wait_for('Window  Help', 10) and t.wait_until(lambda: t.indicator() == (6, 1), 10),
          'the typed line reaches the program; it runs on to the breakpoint and the IDE returns: %r' % (t.indicator(),), t)

    # the program is stopped on the breakpoint: Run offers Continue; Program reset kills it and Run is Run again
    t.key('M-r'); t.pump(0.4)
    names = [r[1] for r in t._menu_rows()]
    t.key('Escape')
    check(names and names[0].startswith('Continue'), 'while the program is stopped the first Run item is Continue: %r' % (names[:1],), t)
    menu(t, 'M-r', 'Program reset')
    t.pump(1)
    t.key('M-r'); t.pump(0.4)
    names = [r[1] for r in t._menu_rows()]
    t.key('Escape')
    check(names and names[0].startswith('Run'), 'after Program reset it is Run again: %r' % (names[:1],), t)


SHAPES = """unit shapes;
interface
type
  TColor = (clRed, clGreen, clBlue);
  TShape = class
  private
    FName: string;
  public
    constructor Create(const AName: string);
    procedure Draw; virtual;
    function Area: double; virtual;
  end;
  TCircle = class(TShape)
    R: double;
    function Area: double; override;
  end;
const
  Pi2 = 6.28;
var
  Count: integer;
procedure Reset(var n: integer; const s: string);
implementation
constructor TShape.Create(const AName: string); begin FName:=AName end;
procedure TShape.Draw; begin end;
function TShape.Area: double; begin Result:=0 end;
function TCircle.Area: double; begin Result:=3.14*R*R end;
procedure Reset(var n: integer; const s: string); begin n:=0 end;
end.
"""
USESHP = """program useshp;
uses shapes;
var c: TCircle;
begin
  c:=TCircle.Create('c');
  writeln(c.Area:0:2);
end.
"""


def section_browser(t):
    """Search > Objects / Modules / Globals / Symbol: the symbol browser, fed from the sources (the compiler is external)"""
    for name, text in (('shapes.pas', SHAPES), ('useshp.pas', USESHP)):
        with open(os.path.join(t.work, name), 'w') as f:
            f.write(text)
    t.key('F3'); t.wait_for('Open a file'); t.type('useshp.pas'); t.key('Enter')
    check(t.wait_for('program useshp'), 'the program is opened', t)
    menu(t, 'M-s', 'Objects')
    check(t.wait_for('Browse: Objects', 5), 'Search > Objects opens the class browser', t)
    txt = t.text()
    check('TShape' in txt and 'TCircle' in txt, 'both classes are listed', t)
    lines = t.lines()
    ti = next((i for i, l in enumerate(lines) if '└──TShape' in l), None)
    ci = next((i for i, l in enumerate(lines) if '└──TCircle' in l), None)
    check(ti is not None and ci is not None and ci == ti + 1 and lines[ci].index('└──TCircle') > lines[ti].index('└──TShape'),
          'TCircle is a descendant of TShape in the tree', t)
    t.key('Escape'); t.pump(0.3)
    menu(t, 'M-s', 'Modules')
    check(t.wait_for('Browse: Units', 5) and 'shapes' in t.text() and 'useshp' in t.text(), 'Search > Modules lists the units', t)
    t.key('Escape'); t.pump(0.3)
    menu(t, 'M-s', 'Globals')
    check(t.wait_for('Browse: Globals', 5), 'Search > Globals opens', t)
    txt = t.text()
    check('Pi2 = 6.28' in txt and 'Count: Integer' in txt and 'Reset(var n: Integer' in txt
          and 'clGreen' in txt, 'constants, variables, procedures with their parameters and enumeration items are there', t)
    t.key('Escape'); t.pump(0.3)
    menu(t, 'M-s', 'Symbol')
    t.wait_for('Enter symbol')
    t.key('End'); t.key(*['BSpace'] * 30); t.type('TShape'); t.key('Enter')
    check(t.wait_for('Browse: TShape', 5) or t.wait_for('TShape', 5), 'Search > Symbol shows a class', t)
    txt = t.text()
    check('Draw' in txt and 'Area' in txt, 'the members of the class are listed', t)


def section_longlines(t):
    """a line longer than 255 bytes is kept whole (the editor, tve, has no limit on the length of a line; only the parts of the IDE that
    take a line as a short string see its first 255 bytes): the file opens without a warning and is saved back byte for byte"""
    path = os.path.join(t.work, 'long.txt')
    text = 'x' * 300 + '\nsecond\n' + '\u0436' * 200 + '\n'
    with open(path, 'w', encoding='utf-8') as f:
        f.write(text)
    t.key('F3'); t.wait_for('Open a file'); t.type('long.txt'); t.key('Enter')
    check(t.wait_for('long.txt', 5), 'the file is opened', t)
    check(not t.wait_for('had too long lines', 1), 'and there is no warning about long lines', t)
    t.key('C-PPage')
    t.type('Q')
    t.key('F2')
    t.pump(1)
    data = open(path, 'rb').read()
    check(data == ('Q' + text).encode('utf-8'), 'the saved file has all the text, nothing was split or cut: %d bytes' % len(data), t)


def section_misc(t):
    """the rest of the menus: Compile (Build, Target, Primary file), Run (Parameters, Run Directory), File (Save all, Reload,
    Command shell), Options > Save, Help, Window (Hide, Close, List)"""
    w = t.work
    with open(os.path.join(w, 'prim.pas'), 'w') as f:
        f.write("program prim;\nuses SysUtils;\nbegin\n  writeln('arg=', paramstr(1));\n  writeln('dir=', GetCurrentDir);\nend.\n")
    with open(os.path.join(w, 'other.pas'), 'w') as f:
        f.write("program other;\nbegin\nend.\n")

    # Compile > Target shows the platform of this system
    menu(t, 'M-c', 'Target')
    check(t.wait_for('Target', 4) and 'Linux' in t.text(), 'Compile > Target... lists the targets (Linux among them)', t)
    close_dialogs(t, 2)

    # Primary file: Make builds that one whatever window is current
    t.key('F3'); t.wait_for('Open a file'); t.type('other.pas'); t.key('Enter')
    t.wait_for('program other')
    menu(t, 'M-c', 'Primary file')
    check(t.wait_for('Primary file', 4), 'Compile > Primary file... opens', t)
    t.type('prim.pas'); t.key('Enter')
    t.pump(0.6)
    t.key('F9')
    check(t.wait_for('Compile successful', 30), 'Make with a primary file compiles it', t)
    t.key('Enter')
    check(os.path.exists(os.path.join(w, 'prim')) and not os.path.exists(os.path.join(w, 'other')),
          'the primary file was built, the current one was not', t)
    menu(t, 'M-c', 'Clear primary file')
    t.pump(0.5)
    # Build (everything again) of the current file
    menu(t, 'M-c', 'Build')
    check(t.wait_for('Compile successful', 30), 'Compile > Build compiles the current file', t)
    t.key('Enter')
    check(os.path.exists(os.path.join(w, 'other')), 'and the executable of the current file exists', t)

    # Run > Parameters and Run Directory: the program sees both
    t.key('F3'); t.wait_for('Open a file'); t.type('prim.pas'); t.key('Enter')
    t.wait_for('program prim')
    menu(t, 'M-r', 'Parameters')
    check(t.wait_for('Program parameters', 4), 'Run > Parameters... opens', t)
    t.key('End'); t.key(*['BSpace'] * 30); t.type('hello'); t.key('Enter')
    t.pump(0.5)
    menu(t, 'M-r', 'Run Directory')
    check(t.wait_for('Directory', 4), 'Run > Run Directory... opens', t)
    t.key('End'); t.key(*['BSpace'] * 60); t.type('/tmp'); t.key('Enter')
    t.pump(0.5)
    t.key('C-F9')
    check(t.wait_until(lambda: 'Press any key' in t.text() or 'Program exited' in t.text(), 25), 'the program runs', t)
    if 'Program exited' in t.text():        # with breakpoints in the list the debugger runs it: the output is on the user screen
        t.key('Enter')
        t.pump(0.5)
        t.key('M-F5')
        t.pump(1)
    t.wait_until(lambda: 'arg=hello' in t.text(), 8)      # the user screen is drawn a moment after the key
    txt = t.text()
    check('arg=hello' in txt, 'it got the parameter', t)
    check('dir=/tmp' in txt, 'and ran in the chosen directory', t)
    t.key('Enter')
    t.wait_for('F9 Make')

    # File > Save all saves every modified window; Reload takes the file from disk again
    t.type('{x}')
    new_file(t)
    t.type('{y}')
    t.key('F2'); t.wait_for('Save File As'); t.type('extra.pas'); t.key('Enter'); t.pump(0.6)
    menu(t, 'M-w', 'Next')
    t.pump(0.3)
    menu(t, 'M-f', 'Save all')
    t.pump(1)
    check('{x}' in open(os.path.join(w, 'prim.pas')).read(), 'File > Save all saved the modified window', t)
    for name in ('prim.pas', 'other.pas'):          # whichever window is the current one
        with open(os.path.join(w, name), 'a') as f:
            f.write('{ changed on disk }\n')
    menu(t, 'M-f', 'Reload')
    t.pump(1)
    for _ in range(4):                      # "modified by another program: reload?" for each window; Yes
        if t.wait_for('Reload new version', 1.5) or t.wait_for('Yes', 0.5):
            t.key('y')
            t.pump(0.4)
    check(t.wait_for('changed on disk', 5), 'File > Reload reads the file again', t)

    # File > Command shell: a real shell on the user screen, EXIT comes back
    menu(t, 'M-f', 'Command shell')
    check(t.wait_for('Type EXIT to return', 8), 'File > Command shell shows the shell', t)
    t.type('echo shell' + 'ok'); t.key('Enter')
    check(t.wait_for('shellok', 5), 'the shell works', t)
    t.type('exit'); t.key('Enter')
    check(t.wait_for('F9 Make', 8) and t.alive(), 'EXIT returns to the IDE', t)

    for _ in range(3):                      # a window that changed on disk asks again when it gets the focus: No
        if t.wait_for('Reload new version', 1):
            t.key('n')
            t.pump(0.4)

    # Options > Save writes the settings
    for name in ('fp.ini',):
        if os.path.exists(os.path.join(w, name)):
            os.remove(os.path.join(w, name))
    menu(t, 'M-o', 'Save', exact=False)
    t.pump(1)
    check(os.path.exists(os.path.join(w, 'fp.ini')), 'Options > Save writes fp.ini', t)

    # Help: the help files are not installed (as in the original): the IDE says so; Help > Files... lets add some
    menu(t, 'M-h', 'Contents')
    check(t.wait_for('CHM help', 5), 'Help > Contents explains that the help files are not installed', t)
    close_dialogs(t, 2)
    menu(t, 'M-h', 'Files')
    check(t.wait_for('Install Help Files', 4), 'Help > Files... opens the list of help files', t)
    close_dialogs(t, 2)

    # Window > Hide, List, Close
    menu(t, 'M-w', 'Hide')
    t.pump(0.4)
    menu(t, 'M-w', 'List')
    check(t.wait_for('Window list', 4) or t.wait_for('prim.pas', 4), 'Window > List shows the windows (also the hidden one)', t)
    close_dialogs(t, 2)
    menu(t, 'M-w', 'Close', exact=True)
    t.pump(0.5)
    check(t.alive(), 'Window > Close closes the current window', t)


def test_exit(fp):
    """File > Exit (Alt+X) on a clean desktop ends the IDE with status 0"""
    t = TmuxTerm(fp, env={'TV_FAR2L': '0'})
    try:
        t.wait_for('Window  Help')
        t.key('M-x')
        check(t.wait_until(lambda: not t.alive(), 6) and 'EXIT=0' in t.stderr(), 'Alt+X leaves the IDE with exit status 0 (%r)' % t.stderr()[-20:], t)
    finally:
        t.close()


def section_mouse(t):
    """the mouse (SGR reports, as a terminal sends them): the menu bar, the cursor, a selection by dragging, the wheel,
    the status line, the close box, activating a window"""
    subprocess.call(['tmux', 'set-option', '-g', 'set-clipboard', 'on'])
    # menu bar: click File, click New
    t.click(3, 0)
    check(t.wait_for('New from template', 3), 'a click on File opens the menu', t)
    rows = t._menu_rows()
    new_row = next(r[0] for r in rows if r[1].startswith('New') and not r[1].startswith('New from'))
    before = t.text().count('noname')
    t.click(6, new_row)
    check(t.wait_until(lambda: t.text().count('noname') > before, 3), 'a click on New opens a window', t)
    type_lines(t, *['line %d some words here' % i for i in range(1, 61)])
    t.key('C-PPage')
    # the cursor goes where the click is (the text starts in the column after the frame, line 1 on the screen row 2)
    t.click(1 + 7, 2)
    check(t.wait_until(lambda: t.indicator() == (1, 8)), 'a click puts the cursor on that character: %r' % (t.indicator(),), t)
    # a drag selects: "some words" is columns 8..17 of the first line
    t.drag(1 + 7, 2, 1 + 17, 2)
    menu(t, 'M-e', 'Copy', exact=True)
    t.pump(0.5)
    buf = subprocess.run(['tmux', 'show-buffer'], capture_output=True, text=True).stdout
    check(buf == 'some words', 'a drag selects text: %r' % buf, t)
    # the wheel scrolls the view
    first = editor_lines(t)[0]
    for _ in range(3):
        t.click(40, 10, button=65)
    check(t.wait_until(lambda: editor_lines(t)[0] != first, 3), 'the wheel scrolls down: %r -> %r' % (first, editor_lines(t)[0]), t)
    t.click(40, 10, button=64)
    # the status line: a click on "F3 Open" opens the file dialog
    last = t.lines()[-1]
    x = last.find('F3 Open')
    t.click(x + 2, len(t.lines()) - 1)
    check(t.wait_for('Open a file', 3), 'a click on F3 Open in the status line opens the dialog', t)
    t.key('Escape')
    t.pump(0.3)
    # the close box of an unmodified window
    close_all(t)
    new_file(t)
    t.pump(0.3)
    n = t.text().count('noname')
    t.click(3, 1)
    check(t.wait_until(lambda: t.text().count('noname') < n, 3), 'a click on the close box closes the window', t)
    # two windows tiled: a click in the other one makes it the active one (the one with the double frame)
    def active_title():
        for l in t.lines():
            m = re.search(r'╔═\[■\][═ ]*([\w.]+)', l)
            if m:
                return m.group(1)
        return None
    new_file(t)
    t.type('first')
    new_file(t)
    t.type('second')
    menu(t, 'M-w', 'Tile')
    t.pump(0.6)
    before = active_title()
    lines = t.lines()
    row = next(i for i, l in enumerate(lines) if 'first' in l and '[■]' not in l)
    t.click(lines[row].index('first') + 2, row)
    t.pump(0.4)
    after = active_title()
    check(before is not None and after is not None and before != after,
          'a click in the other window activates it: %r -> %r' % (before, after), t)


def section_ux(t):
    """the navigation guidelines of vtui (tv3/docs/UX-CONFORMANCE.md): Esc in menus, radio groups, Ctrl+Tab"""
    # a menu: Esc closes the drop-down and keeps the bar, the second Esc leaves the bar
    t.key('M-f')
    check(t.wait_for('Open...'), 'Alt+F opens the File menu', t)
    t.key('Escape')
    check(t.wait_gone('Open...', 2), 'Esc closes the drop-down', t)
    t.key('Down')
    check(t.wait_for('Open...'), '... the menu bar stays active: Down opens the menu again', t)
    t.key('Right')
    check(t.wait_for('Undo') and t.wait_gone('Open...', 2), 'Right in the active menu bar opens the next drop-down (Edit)', t)
    t.key('Escape', 'Escape')
    t.key('Down')
    check(t.wait_gone('Undo', 2), 'the second Esc leaves the menu bar (Down does not open a menu any more)', t)
    # a radio group: the arrow keys move the cursor, Space selects
    new_file(t)
    check(menu(t, 'M-s', 'Find'), 'Search > Find...')
    check(t.wait_for('Case sensitive'), 'the Find dialog is open', t)
    t.key('Tab', 'Tab', 'Tab', 'Down')
    txt = t.text()
    check('(\u2022) Global' in txt and '( ) Selected text' in txt, 'Down moves the cursor of the Scope group, the selection stays on Global', t)
    t.key('Space')
    txt = t.text()
    check('(\u2022) Selected text' in txt and '( ) Global' in txt, 'Space selects the radio button under the cursor', t)
    close_dialogs(t)
    # Esc closes a dialog
    check(menu(t, 'M-s', 'Find'), 'Search > Find... again')
    check(t.wait_for('Case sensitive'), 'the Find dialog is open again', t)
    t.key('Escape')
    check(t.wait_gone('Case sensitive', 2), 'Esc closes the dialog', t)
    # Ctrl+Tab and Ctrl+Shift+Tab walk through the windows
    new_file(t); t.type('aaa')
    new_file(t); t.type('bbb')
    check(editor_lines(t)[:1] == ['bbb'], 'two windows: the second is active', t)
    t.key('C-Tab')
    t.pump(0.4)
    check(editor_lines(t)[:1] != ['bbb'], 'Ctrl+Tab goes to another window: %r' % editor_lines(t)[:1], t)
    t._tmux('send-keys', '-t', t.session, '-H', *['%02x' % b for b in b'\x1b[9;6u'])
    t.pump(0.4)
    check(editor_lines(t)[:1] == ['bbb'], 'Ctrl+Shift+Tab goes back: %r' % editor_lines(t)[:1], t)
    # F1 in a modal dialog opens the help above it (rule D.3); Esc closes the help and the dialog is still there
    check(menu(t, 'M-s', 'Find'), 'Search > Find... for F1')
    check(t.wait_for('Case sensitive'), 'the Find dialog is open for F1', t)
    t.key('F1')
    check(t.wait_for('Esc Close help', 4), 'F1 in a modal dialog opens the help window above it', t)
    t.key('Escape')
    check(t.wait_gone('Esc Close help', 3) and 'Case sensitive' in t.text(), 'Esc closes the help and the dialog is still there', t)
    t.key('Escape')
    check(t.wait_gone('Case sensitive', 2), 'and Esc closes the dialog', t)
    # R.1: the actions are declared once; no key is on two actions
    out = subprocess.run([t.binary, '--list-actions'], capture_output=True, text=True, timeout=20).stdout
    rows = [l.split('\t') for l in out.split('conflicts:')[0].split('\n') if l]
    byname = dict((r[0], r) for r in rows if len(r) == 3)
    check(len(rows) > 80, 'the action table has the menu items of the IDE (%d)' % len(rows))
    check(byname.get('file.open', ['', '', ''])[1] == 'F3' and byname.get('compile.make', ['', '', ''])[1] == 'F9', 'file.open is F3, compile.make is F9')
    check(out.split('conflicts:')[1].strip() == '', 'no key is on two actions: %r' % out.split('conflicts:')[1][:80])


def section_paths(t):
    """no DOS / Windows paths on Unix: the screens carry no drive letter, UNC name or backslash, the source has no new
    hand-spelled separator (tools/check-paths.py), names keep their case"""
    here = os.path.dirname(os.path.abspath(__file__))
    r = subprocess.run([sys.executable, os.path.join(here, '..', '..', 'tools', 'check-paths.py')], capture_output=True, text=True)
    check(r.returncode == 0, 'tools/check-paths.py: %s' % r.stdout.strip().split('\n')[-1])
    bad = re.compile(r'(?<![A-Za-z0-9])[A-Za-z]:\\|\\\\|\\')

    def scan(label):
        txt = t.text()
        hits = [l.strip() for l in txt.split('\n') if bad.search(l)]
        check(not hits, 'no drive letter, UNC name or backslash on the screen %s: %r' % (label, hits[:2]), t)

    with open(os.path.join(t.work, 'bad.pas'), 'w') as f:
        f.write("program bad;\nbegin\n  a := b;\nend.\n")
    open(os.path.join(t.work, 'Foo.pas'), 'w').write("program foo1;\nbegin end.\n")
    open(os.path.join(t.work, 'foo.pas'), 'w').write("program foo2;\nbegin end.\n")
    menu(t, 'M-o', 'Directories'); t.wait_for('Unit directories'); scan('Options > Directories'); close_dialogs(t, 2)
    t.key('F3'); t.wait_for('Open a file'); scan('Open a file')
    check(t.work + '/' in t.text() or t.work in t.text(), 'the Open dialog shows the directory with slashes', t)
    close_dialogs(t, 2)
    menu(t, 'M-f', 'Change dir'); t.wait_for('Change Directory'); scan('Change Directory'); close_dialogs(t, 2)
    menu(t, 'M-o', 'Tools'); t.wait_for('Program titles'); scan('Options > Tools'); close_dialogs(t, 2)
    menu(t, 'M-r', 'Parameters'); t.pump(0.6); scan('Run > Parameters'); close_dialogs(t, 2)
    # the case of a name is kept: Foo.pas and foo.pas are two files and two windows
    for n in ('Foo.pas', 'foo.pas'):
        t.key('F3'); t.wait_for('Open a file'); t.type(n); t.key('Enter'); t.pump(0.6)
    menu(t, 'M-w', 'List'); t.wait_for('Windows'); txt = t.text()
    check('Foo.pas' in txt and 'foo.pas' in txt, 'Foo.pas and foo.pas are two windows in the Window list', t)
    scan('Window list'); close_dialogs(t, 2)
    # the compiler messages
    t.key('F3'); t.wait_for('Open a file'); t.type('bad.pas'); t.key('Enter'); t.pump(0.5)
    t.key('M-F9')
    check(t.wait_for('Compile failed', 30), 'a failed compile for the messages', t)
    t.key('Enter'); t.wait_for('Compiler Messages', 5); scan('Compiler Messages')
    menu(t, 'M-t', 'Messages'); t.pump(0.6); scan('Tools > Messages')
    # a mixed-case program name is built and the executable keeps the case
    open(os.path.join(t.work, 'MixedCase.pas'), 'w').write("program MixedCase;\nbegin writeln('hi') end.\n")
    t.key('F3'); t.wait_for('Open a file'); t.type('MixedCase.pas'); t.key('Enter'); t.pump(0.5)
    t.key('F9')
    check(t.wait_for('Compile successful', 30), 'MixedCase.pas is built', t)
    t.key('Enter')
    check(os.path.exists(os.path.join(t.work, 'MixedCase')) and not os.path.exists(os.path.join(t.work, 'mixedcase')),
          'the executable is MixedCase, not mixedcase: %r' % [n for n in os.listdir(t.work) if n.lower().startswith('mixedcase')])


# Delve is installed in ~/go/bin by go install; the IDE runs with another HOME, so the directory goes on the PATH it inherits
_gobin = os.path.expanduser('~/go/bin')
if os.path.exists(os.path.join(_gobin, 'dlv')):
    os.environ['PATH'] = _gobin + os.pathsep + os.environ.get('PATH', '')

SECTIONS = [('edit', section_edit), ('search', section_search), ('window', section_window), ('tools', section_tools),
            ('options', section_options), ('files', section_files), ('compile', section_compile), ('golang', section_golang),
            ('unicode', section_unicode), ('templates', section_templates), ('clipboard', section_clipboard), ('syscb', section_syscb), ('debug', section_debug), ('debuggo', section_debuggo), ('browser', section_browser), ('longlines', section_longlines), ('misc', section_misc), ('mouse', section_mouse), ('ux', section_ux), ('paths', section_paths)]

if __name__ == '__main__':
    run(sys.argv[1], sys.argv[2:])
    if not sys.argv[2:] or 'exit' in sys.argv[2:]:
        test_exit(sys.argv[1])
    print('%d checks, %d failed' % (count, fails))
    sys.exit(1 if fails else 0)
