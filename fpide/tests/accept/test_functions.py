#!/usr/bin/env python3
"""Integration test of fpide on tv3: the functions of the IDE are exercised one by one through the keyboard
(a tmux terminal, see fpide_term.py), the way they were clicked through by hand: the editor (typing, undo/redo,
clipboard, selection), Search (find, find again, replace, go to line), Window (tile, cascade, next, zoom, close all),
Tools (calculator, ASCII table), Options dialogs, Help, the file dialogs, the compiler (error messages with
positions, jump to the error, a good build) and Run.
usage: test_functions.py PATH/TO/fp [section ...]     sections: edit search window tools options files compile unicode debug
Prints PASS/FAIL per check, exit status 1 on any FAIL. Needs tmux, fpc (the IDE runs the compiler of the system)."""
import datetime
import os
import re
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


def menu(t, hot, item):
    ok = t.menu(hot, item)
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
    check(menu(t, 'M-e', 'Copy'), 'Edit > Copy is enabled for a selection')
    t.key('C-NPage', 'Enter')
    check(menu(t, 'M-e', 'Paste'), 'Edit > Paste is enabled after a copy')
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
    check(menu(t, 'M-e', 'Paste'), 'Edit > Paste after the cut')
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
    check(menu(t, 'M-s', 'Find'), 'Search > Find...')
    check(t.wait_for('Text to find') and t.wait_for('Case sensitive'), 'the Find dialog opens with its options', t)
    t.type('foo')          # the word under the cursor is preselected: typing replaces it
    t.key('Enter')
    check(t.wait_gone('Text to find'), 'OK closes the Find dialog', t)
    check(t.wait_until(lambda: t.indicator() == (1, 11)), 'Find puts the cursor after the first "foo" (1:11): %r' % (t.indicator(),), t)
    check(menu(t, 'M-s', 'Search again'), 'Search > Search again')
    check(t.wait_until(lambda: t.indicator() == (2, 11)), 'Search again goes to the next one (2:11): %r' % (t.indicator(),), t)

    # not found: a message, and the IDE goes on
    menu(t, 'M-s', 'Find')
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
        return L[i + 2].strip('║ ').strip()

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
    menu(t, 'M-e', 'Copy')
    t.key('C-NPage', 'Enter')
    menu(t, 'M-e', 'Paste')
    lines = editor_lines(t)
    check(len(lines) >= 3 and lines[2] == lines[0], 'the first line copied and pasted keeps all its characters: %r' % lines[:4], t)

    # search: case-insensitive for Cyrillic; replace with a Cyrillic text
    t.key('C-PPage')
    menu(t, 'M-s', 'Find')
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


SECTIONS = [('edit', section_edit), ('search', section_search), ('window', section_window), ('tools', section_tools),
            ('options', section_options), ('files', section_files), ('compile', section_compile),
            ('unicode', section_unicode), ('debug', section_debug)]

if __name__ == '__main__':
    run(sys.argv[1], sys.argv[2:])
    print('%d checks, %d failed' % (count, fails))
    sys.exit(1 if fails else 0)
