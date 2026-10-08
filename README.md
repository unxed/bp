# Better Pascal (bp)

Free Pascal as one would want it by default: safe memory, UTF-8 everywhere, goroutines.
No FPC fork and no compiler options: a single unit `BP` gives all of it.

```pascal
program Hello;
uses BP, SysUtils;   // BP goes FIRST in the program (it installs the thread manager before SysUtils)
begin
  WriteLn('Hello, world 😀', CPLength('aё😀'));
end.
```

In all other units `BP` is listed **last** in `uses`: this way it shadows the dangerous primitives (`GetMem(...)` does not
compile, `System.GetMem` is an explicit unsafe). The compiler needs the unit paths: `fpc -Fu<path> -Fu<path>/safe -Fu<path>/ext`,
where `<path>` is the directory of `bp.pas`.

## What `BP` gives

| Part | Layer | Unit `Safe` | Unit `BP` |
|---|---|---|---|
| `TOwned/TShared/TWeak/TSlice/TArena`, `TDefer`, leak counter (`SafeCheckNoLeaks`) | `safe/` | yes | yes |
| FFI: `TCResource` | `safe/` | yes | yes |
| Poisoned `GetMem/New/Dispose/Move/FillChar/FreeAndNil/Pointer/.Free` | `safe/` | yes | yes |
| UTF-8 by default, `CodePoints`, `CPLength` | `ext/` | no | yes |
| Goroutines: `TGroup/TTask`, `TChan<T>`, `Select` | `ext/` | no | yes |
| Thread manager without libc on Linux (`BPThreads`) | `ext/` | no | yes |

`unit Safe` (`safe/safe.pas`) is the safe layer alone. `ext/fpc-utf8/` is a separate UTF-8-only variant for code that does
not use `BP` (a unit inserted with `-Fa`).

Linux builds are static and need no libc by default; `-dSAFE_LIBC` switches to libc (`cwstring`, `cthreads`), needed only for
FFI with C libraries. `-dSAFE_NO_UTF8` turns off the UTF-8 defaults. The specification: [`safe/SPEC.md`](safe/SPEC.md).

## Layout

| Path | What it is | Depends on |
|---|---|---|
| `bp.pas` | `unit BP`: includes `safe/*.inc` and `ext/*.inc`, uses `ext/bpthreads.pas` | `safe/`, `ext/` |
| [`safe/`](safe/README.md) | **Safe Pascal**: memory safety (ownership, slices, arena, defer, FFI, poisoning of the unsafe) | nothing |
| [`ext/`](ext/README.md) | **FPC extensions**: UTF-8 by default, goroutines and channels, thread manager | `safe/` (core) |
| [`fpide/`](fpide/README.md) | **fpide**: the Free Pascal IDE on [tv3](https://github.com/unxed/tv3) | `fpide/tv/` (tv3), `fpide/tve/` (tve), an external `fpc`; not `BP` |
| `tests/` | `tests/safe/`, `tests/ext/`; `tests/run.sh [safe\|ext\|fpc-utf8\|all]` | |
| `.github/workflows/` | `ci` (all tests: portable and libc modes, other distributions, i386 and aarch64), `fpide`, `fpide-accept` | |

`tests/run.sh all` builds every test with no compiler options except the unit paths: the safe layer twice (with `Safe` and
with `BP`), the ext layer with `BP`, `ext/fpc-utf8`, and checks that `bp.pas` includes every file of `unit Safe`.

## Licences

`bp.pas`, `safe/`, `ext/`, `tests/`: MIT (`LICENSE`). `fpide/`: GPL (see `fpide/README.md`).

The repository is still called `sp`; renaming it to `bp` is up to the owner.
