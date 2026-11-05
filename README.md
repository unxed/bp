# Better Pascal (bp)

**The philosophy of Better Pascal:** the simplicity of development of Go with the performance and reliability of Rust.
Take the best of Go (memory safety, code that is simple to write and for a model to generate, build speed,
performance, goroutines, light dependencies) and replace the unpredictability of a collector with the determinism of
owners and regions, in a way that needs no lifetime annotations written by hand: everything is to be inferred.
Whether the reliability of Rust can be reached this way is an open question, and the study of its feasibility is one
of the goals of the project. The performance and the reliability of Rust are the goal the work moves towards, measured as it goes.

**Research questions.** Better Pascal is also research in programming languages. It tests these hypotheses:
1. **Memory safety without changing the compiler:** how far a library and a check before the build over the stock
   compiler can go.
2. **The reliability of Rust without lifetime annotations:** whether everything can be inferred without rejecting too
   many correct programs.
3. **The speed of C without annotations and without a collector:** whether there is a way besides the regions and root
   analysis of Goose: the choice of algorithm and memory in the library (the memory manager, vector kernels, string views).
4. **Several safe memory models in one language** (owners, regions, arenas, a collector): whether the choice helps a
   model pick the approach that fits a task, or harms, and one or two main styles should stay.

Each hypothesis is tested by measurements and tests: the table of guarantees (§8), the benchmarks (§25.2), findings
such as H20. A "no" is a result too.

> **Build with `tools/bp build`, not with `fpc` directly.** `bp build [--release] [fpc options] FILE.pas` checks the
> program (`bpvet --strict --typed`: ownership, regions, borrows) and calls `fpc` only when the check passes, so
> unsafe code is built only where it is declared (`// UNSAFE:`, `// borrow:`, `// root:`). The guarantees of Better
> Pascal are the guarantees of `bp build`; a cached check takes about 30 ms.
> `bp run FILE.pas [args]` runs it (a file with `#!/usr/bin/env -S bp run` is a script), `bp new NAME` starts a project.

**In numbers, against C, Rust, Go and Goose** (one machine, medians; the scripts and the verdicts:
`tests/bench/size.sh` and `safe/SPEC.md` §25.5, `tests/bench/compare.sh` and §25.2, the plan: unxed/bp#181):

| | Bp | C (gcc) | Rust | Go | Goose |
|---|---|---|---|---|---|
| Hello world, size | **288 KiB** (`bp build --release`, smart linking); static, no libc | 14 KiB dynamic, 690 KiB static | 354 KiB stripped, dynamic | 1203 KiB | 54 KiB, dynamic |
| Hello world, peak memory | **0.3 MiB** (with `-XX`), 0.7 MiB | 1.2 MiB dynamic, 0.6 MiB static | 1.8 MiB | 1.6 MiB | 1.5 MiB |
| Hello world, start | **587 us** (with `-XX`) | 732 us dynamic, 445 us static | 1019 us | 1496 us | 904 us |
| Rebuild of a program | 144 ms after an edit (the check and `fpc`) | 55 ms | 237 ms | 67 ms | 110 ms |
| Run time, 4 programs in like-for-like tiers (2026-11-05; §25.2) | 1.3–2.2x of C (the region of objects: 3.3x) | 1x | 1.07–1.97x | 1.10–2.14x | 0.90–1.28x |
| Toolchain | 282 MiB with all units; no C compiler | | 1.2 GiB, needs a C linker | 97 MiB | 28 MiB, compiles through gcc |

- **Ahead:** the memory of a program, the start (all but static C), the size among static binaries, one static file
  that runs on any Linux.
- **Reaching:**
  - the rebuild: on a small program the level of gcc (hello world after an edit: Bp 144 ms, gcc 66 ms, Go 204–230
    ms); on a project of many files the level of gcc and ahead of Go (20 files, 17 thousand lines, after an edit of
    one: Bp 248 ms, gcc 260 ms, Go 349 ms; a clean build: Bp 718 ms, the fastest, gcc 2.7 s, Go 6.9 s;
    `tests/bench/project.sh`);
  - the run time: the gap to C is not in the language (typed, compiled, no collector, the class of C) but in the
    optimizer of FPC (tickets upstream, #185; Bp stays on the releases of FPC and its usual back end) and the map and
    strings of BP; §25.2 splits it;
  - the memory manager of BP is on by default (`BP_HEAP=rtl` for the heap of the RTL); goroutines run M:N on a few
    carriers by default (`BP_MN=0` for one OS thread per task).
- **Accepted as the niche:** a dynamic binary over glibc is smaller, but runs only where that glibc is.

**How it compares** (built with `bp build`; measured 2026-11-04, details in unxed/bp#108 and `safe/SPEC.md` §20):

| | Rust | Go | Goose | Zig | Mojo |
|---|---|---|---|---|---|
| Memory safety | close: ownership, regions and borrows checked before every build | on par, and without a collector: memory is freed deterministically (regions, owners) | on par | better: Zig does not check a use after free at compile time | close |
| Convenience | better: no marks inside a unit, `bpvet --fix` writes them on the interface | close; the GC style is as simple | on par: regions per block and per iteration (`for R in Scope`) | better: the allocator is implicit (the current region) | close |
| Build speed | much better: ~30 ms check + `fpc` | on par | unknown | on par or better | likely better |
| Array iteration | on par (`for C in A.Chunks` is as fast as a plain array) | on par | on par | on par | on par |
| Ecosystem | comparable: every FPC package and Lazarus can be used as is, as unchecked units (like C libraries in Rust or Zig), and moved to the bp dialect step by step | comparable | larger | larger | larger |
| Data races | behind for now: Rust checks `Send`/`Sync` in the compiler; `bp build` checks task fields (S11), but a dynamic array, a `TShared` object or a global shared by goroutines is not checked yet (`safe/SPEC.md` §21.2 closes it) | better in kind: a prohibition before the build, not a detector at run time (`-race`), with the same open cases | behind until §21.2: Goose passes only flat values | better: Zig does not check races | unknown |
| Goroutines | behind in scale: goroutines run M:N on a few carriers by default (§21.3), thousands per GiB rather than millions (44 KiB each); a switch between goroutines 0.8 us | behind in scale, better in structure: a group waits for its tasks, the error of a task reaches `Wait` | unknown | unknown | unknown |
| Deploy | better: one static file without libc by default runs on any distribution (Rust links the glibc of the build machine unless a musl target is chosen) | on par: Go is static by default too | unknown | on par | unknown |
| C and the host | behind until `safe/SPEC.md` §23: today `-dSAFE_LIBC` ties the binary to the build glibc, as Rust does; the plan binds host libraries at run time by name, with no versioned import | better in kind: no C toolchain in the build (cgo needs one); behind in breadth until §23 | unknown | behind: Zig ships libc headers for many versions and `zig cc` | unknown |
| Standard library | larger: the FCL of FPC ships HTTP, JSON, XML, regular expressions, SQL, zip; Rust leaves them to crates | on par: the Go standard library is as broad | larger | larger: the Zig std is small and C libraries fill the gap | unknown |
| For a model | better: `safe/SPEC.md` §0 fits one screen, the marks are written by `bp fix` (§24.2), every finding names its fix; no lifetimes to write | on par: Go is as simple to write and has a far larger recent corpus | better: Goose has almost no corpus | better: Zig changes between releases | unknown |

The Lazarus LCL is not yet tested with `bp build`; the `TComponent` tree is an owner in the typed `bpvet`
(`TFoo.Create(AOwner)` and the published component fields of a form need no marks, `safe/SPEC.md` §21.4), checked on a
form-like unit with a stub of the hierarchy. The plan of concept v3 (one scope object, Send and Sync inferred,
goroutines M:N, the `TComponent` tree as an owner) and what is reused from which language: `safe/SPEC.md` §21.
What the tools still lack against `go`, `cargo` and `zig` (`bp run` and scripts, `--watch`, cross targets, tests with a leak
check, `// derive:`, a profiler, an editor server, a page in the browser): `safe/SPEC.md` §22.
The fresh look of concept v4 (one sentence for all lifetimes, marks of fact written by the machine, `BP` last in the program
file too, what FPC 3.2 already ships and the dialect had not used, the casts and the uninitialised variables that §8 missed):
`safe/SPEC.md` §24.

**Try it**: an HTTP/1.1 server on goroutines, with the scratch of each request in a region
([`examples/httpd/README.md`](examples/httpd/README.md)):

```sh
tools/bp build -Futools/spikes/region -FEout examples/httpd/httpd.pas
out/httpd 8080 &
curl 'localhost:8080/json?n=5'
```

On `/`, with `ab -k -c 64` on a 4 vCPU runner (2026-11-04), it serves 63917 requests per second; the same server in
Go 74685 and in Rust (the standard library, a thread per connection) 63758.

Free Pascal as one would want it by default: safe memory, UTF-8 everywhere, goroutines.
No FPC fork and no compiler options: a single unit `BP` gives all of it.

```pascal
program Hello;
uses BP;   // BP goes last in every uses; tools/bp build adds -FaBPThreads (the thread manager first)
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
| Vector kernels over arrays: `Axpy`, `Dot`, `Sum` ... (unit `BPVec`, SSE2 on x86_64) | `ext/` | no | a unit of its own |

`unit Safe` (`safe/safe.pas`) is the safe layer alone. `ext/fpc-utf8/` is a separate UTF-8-only variant for code that does
not use `BP` (a unit inserted with `-Fa`).

Linux builds are static and need no libc by default; `-dSAFE_LIBC` switches to libc (`cwstring`, `cthreads`), needed only for
FFI with C libraries. `-dSAFE_NO_UTF8` turns off the UTF-8 defaults. The specification: [`safe/SPEC.md`](safe/SPEC.md).

**Dependencies** ([`safe/SPEC.md` §15](safe/SPEC.md), Go modules with git as the registry): write `require
github.com/acme/json v1.4.0` into `deps.txt` next to the program, run `tools/bp get` (it writes `deps.lock` with the commit
of each version), then `tools/bp build FILE.pas` finds the units; `tools/bp vendor` copies them into `vendor/`. A library
is a git repository with a tag `vX.Y.Z` and a `deps.txt` with its `module` line; this repository is `github.com/unxed/bp`.

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
The Pascal examples of the documents are compiled and linted by `tools/doctest.py` in CI.

## Licences

`bp.pas`, `safe/`, `ext/`, `tests/`: MIT (`LICENSE`). `fpide/`: GPL (see `fpide/README.md`).

The repository is still called `sp`; renaming it to `bp` is up to the owner.
