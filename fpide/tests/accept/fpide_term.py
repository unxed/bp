"""A terminal for driving fpide in tests: the IDE runs inside a detached tmux session and is
looked at with `tmux capture-pane`. Keys go in with `send-keys` (names or raw bytes), so no
terminal emulator has to be written. Needs: tmux, python3.  Used by test_accept.py."""
import collections
import itertools
import os
import re
import unicodedata
import shutil
import subprocess
import tempfile
import time


class TmuxTerm:
    ids = itertools.count(1)

    def __init__(self, binary, cols=100, rows=30, args=(), env=None):
        binary = os.path.abspath(binary)
        self.binary = binary
        # a tmux server of its own (-L) and a session name of its own: the tests (and the threads of a test) run side by side
        self.session = 'fpideacc%d_%d' % (os.getpid(), next(TmuxTerm.ids))
        self.socket = self.session
        self.work = tempfile.mkdtemp(prefix='fpide-acc-')
        self.err = os.path.join(self.work, 'stderr.log')
        # the XDG directories are set so that a value of the tmux server does not lead the IDE out of the temp dir
        e = {'TERM': 'xterm-256color', 'HOME': self.work,
             'XDG_CONFIG_HOME': os.path.join(self.work, '.config'), 'XDG_STATE_HOME': os.path.join(self.work, '.local/state'),
             'XDG_DATA_HOME': os.path.join(self.work, '.local/share'), 'XDG_CACHE_HOME': os.path.join(self.work, '.cache')}
        e.update(env or {})
        envs = ' '.join('%s=%s' % kv for kv in e.items())
        cmd = 'cd %s && %s %s %s 2>%s; echo EXIT=$? >> %s; sleep 600' % (
            self.work, envs, binary, ' '.join(args), self.err, self.err)
        subprocess.check_call(['tmux', '-L', self.socket, '-f', '/dev/null', 'new-session', '-d', '-s', self.session, '-x', str(cols), '-y', str(rows), cmd])
        self.socket_path = self._tmux('display-message', '-p', '#{socket_path}').strip()

    def _tmux(self, *a):
        """a tmux command on the server of this terminal; its output"""
        return subprocess.run(['tmux', '-L', self.socket] + list(a), capture_output=True, text=True).stdout

    def text(self):
        """the screen as text; the desktop shade is blanked so the tests need not know it"""
        out = self._tmux('capture-pane', '-t', self.session, '-p')
        return '\n'.join(l.rstrip() for l in out.replace('░', ' ').split('\n')).rstrip('\n')

    def lines(self):
        return self.text().split('\n')

    def key(self, *names):
        """tmux key names: Enter, Escape, F10, M-f (Alt-f), C-Home ..."""
        for n in names:
            self._tmux('send-keys', '-t', self.session, n)
            time.sleep(0.12)

    def click(self, col, row, button=0, double=False):
        """a mouse click at the screen cell (col, row), 0-based, as the terminal sends it (xterm SGR mouse reports)"""
        seqs = [b'\x1b[<%d;%d;%dM' % (button, col + 1, row + 1), b'\x1b[<%d;%d;%dm' % (button, col + 1, row + 1)]
        for q in seqs * (2 if double else 1):
            self._tmux('send-keys', '-t', self.session, '-H', *['%02x' % b for b in q])
            time.sleep(0.05)
        time.sleep(0.2)

    def drag(self, col0, row0, col1, row1, button=0, steps=4):
        """press at (col0,row0), move to (col1,row1) with the button held, release there (SGR mouse reports)"""
        seqs = [b'\x1b[<%d;%d;%dM' % (button, col0 + 1, row0 + 1)]
        for i in range(1, steps + 1):
            c = col0 + (col1 - col0) * i // steps
            r = row0 + (row1 - row0) * i // steps
            seqs.append(b'\x1b[<%d;%d;%dM' % (button + 32, c + 1, r + 1))
        seqs.append(b'\x1b[<%d;%d;%dm' % (button, col1 + 1, row1 + 1))
        for q in seqs:
            self._tmux('send-keys', '-t', self.session, '-H', *['%02x' % b for b in q])
            time.sleep(0.05)
        time.sleep(0.2)

    def paste(self, s):
        """text pasted by the terminal (bracketed paste, as Ctrl+Shift+V does): through a tmux buffer"""
        subprocess.run(['tmux', '-L', self.socket, 'set-buffer', '-b', 'fpideacc', s[:-1] + '\\;' if s.endswith(';') else s], check=True)   # a trailing ';' is tmux syntax
        self._tmux('paste-buffer', '-p', '-d', '-b', 'fpideacc', '-t', self.session)
        time.sleep(0.4)

    def type(self, s):
        """literal text, one byte at a time as hex (so ';' and the like are not tmux syntax)"""
        for b in s.encode('utf-8'):
            self._tmux('send-keys', '-t', self.session, '-H', '%02x' % b)
        time.sleep(0.15)

    @staticmethod
    def _cells(line):
        """one line of `capture-pane -e` as [(char, background)]: the background colour in force
        (tmux sends fg and bg as separate sequences; only the background tells a highlighted row)"""
        cells, bg, i = [], '', 0
        while i < len(line):
            m = re.match(r'\x1b\[([0-9;]*)m', line[i:])
            if m:
                codes = m.group(1).split(';') if m.group(1) else ['0']
                j = 0
                while j < len(codes):
                    c = codes[j]
                    if c in ('0', ''):
                        bg = ''
                    elif c == '49':
                        bg = ''
                    elif c in ('48',) and j + 1 < len(codes):
                        bg = ';'.join(codes[j:j + 3 if codes[j + 1] == '5' else j + 5])
                        j += 2 if codes[j + 1] == '5' else 4
                    elif (c.isdigit() and (40 <= int(c) <= 47 or 100 <= int(c) <= 107)):
                        bg = c
                    j += 1
                i += m.end()
                continue
            cells.append((line[i], bg))
            if unicodedata.east_asian_width(line[i]) in 'WF':
                cells.append((' ', bg))      # a wide character covers two cells; tmux prints it once
            i += 1
        return cells

    def row_backgrounds(self, col):
        """the background colour of the cell in column `col` of every screen row (tmux writes only the
        changes of the attributes, also across line ends: the whole screen is read as one stream)"""
        raw = self._tmux('capture-pane', '-t', self.session, '-p', '-e')
        out, row = [], []
        for ch, bg in self._cells(raw):
            if ch == '\n':
                out.append(row[col] if len(row) > col else None)
                row = []
            else:
                row.append(bg)
        return out

    def _menu_rows(self):
        """[(row, text, highlighted)] of the drop-down box on screen: the box is the `┌...┐` found on
        the screen, a row is highlighted if its colour differs from the other rows'."""
        raw = self._tmux('capture-pane', '-t', self.session, '-p', '-e').split('\n')
        grid = [self._cells(l) for l in raw]
        box = None
        for y, row in enumerate(grid):
            chars = ''.join(c for c, _ in row)
            for m in re.finditer(r'┌─+┐', chars):
                if m.end() - m.start() <= 40:     # a menu box is narrow; an unfocused window's frame is not
                    box = (y, m.start(), m.end() - 1)
                    break
            if box:
                break
        if not box:
            return []
        y0, x0, x1 = box
        rows = []
        for y in range(y0 + 1, len(grid)):
            row = grid[y]
            if len(row) <= x1 or row[x0][0] not in '│├' or row[x1][0] not in '│┤':
                break
            if row[x0][0] == '├':
                continue
            text = ''.join(c for c, _ in row[x0 + 1:x1]).strip()
            rows.append((y, text, row[x0 + 1][1]))   # the blank after the border: no hotkey colour
        if not rows:
            return []
        common = collections.Counter(r[2] for r in rows).most_common(1)[0][0]
        return [(y, text, sgr != common) for y, text, sgr in rows]

    def menu(self, hotkey, label, timeout=4.0, exact=False):
        """open the menu with its Alt-key and choose the item whose text starts with `label`
        (arrow keys only, so it works whatever the item's hotkey is). False if there is no such item."""
        self.key(hotkey)
        self.pump(0.4)
        for _ in range(40):
            rows = self._menu_rows()
            cur = [r for r in rows if r[2]]
            if not rows or not cur:
                return False
            name = re.split(r'\s{2,}', cur[0][1])[0].rstrip('.►').strip()
            if (name == label) if exact else cur[0][1].startswith(label):
                self.key('Enter')
                return True
            self.key('Down')
            self.pump(0.1)
        return False

    def cursor(self):
        """the hardware cursor (row, column) of the terminal"""
        out = self._tmux('display-message', '-p', '-t', self.session, '#{cursor_y},#{cursor_x}').strip()
        y, x = out.split(',')
        return int(y), int(x)

    def indicator(self):
        """(line, column) of the editor indicator in the frame of the active window, or None"""
        for l in self.lines()[-4:]:
            m = re.search(r'═\*?═*\s*(\d+):(\d+)\s', l) or re.search(r'(\d+):(\d+) ═', l)
            if m:
                return int(m.group(1)), int(m.group(2))
        return None

    def wait_until(self, pred, timeout=6.0):
        end = time.time() + timeout
        while time.time() < end:
            if pred():
                return True
            time.sleep(0.1)
        return pred()

    def pump(self, secs):
        time.sleep(secs)

    def wait_for(self, needle, timeout=6.0):
        end = time.time() + timeout
        while time.time() < end:
            if needle in self.text():
                return True
            time.sleep(0.1)
        return False

    def wait_gone(self, needle, timeout=6.0):
        end = time.time() + timeout
        while time.time() < end:
            if needle not in self.text():
                return True
            time.sleep(0.1)
        return False

    def alive(self):
        try:
            return 'EXIT=' not in open(self.err).read()
        except OSError:
            return True

    def stderr(self):
        try:
            return open(self.err).read()
        except OSError:
            return ''

    def close(self):
        self._tmux('kill-server')
        if self.socket_path:
            try:
                os.unlink(self.socket_path)        # tmux leaves the socket file
            except OSError:
                pass
        shutil.rmtree(self.work, ignore_errors=True)
