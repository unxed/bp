#!/usr/bin/env python3
"""Census of the Better Pascal migration of fpide (step 4.0 of unxed/bp#3).

Prints, per unit of fpide/src and in total, the counts of section 2 of safe/FPIDE-ADOPTION.md, so that they can be
reproduced and compared before and after a migration step. It is a progress metric, not a CI gate: the counts are textual
(comments and string literals are stripped first), they show the shape of the code and not exact defect numbers.

  python3 fpide/tools/fpide-census.py                # table of all units, sorted by raw-memory calls
  python3 fpide/tools/fpide-census.py --totals       # only the total row
  python3 fpide/tools/fpide-census.py --unit fplang  # one unit
  python3 fpide/tools/fpide-census.py --src DIR      # another source directory

Columns: raw = GetMem/FreeMem/ReallocMem/AllocMem/Move/FillChar family calls, free = .Free + FreeAndNil, newdisp = New +
Dispose, short = ShortString and string[N], ptr = Pointer/PChar/PAnsiChar/PByte, ext = external declarations,
proc = TProcess/fpSelect/Terminate/Exec, safe = the unit mentions the Safe unit (1) or not (0).
"""
import argparse
import re
import sys
from pathlib import Path

DEFAULT_SRC = Path(__file__).resolve().parents[1] / "src"

# One entry per column: (name, regex applied to the text without comments and string literals).
PATTERNS = [
    ("raw", re.compile(r"(?<![.\w])(GetMem|FreeMem|ReallocMem|AllocMem|Move|FillChar|FillByte|FillWord|FillDWord)\s*\(", re.I)),
    ("free", re.compile(r"\.Free\b|\bFreeAndNil\s*\(", re.I)),
    ("newdisp", re.compile(r"(?<![.\w])(New|Dispose)\s*\(", re.I)),
    ("short", re.compile(r"\bShortString\b|\bstring\s*\[", re.I)),
    ("ptr", re.compile(r"\b(Pointer|PChar|PAnsiChar|PByte)\b", re.I)),
    ("ext", re.compile(r"\bexternal\b", re.I)),
    ("proc", re.compile(r"\b(TProcess|fpSelect)\b|\.Terminate\s*\(|(?<![.\w])Exec\s*\(", re.I)),
    ("safe", re.compile(r"\bSafe\b(?=\s*[,;])", re.I)),
]

# Comments (brace, parenthesis-star, line) and string literals, in the order in which they can start in Pascal source.
STRIP = re.compile(r"\{[^}]*\}|\(\*.*?\*\)|//[^\n]*|'(?:[^'\n]|'')*'", re.S)


def strip(text):
    """Replace comments and string literals by a space, keeping the line structure."""
    return STRIP.sub(lambda m: "\n" * m.group(0).count("\n") or " ", text)


def count(path):
    text = strip(path.read_text(encoding="utf-8", errors="replace"))
    row = {name: len(rx.findall(text)) for name, rx in PATTERNS}
    row["safe"] = min(row["safe"], 1)
    row["lines"] = text.count("\n") + 1
    return row


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--src", type=Path, default=DEFAULT_SRC, help="source directory (default: fpide/src)")
    ap.add_argument("--totals", action="store_true", help="print only the total row")
    ap.add_argument("--unit", help="print only the unit with this name (without extension)")
    args = ap.parse_args()

    files = sorted(p for p in args.src.iterdir() if p.is_file() and p.suffix.lower() in (".pas", ".pp", ".inc"))
    if args.unit:
        files = [p for p in files if p.stem.lower() == args.unit.lower()]
    if not files:
        print("fpide-census: no source file found in %s" % args.src, file=sys.stderr)
        return 1

    cols = [name for name, _ in PATTERNS]
    rows = {p.name: count(p) for p in files}
    total = {c: sum(r[c] for r in rows.values()) for c in cols + ["lines"]}
    total["safe"] = sum(r["safe"] for r in rows.values())

    head = "%-18s %6s " % ("unit", "lines") + " ".join("%7s" % c for c in cols)
    print(head)
    if not args.totals:
        for name in sorted(rows, key=lambda n: (-rows[n]["raw"], n)):
            r = rows[name]
            print("%-18s %6d " % (name, r["lines"]) + " ".join("%7d" % r[c] for c in cols))
    print("%-18s %6d " % ("TOTAL (%d files)" % len(rows), total["lines"]) + " ".join("%7d" % total[c] for c in cols))
    return 0


if __name__ == "__main__":
    sys.exit(main())
