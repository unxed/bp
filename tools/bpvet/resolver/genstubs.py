#!/usr/bin/env python3
"""Declaration stubs of the FPC RTL for the typed bpvet (safe/SPEC.md §20 "Spike 1 result").

genstubs.py OUT SRCDIR...

The units are read from their .ppu with `ppudump -Fj` (fp-utils of the same FPC version as the units). Only the closure
of what the sources in SRCDIR use is written: an interface symbol is a seed when its name occurs as an identifier in the
sources, and every type a written declaration refers to is written too. A class keeps only the members whose names
occur in the sources (and the accessors of the properties it keeps). Routines are `external`, methods get empty bodies.

PPUDUMP: the ppudump binary (default ppudump-3.2.2, then ppudump). FPCUNITS: the directory of the unit directories
(default: the one of `fpc -iV` under /usr/lib/x86_64-linux-gnu/fpc and /usr/lib/fpc). The dumps are cached under
${XDG_CACHE_HOME:-~/.cache}/bpvet-ppu by the CRC of the .ppu file.
"""
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys

# Base types the resolver knows without a declaration (pasresolver BaseTypeNames and the objfpc built-ins).
BUILTIN = {n.lower() for n in """Char AnsiChar WideChar String AnsiString ShortString RawByteString WideString
UnicodeString Single Double Extended CExtended Currency Boolean ByteBool WordBool LongBool QWordBool Byte ShortInt
Word SmallInt LongWord LongInt QWord Int64 Comp Pointer File Text Variant""".split()}

# Always written: the resolver needs them for implicit uses (the default ancestor, array of const, interfaces).
ALWAYS = {"system": {"tobject", "tclass", "iunknown", "iinterface", "tinterfacedobject", "tguid", "tvarrec", "hresult",
                     "pchar", "pansichar", "pwidechar", "sizeint", "sizeuint", "ptrint", "ptruint", "integer"}}

# Generic types: ppudump 3.2.2 does not write their type parameters, so they are declared here.
GENERICS = {"system": ["generic TArray<T> = array of T;"]}

# Interfaces a class implements: ppudump 3.2.2 does not write them.
IMPLEMENTS = {"tinterfacedobject": "IUnknown", "tagregatedobject": "IUnknown"}
IUNKNOWN = {"queryinterface", "_addref", "_release"}

# Routines the typed bpvet declares as compiler magic.
MAGIC = {"write", "writeln", "read", "readln", "halt", "randomize", "initialize", "finalize", "finalizearray",
         "setstring"}

# String flavours other than AnsiString: an overload that needs one is left out when another overload of the same
# routine does without, since the relaxed checks of the typed bpvet cannot choose between string flavours.
OTHER_STRINGS = re.compile(r":\s*(?:const\s+)?(?:ShortString|UnicodeString|WideString|WideChar|Variant|UCS4String|"
                           r"PWideChar|PUnicodeChar|UnicodeChar|String\[)", re.I)

KEYWORDS = {"and", "array", "as", "asm", "begin", "case", "class", "const", "constructor", "destructor", "div", "do",
            "downto", "else", "end", "except", "exports", "file", "finalization", "finally", "for", "function", "goto",
            "if", "implementation", "in", "inherited", "initialization", "inline", "interface", "is", "label",
            "library", "mod", "nil", "not", "object", "of", "on", "operator", "or", "out", "packed", "procedure",
            "program", "property", "raise", "record", "repeat", "resourcestring", "set", "shl", "shr", "string",
            "then", "threadvar", "to", "try", "type", "unit", "until", "uses", "var", "while", "with", "xor", "self",
            "result"}


def die(msg):
    sys.stderr.write("genstubs: %s\n" % msg)
    sys.exit(1)


# ---------------------------------------------------------------- sources

COMMENT = re.compile(r"\{[^}]*\}|\(\*.*?\*\)|//[^\n]*|'(?:[^']|'')*'", re.S)
IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")


def scan_sources(dirs):
    """The identifiers of the sources (lower case) and the units their uses clauses name."""
    idents, uses = set(), set()
    for d in dirs:
        walked = [(os.path.dirname(d), [], [os.path.basename(d)])] if os.path.isfile(d) else os.walk(d)
        for root, _, files in walked:
            for f in files:
                if not f.lower().endswith((".pas", ".pp", ".inc", ".lpr", ".dpr")):
                    continue
                text = open(os.path.join(root, f), encoding="utf-8", errors="replace").read()
                code = COMMENT.sub(" ", text)
                idents.update(m.group(0).lower() for m in IDENT.finditer(code))
                for m in re.finditer(r"\buses\b(.*?);", code, re.S | re.I):
                    for u in m.group(1).split(","):
                        u = re.sub(r"\bin\b.*", "", u, flags=re.S | re.I).strip()
                        if IDENT.fullmatch(u):
                            uses.add(u.lower())
    return idents, uses


# ---------------------------------------------------------------- ppu

def ppu_dirs():
    base = os.environ.get("FPCUNITS")
    if not base:
        ver = subprocess.run([os.environ.get("FPC", "fpc"), "-iV"], capture_output=True, text=True).stdout.strip()
        tgt = subprocess.run([os.environ.get("FPC", "fpc"), "-iTP"], capture_output=True, text=True).stdout.strip()
        tos = subprocess.run([os.environ.get("FPC", "fpc"), "-iTO"], capture_output=True, text=True).stdout.strip()
        for cand in ("/usr/lib/x86_64-linux-gnu/fpc", "/usr/lib/fpc", "/usr/local/lib/fpc"):
            p = os.path.join(cand, ver, "units", "%s-%s" % (tgt, tos))
            if os.path.isdir(p):
                base = p
                break
    if not base or not os.path.isdir(base):
        die("no FPC unit directory (set FPCUNITS)")
    return [os.path.join(base, d) for d in sorted(os.listdir(base)) if os.path.isdir(os.path.join(base, d))]


def ppudump_bin():
    for b in [os.environ.get("PPUDUMP"), "ppudump-3.2.2", "ppudump"]:
        if b and shutil.which(b):
            return b
    die("ppudump not found (Debian, Ubuntu: fp-utils)")


class Units:
    def __init__(self):
        self.dirs = ppu_dirs()
        self.ppudump = ppudump_bin()
        self.cache = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "bpvet-ppu")
        self.loaded = {}

    def find(self, name):
        for d in self.dirs:
            p = os.path.join(d, name + ".ppu")
            if os.path.isfile(p):
                return p
        return None

    def get(self, name):
        name = name.lower()
        if name not in self.loaded:
            path = self.find(name)
            self.loaded[name] = Unit(name, self.dump(path)) if path else None
        return self.loaded[name]

    def dump(self, path):
        data = open(path, "rb").read()
        key = hashlib.sha256(data).hexdigest()[:24]
        cached = os.path.join(self.cache, key + ".json")
        if os.path.isfile(cached):
            return json.load(open(cached))
        r = subprocess.run([self.ppudump, "-Fj", path], capture_output=True, text=True)
        # ppudump writes NaN and Inf as bare words, which JSON does not have.
        text = re.sub(r":(\s*)[-+]?(Nan|Inf)\b", r":\1null", r.stdout)
        try:
            j = json.loads(text)[0]
        except (ValueError, IndexError):
            die("ppudump failed on %s: %s" % (path, r.stderr.strip()[:200]))
        os.makedirs(self.cache, exist_ok=True)
        with open(cached + ".tmp", "w") as f:
            json.dump(j, f)
        os.replace(cached + ".tmp", cached)
        return j


class Unit:
    def __init__(self, name, j):
        self.name = name
        self.title = j["Name"]
        self.refunits = [u.lower() for u in j.get("Units", [])]
        self.top = j.get("Interface", [])
        self.defs = {}      # def id -> def
        self.owner = {}     # def id -> the def of the class or record it is nested in
        self.byname = {}    # lower name -> [top level entries]
        self.enumof = {}    # lower enum element name -> enum def
        for e in self.top:
            self.index(e, None)
            if e.get("Name") and not e["Name"].startswith("$"):
                self.byname.setdefault(e["Name"].lower(), []).append(e)
            if e.get("Type") == "enum":
                for el in e.get("Elements", []):
                    self.enumof[el["Name"].lower()] = e

    def index(self, e, owner):
        if isinstance(e, dict):
            if "Id" in e and e.get("Type") and e["Type"] not in ("proc", "param", "field", "var", "prop", "const",
                                                                 "type"):
                self.defs.setdefault(e["Id"], e)
                if owner is not None:
                    self.owner[e["Id"]] = owner
            elif e.get("Type") == "proc" and "Id" in e:
                self.defs.setdefault(e["Id"], e)
            sub = e if e.get("Type") in ("obj", "rec") else owner
            for k, v in e.items():
                if k in ("Fields", "Params", "Elements") or isinstance(v, (dict, list)) and k not in ("Pos",):
                    self.index(v, sub if k == "Fields" else owner)
        elif isinstance(e, list):
            for v in e:
                self.index(v, owner)


# ---------------------------------------------------------------- generator

def is_named(d):
    return bool(d.get("Name")) and not d["Name"].startswith("$")


class Gen:
    def __init__(self, units, idents):
        self.units = units
        self.idents = idents
        self.want = {}          # unit name -> set of top level lower names
        self.queue = []
        self.seen = set()       # (unit, def) already walked

    # -- references

    def deref(self, unit, ref):
        """(unit, def) for a {Unit, Id} reference made inside unit."""
        if ref is None:
            return None, None
        if "Unit" in ref:
            u = self.units.get(unit.refunits[ref["Unit"]])
        else:
            u = unit
        if u is None or "Id" not in ref:
            return u, None
        return u, u.defs.get(ref["Id"])

    def need(self, u, name):
        name = name.lower()
        s = self.want.setdefault(u.name, set())
        if name not in s:
            s.add(name)
            self.queue.append((u, name))

    def need_ref(self, unit, ref):
        u, d = self.deref(unit, ref)
        if d is None:
            return
        if self.top_named(u, d):
            self.need(u, d["Name"])
        else:
            self.need_def(u, d)

    def top_named(self, u, d):
        return is_named(d) and d["Name"].lower() in u.byname and d.get("Id") not in u.owner

    def need_def(self, u, d):
        key = (u.name, id(d))
        if key in self.seen:
            return
        self.seen.add(key)
        t = d.get("Type")
        if t in ("ptr",):
            self.need_ref(u, d.get("Ptr"))
        elif t == "array":
            self.need_ref(u, d.get("ElType"))
        elif t == "set":
            self.need_ref(u, d.get("ElType"))
        elif t == "classref":
            self.need_ref(u, d.get("Ref"))
        elif t in ("proctype", "proc"):
            self.need_ref(u, d.get("RetType"))
            for p in d.get("Params", []):
                if p.get("Type") == "param":
                    self.need_ref(u, p.get("VarType"))
        elif t == "rec":
            for f in d.get("Fields", []):
                if f.get("Type") == "field":
                    self.need_ref(u, f.get("VarType"))
        elif t == "obj":
            self.need_ref(u, d.get("Ancestor"))
            for m in self.members(u, d):
                self.need_member(u, m)
        elif t == "enum":
            pass

    def need_member(self, u, m):
        t = m.get("Type")
        if t in ("field", "var"):
            self.need_ref(u, m.get("VarType"))
        elif t == "proc":
            self.need_def(u, m)
        elif t == "prop":
            self.need_ref(u, m.get("PropType"))
            for p in m.get("Params", []) or []:
                self.need_ref(u, p.get("VarType"))

    def members(self, u, d):
        """The members of a class written in the stub: those named in the sources, the default property (L[I] does not
        name it), and the accessors they need."""
        fields = d.get("Fields", [])
        keep = []
        keepsym, keepid = set(), set()
        for m in fields:
            if m.get("Type") == "prop" and (m["Name"].lower() in self.idents or "default" in m.get("Options", [])):
                for acc in (m.get("Getter"), m.get("Setter")):
                    if acc:
                        keepsym.add(acc.get("SymId"))
                        keepid.add(acc.get("Id"))
        for m in fields:
            t = m.get("Type")
            if t not in ("field", "var", "proc", "prop") or not is_named(m):
                continue
            if t == "proc" and "operator" in m.get("Options", []):
                continue
            if (m["Name"].lower() in self.idents or m.get("SymId") in keepsym and t in ("field", "var")
                    or t == "prop" and "default" in m.get("Options", [])
                    or m.get("Id") in keepid and t == "proc"
                    or m["Name"].lower() in ("create", "destroy")
                    or m["Name"].lower() in IUNKNOWN and t == "proc"):
                keep.append(m)
        return keep

    # -- closure

    def run(self, seeds):
        for uname in seeds:
            u = self.units.get(uname)
            if u is None:
                continue
            self.want.setdefault(u.name, set())
            for name in u.byname:
                if name in self.idents or name in ALWAYS.get(u.name, ()):
                    self.need(u, name)
            for name, enum in u.enumof.items():
                if name in self.idents and is_named(enum):
                    self.need(u, enum["Name"])
        while self.queue:
            u, name = self.queue.pop()
            for e in u.byname.get(name, []):
                self.need_entry(u, e)

    def need_entry(self, u, e):
        t = e.get("Type")
        if t == "type":
            self.need_ref(u, e.get("Ref"))
        elif t == "const":
            self.need_ref(u, e.get("TypeRef"))
        elif t in ("var",):
            self.need_ref(u, e.get("VarType"))
        elif t == "prop":
            self.need_ref(u, e.get("PropType"))
        else:
            self.need_def(u, e)

    # -- writing types

    def tname(self, unit, ref, ctx=None):
        """The text of a type reference."""
        u, d = self.deref(unit, ref)
        if d is not None and d.get("Type") == "file" and d.get("FileType", "").lower() == "text":
            return "Text"
        if d is None or d.get("Type") == "file":
            return None     # fcl-passrc 3.2.2 has no typed or untyped files: a declaration that needs one is left out
        if self.top_named(u, d):
            if u.name != unit.name and u.name not in ("system", "objpas") and d["Name"].lower() not in BUILTIN:
                return "%s.%s" % (u.title, d["Name"])
            return d["Name"]
        if is_named(d) and d.get("Type") in ("ord", "float", "string", "variant"):
            return d["Name"]
        return self.texpr(u, d, ctx)

    def texpr(self, u, d, ctx=None):
        t = d.get("Type")
        if t == "ptr":
            pu, pd = self.deref(u, d.get("Ptr"))
            if pd is None or pd.get("OrdType") == "void":
                return "Pointer"
            n = self.tname(u, d.get("Ptr"))
            return "^%s" % n if n and re.fullmatch(r"[\w.]+", n) else "Pointer"
        if t == "array":
            el = self.tname(u, d.get("ElType"))
            if el is None:
                return None
            if "dynamic" in d.get("Options", []) or ctx == "param" and d.get("High") == -1:
                return "array of %s" % ("const" if el == "TVarRec" and ctx == "param" else el)
            return "array[%d..%d] of %s" % (d.get("Low", 0), d.get("High", 0), el)
        if t == "set":
            el = self.tname(u, d.get("ElType"))
            return "set of %s" % el if el else None
        if t == "classref":
            n = self.tname(u, d.get("Ref"))
            return "class of %s" % n if n else None
        if t == "proctype":
            # fcl-passrc takes a procedure type only in a type declaration; elsewhere it stands as Pointer.
            return self.signature(u, d, None, ctx="type") if ctx == "decl" else "Pointer"
        if t == "enum":
            return self.enumtext(d)
        if t == "string":
            return {"short": "String[%d]" % d.get("Len", 255), "ansi": "AnsiString", "wide": "WideString",
                    "unicode": "UnicodeString"}.get(d.get("StrType"), "String")
        if t == "ord":
            if d.get("OrdType") in ("bool", "pasbool"):
                return "Boolean"
            return "%d..%d" % (d.get("Low", 0), d.get("High", 0))
        if t == "float":
            return {"single": "Single", "double": "Double", "extended": "Extended", "comp": "Comp",
                    "currency": "Currency"}.get(d.get("FloatType"), "Double")
        if t in ("variant",):
            return "Variant"
        if t == "obj" and is_named(d):
            return d["Name"]
        if t == "rec" and is_named(d):
            return d["Name"]
        return None

    def enumtext(self, d):
        els, nxt = [], d.get("Low", 0)
        for el in d.get("Elements", []):
            v = el.get("Value", nxt)
            els.append(el["Name"] if v == nxt else "%s = %d" % (el["Name"], v))
            nxt = v + 1
        return "(%s)" % ", ".join(els)

    def params(self, u, d):
        out = []
        for p in d.get("Params", []):
            if p.get("Type") != "param" or not is_named(p) or p["Name"].startswith("$"):
                continue
            pu, pd = self.deref(u, p.get("VarType"))
            spez = p.get("Spez")
            name = p["Name"]
            if name.lower() in KEYWORDS:
                name = "&" + name
            if pd is not None and pd.get("Type") == "formal":
                out.append("%s %s" % (spez or "var", name))
                continue
            tn = self.tname(u, p.get("VarType"), ctx="param")
            if tn is None:
                return None
            s = "%s%s: %s" % (spez + " " if spez else "", name, tn)
            dv = self.constval(u, p.get("Default"), p.get("VarType"))
            if p.get("Default") is not None and dv is not None:
                s += " = " + dv
            out.append(s)
        return "; ".join(out)

    def signature(self, u, d, name, ctx=None, owner=None):
        opts = d.get("Options", [])
        ps = self.params(u, d)
        if ps is None:
            return None
        if "constructor" in opts:
            kind = "constructor"
        elif "destructor" in opts:
            kind = "destructor"
        elif "function" in opts or "procedure" not in opts and not self.isvoid(u, d.get("RetType")):
            kind = "function"
        else:
            kind = "procedure"
        head = kind + (" " + name if name else "")
        if ps:
            head += "(%s)" % ps
        if kind == "function":
            r = self.tname(u, d.get("RetType"))
            if r is None:
                return None
            head += ": " + r
        if ctx == "type" and d.get("MethodPtr"):
            head += " of object"
        if "classmethod" in opts and ctx != "type" and kind not in ("constructor", "destructor"):
            head = "class " + head
        return head

    def isvoid(self, u, ref):
        _, d = self.deref(u, ref)
        return d is None or d.get("OrdType") == "void"

    def constval(self, u, c, typeref=None):
        if c is None:
            return None
        vt, v = c.get("ValType"), c.get("Value")
        tu, td = self.deref(u, c.get("TypeRef") or typeref)
        if vt == "int":
            if td is not None and td.get("Type") == "ord" and td.get("OrdType") in ("bool", "pasbool"):
                return "True" if v else "False"
            if td is not None and td.get("Type") == "ord" and td.get("OrdType") in ("char", "uchar", "widechar"):
                return "#%d" % v
            if td is not None and td.get("Type") == "ptr":
                return "nil" if v == 0 else "PTRCONST"
            if td is not None and td.get("Type") == "enum":
                for el in td.get("Elements", []):
                    if el.get("Value") == v:
                        return el["Name"]
            return str(v)
        if vt == "string":
            return "'" + str(v).replace("'", "''") + "'"
        if vt == "float":
            return None if v is None else repr(float(v))
        if vt == "pointer":
            return "nil" if not v else "Pointer(%s)" % v
        return None

    # -- writing a unit

    def write_unit(self, u, out):
        p = self.parts(u)
        if u.name == "system" and self.units.get("objpas") is not None:
            # objfpc mode sees System through objpas (Integer = LongInt, MaxInt, ...): one stub holds both.
            o = self.parts(self.units.get("objpas"))
            over = {n.lower() for n in o["names"]}
            for k in ("types", "consts", "vars", "procs"):
                p[k] = [x for x in p[k] if self.declname(x) not in over] + o[k]
            p["classes"] += o["classes"]
            p["bodies"] += o["bodies"]
            p["uses"] = sorted(set(p["uses"]) | set(o["uses"]) - {"objpas"}, key=str.lower)
        types = p["types"]
        uses = p["uses"]
        consts, vars_, procs, bodies, classes = p["consts"], p["vars"], p["procs"], p["bodies"], p["classes"]
        w = []
        w.append("{ Generated by tools/bpvet/resolver/genstubs.py from %s.ppu: a declaration stub for the typed"
                 " bpvet. }" % u.name)
        w.append("unit %s;" % u.title)
        w.append("{$mode objfpc}{$H+}{$modeswitch advancedrecords}")
        w.append("interface")
        if uses:
            w.append("uses %s;" % ", ".join(uses))
        generics = GENERICS.get(u.name, [])
        if types or generics:
            w.append("type")
            w.extend("  " + g for g in generics)
            for c in classes:
                w.append("  %s = class;" % c)
            for _, tx in types:
                w.extend("  " + l for l in tx.split("\n"))
        if consts:
            w.append("const")
            w.extend("  " + c for c in consts)
        if vars_:
            w.append("var")
            w.extend("  " + v for v in vars_)
        w.extend(procs)
        if procs and not (types or consts or vars_):
            pass
        w.append("implementation")
        w.extend(bodies)
        w.append("end.")
        text = "\n".join(w) + "\n"
        # A forward class declaration of an interface is written as an interface.
        for _, tx in types:
            m = re.match(r"(\w+) = interface", tx)
            if m:
                text = text.replace("  %s = class;\n" % m.group(1), "  %s = interface;\n" % m.group(1), 1)
        with open(os.path.join(out, u.name + ".pp"), "w") as f:
            f.write(text)

    def parts(self, u):
        want = self.want.get(u.name, set())
        types, consts, vars_, procs, bodies = [], [], [], [], []
        classes = []
        done = set()
        for name in sorted(want):
            for e in u.byname.get(name, []):
                t = e.get("Type")
                key = (t, e.get("Id"), name)
                if key in done:
                    continue
                done.add(key)
                if u.name in ("system", "objpas") and (name in BUILTIN or name in ("true", "false")):
                    continue
                if t == "type":
                    tn = self.tname(u, e.get("Ref"))
                    if tn and tn.lower() != name:
                        types.append((e, "%s = %s;" % (e["Name"], tn)))
                elif t == "const":
                    v = self.constval(u, e)
                    if v == "PTRCONST":
                        # fcl-passrc 3.2.2 does not evaluate Pointer(-1): a typed constant has the same type
                        consts.append("%s: Pointer = nil;" % e["Name"])
                    elif v is not None:
                        consts.append("%s = %s;" % (e["Name"], v))
                elif t == "var":
                    tn = self.tname(u, e.get("VarType"))
                    if tn:
                        vars_.append("%s: %s;" % (e["Name"], tn))
                elif t == "proc":
                    if "operator" in e.get("Options", []):
                        continue
                    s = self.signature(u, e, e["Name"])
                    if s and name not in MAGIC:
                        procs.append("%s; overload; external;" % s)
                elif t == "obj":
                    text = self.classtext(u, e, bodies)
                    if text:
                        classes.append(e["Name"])
                        types.append((e, text))
                elif t == "rec":
                    types.append((e, self.rectext(u, e)))
                elif t in ("ord", "float", "string", "variant"):
                    if name not in BUILTIN and not e["Name"].startswith("$"):
                        tx = self.texpr(u, e)
                        if tx:
                            types.append((e, "%s = %s;" % (e["Name"], tx)))
                elif t in ("ptr", "array", "set", "classref", "proctype", "enum"):
                    tx = self.texpr(u, e, "decl")
                    if tx:
                        types.append((e, "%s = %s;" % (e["Name"], tx)))
        types = self.order(u, types)
        procs = self.prune(procs)
        uses = sorted({self.units.get(n).title for n in self.ref_units(u)} - {u.title, "System", "objpas"},
                      key=str.lower)
        return {"types": types, "consts": consts, "vars": vars_, "procs": procs, "bodies": bodies,
                "classes": classes, "uses": uses, "names": list(want)}

    def prune(self, procs):
        groups = {}
        for p in procs:
            groups.setdefault(self.declname(p), []).append(p)
        out = []
        for p in procs:
            g = groups[self.declname(p)]
            plain = [q for q in g if not OTHER_STRINGS.search(q)]
            if plain and p not in plain:
                continue
            out.append(p)
        return out

    @staticmethod
    def declname(x):
        text = x[1] if isinstance(x, tuple) else x
        m = re.match(r"\s*(?:class\s+)?(?:function|procedure)?\s*&?(\w+)", text)
        return m.group(1).lower() if m else ""

    def ref_units(self, u):
        names = set()

        def walk(x):
            if isinstance(x, dict):
                if "Unit" in x and isinstance(x["Unit"], int) and x["Unit"] < len(u.refunits):
                    names.add(u.refunits[x["Unit"]])
                for k, v in x.items():
                    if k != "Pos":
                        walk(v)
            elif isinstance(x, list):
                for v in x:
                    walk(v)
        for name in self.want.get(u.name, ()):
            walk(u.byname.get(name, []))
        return {n for n in names if self.units.get(n) is not None}

    def rectext(self, u, d):
        lines = ["%s = record" % d["Name"]]
        for f in d.get("Fields", []):
            if f.get("Type") == "field" and is_named(f):
                tn = self.tname(u, f.get("VarType"))
                if tn:
                    lines.append("  %s: %s;" % (self.ident(f["Name"]), tn))
        lines.append("end;")
        return "\n".join(lines)

    def ident(self, n):
        return "&" + n if n.lower() in KEYWORDS else n

    def classtext(self, u, d, bodies):
        kind = d.get("ObjType", "class")
        if kind not in ("class", "interface", "object", "dispinterface"):
            return None
        anc = self.tname(u, d.get("Ancestor")) if d.get("Ancestor") else None
        head = "%s = %s" % (d["Name"], "interface" if kind == "dispinterface" else kind)
        intf = IMPLEMENTS.get(d["Name"].lower())
        if anc or intf:
            head += "(%s)" % ", ".join(x for x in (anc or "TObject", intf) if x)
        lines = [head]
        if kind == "interface" and d.get("IID"):
            lines.append("  ['%s']" % d["IID"])
        if kind != "interface":
            lines.append("public")
        members = self.members(u, d)
        fieldsyms = {m.get("SymId"): m["Name"] for m in d.get("Fields", []) if m.get("Type") in ("field", "var")
                     and is_named(m)}
        procids = {m.get("Id"): m["Name"] for m in d.get("Fields", []) if m.get("Type") == "proc" and is_named(m)}
        # A property read or written by a class method is a class property, and its accessors are static (as FPC
        # requires); ppudump writes neither, only "classmethod" on the accessor (TEncoding.ASCII, GetASCII).
        classprocs = {m.get("Id") for m in d.get("Fields", []) if m.get("Type") == "proc"
                      and "classmethod" in m.get("Options", [])}
        classaccs = {a.get("Id") for m in members if m.get("Type") == "prop"
                     for a in (m.get("Getter"), m.get("Setter")) if a and a.get("Id") in classprocs}
        for m in members:
            if m.get("Type") in ("field", "var") and kind != "interface":
                tn = self.tname(u, m.get("VarType"))
                if tn:
                    lines.append("  %s: %s;" % (self.ident(m["Name"]), tn))
        for m in members:
            if m.get("Type") == "proc":
                s = self.signature(u, m, self.ident(m["Name"]), owner=d)
                if not s:
                    continue
                opts = m.get("Options", [])
                mods = ["overload"]
                if "virtual" in opts and kind != "interface":
                    mods.append("override" if "overriding" in opts else "virtual")
                if "abstract" in opts and "overriding" not in opts and kind != "interface":
                    mods.append("abstract")
                if m.get("Id") in classaccs:
                    mods.append("static")
                lines.append("  %s; %s;" % (s, "; ".join(mods)))
                if kind != "interface" and "abstract" not in opts:
                    q = self.signature(u, m, "%s.%s" % (d["Name"], self.ident(m["Name"])), owner=d)
                    bodies.append("%s; begin end;" % q)
        for m in members:
            if m.get("Type") == "prop":
                tn = self.tname(u, m.get("PropType"))
                if not tn:
                    continue
                ps = self.params(u, m) if m.get("Params") else ""
                if ps is None:
                    continue
                cls = any(a and a.get("Id") in classaccs for a in (m.get("Getter"), m.get("Setter")))
                s = "  %sproperty %s%s: %s" % ("class " if cls else "", self.ident(m["Name"]), "[%s]" % ps if ps else "",
                                              tn)
                for word, acc in (("read", m.get("Getter")), ("write", m.get("Setter"))):
                    if acc:
                        n = fieldsyms.get(acc.get("SymId")) or procids.get(acc.get("Id"))
                        if n:
                            s += " %s %s" % (word, n)
                if " read " not in s and " write " not in s:
                    continue
                s += ";"
                if "default" in m.get("Options", []):
                    s += " default;"
                lines.append(s)
        lines.append("end;")
        return "\n".join(lines)

    def order(self, u, types):
        """Types in an order where each is declared before a use that needs it (pointers and classes may wait)."""
        names = {e["Name"].lower(): (e, tx) for e, tx in types}
        seen, out = set(), []

        def deps(e):
            r = set()

            def walk(x, via_ptr):
                if isinstance(x, dict):
                    if x.get("Type") in ("ptr", "classref"):
                        via_ptr = True
                    if "Id" in x and "Type" not in x and not via_ptr and "Unit" not in x:
                        dd = u.defs.get(x["Id"])
                        if dd is not None and is_named(dd) and dd.get("Type") not in ("obj",):
                            r.add(dd["Name"].lower())
                    for k, v in x.items():
                        if k not in ("Pos",):
                            walk(v, via_ptr)
                elif isinstance(x, list):
                    for v in x:
                        walk(v, via_ptr)
            walk({k: v for k, v in e.items() if k != "Id"}, False)
            if e.get("Type") == "obj" and e.get("Ancestor") and "Unit" not in e["Ancestor"]:
                ad = u.defs.get(e["Ancestor"]["Id"])
                if ad is not None and is_named(ad):
                    r.add(ad["Name"].lower())
            return r

        def visit(n, stack):
            if n in seen or n not in names:
                return
            if n in stack:
                return
            stack.add(n)
            for dn in deps(names[n][0]):
                if dn != n:
                    visit(dn, stack)
            stack.discard(n)
            seen.add(n)
            out.append(names[n])
        for e, _ in types:
            visit(e["Name"].lower(), set())
        return out


def main():
    if len(sys.argv) < 3:
        die("usage: genstubs.py OUT SRCDIR...")
    out = sys.argv[1]
    idents, uses = scan_sources(sys.argv[2:])
    units = Units()
    rtl = sorted(n for n in uses | {"system", "objpas"} if units.get(n) is not None)
    g = Gen(units, idents)
    g.run(rtl)
    os.makedirs(out, exist_ok=True)
    written = []
    todo = sorted(set(g.want) | set(rtl))  # a used unit is written even when none of its symbols is used
    while todo:
        name = todo.pop(0)
        u = units.get(name)
        if u is None or name == "objpas" or name in written:
            continue
        g.write_unit(u, out)
        written.append(name)
        # the units its stub uses are written too (a unit named only through a type of another one)
        with open(os.path.join(out, u.name + ".pp"), encoding="utf-8") as f:
            m = re.search(r"^uses\s+([^;]*);", f.read(), re.M)
        if m:
            todo += [n.strip().lower() for n in m.group(1).split(",") if n.strip().lower() not in written]
    print("genstubs: %d units, %d symbols: %s" % (len(written), sum(len(v) for v in g.want.values()),
                                                   " ".join(written)))


if __name__ == "__main__":
    main()
