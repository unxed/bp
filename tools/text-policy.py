#!/usr/bin/env python3
"""The text policy of this repository: tools/text-policy.py (exit code 1 when it is broken).

1. Every tracked text file is UTF-8 (no code page bytes, no U+FFFD, no byte order mark).
2. Comments, documents, hard-coded strings and messages are English: a letter outside ASCII (Cyrillic, Greek, CJK, an
   accented Latin letter, ...) is allowed only where ALLOWED lists it, that is where it is data: the text that a test feeds
   to the code, an example of a non-ASCII string in a comment or a document, a language resource, a table of characters,
   a person's name. Symbols (arrows, dashes, box drawing, emoji) are not letters and are allowed everywhere.
"""
import re
import subprocess
import sys
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# (file pattern, line pattern or None for the whole file, the reason)
ALLOWED = [
    (r"^tests/", None, "the text of a test is data"),
    (r"^ext/fpc-utf8/test_utf8\.pas$", None, "the text of a test is data"),
    (r"^fpide/tests/", None, "the text of a test is data"),
    (r"^README\.md$", r"CPLength\('a", "an example of a UTF-8 literal"),
    (r"^ext/fpc-utf8/README\.md$", r"Pos\('", "an example of a UTF-8 literal"),
    (r"^ext/fpc-utf8/utf8everywhere\.pas$", r"CodePoints\('a", "an example of a UTF-8 literal (a comment)"),
    (r"^ext/utf8\.intf\.inc$", r"CodePoints\('a", "an example of a UTF-8 literal (a comment)"),
    (r"^fpide/src/wconstsh\.inc$", None, "the Hungarian language resource of the IDE"),
    (r"^fpide/src/whtml\.pas$", r"then E:='", "the table of the HTML character entities"),
    (r"^fpide/src/(fpviews|wconsts)\.pas$", r"B\u00e9rczi G\u00e1bor|Kl\u00e4mpfl|Mich\u00e4el", "the names of the authors"),
]


def tracked():
    out = subprocess.check_output(["git", "-C", str(ROOT), "ls-files", "-z"]).decode("utf-8")
    for name in out.split("\0"):
        path = ROOT / name
        if name and path.is_file() and not path.is_symlink():
            yield name, path.read_bytes()


def foreign_letter(line):
    return any(ord(ch) > 127 and unicodedata.category(ch).startswith("L") for ch in line)


def allowed(name, line):
    for file_pattern, line_pattern, _ in ALLOWED:
        if re.search(file_pattern, name) and (line_pattern is None or re.search(line_pattern, line)):
            return True
    return False


def check():
    problems = []
    for name, data in tracked():
        if b"\0" in data:
            continue
        try:
            text = data.decode("utf-8")
        except UnicodeDecodeError as error:
            problems.append("%s: not UTF-8 (byte %d)" % (name, error.start))
            continue
        if text.startswith("\ufeff") or "\ufffd" in text:
            problems.append("%s: byte order mark or U+FFFD" % name)
        for number, line in enumerate(text.split("\n"), 1):
            if foreign_letter(line) and not allowed(name, line):
                problems.append("%s:%d: a non-English letter (translate it, or list it in tools/text-policy.py): %s"
                                % (name, number, line.strip()[:80]))
    return problems


if __name__ == "__main__":
    found = check()
    for problem in found:
        print("POLICY:", problem)
    print("text policy: %d problems" % len(found))
    sys.exit(1 if found else 0)
