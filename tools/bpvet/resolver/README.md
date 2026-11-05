# A patched resolver for the typed mode of `bpvet`

`bpvet` reads types with `PasResolver` of `fcl-passrc` (safe/SPEC.md §20, "Spike 1 result"). The resolver, the parser and
the tree of FPC 3.2.2 reject constructs that FPC itself accepts and that Better Pascal uses; `pastree.patch`,
`pparser.patch` and `pasresolver.patch` change them (each patch header says what and why). The repository keeps only the
patches: `get.sh OUT` takes the original files of FPC 3.2.2, checks their SHA-256, applies the patches and leaves the
result in `OUT`, from where `bpvet` is built (`-FuOUT -FiOUT`, `build.sh`).

Licence: the patch and the patched file are under the licence of `fcl-passrc`, the LGPL with the static linking exception
of Free Pascal (`COPYING.FPC` in the FPC sources). The exception allows linking them with the MIT code of `bpvet`; the
changed source is this patch applied to the published FPC file. The rest of `bpvet` stays MIT.

FPC main has most of the changes; the rest are offered upstream when `bpvet` moves to the next FPC release.

`genstubs.py OUT SRC...` writes the declaration stubs of the RTL that the typed mode reads (`bpvet --typed --rtl OUT`),
from `ppudump -Fj` of the installed units (Debian, Ubuntu: fp-utils); its header says how.

Items of `pasresolver.patch` that follow the rule of safe/SPEC.md §20 ("the resolver only resolves, FPC checks"), found
by programs built with `tools/bp build` (unxed/bp#146); each is a construct FPC accepts:

- `String` is `AnsiString` under `{$H+}` (`Char` is `AnsiChar`): `array of String` fits an open array of `AnsiString`, and
  a `String` variable fits a `var` or `out` `AnsiString` (`RunCommand`).
- `#13#10` is a string literal: `TPasResolver.IsCharLiteral` stops at a second `#` (it summed the digits to 1310 and
  took a `WideChar`), so `Pos(#13#10, S)` does not match the `Char` overload as well.
- `Insert` and `Delete` take a string variable; FPC has them as compiler procedures, so the stubs do not declare them.
- `S[1]` of a string variable goes to a `var` argument (`Stream.ReadBuffer(S[1], N)`).
- A procedure with the default calling convention fits a procedure type with a declared one: `{$calling cdecl}` is not
  read. `genstubs.py` also gives the procedure types of the RTL their calling convention (`signalhandler_t` is `cdecl`),
  and writes the default `[]` of a set parameter (`RunCommand(Exe, Args, S)`).

`bpvet` reads a file through `TFileStreamLineReader`: the text file of Pascal holds a name of 255 characters, so a longer
path (the cache of `bp run`) ended in an access violation.
