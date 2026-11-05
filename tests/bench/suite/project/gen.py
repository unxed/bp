# SPDX-License-Identifier: MIT
"""The project of tests/bench/project.sh (safe/SPEC.md §25.5): the same program of many files in Bp, C, Go, Rust and
Goose, for the time of a rebuild after an edit of one file.

usage: python3 gen.py OUT [--modules N] [--funcs N] [--langs bp,c,go,rust,goose] [--salt N | --edit N]
  (default 20 modules of 40 functions, every language); prints the line the program prints

Module m00 holds base(); every other module mNN uses it and holds FUNCS functions fNN_II(x) of unsigned 64-bit
arithmetic modulo P = 1000000007, which never overflows, so a build with overflow checks runs it too; the main
program calls each function once and prints the sum. Each language gets its usual layout: Bp units and a program in
one directory; C a .c and a .h per module, the headers of the C library included as a real module would, and a
Makefile; Go a package per directory of one module; Rust one crate of a module per file (cargo); Goose files that the
root file imports. --salt N adds N in the body of the last function of the last module, which nothing but the main
program calls; --edit N does the same and writes only the source of that module (not its header): the edit of one
file that a rebuild then compiles.
"""
import os
import sys

P = 1000000007

ONLY = None  # with --edit: the name of the one module whose source is written


def name(k):
    return "m%02d" % k


def fname(k, i):
    return "f%02d_%02d" % (k, i)


def add_of(k, i, mods, funcs, salt):
    return k * 100 + i + (salt if (k, i) == (mods - 1, funcs - 1) else 0)


def expected(mods, funcs, salt):
    s = 0
    for k in range(1, mods):
        for i in range(funcs):
            r = s
            for j in range(4):
                r = (r * 31 + add_of(k, i, mods, funcs, salt) + j * 7 + 1) % P
            s = (s + r) % P
    return s


def write(path, text):
    if ONLY is not None:
        base, ext = os.path.splitext(os.path.basename(path))
        if base != ONLY or ext not in (".pas", ".c", ".go", ".rs", ".goose"):
            return
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)


def calls(mods, funcs):
    return [(k, i) for k in range(1, mods) for i in range(funcs)]


def gen_bp(out, mods, funcs, salt):
    d = os.path.join(out, "bp")
    write(os.path.join(d, "m00.pas"),
          "unit m00;\n\n{$mode objfpc}{$H+}\n\ninterface\n\nuses\n  BP;\n\n"
          "function Base(const J: QWord): QWord;\n\nimplementation\n\n"
          "function Base(const J: QWord): QWord;\nbegin\n  Result := J * 7 + 1;\nend;\n\nend.\n")
    for k in range(1, mods):
        decl = "".join("function F%02d_%02d(const X: QWord): QWord;\n" % (k, i) for i in range(funcs))
        body = "".join(
            "function F%02d_%02d(const X: QWord): QWord;\nvar\n  J: Integer;\nbegin\n  Result := X;\n"
            "  for J := 0 to 3 do\n    Result := (Result * 31 + %d + Base(QWord(J))) mod %d;\nend;\n\n"
            % (k, i, add_of(k, i, mods, funcs, salt), P) for i in range(funcs))
        write(os.path.join(d, name(k) + ".pas"),
              "unit %s;\n\n{$mode objfpc}{$H+}\n\ninterface\n\nuses\n  m00, BP;\n\n%s\nimplementation\n\n%send.\n"
              % (name(k), decl, body))
    units = "".join("  %s,\n" % name(k) for k in range(1, mods))
    body = "".join("  S := (S + F%02d_%02d(S)) mod %d;\n" % (k, i, P) for k, i in calls(mods, funcs))
    write(os.path.join(d, "main.pas"),
          "program main;\n\n{$mode objfpc}{$H+}\n\nuses\n%s  BP;\n\nprocedure Run;\nvar\n  S: QWord;\nbegin\n"
          "  S := 0;\n%s  WriteLn(S);\nend;\n\nbegin\n  Run;\nend.\n" % (units, body))


def gen_c(out, mods, funcs, salt):
    d = os.path.join(out, "c")
    inc = "#include <stdint.h>\n#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n"
    write(os.path.join(d, "m00.h"), "#ifndef M00_H\n#define M00_H\n#include <stdint.h>\nuint64_t base(uint64_t j);\n#endif\n")
    write(os.path.join(d, "m00.c"), inc + '#include "m00.h"\n\nuint64_t base(uint64_t j) { return j * 7 + 1; }\n')
    for k in range(1, mods):
        n = name(k)
        write(os.path.join(d, n + ".h"),
              "#ifndef %s_H\n#define %s_H\n#include <stdint.h>\n%s#endif\n"
              % (n.upper(), n.upper(), "".join("uint64_t %s(uint64_t x);\n" % fname(k, i) for i in range(funcs))))
        write(os.path.join(d, n + ".c"),
              inc + '#include "m00.h"\n#include "%s.h"\n\n' % n + "".join(
                  "uint64_t %s(uint64_t x) {\n    uint64_t r = x;\n    for (int j = 0; j < 4; j++)\n"
                  "        r = (r * 31 + %d + base((uint64_t)j)) %% %d;\n    return r;\n}\n\n"
                  % (fname(k, i), add_of(k, i, mods, funcs, salt), P) for i in range(funcs)))
    write(os.path.join(d, "main.c"),
          inc + "".join('#include "%s.h"\n' % name(k) for k in range(1, mods)) +
          "\nint main(void) {\n    uint64_t s = 0;\n" +
          "".join("    s = (s + %s(s)) %% %d;\n" % (fname(k, i), P) for k, i in calls(mods, funcs)) +
          '    printf("%llu\\n", (unsigned long long)s);\n    return 0;\n}\n')
    objs = " ".join(name(k) + ".o" for k in range(mods)) + " main.o"
    rules = "".join("%s.o: %s.c %s.h m00.h\n" % (name(k), name(k), name(k)) for k in range(mods))
    rules += "main.o: main.c " + " ".join(name(k) + ".h" for k in range(mods)) + "\n"
    write(os.path.join(d, "Makefile"), "CFLAGS = -O2\nmain: %s\n\t$(CC) -o main %s\n%s" % (objs, objs, rules))


def gen_go(out, mods, funcs, salt):
    d = os.path.join(out, "go")
    write(os.path.join(d, "go.mod"), "module proj\n\ngo 1.22\n")
    write(os.path.join(d, "m00", "m00.go"), "package m00\n\nfunc Base(j uint64) uint64 { return j*7 + 1 }\n")
    for k in range(1, mods):
        write(os.path.join(d, name(k), name(k) + ".go"),
              'package %s\n\nimport "proj/m00"\n\n' % name(k) + "".join(
                  "func F%02d_%02d(x uint64) uint64 {\n\tr := x\n\tfor j := 0; j < 4; j++ {\n"
                  "\t\tr = (r*31 + %d + m00.Base(uint64(j))) %% %d\n\t}\n\treturn r\n}\n\n"
                  % (k, i, add_of(k, i, mods, funcs, salt), P) for i in range(funcs)))
    write(os.path.join(d, "main.go"),
          'package main\n\nimport (\n\t"fmt"\n' + "".join('\t"proj/%s"\n' % name(k) for k in range(1, mods)) +
          ")\n\nfunc main() {\n\tvar s uint64\n" +
          "".join("\ts = (s + %s.F%02d_%02d(s)) %% %d\n" % (name(k), k, i, P) for k, i in calls(mods, funcs)) +
          "\tfmt.Println(s)\n}\n")


def gen_rust(out, mods, funcs, salt):
    d = os.path.join(out, "rust")
    write(os.path.join(d, "Cargo.toml"), '[package]\nname = "proj"\nversion = "0.1.0"\nedition = "2021"\n\n[workspace]\n')
    write(os.path.join(d, "src", "m00.rs"), "pub fn base(j: u64) -> u64 {\n    j * 7 + 1\n}\n")
    for k in range(1, mods):
        write(os.path.join(d, "src", name(k) + ".rs"),
              "use crate::m00::base;\n\n" + "".join(
                  "pub fn %s(x: u64) -> u64 {\n    let mut r = x;\n    for j in 0..4u64 {\n"
                  "        r = (r * 31 + %d + base(j)) %% %d;\n    }\n    r\n}\n\n"
                  % (fname(k, i), add_of(k, i, mods, funcs, salt), P) for i in range(funcs)))
    write(os.path.join(d, "src", "main.rs"),
          "".join("mod %s;\n" % name(k) for k in range(mods)) + "\nfn main() {\n    let mut s: u64 = 0;\n" +
          "".join("    s = (s + %s::%s(s)) %% %d;\n" % (name(k), fname(k, i), P) for k, i in calls(mods, funcs)) +
          '    println!("{}", s);\n}\n')


def gen_goose(out, mods, funcs, salt):
    d = os.path.join(out, "goose")
    write(os.path.join(d, "m00.goose"), "fn base(j: u64) -> u64 { return j * 7 + 1; }\n")
    for k in range(1, mods):
        write(os.path.join(d, name(k) + ".goose"),
              "import m00;\n\n" + "".join(
                  "fn %s(x: u64) -> u64 {\n    var r = x;\n    for j in 4 {\n"
                  "        r = (r * 31 + %d + base(j as u64)) %% %d;\n    }\n    return r;\n}\n\n"
                  % (fname(k, i), add_of(k, i, mods, funcs, salt), P) for i in range(funcs)))
    write(os.path.join(d, "main.goose"),
          "import std;\n" + "".join("import %s;\n" % name(k) for k in range(1, mods)) +
          "\nfn main() {\n    var s: u64 = 0;\n" +
          "".join("    s = (s + %s(s)) %% %d;\n" % (fname(k, i), P) for k, i in calls(mods, funcs)) +
          "    print(s);\n}\n")


GENS = {"bp": gen_bp, "c": gen_c, "go": gen_go, "rust": gen_rust, "goose": gen_goose}


def main():
    global ONLY
    args = sys.argv[1:]
    out = args.pop(0)
    mods, funcs, salt, langs = 20, 40, 0, list(GENS)
    while args:
        opt, val = args.pop(0), args.pop(0)
        if opt == "--modules":
            mods = int(val)
        elif opt == "--funcs":
            funcs = int(val)
        elif opt == "--langs":
            langs = val.split(",")
        elif opt == "--salt":
            salt = int(val)
        elif opt == "--edit":
            salt = int(val)
            ONLY = name(mods - 1)
        else:
            sys.exit("gen.py: unknown option " + opt)
    for lang in langs:
        GENS[lang](out, mods, funcs, salt)
    print(expected(mods, funcs, salt))


if __name__ == "__main__":
    main()
