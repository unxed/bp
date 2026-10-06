#!/usr/bin/env python3
"""Mechanical FV object→tv3 class migration for fpide Pascal units."""
from __future__ import annotations

import re
import sys
from pathlib import Path

TV_BASES = [
    "Label", "Button", "History", "CheckBoxes", "RadioButtons", "InputLine",
    "Dialog", "FileDialog", "StaticText", "ScrollBar", "Collection",
    "StringCollection", "BufStream", "RangeValidator", "MenuBox", "View",
    "Cluster", "ListBox", "Window", "Group", "Scroller", "Frame", "Object",
    "SortedCollection", "Memo", "StatusLine", "MenuBar", "MenuPopup",
]


def convert(text: str) -> str:
    if "{$mode objfpc}" not in text:
        text = re.sub(
            r"(unit\s+\w+\s*;\s*\n)",
            r"\1\n{$mode objfpc}{$H-}\n{$modeswitch nestedprocvars}\n{$modeswitch autoderef}\n",
            text,
            count=1,
            flags=re.I,
        )

    for tn in re.findall(r"\b(T\w+)\s*=\s*object\s*\(", text):
        pn = "P" + tn[1:]
        text = re.sub(rf"\b{pn}\s*=\s*\^{tn}\b", f"{pn} = {tn}", text)

    text = re.sub(r"\bobject\s*\(", "class(", text)
    text = re.sub(r"\bconstructor\s+Init\b", "constructor Create", text, flags=re.I)
    text = re.sub(r"\bdestructor\s+Done\b", "destructor Destroy", text, flags=re.I)
    text = re.sub(r"\b(constructor\s+\w+)\.Init\b", r"\1.Create", text, flags=re.I)
    text = re.sub(r"\b(destructor\s+\w+)\.Done\b", r"\1.Destroy", text, flags=re.I)
    text = re.sub(r"\binherited\s+Init\b", "inherited Create", text, flags=re.I)
    text = re.sub(r"\binherited\s+Done\b", "inherited Destroy", text, flags=re.I)
    text = re.sub(r"\binherited\s+done\b", "inherited Destroy", text)
    text = text.replace("@Self", "Self").replace("@self", "Self")

    text = re.sub(r"\bDispose\s*\(\s*([^,\n]+)\s*,\s*Destroy\s*\)", r"\1.Free", text, flags=re.I)
    text = re.sub(r"\bDispose\s*\(\s*([^,\n]+)\s*,\s*Done\s*\)", r"\1.Free", text, flags=re.I)

    # Forward class decls before PFoo = TFoo (including "type PFoo = TFoo")
    lines = text.splitlines(True)
    seen: set[str] = set()
    out: list[str] = []
    for line in lines:
        m = re.match(r"^(\s*)(type\s+)?(P\w+)\s*=\s*(T\w+)\s*;\s*$", line, flags=re.I)
        if m:
            indent, typekw, _pn, tn = m.groups()
            if tn not in seen:
                prefix = f"{indent}type " if typekw else indent
                # If line already has type keyword, emit forward then P=T under same type block
                if typekw:
                    out.append(f"{indent}type\n")
                    out.append(f"{indent}  {tn} = class;\n")
                    out.append(f"{indent}  {_pn} = {tn};\n")
                    seen.add(tn)
                    continue
                out.append(f"{indent}{tn} = class;\n")
                seen.add(tn)
        m2 = re.match(r"^(\s*)(T\w+)\s*=\s*class", line)
        if m2:
            seen.add(m2.group(2))
        out.append(line)
    text = "".join(out)

    aliases = dict(re.findall(r"\b(P\w+)\s*=\s*(T\w+)\s*;", text))
    for base in TV_BASES:
        aliases.setdefault(f"P{base}", f"T{base}")

    def ins_new(m: re.Match[str]) -> str:
        pt, ctor, args = m.group(1), m.group(2), m.group(3)
        method = "Create" if ctor.lower() == "init" else ctor
        return f"Insert({aliases.get(pt, 'T' + pt[1:])}.{method}({args}))"

    text = re.sub(
        r"\bInsert\s*\(\s*New\s*\(\s*(P\w+)\s*,\s*(\w+)\s*\((.*?)\)\s*\)\s*\)",
        ins_new,
        text,
        flags=re.S | re.I,
    )

    def asg_new(m: re.Match[str]) -> str:
        var, pt, ctor, args = m.group(1), m.group(2), m.group(3), m.group(4)
        method = "Create" if ctor.lower() == "init" else ctor
        return f"{var} := {aliases.get(pt, 'T' + pt[1:])}.{method}({args})"

    text = re.sub(
        r"\b(\w+)\s*:=\s*New\s*\(\s*(P\w+)\s*,\s*(\w+)\s*\((.*?)\)\s*\)",
        asg_new,
        text,
        flags=re.S | re.I,
    )
    # Nearest preceding "Name: PType" wins (file-global last-wins pollutes short names like P).
    vardecls: list[tuple[int, str, str]] = [
        (m.start(), m.group(1), m.group(2))
        for m in re.finditer(r"\b([A-Za-z_]\w*)\s*:\s*(P\w+)\b", text)
    ]

    def nearest_ptype(name: str, pos: int) -> str | None:
        pt = None
        for dpos, dname, dtype in vardecls:
            if dpos >= pos:
                break
            if dname == name:
                pt = dtype
        return pt

    def new_ctor(m: re.Match[str]) -> str:
        target, ctor, args = m.group(1), m.group(2), m.group(3)
        method = "Create" if ctor.lower() == "init" else ctor
        # New(PFoo, Ctor(...)) type form
        bare = re.match(r"^(P\w+)$", target)
        if bare and len(target) > 1 and target[1:2].isupper() and nearest_ptype(target, m.start()) is None:
            tn = aliases.get(target, "T" + target[1:])
            return f"{tn}.{method}({args})"
        # strip index for type lookup: ReservedWords[I] -> ReservedWords
        base = re.sub(r"\[.*\]$", "", target)
        pt = nearest_ptype(base, m.start())
        if pt:
            tn = aliases.get(pt, "T" + pt[1:] if pt.startswith("P") else pt)
            return f"{target} := {tn}.{method}({args})"
        return f"{target} := {target}.{method}({args})  {{ TODO: New ctor type }}"

    text = re.sub(
        r"\bNew\s*\(\s*([A-Za-z_]\w*(?:\[[^\]]+\])?)\s*,\s*(\w+)\s*\((.*?)\)\s*\)",
        new_ctor,
        text,
        flags=re.S | re.I,
    )

    def new_ctor_noargs(mm: re.Match[str]) -> str:
        target, ctor = mm.group(1), mm.group(2)
        method = "Create" if ctor.lower() == "init" else ctor
        if target.startswith("P") and len(target) > 1 and target[1:2].isupper() and nearest_ptype(target, mm.start()) is None:
            return f"{aliases.get(target, 'T' + target[1:])}.{method}"
        pt = nearest_ptype(target, mm.start())
        if pt:
            tn = aliases.get(pt, "T" + pt[1:] if pt.startswith("P") else pt)
            return f"{target} := {tn}.{method}"
        return f"{target} := {target}.{method}  {{ TODO: New ctor type }}"

    text = re.sub(
        r"\bNew\s*\(\s*([A-Za-z_]\w*)\s*,\s*(\w+)\s*\)",
        new_ctor_noargs,
        text,
        flags=re.I,
    )

    text = text.replace("GetPalette: PPalette", "GetPalette: TPalette")
    text = re.sub(
        r"function\s+(\w+)\.GetPalette:\s*TPalette;\s*const\s+P:\s*string\[[^\]]+\]\s*=\s*(\w+);\s*begin\s+GetPalette\s*:=\s*@P;\s*end;",
        r"function \1.GetPalette: TPalette;\nbegin\n  Result := MakePalette(\2);\nend;",
        text,
        flags=re.S | re.I,
    )

    text = text.replace("B: TDrawBuffer", "B: TFVDrawBuffer")
    text = re.sub(r"\bGetColor\(", "GetColorW(", text)
    text = re.sub(r"\bWriteLine\(", "WriteLineW(", text)
    text = re.sub(r"\bWriteBuf\(", "WriteBufW(", text)
    text = text.replace("Event.Double", "((Event.EventFlags and meDoubleClick) <> 0)")
    text = text.replace("Event.KeyShift", "Event.ControlKeyState")
    text = text.replace("mfOkButton", "mfOKButton")

    keep = {
        "PString", "PStr", "PChar", "PByte", "PWord", "PMenu", "PMenuItem",
        "PStatusItem", "PStatusDef", "PEvent", "PNode", "PPoint", "PRect",
    }

    def drop_caret(m: re.Match[str]) -> str:
        return m.group(0) if m.group(1) in keep else f"{m.group(1)}."

    text = re.sub(r"\b([A-Za-z_]\w*)\^\.", drop_caret, text)
    text = re.sub(
        r"\bwith\s+(\w+)\^\s+do\b",
        lambda m: m.group(0) if m.group(1) in keep else f"with {m.group(1)} do",
        text,
    )
    text = re.sub(r"(\.At\([^)]+\))\^\.", r"\1.", text)
    text = re.sub(r"\)\^\.", ").", text)

    for n in ["Application", "Desktop", "DeskTop", "Owner", "Stream", "S", "Control", "Dialog"]:
        text = re.sub(rf"\b{n}\^\.", f"{n}.", text)

    text = re.sub(
        r"(function\s+\w+\.At\([^)]+\):\s*(P\w+);\s*begin\s*)At\s*:=\s*inherited\s+At\(([^)]+)\);",
        r"\1At := \2(inherited At(\3));",
        text,
    )
    return text


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: class-migrate-unit.py FILE.pas...", file=sys.stderr)
        return 2
    for arg in sys.argv[1:]:
        path = Path(arg)
        raw = path.read_bytes()
        for enc in ("utf-8", "latin-1", "cp1251"):
            try:
                text = raw.decode(enc)
                break
            except UnicodeDecodeError:
                continue
        else:
            print("skip", path, "encoding")
            continue
        # Allow re-run on partially migrated units (classes already, New/Dispose left).
        if "object(" not in text and "object (" not in text:
            if "New(" not in text and "Dispose(" not in text:
                print("skip", path.name, "(no object()/New/Dispose)")
                continue
        new = convert(text)
        path.write_bytes(new.encode(enc))
        left = len(re.findall(r"\bobject\s*\(", new))
        news = len(re.findall(r"\bNew\s*\(", new))
        print("converted", path.name, "object( left:", left, "New( left:", news)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
