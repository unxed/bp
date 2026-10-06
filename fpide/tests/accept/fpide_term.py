"""A terminal for driving fpide in tests: the IDE runs inside a detached tmux session and is
looked at with `tmux capture-pane`. Keys go in with `send-keys` (names or raw bytes), so no
terminal emulator has to be written. Needs: tmux, python3.  Used by test_accept.py."""
import collections
import os
import re
import shutil
import subprocess
import tempfile
import time


class TmuxTerm:
    def __init__(self, binary, cols=100, rows=30, args=(), env=None):
        binary = os.path.abspath(binary)
        self.session = 'fpideacc%d' % os.getpid()
        self.work = tempfile.mkdtemp(prefix='fpide-acc-')
        self.err = os.path.join(self.work, 'stderr.log')
        e = {'TERM': 'xterm-256color', 'HOME': self.work}
        e.update(env or {})
        envs = ' '.join('%s=%s' % kv for kv in e.items())
        cmd = 'cd %s && %s %s %s 2>%s; echo EXIT=$? >> %s; sleep 600' % (
            self.work, envs, binary, ' '.join(args), self.err, self.err)
        subprocess.check_call(['tmux', 'new-session', '-d', '-s', self.session, '-x', str(cols), '-y', str(rows), cmd])

    def _tmux(self, *a):
        return subprocess.run(['tmux'] + list(a), capture_output=True, text=True).stdout

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

    def type(self, s):
        """literal text, one byte at a time as hex (so ';' and the like are not tmux syntax)"""
        for b in s.encode('utf-8'):
            self._tmux('send-keys', '-t', self.session, '-H', '%02x' % b)
        time.sleep(0.15)

    def _menu_rows(self):
        """[(row, text, highlighted)] of the drop-down box on screen. The highlighted row is the one
        whose colour attributes differ from the others'."""
        raw = self._tmux('capture-pane', '-t', self.session, '-p', '-e').split('\n')
        rows = []
        for i, l in enumerate(raw):
            parts = l.split('│')
            if len(parts) >= 3:
                text = re.sub(r'\x1b\[[0-9;]*m', '', parts[1]).strip()
                sgr = tuple(re.findall(r'\x1b\[([0-9;]*)m', parts[1]))[:2]
                rows.append((i, text, sgr))
        if not rows:
            return []
        common = collections.Counter(r[2] for r in rows).most_common(1)[0][0]
        return [(i, text, sgr != common) for i, text, sgr in rows]

    def menu(self, hotkey, label, timeout=4.0):
        """open the menu with its Alt-key and choose the item whose text starts with `label`
        (arrow keys only, so it works whatever the item's hotkey is). False if there is no such item."""
        self.key(hotkey)
        self.pump(0.4)
        for _ in range(40):
            rows = self._menu_rows()
            cur = [r for r in rows if r[2]]
            if not rows or not cur:
                return False
            if cur[0][1].startswith(label):
                self.key('Enter')
                return True
            self.key('Down')
            self.pump(0.1)
        return False

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
        self._tmux('kill-session', '-t', self.session)
        shutil.rmtree(self.work, ignore_errors=True)
