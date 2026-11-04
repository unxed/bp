# Better Pascal (bp)

> **Build with `tools/bp build`, not with `fpc` directly.** `bp build [--release] [fpc options] FILE.pas` checks the
> program (`bpvet --strict --typed`: ownership, regions, borrows) and calls `fpc` only when the check passes, so
> unsafe code is built only where it is declared (`// UNSAFE:`, `// borrow:`, `// root:`). The guarantees of Better
> Pascal are the guarantees of `bp build`; a cached check takes about 30 ms.

**How it compares** (built with `bp build`; measured 2026-11-04, details in unxed/bp#108 and `safe/SPEC.md` §20):

| | Rust | Go | Goose | Zig | Mojo |
|---|---|---|---|---|---|
| Memory safety | close: ownership, regions and borrows checked before every build | on par, and without a collector: memory is freed deterministically (regions, owners) | on par | better: Zig does not check a use after free at compile time | close |
| Convenience | better: no marks inside a unit, `bpvet --fix` writes them on the interface | close; the GC style is as simple | on par: regions per block and per iteration (`for R in Scope`) | better: the allocator is implicit (the current region) | close |
| Build speed | much better: ~30 ms check + `fpc` | on par | unknown | on par or better | likely better |
| Array iteration | on par (`for C in A.Chunks` is as fast as a plain array) | on par | on par | on par | on par |
| Ecosystem | comparable: every FPC package and Lazarus can be used as is, as unchecked units (like C libraries in Rust or Zig), and moved to the bp dialect step by step | comparable | larger | larger | larger |
| Data races | behind for now: Rust checks `Send`/`Sync` in the compiler; `bp build` checks task fields (S11), but a dynamic array, a `TShared` object or a global shared by goroutines is not checked yet (`safe/SPEC.md` §21.2 closes it) | better in kind: a prohibition before the build, not a detector at run time (`-race`), with the same open cases | behind until §21.2: Goose passes only flat values | better: Zig does not check races | unknown |
| Goroutines | behind in scale: one task is one OS thread, thousands of them (async Rust runs millions; plan: M:N, §21.3) | behind in scale, better in structure: a group waits for its tasks, the error of a task reaches `Wait` | unknown | unknown | unknown |

The Lazarus LCL is not yet tested with `bp build`. The plan of concept v3 (one scope object, Send and Sync inferred,
goroutines M:N, the `TComponent` tree as an owner) and what is reused from which language: `safe/SPEC.md` §21.

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
