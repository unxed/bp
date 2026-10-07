#!/usr/bin/env python3
"""FV const TStreamRec records -> tv3 var records filled at run time.

tv3 registers a type with TStreamRec(ObjType, VmtLink, Load, Store), where Load/Store are
factories (function(S): TStreamable / procedure(P; S)), not constructor pointers
(tv/DESIGN.md, TvObjs). This rewrites every
    RFoo: TStreamRec = (ObjType: N; VmtLink: ...; Load: @TFoo.Load; Store: @TFoo.Store);
into `var RFoo: TStreamRec;` plus Build_/Store_ factories and a FillStreamRecs_<unit>
procedure called before the unit's first RegisterType. Idempotent. usage: <files...>
"""
import re, sys
from pathlib import Path

REC = re.compile(
    r"(?P<name>\bR\w+)\s*:\s*TStreamRec\s*=\s*\(\s*ObjType\s*:\s*(?P<n>\w+)\s*;\s*"
    r"VmtLink\s*:[^;]*;\s*Load\s*:\s*@(?P<cls>\w+)\.Load\s*;\s*"
    r"Store\s*:\s*@\w+\.Store\s*\)\s*;[ \t]*", re.S)

def convert(path):
    t = Path(path).read_bytes().decode('utf-8', 'surrogateescape')
    recs = [(m['name'], m['n'], m['cls']) for m in REC.finditer(t)]
    if not recs:
        return False
    def repl(m):
        # keep a const section alive if more constants follow
        rest = t[m.end():m.end() + 400]
        nxt = re.match(r"(?:\s|\{\$[^}]*\}|\{[^}]*\})*(\w+)\s*([:=])", rest)
        more = bool(nxt and nxt.group(1).lower() not in ('procedure', 'function', 'type', 'var',
                    'const', 'implementation', 'constructor', 'destructor') and nxt.group(2) in ':=')
        return f"\nvar {m['name']}: TStreamRec;\n" + ("const\n" if more else "")
    t = REC.sub(repl, t)
    t = re.sub(r"(?i)\nconst\n(?:[ \t]*\n)*(?=[ \t]*var )", "\n", t)
    unit = Path(path).stem
    block = ["{ tv3 stream registration: factories + run-time record fill (see tools/fpide-streamrec-migrate.py) }"]
    for name, n, cls in recs:
        block.append(f"function Build_{name}(S: TStream): TStreamable;\nbegin\n  Result := TStreamable(Pointer({cls}.Load(S)));\nend;\n")
        block.append(f"procedure Store_{name}(P: TStreamable; S: TStream);\nbegin\n  {cls}(Pointer(P)).Store(S);\nend;\n")
    block.append(f"procedure FillStreamRecs_{unit};\nbegin")
    for name, n, cls in recs:
        block.append(f"  {name}.ObjType := {n};\n  {name}.VmtLink := PtrUInt(System.TClass({cls}));\n"
                     f"  {name}.Load := @Build_{name};\n  {name}.Store := @Store_{name};\n  {name}.Next := nil;")
    block.append("end;\n")
    code = "\n".join(block) + "\n"
    impl = t.lower().index("\nimplementation")
    call = re.search(r"^[ \t]*RegisterType\(", t[impl:], re.M)
    if not call:
        print(f"{path}: no RegisterType call, add FillStreamRecs_{unit} by hand", file=sys.stderr)
        code = f"{{$ifndef NOOBJREG}}\n{code}{{$endif}}\n"
        pos = len(t.rstrip()) - len("end.")
        t = t[:pos] + code + t[pos:]
    else:
        cpos = impl + call.start()
        hdr = list(re.finditer(r"^(procedure|function)\s", t[:cpos], re.M))[-1]
        t = t[:hdr.start()] + "{$ifndef NOOBJREG}\n" + code + "{$endif}\n\n" + t[hdr.start():]
        # call the fill before every RegisterType run
        t = re.sub(r"(?m)^(?P<i>[ \t]*)(?<!\w)(?=RegisterType\()(?<!Fill)",
                   lambda m: m['i'] + f"FillStreamRecs_{unit};\n" + m['i'], t, count=0)
        # one call per run of consecutive RegisterType lines
        t = re.sub(rf"((?:[ \t]*FillStreamRecs_{unit};\n)[ \t]*RegisterType\([^\n]*\n)((?:[ \t]*FillStreamRecs_{unit};\n[ \t]*RegisterType\([^\n]*\n)+)",
                   lambda m: m[1] + re.sub(rf"[ \t]*FillStreamRecs_{unit};\n", "", m[2]), t)
    Path(path).write_bytes(t.encode('utf-8', 'surrogateescape'))
    print(f"{path}: {len(recs)} records")
    return True

if __name__ == "__main__":
    for p in sys.argv[1:]:
        convert(p)
