# Better Pascal (bp)

Free Pascal as one would want it by default: safe memory, UTF-8 everywhere, goroutines.
No FPC fork and no compiler options: a single unit `BP`.

```pascal
program Hello;
uses BP, SysUtils;   // BP goes FIRST in the main program (it installs the thread manager before SysUtils)
begin
  WriteLn('Hello, world 😀', CPLength('aё😀'));
end.
```

In all other units `BP` is listed **last** in `uses`: this way it shadows the dangerous primitives (`GetMem(...)` will not compile,
`System.GetMem` is explicitly unsafe). The compiler needs the path to the directory containing `bp.pas`: `fpc -Fu<path> -Fu<path>/safe -Fu<path>/ext`.

## Three parts of the repository

| Directory | Part | Depends on |
|---|---|---|
| [`safe/`](safe/README.md) | **Safe Pascal**: memory safety (ownership, slices, arena, defer, FFI, poisoning of the unsafe) | nothing |
| [`ext/`](ext/README.md) | **FPC extensions**: UTF-8 by default, goroutines and channels, thread manager | `safe/` (core) |
| [`fpide/`](fpide/README.md) | **fpide**: Free Pascal IDE on [tv3](https://github.com/unxed/tv3) | only `tv/` and an external `fpc` |

| File | What it is |
|---|---|
| `bp.pas` | `unit BP`: combines `safe/*.inc` and `ext/*.inc` into one unit (safe + UTF-8 + goroutines) |
| `safe/safe.pas` | `unit Safe`: the safe layer only, if you need nothing else |
| `tests/` | `tests/safe/` and `tests/ext/`; `tests/run.sh [safe\|ext\|all]` |
| `.github/workflows/` | `ci` (safe + ext, cross builds), `fpide`, `fpide-accept` |

License: MIT (`LICENSE`). The `fpide/` code is derived from the FPC IDE (GPL, see `fpide/README.md`); it is not present in `safe/` or `ext/`.

The repository is still called `sp`; renaming it to `bp` is up to the owner.
