#!/usr/bin/env python3
"""Doc tests of this repository (safe/SPEC.md §22.3): the Pascal examples of the documents must not rot.

usage: tools/doctest.py [--keep DIR] [--bpvet PATH] [FILES...]

Extracts the fenced code blocks whose info string starts with `pascal`:
  ```pascal plan   a design that does not compile yet (a planned API): counted and skipped
  ```pascal sketch an illustration that is not a program of its own (a snippet, names that the page does not declare,
                   code that is wrong on purpose and that bpvet rejects): counted as skipped
  ```pascal        checked: written as a program (a block with a `program`/`unit`/`library` header as it is; a block
                   with statements gets `program DocN;` and `{$mode objfpc}{$H+}` on top unless it has a mode directive;
                   a block of declarations gets `type` when it starts with a declaration of a type, and an empty
                   `begin end.`; a routine without a body or a table is a fragment and is skipped), compiled with fpc
                   (the unit paths of this repository, nothing is run) and, with --bpvet, checked by `bpvet --strict`.
Blocks of other languages and plain ``` blocks are not touched. Default files: README.md, safe/SPEC.md, safe/README.md,
ext/README.md, ext/fpc-utf8/README.md and examples/*/README.md. Exit code 1 on any failure; the last line is
`doc tests: N checked, M plan, K skipped, F failed`. A failure names the file, the line of the document and the message.
"""
import argparse
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_FILES = ["README.md", "safe/SPEC.md", "safe/README.md", "ext/README.md", "ext/fpc-utf8/README.md"]

FENCE = re.compile(r"^(\s*)(`{3,}|~{3,})\s*(.*?)\s*$")
HEADER = re.compile(r"(?:^|\})\s*(program|unit|library)\s+([A-Za-z_]\w*)", re.I | re.M)
MODE = re.compile(r"\{\$mode\b", re.I)
END_DOT = re.compile(r"^\s*end\s*\.", re.I | re.M)
BEGIN = re.compile(r"^\s*begin\b", re.I | re.M)
USES = re.compile(r"^\s*uses\b", re.I | re.M)
SECTION = re.compile(r"^\s*(type|var|const|uses|label|threadvar|resourcestring|procedure|function|class|constructor|"
                     r"destructor|operator)\b", re.I)
ROUTINE = re.compile(r"^(procedure|function|constructor|destructor|operator)\b", re.I)
FPC_MSG = re.compile(r"^(?P<file>.+?)\((?P<line>\d+)(?:,\d+)?\) (?P<kind>Error|Fatal): (?P<msg>.*)$")
VET_MSG = re.compile(r"^(?P<file>.+?)\((?P<line>\d+),\d+\) (?P<msg>(?:Error|Warning): SAFE-.*)$")


def blocks(path):
    """Yield (info, first line number of the content, text) of every fenced block of the document."""
    lines = path.read_text(encoding="utf-8").split("\n")
    i = 0
    while i < len(lines):
        m = FENCE.match(lines[i])
        if not m:
            i += 1
            continue
        indent, fence, info = len(m.group(1)), m.group(2), m.group(3)
        j = i + 1
        while j < len(lines):
            c = FENCE.match(lines[j])
            if c and c.group(2)[0] == fence[0] and len(c.group(2)) >= len(fence) and not c.group(3):
                break
            j += 1
        body = [ln[indent:] if ln[:indent].strip() == "" else ln for ln in lines[i + 1:j]]
        yield info, i + 2, "\n".join(body) + "\n"
        i = j + 1


def code_lines(text):
    """The lines of a block without the comments (// and { } on one line), for the shape tests."""
    out = []
    for ln in text.split("\n"):
        ln = re.sub(r"//.*$", "", ln)
        ln = re.sub(r"\{[^$}][^}]*\}", "", ln)
        out.append(ln)
    return "\n".join(out)


def program_of(text, number):
    """Return (source, number of lines added on top) or (None, reason) when the block is a fragment to skip."""
    code = code_lines(text)
    if HEADER.search(code):
        return text, 0
    first_line, _, rest = text.partition("\n")
    if re.match(r"^\s*(\{\$[^}]*\}\s*)+$", first_line):
        # the block starts with its directives ({$mode objfpc}{$H+}): they stay before the program heading, on one line
        head = "%s program Doc%d;\n" % (first_line.rstrip(), number)
        if END_DOT.search(code):
            return head + rest, 0
        return (None, "fragment") if _unbodied(code) else (head + rest + "begin\nend.\n", 0)
    mode = "" if MODE.search(text) else "{$mode objfpc}{$H+}\n"
    head = "program Doc%d;\n%s" % (number, mode)
    if END_DOT.search(code):
        return head + text, head.count("\n")
    if _unbodied(code):
        return None, "fragment"
    first = next((ln for ln in code.split("\n") if ln.strip()), "")
    prefix = "" if SECTION.match(first) else "type\n"
    return head + prefix + text + "begin\nend.\n", (head + prefix).count("\n")


def _unbodied(code):
    """A routine heading at the top level whose body is missing (an API listing): every segment that starts with a
    heading at column 0 must have a `begin`, `asm`, `external` or `forward` before the next heading."""
    segments = re.split(r"^(?=(?:procedure|function|constructor|destructor|operator)\b)", code, flags=re.I | re.M)
    for seg in segments:
        if ROUTINE.match(seg) and not re.search(r"^\s*begin\b|^\s*asm\b|\b(external|forward)\b", seg, re.I | re.M):
            return True
    return False


def run(cmd, cwd):
    p = subprocess.run(cmd, cwd=str(cwd), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                       errors="replace")
    return p.returncode, p.stdout


def check(source, offset, work, lib, bpvet, doc, line0):
    """Compile the program and lint it; return the list of failure messages."""
    header = HEADER.search(code_lines(source))
    name = header.group(2) if header else "Doc"
    src = work / (name + ".pas")
    src.write_text(source, encoding="utf-8")
    out = work / "out"
    out.mkdir(exist_ok=True)
    fails = []

    def where(n):
        return "%s:%d" % (doc, line0 + n - 1 - offset)

    code, text = run(["fpc", "-vewn", "-FE" + str(out), "-FU" + str(out)] + lib + [str(src)], work)
    if code != 0:
        for ln in text.split("\n"):
            m = FPC_MSG.match(ln)
            if m:
                fails.append("%s: fpc %s: %s" % (where(int(m.group("line"))), m.group("kind"), m.group("msg")))
        if not fails:
            fails.append("%s: fpc failed: %s" % (doc, text.strip().split("\n")[-1] if text.strip() else code))
        return fails
    if bpvet:
        vopts = [a for a in lib if a.startswith(("-Fu", "-Fi"))]
        code, text = run([bpvet, "--strict"] + vopts + [str(src)], work)
        if code != 0:
            for ln in text.split("\n"):
                m = VET_MSG.match(ln)
                if m:
                    fails.append("%s: bpvet %s" % (where(int(m.group("line"))), m.group("msg")))
            if not fails:
                fails.append("%s: bpvet failed (exit %d): %s" % (doc, code, text.strip().split("\n")[-1:]))
    return fails


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--keep", metavar="DIR", help="keep the written programs and the build output in DIR")
    ap.add_argument("--bpvet", metavar="PATH", help="also check each program with `PATH --strict`")
    ap.add_argument("files", nargs="*")
    args = ap.parse_args()

    files = args.files
    if not files:
        files = [f for f in DEFAULT_FILES if (ROOT / f).is_file()]
        files += sorted(str(p.relative_to(ROOT)) for p in (ROOT / "examples").glob("*/README.md"))
    lib = ["-Fu%s" % ROOT, "-Fu%s/safe" % ROOT, "-Fu%s/ext" % ROOT, "-Fi%s/safe" % ROOT, "-Fi%s/ext" % ROOT,
           "-Fu%s/tools/spikes/region" % ROOT]
    bpvet = str(Path(args.bpvet).resolve()) if args.bpvet else None
    keep = Path(args.keep).resolve() if args.keep else None
    tmp = Path(tempfile.mkdtemp(prefix="doctest-")) if not keep else keep
    tmp.mkdir(parents=True, exist_ok=True)

    checked = plan = skipped = failed = 0
    try:
        for f in files:
            path = Path(f)
            if not path.is_absolute() and not path.exists():
                path = ROOT / f
            doc = f
            number = 0
            for info, line0, text in blocks(path):
                words = info.split()
                if not words or words[0] != "pascal":
                    continue
                number += 1
                if words[1:2] == ["plan"]:
                    plan += 1
                    continue
                if words[1:2] == ["sketch"]:
                    skipped += 1
                    continue
                source, offset = program_of(text, number)
                if source is None:
                    skipped += 1
                    print("%s:%d: skipped: %s" % (doc, line0, offset))
                    continue
                work = tmp / ("%s-%d" % (re.sub(r"\W+", "_", f), number))
                shutil.rmtree(work, ignore_errors=True)
                work.mkdir(parents=True)
                checked += 1
                fails = check(source, offset, work, lib, bpvet, doc, line0)
                for m in fails:
                    print(m)
                failed += 1 if fails else 0
    finally:
        if not keep:
            shutil.rmtree(tmp, ignore_errors=True)
    print("doc tests: %d checked, %d plan, %d skipped, %d failed" % (checked, plan, skipped, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
