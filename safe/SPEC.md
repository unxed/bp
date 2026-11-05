# Better Pascal — specification v0.6

Safe-by-default Free Pascal. Not a fork, not a new syntax: **one unit `BP` and one line in every module**:
`uses ..., BP;` last in every module, the program file included. Works on stock FPC 3.2+: `tools/bp build` adds
`-FaBPThreads`, which installs the thread manager first (§24.3); with a bare `fpc`, add that switch or put `BP` first
in the program file.

`BP` (`bp.pas`) is made of two layers: the safe layer (`safe/*.inc`: ownership, slices, arena, defer, FFI, the poisoned
primitives) and the ext layer (`ext/*.inc` and `ext/bpthreads.pas`: UTF-8 by default, goroutines, the thread manager).
`unit Safe` (`safe/safe.pas`) is the safe layer alone. Below, "Safe Pascal" and `uses Safe` name the safe layer and its
rules; everything said about them holds for `BP`, which includes the same code.

The document is written so that it can be attached to a prompt in full: a model that writes code
strictly by §0 writes Safe Pascal code. The remaining sections explain §0 and define the API.

Porting all of this (or ideas from it) into FPC/Lazarus in any form is **welcome**: nothing is required
from us for that, and Safe Pascal needs nothing from FPC to work either.
License: MIT (`LICENSE`, the SPDX header of each file).

Versions and what was verified on which targets: §2 (table) and §17 (history).

### What actually exists and what is only a plan so far (v0.6)

| Part | Status | Where |
|---|---|---|
| UTF-8 by default, `CodePoints`/`CPLength` (ext layer, unit `BP`) | **implemented, tests** | §3, `test_utf8` |
| `TOwned/TShared/TWeak/TSlice/TArena`, R1–R4 | **implemented, tests, CI** | §4–5, `test_safe` |
| Shadowing of `GetMem/New/Dispose/Move/FillChar/FreeAndNil`, `.Free`, `Pointer` (S1–S4) | **implemented (compiler), compile tests `mf_*.pas`** | §6 |
| `TDefer`, `SafeLiveCount`/`SafeCheckNoLeaks` (R5) | **implemented, tests** | §5, §12 |
| FFI: `TCResource`, the `ffi_libc` binding | **implemented, test** (needs libc, `-dSAFE_LIBC`) | §13 |
| Goroutines: `TGroup/TTask/TChan/Select`, R6–R8 (ext layer, unit `BP`) | **implemented, tests** | §14, `test_go` |
| Threads without libc (`ext/bpthreads.pas`: `clone`+`futex`+`mmap`), Linux without libc by default | **implemented, tests** (`test_threads`; x86_64, i386, aarch64, Alpine) | §18 |
| Sum types: example and test; **S13 checks (`case` exhaustiveness, tag)** | example and test exist; **checks (linter) — plan** | §16, `test_sumtype` |
| Go-style package manager: `deps.txt`, `deps.lock`, MVS, `vendor`, mirrors, Software Heritage, unsafe audit | `deps.txt`, `deps.lock`, MVS, the module cache, `vendor`, mirrors: **implemented, test, CI** (`tools/bp get`, `tools/bp vendor`, `tests/deps.sh`); Software Heritage, the unsafe audit: **plan** | §15 |
| The `sp` tool (`build/test/vet/fmt/doc/get/vendor/unsafe/embed/fuzz`) | **plan only** | §16 |
| Linter `bpvet` (`tools/bpvet`, on `fcl-passrc`): the frame and rule S7 | **implemented, lint tests, CI** | §6 |
| `bpvet` rule S4 (`^T`, `@`, pointer arithmetic) | **implemented, lint tests, CI** | §6 |
| `bpvet` rule S6 (`TFoo.Create` at once into `Own/Share/Adopt/Go`/`raise`, else `// UNSAFE:`) | **implemented, lint tests, CI** | §6 |
| `bpvet` rule S9 (`UnicodeString/WideString/ShortString`, `String[N]` only under `// UNSAFE:`) | **implemented, lint tests, CI** | §6 |
| `bpvet` rule S10, static part (`TOwned` copied only through `.Move`, no `TOwned` by value in a parameter) | **implemented, lint tests, CI**; the `SAFE_DEBUG` runtime check is **plan** | §6 |
| `bpvet` rule S5, fields and globals (a field/global of a class declared in the module or of a common RTL class only with `// borrow:`) | **implemented, lint tests, CI**; classes of other units and the borrow-escape rule are **plan** | §6 |
| `bpvet` rule S15 (no `TShared` cycles: a warning on a `TShared` field that leads back to its own class, heuristic over one module) | **implemented, lint tests, CI**; the `SAFE_DEBUG` cycle report of `SafeCheckNoLeaks` is **implemented, test** (`test_safe`, `SharedCycleReported`) | §6, H2 |
| `bpvet` rule S11 (a field of a task with a class type is an error, also with `// borrow:`; so is a field with an interface type or a named pointer type) | **implemented, lint tests, CI**; a field `^T` is caught by S4; the thread-safe `TWeak.TryLock` (a lock in the cell) is **implemented, stress test** (`test_threads`; x86_64, i386, aarch64) | §6, §14, H6 |
| `bpvet` rules S13–S14 | S13 `case` over an enumeration of the module: **implemented, lint tests, CI**; S13 variant field read in a branch of `case X.Tag of` with another tag or outside any `case` over its tag (a write `X.Field := …` is allowed): **implemented, lint tests, CI**; S14 copy-heavy by-value parameters (`String`, open arrays except `array of const`, records and dynamic arrays of this or a used unit): **error, implemented, lint tests, CI**; other by-value parameters not syntactically changed and input-only `var` parameters: **warning, implemented, lint tests, CI** | §6, §11 |
| Fuzzing (`fuzz_*.pas`, `sp fuzz`) | **plan only** | §16 |
| Immutability by default (S14) | copy-heavy by-value parameters (`String`, open arrays except `array of const`, records and dynamic arrays): **error**; other by-value parameters not syntactically changed: **warning**; input-only `var` parameters: **warning**; all implemented in `bpvet` S14 with lint tests and CI | §16 |
| Lazarus package (OPM), Windows in CI | **plan** | §11 |
| CI: "no INTERP/NEEDED" check, Alpine/Debian/Ubuntu 16.04/CentOS 7 in containers, i386 and aarch64 under qemu | **implemented** (`.github/workflows/ci.yml`) | §18 |
| Support for `object` (Turbo Pascal) | **plan** | §19 |
| Memory styles: several safe styles in one program, the decision tree, style boundaries (S18), the `// BP-STYLES:` allow-list | **design (plan)** | §20 |
| Region style (an idea from Goose): `TRegion`, `TRegionObject`, `TGrowArray<T>`, zero cost in a release build | **design (plan)** | §20 |
| Root analysis in `bpvet` (S17): rooted references are checked statically, no runtime cost | **design (plan)**; needs a typed `bpvet` (`fcl-passrc` `PasResolver`) | §20 |
| GC style: `TGcObject` classes (`N.Next.X`, as in Go), a heap per goroutine, mark and sweep, edges from published fields, roots from the stack of the goroutine | **design (plan)**; was "deliberately not adopted" until 2026-11-04 (§18) | §20 |
| Concept v3: one scope object (`S.Hold`, `S.Defer`; `TArena` and a local `TOwned` fold into the region), Send and Sync inferred, goroutines M:N on the stacks of `BPThreads`, the `TComponent` tree as an owner | **design (plan)** | §21 |
| Final touches: `bp run` and scripts, `--watch`, `bp new` (these three exist, `tools/bp`, `tests/bp.sh`), the `fpc` line and `--target`, readable findings and `bp explain`, the format check (S20), `bp test` with a leak check after each test, `// derive:`, a profiler, `bp lsp`, a page in the browser | **`bp run`, `--watch`, `bp new` implemented, tests**; doc tests exist (`tools/doctest.py`); the rest design (plan) | §22 |
| Systems programming and C without versions: profiles S/U/H/F, `CLib.Bind` (a table of names bound at run time), profile U (no `PT_INTERP`, no `DT_NEEDED`, the host libc through its loader), Layer 1 C code linked freestanding, `bp bind`, a freestanding kernel, `TMmio<T>`, inferred contexts (S23) | **design (plan)**; the facts of §23.3 are measured | §23 |
| Concept v4: one sentence for all lifetimes, marks of fact written by the machine, `BP` last in the program file too (`-FaBPThreads`), closures that cannot escape (`nestedprocvars`), extension methods (`typehelpers`), interfaces as borrows (`{$interfaces corba}`), `// raises:` inferred, the casts and the uninitialised variables the table of §8 missed (S24, S25, `-Sew`) | **design (plan)**; the facts of §24 are measured | §24 |
| An uninitialized local class reference, function result or `out` parameter (H19) | **checked:** `tools/bp build` adds `-Sew` (`tests/safe/compile/mf_uninit.pas`) and runs the typed `bpvet`: S26a proves the assignment on every path (also where FPC does not warn: a branch, an `out` parameter, a result), S26b keeps a class under 64 KiB so a nil dereference faults | §8, §22.9 |
| Data races through a dynamic array, a `TShared` object or a global shared by goroutines (H14–H16) | **checked** by the typed `bpvet` (`tools/bp build`): S11m, S11s, S19; `SAFE_DEBUG` R17 at `Send` | §8, §21.2 |
| Class casts and untyped parameters (H17, H18): an unchecked downcast, `TBig(Buf)[N]` over a `var Buf`, `absolute` | **checked** by the typed `bpvet` (`tools/bp build`): S24 (`--fix` writes `as`), S25 | §8, §24.6 |
| Speed competitive with C, Rust, Go and Goose on the same algorithm | **goal**, not measured yet; the order of the work: §25 | §25.2 |

---

## §0. Rule card (for the model and for the reviewer)

```
HEADER OF EVERY MODULE
  program Name; / unit Name;          // Name is the name of the file: one source of the name (S21; bp fix writes it)
  {$mode objfpc}{$H+}                 // this is what Lazarus writes into a new module anyway
  uses ..., SysUtils, ..., Safe;      // Safe goes LAST in uses (S7)
  Reserved words in lower case: begin, end, unit, procedure, if, then (S22; bp fix lowers them).
  Identifiers in CamelCase: TFoo, DoWork, String.

STRINGS                                (UTF-8 everywhere)
  The only string type is String, always UTF-8.
  Length(S) and S[i] are BYTES. Pos/Copy/Delete on byte indices are correct.
  Characters are rarely needed: for Ch in CodePoints(S) (Ch: String), CPLength(S).
  UnicodeString/WideString/ShortString/PChar — only at the OS boundary, in unsafe code.
  Binary data — specialize TArray<Byte>, not String.

DATA AND LIFETIME                      (chosen by data structure, not by project; the first that fits wins, §20)
  1. By default — values: record, String, specialize TArray<T>. No lifetime problems.
  2. An object with one owner         → specialize TOwned<TFoo>.Own(TFoo.Create(...))
  3. An object with several owners    → specialize TShared<TFoo>.Share(TFoo.Create(...))
     back reference / cache / observer → TWeak<TFoo> from Shared.Weak (Shared cycles are forbidden)
  4. Many objects with the same fate  → TArena: A := TArena.Create; X := A.Adopt(TFoo.Create) as TFoo
  5. COM interfaces (TInterfacedObject) — a ready-made Shared; hold the object ONLY through the interface.
  PLAN (§20, not implemented yet; do not write it until §0 status says so):
  6. Data of one step (a request, a frame, a pass)   → TRegion; N := TNode.Create (TNode = class(TRegionObject)),
     TGrowArray<T>: freed at once, zero cost
  7. A graph with cycles where no owner is natural      → TNode = class(TGcObject); N := TNode.Create: collected
  Styles mix in one program. Between styles only values are copied; region objects, borrows and GC objects never cross
  into another style, a task field, a channel or a global (S18).

REFERENCES
  Fields own, locals borrow:
    field/global variable of a class type  → TOwned/TShared/TWeak/interface
    parameter/local variable of a class type → borrow, lives no longer than the call
    a borrow field/global is allowed only with a comment  // borrow: <who owns it>   (S5, checked by bpvet)
    the result of .Get or a class parameter is not saved into a field or a global: Cache := Box.Get, Self.F := AObj (S5)
  The result of TFoo.Create goes straight into Own/Share/Adopt, into an interface or into raise (S6).
  No .Free, FreeAndNil, Destroy, GetMem, New, Dispose, Move, FillChar, Pointer, ^T, @ (S1–S4).
  Instead of FillChar(R, SizeOf(R), 0) — R := Default(TRec).
  A slice parameter is an open array: procedure Parse(const Data: array of Byte); Parse(Buf[10..20]).
    A stored slice is specialize TSlice<T> (as in Go: array + start + length, with bounds checking).

ERRORS AND ABSENCE
  No Option and no magic nil: "may be absent" = function TryX(...; out V): Boolean.
  A safety rule violation at runtime = an ESafety exception, never UB.

SUM TYPES AND PARAMETERS               (§16; enum and match from Rust without a new library)
  A tagged variant record: TShape = record case Kind: TShapeKind of skCircle: (R: Double); skRect: (W, H: Double); end;
  Created only by a constructor function (Circle(2.0)); a variant field is read only in the branch of its tag
  inside case S.Kind of; a case over an enumeration lists ALL values and has no else (S13).
  String and other managed types go in the common part of the record (FPC does not allow them in the variant part).
  Parameters are const by default; var/out only when the caller must see the change (S14).

CLEANUP AND TESTS                      (§5; an idea from Zig)
  Non-memory (a handle, terminal mode, a lock): D := TDefer.Call(@Self.Close) — called on leaving the scope
  and on an exception; D.Cancel — "success, no need to call".
  End of a test: SafeCheckNoLeaks — no live owned objects, nothing suppressed in TDefer (R5).

OLD STYLE                              (§12)
  object, New(P, Init(...)), Dispose(P, Done), ShortString/String[N], records via Move: not covered by the concept.
  Until it is decided (extend Safe to object / move to class), such code is // UNSAFE-UNIT: with a safe facade.

TARGETS                                (§2, table of what was verified)
  Linux (x86_64, i386, aarch64): by default a static binary without libc, works on any distribution;
  threads — BPThreads (inside BP). FFI to C libraries and libc — only with -dSAFE_LIBC (§18).
  DOS: no threads, TGroup.Go raises R8. Windows x86_64: the tests pass under wine in CI (BPThreads is empty there, the RTL thread manager is used).

UNSAFE
  Unsafe things are written with full names (System.GetMem, SysUtils.FreeAndNil, System.Pointer)
  and on the line above — a comment  // UNSAFE: <why this is safe>.
  A whole unsafe module: lives in unsafe/, first line  // UNSAFE-UNIT: <why>.
  Raw pointers do not leave unsafe code into the safe API.

GOROUTINES                             (§14; "do not communicate by sharing memory — share memory by communicating")
  G := TGroup.Create;  G.Go(TWorker.Create(Args, Ch));  ...  G.Wait;   // the group waits for everyone, also on leaving the scope
  A task = a class descending from TTask: arguments are fields set in the constructor, the code is Run.  Simple case: G.Go(@Proc).
  Task fields and messages: values, String, TChan, TOwned via Move. Not borrows, not shared objects (S11).
    A TArray (or a record holding one) only as the last use of a local or as Copy(A): an array is shared by reference.
    TShared only of a class nobody changes after its constructor; a global is written only in initialization (§21.2).
  Channels: Ch := specialize TChan<T>.Create(Cap); Send / Recv(out V): Boolean / TryRecv / Close; for V in Ch.
  select: case Select([A.Sel, B.Sel, Done], TimeoutMs) of ... — then TryRecv; -1 = timeout.
  Cancellation: G.Cancel → Done is closed; in a task — Cancelled or Done in Select. A task error → G.Wait raises R7.
  The thread manager (on Linux threads without libc, §18; with -dSAFE_LIBC and on other Unixes — cthreads) is installed
  by -FaBPThreads, which tools/bp build adds: BP stays last in the program file too (§24.3). A bare fpc without the
  switch and with BP not first → the first Go stops the program (code 211).

FFI                                    (§13; like cgo)
  external declarations — only in a binding module (// UNSAFE-UNIT:), a safe facade outward.
  String → C: System.PChar(S) for the duration of the call. C → String: assignment (a copy).
  Memory/a handle from C goes straight into TOwned<TCResource> with a paired release function.
  Callback from C: cdecl, do not let exceptions escape (try..except inside).
```

---

## §1. The idea in one paragraph

FPC already has almost everything: reference-counted strings with an encoding, dynamic arrays, records
with automatic finalization, interfaces with an atomic counter, range checks,
exceptions with guaranteed finalization. Three things are missing: **(1)** the right defaults
(UTF-8), **(2)** a couple of thin wrappers for objects and **(3)** a way to make the dangerous visible.
Better Pascal provides all three in one unit, and it "poisons" the dangerous primitives by name shadowing:
the `BP` unit (or `Safe`), placed last in `uses`, declares same-named symbols, and the compiler itself
rejects `GetMem(...)` with a message saying what to do instead. The full name
(`System.GetMem`) bypasses the shadowing — this is the explicit opt-in to unsafe, visible to grep.

## §2. Integration

| Method | What to do | Industry analogue |
|---|---|---|
| **Copy alongside** (main) | put `bp.pas`, `safe/` and `ext/` next to the sources; `-Fu` for `safe/` and `ext/` | SQLite amalgamation, stb, vendoring in Go |
| Shared copy | `-Fu<path> -Fu<path>/safe -Fu<path>/ext` in `~/.fpc.cfg` | `GOPATH` |
| Lazarus | a package in OPM (plan, §11) | npm / cargo |
| Upstream | a module shipped with FPC — do nothing | `std` |

Apart from the unit paths, no switches are needed: `-Fa`, `-Mobjfpc`, `-Sh`, `-FcUTF8` are not needed:

- UTF-8 is enabled in the `initialization` of the `BP` unit, and it is in the `uses` of every module → it is guaranteed
  to run before the main program. `-Fa` (which also only applies to programs) is not needed.
- `{$mode objfpc}{$H+}` is inserted by Lazarus into every new module anyway.
- `-FcUTF8` is not needed and is **harmful**: literals without `{$codepage}` are stored as is (UTF-8 bytes) with the encoding `CP_ACP`,
  and `CP_ACP` at runtime = `DefaultSystemCodePage` = UTF-8. This is how Lazarus works. With `-FcUTF8` (and with `{$codepage utf8}`)
  literals become `UnicodeString`, and `Pos(<a literal of Cyrillic letters>, S)` returns 0 (verified, FPC 3.2.2; a Latin literal does not show it) — do not enable it.

`uses Safe` is both an import and a declaration "this module is safe" (cf. `#![forbid(unsafe_code)]`
in Rust). A module without `uses Safe` is considered unsafe and must be marked (§7).

To disable the UTF-8 initialization of `BP` (if the application manages encodings itself): `-dSAFE_NO_UTF8`.

Linux is built without libc by default (§18): `cwstring` and `cthreads` are not needed, `-dSAFE_NO_CWSTRING` remains only for the case of `-dSAFE_LIBC` on a static build without libc.

### Verified on targets (2026-10-03, on v0.5 code; FPC 3.2.2)

Tests: `test_safe` (core), `test_go` (goroutines, §14), `test_threads` (thread manager, §18), `test_sumtype` (sum types, §16), `test_ffi` (FFI, §13). Build with no compiler options:

| Target | `test_safe` | `test_go` | `test_threads` | `test_sumtype` | `test_ffi` |
|---|---|---|---|---|---|
| x86_64 Linux (CI of this repository) | ✔ | ✔ | ✔ | ✔ | ✔ (`-dSAFE_LIBC`) |
| i386 Linux, static without libc (our cross-compiler) | ✔ 0 failures | ✔ 0 | ✔ 0 | ✔ 0 | ✘ no libc to link against |
| aarch64 Linux, static without libc (qemu) | ✔ 0 | ✔ 0 | ✔ 0 | ✔ 0 | ✘ same |
| DOS (go32v2, DOSBox-X) | ✔ 0 | skipped: no threads, `TGroup.Go` raises R8 | skipped (no threads on DOS) | ✔ 0 | ✘ no external libraries |
| Windows x86_64 (cross-compiler, wine 9, ubuntu-latest, 2026-11-04) | ✔ 0 failures | ✔ 0 | ✔ 0 | ✔ 0 | not built: the facade is over libc, the test is Unix-only |

Conclusion: after v0.5 (Linux without libc by default) the core, goroutines, threads and sum types work on all verified Linux targets, including static i386 and aarch64 without libc, without any switches;
FFI depends on libc/the OS. To check your own set: `tests/run.sh` with `FPC`/`FPCOPTS`/`RUN` of a cross-compiler (qemu-user); the repository CI runs Linux x86_64, i386 and aarch64, and Windows x86_64 under wine (job `windows`).
Windows notes: `test_utf8` (6 checks: byte lengths, `Pos`, `Copy`, the two default code pages) passes under wine; what the real Windows console shows after `SetConsoleOutputCP(CP_UTF8)` is not checked, wine in CI has no console to read it back. On Windows `BPThreads` is empty and `test_threads` runs on the thread manager of the RTL. The compile checks (`tests/*/compile`) and `ext/fpc-utf8` are not run for Windows.

## §3. Strings: UTF-8 everywhere

- `String` = `AnsiString` with `DefaultSystemCodePage = CP_UTF8`. File names, the console, `Input/Output` — UTF-8.
  `BP` does it: on Linux with `fpwidestring` (no libc), on other Unix with `cwstring`, on Windows UTF-8 is enabled in the console.
- Indices and lengths are in bytes (like Go and Rust). UTF-8 is self-synchronizing: a substring search
  by bytes cannot find "half a character", so `Pos/Copy/Delete/StringReplace` are correct.
- A character (code point) is also a `String`: `for Ch in CodePoints(S) do if Ch = '<one non-ASCII character>' then ...`.
  A broken or truncated byte is a separate "character"; the iteration does not loop and loses nothing.
- Conversion to UTF-16 — only at the boundary with the OS/a library, in unsafe code.
- Known limitation: case conversion on Unix goes through libc and depends on the locale (`LANG=C` →
  Cyrillic does not change case).

## §4. Ownership model

Reductions relative to the original concept (and why):

| Was | Became | Why |
|---|---|---|
| `Option<T>` | `TryX(out V): Boolean` | This is a native Pascal idiom (`TryStrToInt`, `TDictionary.TryGetValue`), zero new things |
| `Borrow<T>` | an ordinary reference in a parameter/local | A wrapper type gives no guarantees without a borrow checker; the rule "fields own, locals borrow" is checked by the linter |
| `Slice<T>` for parameters | an open array `array of T` | The compiler itself passes pointer+length, checks bounds under `{$R+}` and **does not let you store** an open array — it is a borrow by construction |
| `Slice<T>` for storage | `TSlice<T>` on top of `TArray<T>` | A reference-counted dynamic array: the slice keeps the array alive, a dangling slice is impossible. Go slice semantics |
| `Owned<T>` = unique pointer | `TOwned<T>` on a counter | see below |
| `GCHeap` | `TGcObject` classes, an optional style (§20, plan) | Only for graphs where ownership is unnatural; a program that does not use it has no GC at all |
| `unsafe begin end` | full names + `// UNSAFE:` | We do not change the syntax; the full name bypasses shadowing and is greppable |

### Why `TOwned` is reference-counted rather than unique

In FPC a record is copied differently in different places (assignment, a by-value parameter,
temporary function results), and the `Copy`/`AddRef` operators of managed records do not allow
a reliable implementation of ownership transfer. A unique pointer copied "past" the operator
gives a double free. Therefore:

- `TOwned` and `TShared` are built the same way: a record = a reference to the object + a "lifetime" interface.
  The counter is maintained by the compiler itself (an interface field in the record), there are no custom operators.
- An accidental copy of `TOwned` **does not break memory**: it merely extends the object's life until the death of the last copy.
- Uniqueness is a contract, not a mechanism: the linter requires `TOwned` to be copied only through
  `.Move`, and to be passed in parameters as `const` (borrow) or `var`. When the contract is observed, destruction
  is deterministic and happens exactly when the owner leaves its scope.

The price is one atomic increment on creation and on `Move`. That is cheap.

### Selection table

| Data | Type | Destruction |
|---|---|---|
| values, strings, arrays | `record`, `String`, `TArray<T>` | automatic, as always |
| an object with one owner (file, socket, dialog form) | `TOwned<T>` | when the owner leaves its scope or on `Reset` |
| a truly shared object | `TShared<T>` | when the last reference is gone |
| back reference, cache, subscriber | `TWeak<T>` | does not own; `TryLock` fails safely if the object is gone |
| tree/graph/AST/parse results | `TArena` | all at once: `FreeAll` or the arena leaving its scope |
| an OS resource | a wrapper class with a destructor + `TOwned` | RAII: the destructor closes the handle |
| data of one step: buffers, parse tables, intermediate objects (plan, §20) | `TRegion` + `TRegionObject` classes + `TGrowArray<T>` | all at once when the region leaves its scope: one store (+ finalizers only for types with strings) |
| a graph with cycles, no natural owner (plan, §20) | a `TGcObject` class | by the collector of the goroutine |

Inside an arena objects refer to each other with raw references marked `// borrow: arena`.

## §5. API (`safe/core.intf.inc`)

In objfpc mode generics require `specialize`; it is customary to declare synonyms:
`type TFooBox = specialize TOwned<TFoo>;`.

```pascal
ESafety = class(Exception);              // a safety violation at runtime

generic TOwned<T: class> = record
  class function Own(AObj: T): TOwned; static; // take into ownership; nil → empty
  function Get: T;                        // borrow; empty → ESafety (R1)
  function TryGet(out AObj: T): Boolean;
  function IsEmpty: Boolean;
  function Move: TOwned;                  // B := A.Move; A is empty
  procedure Reset;                        // destroy now (if the owner is the last one)
end;

generic TShared<T: class> = record
  class function Share(AObj: T): TShared; static;
  function Get: T; function TryGet(out AObj: T): Boolean; function IsEmpty: Boolean;
  procedure Reset;
  function Weak: specialize TWeak<T>;
  function TryLock(const W: specialize TWeak<T>): Boolean; // Self := a strong reference, if alive
end;

generic TWeak<T: class> = record
  function IsAlive: Boolean;
  procedure Reset;
end;

generic TSlice<T> = record                // a stored slice (Go semantics: a write is visible in all slices)
  class function From(const A: specialize TArray<T>): TSlice; static;
  function Sub(AStart, ALen: SizeInt): TSlice;  // out of bounds → ESafety (R2)
  function Len: SizeInt;
  function ToArray: specialize TArray<T>;       // a copy
  property Items[I: SizeInt]: T; default;      // 0-based, out of bounds → ESafety (R2)
end;

TArena = record
  class function Create: TArena; static;
  function Adopt(AObj: TObject): TObject;  // the result is a borrow: X := A.Adopt(TFoo.Create) as TFoo
  procedure FreeAll;                       // destroys in reverse order
  function Count: SizeInt;
  function Generation: LongWord;           // how many times FreeAll ran
end;

TArenaRef<T: class> = record              // a checked arena reference (H3): R := TNodeRef.Adopt(TNode.Create, Arena)
  class function Adopt(AObj: T; var A: TArena): TArenaRef; static;
  function Get: T;                         // after FreeAll, with debug checks on at Adopt → ESafety (R10)
  function IsStale: Boolean;               // debug checks only: the arena was freed after Adopt
end;

function CodePoints(const S: String): TCodePointEnumerator;  // for Ch in CodePoints(S)
function CPLength(const S: String): SizeInt;

TDefer = record                          // an idea from Zig: defer. A scope guard (also on an exception)
  class function Call(AProc: TSafeDeferProc): TDefer; static;  // D := TDefer.Call(@Self.CloseHandle)
  procedure Cancel;                      // success: the deferred call is not needed
end;                                     // TSafeDeferProc = procedure of object

function SafeLiveCount: LongInt;         // how many objects are currently owned (Own/Share/Adopt)
procedure SafeCheckNoLeaks;              // at the end of a test: no live ones and nothing suppressed in TDefer, otherwise ESafety R5
function SafeDeferFailures: LongInt;     // exceptions suppressed in deferred calls
```

Runtime checks (always enabled, cost one comparison):

| Code | Situation |
|---|---|
| R1 | `Get` on an empty `TOwned/TShared` (after `Move`/`Reset`) |
| R2 | index or `Sub` out of the bounds of a `TSlice` |
| R3 | `Own/Share/Adopt` of a `TInterfacedObject` object (it is owned by the interface counter — hold it through an interface) |
| R4 | `TArena` is not created (`TArena.Create`) |
| R5 | `SafeCheckNoLeaks` at the end of a test: live owned objects remain, suppressed exceptions in `TDefer`, or task errors not collected by `TGroup.Wait` |
| R6 | `Send` to a closed channel, a repeated `Close` (like panic in Go) |
| R7 | a group task failed: `TGroup.Wait` raises with the original class and exception text |
| R8 | `TGroup.Go` without threads: no thread manager is installed, or the target has no threads (DOS) |
| R9 | debug checks on (`-dSAFE_DEBUG` or `SafeDebugChecks := True`): `TOwned.Reset` while a copy of the owner is alive (S10); the message names the class |
| R10 | debug checks on at `TArenaRef.Adopt`: `TArenaRef.Get` after `TArena.FreeAll` of its arena (the arena generation changed, H3); the message names the class. With checks off `TArenaRef` keeps no arena link and `Get` is one comparison |

Thread safety: the counters are atomic, so `TShared` can be copied between threads;
`TWeak.TryLock` from different threads concurrently with the last `Reset` is safe: it reads the life under a spin
lock in the cell, which the destructor also takes to clear it, and adds a reference only while the count is above
zero, so a dying object is never revived (H6, the stress test in `test_threads`). `TShared.Weak` itself is called by a
holder of the strong reference; the first `Weak` of one object from two threads at once is not synchronised.

## §6. What enforces each rule

| Rule | What is forbidden | What catches it now |
|---|---|---|
| S1 | `GetMem/FreeMem/ReallocMem/AllocMem/New/Dispose` | **compiler**: shadowed by a stub type → an error + the message `SAFE-S1` |
| S2 | `Move/FillChar` | **compiler**: the same, `SAFE-S2` |
| S3 | `.Free`, `FreeAndNil`, `.Destroy` | `FreeAndNil` and `.Free` are a compiler error. `.Free` is closed off by a `TObject` helper with the method `Free(const X: SAFE_S3_NoFree_UseTOwnedReset_or_UnsafeDestroy)`: without an argument the call does not compile, and the type name in the "Found declaration" message explains the rule. `.Destroy` — linter |
| S4 | `Pointer, PByte, PChar, PAnsiChar, PWideChar`, `^T`, `@`, pointer arithmetic | the types — warning `SAFE-S4`; `^T`, `@`, pointer arithmetic — `bpvet` S4 |
| S5 | a field/global variable of a class type without `// borrow:` | `bpvet` S5: an error on a global or a field of a class/object/record whose type is a class declared in the module or a common RTL class (`TObject`, `Exception`, `TStringList`, `TList`, `TStream`, `TThread`, …), unless the line ends with or follows `// borrow: <who owns it>`; a module marked `// UNSAFE-UNIT:` is not checked; an assignment `Name := X.Get` / `Self.Name := X.Get` into a global of the module or a field of its class without `// borrow:`, and `Name := AParam` / `Self.Name := AParam` where `AParam` is a parameter of such a class type (a one-line routine header); `Owner.Reset`/`Owner.Move` after `Local := Owner.Get` while `Local` is still used later in the same routine (before a new `Local := …`), unless `// UNSAFE: <why>` stands on the line above or at its end; task fields are covered by the field rule; closures are not checked: FPC 3.2.2 does not compile anonymous procedures or `reference to` types (fcl-passrc 3.2.2 parses them for pas2js); a class of another unit counts when that unit's file lies next to the checked file (`name.pas` in the same directory; classes declared in its interface, read as text); or in a directory given with `bpvet -FuDIR` (CI: `-Fusafe -Fuext` for tests/) |
| S6 | `TFoo.Create` not immediately into `Own/Share/Adopt`/an interface/`raise` | linter; partly at runtime (R3) |
| S7 | `Safe` is not last in `uses` | `bpvet`: an error when a unit follows `Safe`/`BP` in its `uses`; a warning when the implementation `uses` come after `Safe`/`BP` of the interface, and when units follow `BP` that is first in a program (§14); a warning is not reported when the uses are marked `// UNSAFE: <why>` (§7), an error has no mark. Otherwise `FreeAndNil` from SysUtils is not shadowed and the helper may be overridden |
| S8 | unsafe code without `// UNSAFE:` / a module without `uses Safe` and without `// UNSAFE-UNIT:` | linter |
| S9 | `UnicodeString/WideString/ShortString` outside unsafe | `bpvet` S9: an error on the type name or a sized `String[N]` (a `ShortString`) without a `// UNSAFE: <why>` mark on the line above or at the end of the line (§7); a `// UNSAFE-UNIT:` module is not checked |
| S10 | a copy of `TOwned` not via `.Move`; `TOwned` by value in a parameter | `bpvet` S10: an error on `X := Y` where `Y` is declared with a `TOwned` type and on a `TOwned` parameter without `const`/`var`/`out`/`constref`, unless marked `// UNSAFE: <why>` (§7); at run time R9 in debug mode; the runtime is safe in any case (§4) |
| S11 | a field of a `TTask` task is a borrow or a mutable object accessible to other threads | `bpvet` S11: an error on a field of a task class of the module (descending from `TTask`, directly or through a task class of the module) whose type is a class (the class set of S5: the module, common RTL classes, classes of used units next to the file or by `-Fu`), also when the field is marked `// borrow:`: a task runs on another thread and can outlive the caller; the same error on a field whose type is an interface (of the module, `IInterface`, `IUnknown`, `IInvokable`, interfaces of used units next to the file or by `-Fu`): the object behind it is shared with the caller; `// UNSAFE: <why>` on the line above or at its end drops it; a `// UNSAFE-UNIT:` module is not checked; a field `^T` needs no rule of S11: S4 already rejects it without `// UNSAFE:` (`tests/lint/s11_ptr_bad.pas`); the same error of S11 on a field of a named pointer type: `Pointer`, `PChar` and the other pointer types of System that S4 knows, or a pointer type of the module (`PNode = ^TNode`; `tests/lint/s11_ptrtype_bad.pas`, `s11_ptrmod_bad.pas`): the memory behind it has no owner; a pointer type of a used unit next to the file or by `-Fu` counts too (`s11_ptr_other_bad.pas`); a full name `System.PChar` is already an error of S8, one `// UNSAFE:` covers both (`s11_ptrsys_bad.pas`) |
| S12 | `external` outside a `// UNSAFE-UNIT:` module; a binding's public API with pointers | linter |
| S13 | a `case` over an enumeration does not list all values or has `else`; a variant field is read outside the branch of its tag (§16) | `bpvet` S13 (FPC 3.2.2 does not warn): an error on a `case` whose labels are all plain values of one enumeration of the module and which has `else` or misses a value (`tests/lint/s13_bad.pas`, `s13_else_bad.pas`); `// UNSAFE: <why>` on the line above or at its end drops it; bpvet has no types, so the enumeration is found by the labels: ranges, constants and enumerations of other units are not checked; inside a branch of `case X.Tag of` (Tag — the tag field of a variant record of the module) `X.Field` of a variant field of another tag is an error (`tests/lint/s13_variant_bad.pas`), the same mark drops it; `X.Field` of a variant field read outside every `case` over its tag is an error too (`tests/lint/s13_read_bad.pas`; a write `X.Field := …` is allowed, `s13_read_ok.pas`), the same mark drops it |
| S14 | a parameter without `const`/`var`/`out`; `var` although the caller does not need the change (§16) | `bpvet` S14: an error on a by-value `String`, `AnsiString`, `UnicodeString`, `WideString`, `RawByteString` or `UTF8String` (`s14_bad.pas`, `s14_method_bad.pas`), a record of this or an imported unit (`s14_record_bad.pas`, `s14_other_bad.pas`), an open array `array of T` except `array of const` (`s14_openarray_bad.pas`), or a dynamic array of this or an imported unit (`s14_dynarray_bad.pas`, `s14_other_dynarray_bad.pas`) without `const`, `constref`, `var` or `out`; other by-value parameters not syntactically written in a routine body are warnings (`s14_scalar_bad.pas`), as are `var` parameters without a detected write (`s14_var_bad.pas`). Writes through assignment targets, call arguments, method receivers, `@`, `for`, `with` and nested routines count. Overrides, routines without bodies, and routines whose address is taken in the module are skipped; untyped `var` parameters are skipped. The interface/class declaration and body produce one finding; `// UNSAFE: <why>` on or above the parameter drops either warning or error (`s14_ok.pas`, `s14_var_ok.pas`) |
| S15 | a `TShared` cycle: a field of a class holds through `TShared` an object that leads back to the class of the field (H2) | `bpvet` S15: a warning on a field of a class of the module whose type is `specialize TShared<X>` or a module alias of it, when `X` is the class itself or reaches it through such fields of classes of the module, with the path and the hint "a back reference is `TWeak`"; `// UNSAFE: <why>` on the line above or at its end drops it (the program breaks the cycle itself); a heuristic by names over one module, the type is read from the line of the field, classes of other units are not followed; a `// UNSAFE-UNIT:` module is not checked |
| S16 | range checks switched off in a module that uses `Safe`/`BP` (H12) | `bpvet` S16 warns on an explicit `{$R-}` in a module using `Safe` or `BP`, unless `// UNSAFE: <why>` is on that line or the line above (`tests/lint/s16_bad.pas`, `s16_ok.pas`); debug builds compile these modules with `-Cr -Co` (`{$R+}{$Q+}`); release builds may disable those compiler checks, while runtime checks R1–R4 remain enabled |
| S11m | Send = move (H14): a value that holds a dynamic array goes to another goroutine shared with the sender | `bpvet` S11m (typed, `tools/bpvet/bpvetrace.pas`): an error on the argument of `Ch.Send` (a `TChan`) and on an argument of the constructor of a task (a descendant of `TTask`) whose type holds a dynamic array (one, a static array of one, a record with one; not `TChan`, `TShared`, `TOwned`, `TWeak`, `TGroup`; a `String` does not count: it is copied on write), unless it is `Copy(X)`, an array literal, the result of a function, or the last use of a local: the next read of it (in a loop also the next iteration and the reads after the loop) is none, `X := ...` or `SetLength(X, ...)`; a parameter (also by value: a dynamic array passed by value is the array of the caller, only its reference count grows), a field, a global and a local read by a nested routine are errors (`tests/lint/s11m_ok.pas`, `s11m_param_bad.pas`, `s11m_valparam_bad.pas`, `s11m_after_bad.pas`, `s11m_loop_bad.pas`, `s11m_task_bad.pas`, `s11m_nested_bad.pas`); `// UNSAFE: <why>` drops it |
| S11s | Sync (H15): an object behind `TShared` reached by two goroutines and changed | `bpvet` S11s (typed): an error on a field of a task class and on a `TChan` (a variable, a field, a parameter) whose type carries `TShared<X>` (also inside a record), unless `X` is frozen or marked `// sync: <the lock or the protocol>` on its declaration line or the comment lines above; frozen: no field of `X` or of its ancestors is written outside the constructors and destructors of `X` and its descendants (an assignment, a `var`/`out` argument, `Inc`, `Dec`, `SetLength`, `Include`, `Exclude`, `Delete`, `Insert`), the type of every field is frozen (values, `String`, `TChan`, `TShared`/`TOwned` of a frozen class, records and arrays of them; not `Pointer`, not an interface), and every ancestor below `TObject`/`TInterfacedObject` is of the module; the finding names the field and the routine that writes it (`tests/lint/s11s_ok.pas`, `s11s_bad.pas`, `s11s_chan_bad.pas`) |
| S19 | `static mut` (H16): a global of a unit written while goroutines run | `bpvet` S19 (typed): an error on a write (an assignment to it or through it, a `var`/`out` argument, `Inc`, `SetLength` and the others of S11s) to a global variable of a unit in a routine; allowed in `initialization`, `finalization`, a `threadvar`, an `Interlocked*` call (atomic), and in the main block and the routines of a program, whose globals are the locals of the main goroutine: there the error is on any use of a global of the program in a routine that a task reaches (from the `Run` of a task class of the program or a `Go(@Proc)`, through calls and overrides), except a `TChan`, a `TRTLCriticalSection` and an argument of an `Interlocked*` call; `// UNSAFE: <the lock>` on the line or the comment lines above drops it; a `// UNSAFE-UNIT:` module is not checked (`tests/lint/s19_ok.pas`, `s19_bad.pas`, `s19_var_bad.pas`, `s19_prog_ok.pas`, `s19_prog_bad.pas`) |
| S24 | an unchecked class cast (H17): `TB(O)` where `O` holds a `TA` reads the object as a `TB` with no check | `bpvet` S24 (`tools/bpvet/bpvetcast.pas`, typed): an error on a typecast whose callee is a class type (an alias of one too) and whose operand has a class type (not an interface, not a class reference), when the target is a descendant of the class of the operand, `TObject` included: `TSquare(S)` of a `TShape`, `TButton(Sender)`. The finding says to write `O as TB`; `--fix` (and `bp fix`) rewrites `TB(O)` to `(O as TB)` in the file (the operand gets parentheses of its own when it has a blank outside brackets and strings). A cast to the same class or to an ancestor (an upcast) stays; so does a cast from `Pointer`, an integer or `nil`, which is S4 (S24 reads only class operands). The cast of a class to a class of another branch (neither is an ancestor of the other) is an error without a fix: the object is never a `TB`, and `as` would not compile. `--fix` writes a cast only when the casts of the tree and of the text of that line match one to one (the n-th `TB(` of the line, strings and comments left out) and the cast is in the file itself, not in an include file; the others stay findings. `// UNSAFE: <why>` on the line or the comment lines above drops it; a `// UNSAFE-UNIT:` module is not checked (`tests/lint/s24_ok.pas`, `s24_bad.pas`, `s24_object_bad.pas`, `s24_alias_bad.pas`, `s24_branch_bad.pas`; the `--fix` test of `tests/lint.sh` turns `s24_fix.src` into `s24_fix.expected` and checks that the result is clean) |
| S25 | an untyped parameter, a typecast of one, `absolute` (H18): `procedure Poke(var Buf; N: Integer)` with `TBig(Buf)[N] := 1` writes anywhere | `bpvet` S25 (`bpvetcast.pas`, typed): an error on (1) a `var`, `const` or `out` parameter with no type, in a routine, a method (at its declaration in the class, not again at its implementation) or a procedure type of the module; (2) a typecast `T(X)`, to any type, of such a parameter (`TBig(Buf)[N]`, `Byte(Buf)`); (3) a variable declared with `absolute`, global or local. `// UNSAFE: <why>` on the line, on the comment lines above it or, for (1), above the routine drops the finding; it drops (2) only at the cast, since the mark on the parameter says why the parameter has no type, not that every use of it is right. A call of an RTL routine that takes an untyped parameter (`Move`, `FillChar`, `BlockRead`) is not S25: BP wraps or poisons those (S4); a facade in `BP` with an untyped parameter carries the mark and is safe to call. A `// UNSAFE-UNIT:` module is not checked (`tests/lint/s25_ok.pas`, `s25_param_bad.pas`, `s25_const_bad.pas`, `s25_proctype_bad.pas`, `s25_cast_bad.pas`, `s25_absolute_bad.pas`) |
| S26a | definite assignment (H19): a class reference that FPC does not zero, read or returned before it is assigned | `bpvet` S26a (typed, `tools/bpvet/bpvetnil.pas`): an error on the first read of a local of a class or class-of type that is not assigned on every path before it, and on the end of a routine (or an `Exit`) where its result or an `out` parameter of such a type is not assigned on every path; branches are joined, a `while` or `for` body may not run (a `for` with constant bounds in its direction runs), a handler of `try...except` and a `finally` block start from the state before `try`; a `var` argument, `@F`, a name used by a nested routine and `asm` count as assignments; what `-Sew` already catches is reported too (`tests/lint/s26a_bad.pas`, `s26a_out_bad.pas`, `s26a_result_bad.pas`, `s26a_finally_bad.pas`, `s26a_ok.pas`); `// UNSAFE: <why>` on the line or above |
| S26b | a class whose instance is larger than 64 KiB: a field of a nil reference past the unmapped first pages would not fault | `bpvet` S26b (typed): an error on a class of the module whose fields with those of its ancestors, counted from below (no alignment, no variant parts), exceed 65536 bytes; a large buffer goes into a dynamic array (`s26b_bad.pas`, `s26b_ok.pas`) |
| S21 | a file without a `program`/`unit`/`library`/`package` header, or a header whose name is not the name of the file (two sources of one name) | `bpvet` S21 (`bpvetstyle.pas`, over the text before the parse): an error; the name is compared without letter case (`unit Region` in `region.pas`); a file without a header is a `unit` when it has `interface`, else a `program`; `bpvet --fix` / `tools/bp fix` inserts the header before the first token or writes the name of the file into it; a file whose name is not an identifier (dots allowed) is reported without a fix (`tests/lint/s21_none_bad.pas`, `s21_name_bad.pas`, `s21_ok.pas`) |
| S22 | a reserved word with an upper-case letter (`Begin`, `END`): the style of Better Pascal is lower case, upper case is the style of the 1980s and stands out in the text | `bpvet` S22: a warning (an error with `--strict`, so in `tools/bp build`); `--fix` lowers the word; comments, strings, `&escaped` identifiers and the bodies of `asm` blocks are skipped; `string` is not checked, it is written as the type it names (`String`); directives (`override`, `virtual`) are not reserved words and are not checked (`tests/lint/s22_bad.pas`) |

Warnings are turned into errors with one directive in a module, `{$WARN SYMBOL_DEPRECATED ERROR}`,
or with the switch `-Sew` for the whole project. Migration modes: **permissive** — warnings;
**strict** — errors.

`bpvet` checks the rules marked "linter" (S3, S4, S5, S6, S7, S8, S9, S10, S11, S12, S13, S14, S15). It reads the sources with `fcl-passrc`
(shipped with FPC) and prints FPC messages, one line each with the fix: `file(line,col) Error: SAFE-S7 ...`. Build and
run: `tools/bpvet/build.sh out/bpvet && out/bpvet [--report|--strict] FILE|DIR...`. By default errors fail (exit code 1)
and warnings are printed; `--report` prints every finding as a warning and never fails (permissive), `--strict` makes
warnings errors (strict); a file it cannot parse gives exit code 2. Lint tests: `tests/lint/*.pas`, `tests/lint.sh`.
CI (job `lint`) runs `--strict` over `safe/`, `ext/` and `tests/` (except `tests/lint`, whose `*_bad.pas` have findings
by design).

Recommended FPC checks for a debug build (in Lazarus — the Debug build mode):
`-Cr -Co -CR -Sa -gh -gt` (ranges, overflow, object checks, assert, heaptrc, garbage
in local variables). In a release you can drop `-Cr -Co -CR`; the R1–R4 checks remain.

## §7. Unsafe

```pascal sketch
// UNSAFE: Buf is allocated for Len bytes on the line above and freed in the finally of this same procedure
System.GetMem(Buf, Len);
```

- Inside a safe module: full names (`System.GetMem`, `System.Move`, `System.Pointer`,
  `SysUtils.FreeAndNil`, `Obj.Destroy`) and a `// UNSAFE:` comment on the line above.
- Whole modules (WinAPI bindings, terminal, allocators, C libraries): the `unsafe/` folder,
  first line `// UNSAFE-UNIT: <why>`, `uses Safe` may be omitted.
- Boundary: the public API of an unsafe module uses only the types from §4–5; raw pointers do not leave it.

## §8. An honest table of guarantees

| Guarantee | Level | Register |
|---|---|---|
| No `GetMem/FreeMem/New/Dispose/Move/FillChar/FreeAndNil` outside unsafe | compiler | — |
| Double free through `TOwned/TShared/TArena` is impossible | runtime construction (counter) | — |
| Access to an empty owner, going out of slice bounds | runtime (ESafety) | — |
| A dangling `TSlice`, a dangling `TWeak` | impossible by construction | — |
| `.Free` outside unsafe | compiler (error) | — |
| raw pointers outside unsafe | compiler warning (named pointer types) + linter (plan) (`^T`, `@`, arithmetic) | H4 |
| A borrow (parameter/local) does not outlive the owner | linter (plan) (S5) + programmer | H1 |
| No `TShared` cycles | programmer + linter `bpvet` (S15, heuristic) | H2 |
| Arena objects are not used after `FreeAll` | through `TArenaRef<T>`: runtime in debug (R10); a plain `// borrow: arena` reference — programmer, `-gh` | H3 |
| `TOwned` is unique: copied only through `.Move`, never by value | programmer + linter `bpvet` (S10); the runtime is safe in any case (§4) | H5 |
| Task fields are not shared mutable objects; `TWeak.TryLock` across threads | programmer + linter `bpvet` (S11: class, interface and pointer fields of a task); `TryLock` takes a lock in the cell (stress test in `test_threads`) | H6 |
| A class reference is assigned before it is read; a nil dereference is an exception, then impossible | the typed `bpvet`: S26a definite assignment, S26b the size of a class (a nil dereference is an exception); plan: S26c nil analysis (§22.9) | H19 |
| A dynamic array, a `TShared` object or a global is not changed by two goroutines at once | the typed `bpvet`: S11m (Send = move), S11s (Sync = frozen or `// sync:`), S19 (`static mut`) (§21.2) | H14–H16 |
| `.Destroy` outside unsafe | linter (S3) | H7 |
| Owner-or-nothing for `TFoo.Create`, no legacy string types | linter `bpvet` (S6, S9); R3 only for `TInterfacedObject` | H8 |
| `Safe` is last in `uses` | linter `bpvet` S7, an error in a program too (`tools/bp build` adds `-FaBPThreads`, §24.3) | H9 |
| Unsafe code is marked, `external` only in unsafe modules | linter (plan) (S8, S12) | H10 |
| Exhaustive `case`, `const` parameters | `bpvet` S13; S14 errors on copy-heavy by-value parameters and warns on other by-value parameters not changed by the body and unused `var` parameters | H11 |
| Range and overflow checks are not switched off in safe code | programmer | H12 |
| Turbo Pascal style `object` code | not covered (§19) | H13 |
| A region object or a `TGrowArray` element does not outlive its region | plan: `bpvet` S17 (static, zero cost); `SAFE_DEBUG` R12 (released pages lose access) as a second net | §20 |
| A GC object is never freed while reachable; cycles are collected | plan: the collector + `bpvet` S18 (where a GC reference may live, it stays in its goroutine) | §20 |
| A class cast is checked (`as`); no cast from a pointer or an integer to a reference | the typed `bpvet`: S24 (`--fix` writes `as`), S4 for a pointer or an integer (§24.6) | H17 |
| No untyped parameter, no variable typecast of one, no `absolute` outside unsafe | the typed `bpvet`: S25 (§24.6) | H18 |
| A variable is initialised before it is read | `bp build` adds `-Sew` (the warning of FPC is an error); a class reference: S26a | H19 |

We do not claim this is Rust. We claim: in safe code there is no **syntactic**
way to make the typical memory errors, and the remaining holes are listed above.

### Risk register (plan unxed/bp#56)

Every row of the table above that rests on "programmer" or on "linter (plan)" has an entry
here: an example of the error, what catches it now, what will catch it, and the step of the
plan in unxed/bp#56 that closes it. `bpvet` is the linter (§6; rules after S7 are planned). A row leaves the
register when its step is merged; step 16 checks that nothing "programmer" is left without a
compensating check, and accepted risks are listed with a reason.

| Id | Hole | Now | Target | Step |
|---|---|---|---|---|
| H1 | a borrow outlives its owner | nothing | `bpvet` S5 + borrow-escape rule | 7 |
| H2 | `TShared` cycle | R5 counts live objects; in `SAFE_DEBUG` it reports the objects reachable only from each other (number, types, path); `bpvet` S15 warns on a field that closes a cycle | `SAFE_DEBUG` cycle report + lint warning | 9 |
| H3 | use after `TArena.FreeAll` | `TArenaRef<T>` + arena generations → `ESafety` R10 in debug; plain borrows: `-gh`, sometimes | done; release cost measured (`tests/bench/bench_arena.pas`): `Get` is a call, not yet zero cost | 8 |
| H4 | `^T`, `@`, pointer arithmetic | `bpvet` S4 | `bpvet` S4 | 4 |
| H5 | a copy of `TOwned` | nothing (the runtime stays safe) | `bpvet` S10 + `SAFE_DEBUG` runtime check | 6 |
| H6 | shared task fields; `TryLock` race | `bpvet` S11: a class, interface or named pointer field of a task is an error | `bpvet` S11 + lock in the cell, stress test | 10 |
| H7 | `.Destroy` | nothing | `bpvet` S3 | 4 |
| H8 | `TFoo.Create` not owned; `ShortString` | R3 partly | `bpvet` S6, S9 | 5 |
| H9 | `Safe` not last in `uses` | `bpvet` S7, an error in every module; `tools/bp build` adds `-FaBPThreads`, so `BP` is last in the program file too (§24.3) | — (done) | 2, 2b; §24 step 1 |
| H10 | unmarked unsafe code, stray `external` | nothing | `bpvet` S8, S12 | 3 |
| H11 | non-exhaustive `case`, missing `const` | `bpvet` S13; S14 errors on copy-heavy parameters and warns when other by-value parameters are not changed | `bpvet` S13, S14 | 11 |
| H12 | `{$R-}` in safe code | the debug-build recommendation (§6) | rule `{$R+}{$Q+}` + `bpvet` warning | 12 |
| H13 | `object`, `New(P, Init)` | nothing: such code stays unsafe | owner over `object` + lint rules | 13 |
| H14 | a dynamic array shared by goroutines: `TChan.Send` keeps the same array (`FBuf[...] := V`), a `TArray` task field shares it with the caller | `bpvet` S11m (typed): `Send` and the constructor of a task take `Copy(X)`, a fresh value or the last use of a local | — (done: `SAFE_DEBUG` R17 at `Send`) | §21 step 1 |
| H15 | a mutable object behind `TShared` used by two goroutines | `bpvet` S11s (typed): `TShared<X>` in a task field or a message needs `X` frozen (inferred over the module) or `// sync: <how>` | a class of another unit is frozen when that unit marks it | §21 step 1 |
| H16 | a global written while goroutines run | `bpvet` S19 (typed): a global of a unit is written only in `initialization`/`finalization`, atomically (`Interlocked*`) or under `// UNSAFE: <the lock>` | — (done: S19 also on the globals of a program named by a routine a task reaches) | §21 step 1 |
| H17 | an unchecked class cast: `TB(O).Y[100]` on an object that is a `TA` reads past it (§24.6) | `bpvet` S24 (typed): a downcast is `O as TB`, `--fix` rewrites it; a cast between classes of different branches is an error; a cast from `Pointer` or an integer to a reference is S4 | — (done: the 2 downcasts of `safe/core.impl.inc` are `as`) | §24 step 3 |
| H18 | an untyped parameter with a variable typecast, `TBig(Buf)[N] := 1`, writes anywhere (§24.6); `absolute` | `bpvet` S25 (typed): an untyped `var`/`const`/`out` parameter, a typecast of one and `absolute` are errors outside a `// UNSAFE:` mark | — (done: the 5 untyped parameters of the repository are in `ext/bpthreads.pas`, a `// UNSAFE-UNIT:`) | §24 step 3 |
| H19 | an uninitialised local of a class type is a garbage pointer: `var F: TFoo; WriteLn(F.X)` | FPC: a warning | done: `bp build` adds `-Sew` (`mf_uninit.pas`; the region runtime had two results never set, fixed); S26a in the typed `bpvet`: definite assignment of a local, a function result and an `out` parameter of a class type; S26b: a class under 64 KiB (§22.9) | §24 step 2, §22 step 0 |

**H1. A borrow outlives its owner.**

```pascal sketch
var Cache: TFoo;                      // a global of a class type without // borrow:
procedure Load;
var Box: TFooBox;
begin
  Box := TFooBox.Own(TFoo.Create);
  Cache := Box.Get;                   // the borrow escapes into a global
end;                                  // Box destroys the object here
// later: Cache.Run — use after free (UB)
```

Now: nothing; with `-gh` in a debug build the freed memory is sometimes visible. Target: `bpvet`
S5 (a field or global of a class type only as `TOwned/TShared/TWeak`/interface or with
`// borrow: <owner>`) plus the escape rule: the result of `.Get` and a class-type parameter
cannot be stored into a field, a global, a closure or a task field; `Reset`/`Move` of the owner
while a borrow from it is alive in the same procedure is an error. Step 7. Closures: FPC 3.2.2,
the compiler of this dialect, has no anonymous procedures, so a borrow cannot escape into one;
the rule is added when the dialect moves to FPC 3.3+.

**H2. A `TShared` cycle.**

```pascal sketch
type
  TNode = class;
  TNodeRef = specialize TShared<TNode>;
  TNode = class
    Next: TNodeRef;                   // a strong reference inside the same graph
  end;
var A, B: TNodeRef;
begin
  A := TNodeRef.Share(TNode.Create); B := TNodeRef.Share(TNode.Create);
  A.Get.Next := B; B.Get.Next := A;   // neither counter reaches zero: both leak
end;
```

Now: `SafeCheckNoLeaks` raises R5 with the number of live objects; with debug checks on (`-dSAFE_DEBUG` or
`SafeDebugChecks := True` when the objects are made) it adds the number of those reachable only from each other,
their types and the path of the cycle (`… 2 of them are reachable only from each other, a TShared cycle (H2): types
TNode, path TNode -> TNode -> TNode; make the back reference a TWeak`). It finds the owners in the fields of the
objects themselves, not in dynamic arrays or heap records they point to. `bpvet` S15 warns on a `TShared` field of a class of the module that leads back to its own class
(with the path of fields and the hint "a back reference is `TWeak`"). Target: in `SAFE_DEBUG` `SafeCheckNoLeaks` reports live
`TShared` objects reachable only from each other (type, count, path of the cycle); `bpvet` warns
on a `TShared<T>` field in a class that is itself held by `TShared` of the same graph, with the
hint "a back reference is `TWeak`". Step 9.

**H3. Use after `TArena.FreeAll`.**

```pascal sketch
var
  Arena: TArena;
  N: TNode;                           // borrow: arena
begin
  Arena := TArena.Create;
  N := Arena.Adopt(TNode.Create) as TNode;
  Arena.FreeAll;
  WriteLn(N.Name);                    // use after free (UB)
end;
```

Now (step 8, first part): `FreeAll` bumps the arena generation (`TArena.Generation`); a reference
taken as `R := TNodeRef.Adopt(TNode.Create, Arena)` (`TNodeRef = specialize TArenaRef<TNode>`) with
debug checks on (`-dSAFE_DEBUG` or `SafeDebugChecks := True`) remembers the generation, and `R.Get`
after `FreeAll` raises `ESafety` R10 instead of touching a destroyed object. The generation lives in
a small cell that outlives the arena while a `TArenaRef` holds it, so the check is valid after the
arena itself is gone. With checks off `TArenaRef` keeps no arena link: `Get` is one comparison and
returns the plain reference. A plain `// borrow: arena` variable is still the programmer's
responsibility (`-gh` sometimes). The cost is measured by `tests/bench/bench_arena.pas` (`tests/bench/run.sh`,
`-O2`; the CI job `portable` prints the table, report only, no thresholds): a plain reference against
`TArenaRef.Get` with checks off and with `SAFE_DEBUG`. First measurement (2026-10-21, ubuntu-latest, FPC 3.2.2,
x86_64, 200M reads of one field): plain reference 1.6 ns/op, `TArenaRef.Get` with checks off 8.2 ns/op,
with `SAFE_DEBUG` 8.4 ns/op. So the generation check itself is almost free, but the release build is not
zero cost yet: `Get` is a non-inlined call on a record with a managed field. Until it is inlined, take
`R.Get` once into a local borrow in a hot loop.

**H4. `^T`, `@` and pointer arithmetic.**

```pascal sketch
type PInt = ^Integer;                 // ^T: no warning today
procedure Bump;
var X: Integer; P: PInt;
begin
  P := @X;                            // @: no warning today
  Inc(P, 4);                          // now points outside X
  P^ := 1;                            // memory corruption
end;
```

Now: the named types `Pointer, PByte, PChar, PAnsiChar, PWideChar` give the `SAFE-S4`
compiler warning; `^T`, `@` and pointer arithmetic (`Inc(P)`, `P + N` over a name declared with a pointer type
in the module) outside code marked `// UNSAFE:` are a `bpvet` S4 error; a dereference `P^` and `Inc(P^)` are
not, nor is `@Proc` / `@Obj.Method` of a procedure or method declared in the module (a procedural value for
`TDefer.Call`, `TGroup.Go` or a `TProcedure` parameter; `@` of a routine of another unit is still reported). Step 4.

**H5. A copy of `TOwned`.**

```pascal sketch
procedure Use(Box: TFooBox);          // TOwned by value: a hidden copy
begin
  Box.Get.Run;
end;
var A, B: TFooBox;
begin
  A := TFooBox.Own(TFoo.Create);
  B := A;                             // a copy instead of A.Move
  A.Reset;                            // the object lives on in B: the "unique" owner is not unique
end;
```

Now: nothing; the counter keeps the runtime safe (no double free, §4), but the lifetime is no
longer the one the code shows. Target: `bpvet` S10 (copy only through `.Move`, no `TOwned` by
value) plus a `SAFE_DEBUG` check: destroying an owner while the counter shows a live extra copy
raises `ESafety` with the type name. Step 6.

**H6. Shared task fields; `TWeak.TryLock` across threads.**

```pascal sketch
type
  TWorker = class(TTask)
    Log: TStringList;                 // a mutable object the caller also uses
    procedure Run; override;
  end;
procedure TWorker.Run;
begin
  Log.Add('done');                    // a data race with the caller's thread
end;
```

Now: `bpvet` S11 rejects a field of a task whose type is a class (also with `// borrow:`), an interface or a named pointer type; `TWeak.TryLock` from another thread concurrently with the last `Reset` is safe: a lock in the cell and a
count that never grows back from zero (stress test in `test_threads`, x86_64, i386 and aarch64 in CI). Target: `bpvet` S11 allows task fields only of value types, `String`, `TArray`, `TChan`,
`TShared`, or `TOwned` passed through `Move`. Step 10.

**H7. `.Destroy` outside unsafe.**

```pascal sketch
var Box: TFooBox; F: TFoo;
begin
  Box := TFooBox.Own(TFoo.Create);
  F := Box.Get;
  F.Destroy;                          // compiles: .Free is closed off, .Destroy is not
end;                                  // Box destroys the object again: double free
```

Now: `bpvet` S3 error, the hint is `TOwned.Reset` or `// UNSAFE:`. Step 4.

**H8. `TFoo.Create` not passed to an owner; legacy string types.**

```pascal sketch
procedure Leak;
var F: TFoo; S: ShortString;
begin
  F := TFoo.Create;                   // not into Own/Share/Adopt/an interface/raise
  F.Run;                              // an exception here leaks F, and .Free is closed off anyway
  S := StringOfChar('x', 300);       // ShortString: 255 bytes, the rest is cut silently
end;
```

Now: R3 catches only `Own/Share/Adopt` of a `TInterfacedObject`; the rest passes. Target:
`bpvet` S6 and S9. Step 5.

**H9. `Safe` is not last in `uses`.**

```pascal sketch
uses Safe, Classes, SysUtils;         // SysUtils comes after Safe
var Obj: TFoo;
begin
  Obj := TFoo.Create;
  FreeAndNil(Obj);                    // SysUtils.FreeAndNil wins: compiles, S3 is bypassed
end.
```

Now: `bpvet` S7 reports it as an error (step 2). It also warns when the implementation `uses` come after `Safe` of
the interface (they shadow it there, `tests/safe/compile/mf_s07_impl_shadow.pas`) and when units follow `BP` that is
first in a program. **Step 2b is done (§24.3):** `tools/bp build` adds `-FaBPThreads`, which installs the thread
manager first, so `BP` is last in the program file too, and S7 reports a unit after `BP` there as an error, as in a
unit (`tests/lint/s07_program_bp.pas`; `tests/ext/compile/mf_bp_last.pas` runs a goroutine with `uses SysUtils, BP`).
The test programs lost their `// UNSAFE:` on `uses`; `tests/run.sh` builds them with the same switch.

**H10. Unmarked unsafe code, `external` in a safe module.**

```pascal sketch
unit Fast;                            // neither `uses Safe` nor `// UNSAFE-UNIT:`
interface
function CStrLen(S: PChar): SizeInt; cdecl; external 'c' name 'strlen';
                                      // external outside unsafe/, a pointer in the public API
implementation
end.
```

Now: `bpvet` S8 (`// UNSAFE:` / `// UNSAFE-UNIT:` marks) and S12 (`external` only in a
`// UNSAFE-UNIT:` module, no pointers in a binding's public API). Step 3.

**H11. A non-exhaustive `case`, a parameter without `const`.**

```pascal sketch
type TColor = (Red, Green, Blue);
function ColorName(C: TColor): String; // no const
begin
  case C of
    Red: Result := 'red';
    Green: Result := 'green';
  end;                                // Blue is missing: Result is garbage, FPC 3.2.2 is silent
end;
```

Now: `bpvet` S13 reports the missing `Blue`; S14 warns that `C` is never changed and should be `const`. Step 11.

**H12. Range checks switched off in safe code.**

```pascal sketch
{$R-}                                 // without // UNSAFE:
var A: array[0..3] of Integer; I: Integer;
begin
  for I := 0 to 4 do
    A[I] := 0;                        // writes past the end of A
end.
```

Now: only the recommendation of a debug build with `-Cr -Co` (§6). A module with
`uses Safe`/`BP` should be compiled with `{$R+}{$Q+}` in debug; release builds may disable these
compiler checks because runtime checks R1–R4 remain enabled. `bpvet` S16 warns on an explicit
`{$R-}` without `// UNSAFE: <why>` on the directive or the preceding line. Step 12.

**H13. Turbo Pascal style `object` code.**

```pascal sketch
type
  PView = ^TView;
  TView = object
    constructor Init;
    destructor Done; virtual;
  end;
var V: PView;
begin
  New(V, Init);                       // S1 forbids New: such code can only live in unsafe
  Dispose(V, Done);
  V^.Done;                            // use after free: nothing checks it
end.
```

Now: not covered; such code stays in unsafe modules (§19). Target: an owner over an `object`
type (pointer + lifetime lock with the `Done` + `Dispose` release procedure) and lint rules for
such code; the decision "(a) works / does not work, (b) is needed" is recorded in §19 (needed by
unxed/dn#87). Step 13.

## §9. Migrating existing code

1. Add `Safe` last in the module's `uses` — get a list of warnings and errors.
2. S1/S2 errors (raw allocations) — move to unsafe modules or replace with `TArray<T>`/`TSlice<T>`.
3. `Create ... try finally Free` → `TOwned`. Object fields with a manual `Free` in the destructor → `TOwned` fields.
4. Shared objects → `TShared`, back references → `TWeak`.
5. Trees and temporary structures → `TArena`.
6. Turn on strict.

## §10. Example

```pascal
{$mode objfpc}{$H+}
uses Classes, SysUtils, Safe;

type
  TStringsBox = specialize TOwned<TStringList>;

function CountWords(const FileName: String): SizeInt;
var
  Lines: TStringsBox;
  Line, W: String;
begin
  Lines := TStringsBox.Own(TStringList.Create);
  Lines.Get.LoadFromFile(FileName);     // UTF-8 name and UTF-8 content
  Result := 0;
  for Line in Lines.Get do
    for W in Line.Split([' ']) do
      if W <> '' then Inc(Result);
end;                                    // the list is destroyed here, also on an exception
```

## §11. Next iterations (what does not exist yet)

- **Linter** `bpvet` on `fcl-passrc` (the Pascal parser shipped with FPC; §6): S3, S4, S5 (fields and globals), S6, S7, S8, S9, S10 (static part), S11 (class, interface and pointer fields of a task), S12 and S15 are done, the borrow-escape part of S5,
  rules S13–S14 are next (unxed/bp#56); output in the format of FPC messages so that the IDE shows them as compiler errors.
- **Lazarus package** `safepascal.lpk` in OPM: one-click installation.
- **Memory styles** (§20): the region style from Goose with the root analysis S17 in `bpvet`, and the GC style (`TGcObject`).
  The earlier sketch "a tracing arena with `procedure Trace(V: TVisitor)`" is replaced by §20: there the edges are the
  published fields, read from the VMT, so a class needs no hand-written `Trace`.
- **Modules and dependencies as in Go** (§15) and the **`sp` tool** — one command for building, testing,
  checking, formatting and dependencies (§16).
- Windows in CI; `ParamStr` in UTF-8 on Windows.

## §12. Ideas from Zig: what was adopted and what was not (v0.2), and lessons from practice

Rationale: for safety Zig uses not a borrow checker but **explicitness and verification tools**: the allocator is passed as a parameter, the test allocator catches leaks, `defer` keeps cleanup next to
acquisition, errors are in the result type. This fits the Safe Pascal philosophy ("no fork, no new syntax, a violation is visible").

| Zig idea | What was done | Where |
|---|---|---|
| a test allocator that catches leaks | `SafeLiveCount` + `SafeCheckNoLeaks` (R5): a counter of live owned objects, one atomic increment/decrement | §5, R5, `tests/safe/test_safe.pas` |
| `defer` / `errdefer` | `TDefer.Call` / `Cancel`: a guard record, fires on leaving the scope and on an exception; an exception inside a deferred call is not lost but counted (`SafeDeferFailures`) | §5 |
| the allocator as an explicit parameter | a rule, no code: a function that creates objects takes a `TArena` or returns a `TOwned` (it is visible who is responsible for the memory) | §4 |
| errors as values | for now `TryX(out V): Boolean`; for functions with several failure causes an enumeration of causes (`TFileError`) is recommended instead of Boolean | §0 (idea, no API) |
| integer overflow = an error in safe mode | in FPC this is `-Co`; recommended for a debug build (§6) | §6 |
| `comptime`, `?T` options, non-owning slices | **not adopted**: not in FPC / a conscious refusal (§4) / we have a reference-counted `String` | |

**A lesson from practice (the DOS Navigator port, `unxed/dn`).** A measurement on real code (161 DN files): `New(` 843, `Dispose(` 421, `object` types 230 versus one `class`, `ShortString`/`String[N]` about 300.
Code in the Turbo Pascal style (`object`, `New(P, Init(...))`, `Dispose(P, Done)`) is not covered by the concept: `TOwned<T: class>` does not accept `object`, and shadowing `New/Dispose` gives thousands of
S1 errors that are not defects. Options to be decided before a mass migration of such code: (a) extend Safe Pascal to `object` (an owner over an `object` type, `Init/Done`);
(b) move the code to `class`; (c) keep such a layer as a `// UNSAFE-UNIT:` with a safe facade. Binary file formats read by records with `String[N]` and `Move` require a separate
"format layer" (§7). More details: `unxed/dn`, `PLAN.md`, the section "Safe Pascal as the DN code style".

## §13. FFI: like cgo, only without cgo

In Go the boundary with C is a file with `import "C"`, rules for passing pointers and a pair of functions
`C.CString`/`C.GoString`. In FPC calling C is already built in (`external`, `cdecl`, the `ctypes` module,
headers are translated by `h2pas`), so there is almost nothing to add — only the boundary is needed:

| Go (cgo) | Safe Pascal |
|---|---|
| a file with `import "C"` | a binding module `// UNSAFE-UNIT:` (`*_c.pas` or the `unsafe/` folder), containing all `external` (S12) |
| Go memory into C — only for the duration of the call, C does not keep it | **F1**: `System.PChar(S)`, `@A[0]` + `Length(A)` from a `const`/`var` parameter — only for the duration of the call |
| you must not give C pointers to Go pointers | **F2**: only flat data goes to C (numbers, bytes, records without managed fields) |
| `C.CString` + `defer C.free`, `C.GoString` | **F3**: memory from C goes straight into `TOwned<TCResource>` with a paired `free`; a C string → `String` by assignment (a copy) |
| `//export` + panic does not cross C | **F4**: a `cdecl` callback; do not let an exception escape into C frames (`try..except` inside) |
| `runtime.LockOSThread` | **F5**: call thread-bound C libraries from a single task; threads created by C do not call Pascal without RTL initialization |

API (`safe/core.intf.inc`): `TCFreeProc = procedure(P: Pointer); cdecl` and `TCResource` (holds a pointer and a function,
releases in the destructor). A sample binding is `tests/ffi_libc.pas` (`strlen`, `strdup/free`, `qsort`
with a callback in Pascal), the test is `tests/test_ffi.pas`.

Availability: FFI through libc requires a dynamic build (on static Linux without libc and on DOS `external 'c'` does not link; see the table in §2). For such targets the binding is written against their own libraries.

What cgo does not have and we get for free: FPC strings are always null-terminated, so a string
goes to C **without a copy** (`C.CString` in Go always copies); the cost of a C call is an ordinary function call.

**Sockets go through fcl-net (unxed/bp#146, item 9).** `fpBind` and `fpsetsockopt` of the RTL take a record by its
address, which S4 rejects outside `// UNSAFE:`; S4 keeps no exemption for it. A program takes a listening socket from
`TInetServer` and a connection from `TSocketStream` of fcl-net (`ssockets`), as `examples/httpd` does; the raw socket
calls stay inside a `// UNSAFE-UNIT:` module when a program needs them.

## §14. Goroutines: like Go, better in places

The Go principle — "share memory by communicating" — maps onto the Safe Pascal ownership model: ownership
passes into the task (fields, `Move`), and values come back through a channel.

| Go | Safe Pascal | Better or worse how |
|---|---|---|
| `go f(x)` | `G.Go(TF.Create(X))` / `G.Go(@Proc)` | worse: no closures in FPC 3.2 (in 3.3+ an overload with an anonymous procedure can be added) |
| `chan T`, `make(chan T, n)` | `specialize TChan<T>`, `TChan.Create(N)`; a copy of the record is the same channel | the same: a reference type, `N = 0` — rendezvous |
| `v, ok := <-ch`, `for v := range ch` | `Ch.Recv(V)`, `for V in Ch` | the same |
| `select` | `Select([A.Sel, B.Sel], TimeoutMs)` + `TryRecv` | worse: receive only, not atomic with the receive (retry on failure); plan: atomic, with send cases (§21.3) |
| `sync.WaitGroup`, `errgroup` | `TGroup` | **better**: the group waits for the tasks on leaving the scope (structured concurrency), a goroutine leak is impossible |
| a panic in a goroutine kills the process | error → group cancellation → `Wait` raises R7 with the original text | **better** |
| `context.Context` | `G.Cancel`, `Done` (a closed channel) in `Select`, `Cancelled` | the same in meaning, without an extra parameter |
| races are caught by `-race` | races are prevented by S11, S11m, S11s and S19: only values, moved arrays, channels, `TShared` of frozen or `// sync:` classes, `Move` go into a task, and globals are written in `initialization` | different: a prohibition instead of a detector (§21.2), with the `SAFE_DEBUG` net R17 at `Send` |
| M:N scheduler, millions of goroutines | one task = one OS thread | worse: thousands, not millions; honestly "conditional" goroutines; plan: M:N on the stacks of `BPThreads` (§21.3) |

Design (we reuse the RTL, minimal custom code): a thread is `BeginThread`; a lock is `TRTLCriticalSection`;
waiting is an `RTLEvent` (a binary semaphore). A waiting thread puts its event into the channel's waiter list
while holding its lock, and whoever changed the state wakes everyone on the list — this way a wakeup is not lost
(the same idea as `sudog` in the Go runtime), and `Select` is the same registration in several channels at once.
FPC strings and dynamic arrays count references atomically, so values are passed between threads as is.

The thread manager must be initialized before SysUtils, so `BP` (which uses `BPThreads` first) goes first in the `uses`
**of the program file** (one place per project); in the other units `BP` goes last. If `BP` comes too late, the first
`Go` stops the program with an explanation (code 211, `tests/ext/compile/mf_threads_order.pas`).
On Linux `BPThreads` is threads on `clone`/`futex`/`mmap` without libc (§18), with `-dSAFE_LIBC` and on other
Unixes — `cthreads`. On DOS (go32v2) there are no threads: `TGroup.Go` raises R8 immediately.

Limitations of v0.3: `Select` is receive-only; no timers (`time.After`) — there is a `Select` timeout;
no deadlock detection ("all goroutines are asleep"). All three are in the plan of §21.3.

## §15. Dependencies like Go, without a proxy (plan)

In Go modules "just work", so there is nothing to fix: we take the whole model, in the same words and the same
commands, and change only what in Go rests on Google's infrastructure (the proxy `proxy.golang.org`
and the checksum database `sum.golang.org`). We have no infrastructure of our own and will not have any.

**What we take unchanged**

| Go | Safe Pascal |
|---|---|
| module path = repository address, no registry | the same: `github.com/acme/json`, `codeberg.org/bob/log`, any git |
| version = a git tag `vX.Y.Z` (semver) | the same |
| `go.mod`: `require path version` | `deps.txt`, the same syntax (below) |
| MVS: of all the requirements on a module the **greatest of the minimums** is taken; no solver, no surprises, updates only on command | the same, the same algorithm |
| major version v2+ — a new path (`/v2`) | v2+ — **new module names** (`Acme.Json2`): the FPC module namespace is shared per program, and two major versions must coexist in one program |
| the `go 1.22` line in `go.mod` | the `safe 0.4` line: which version of the rules of this spec the module follows (an analogue of editions in Rust) |
| `go mod vendor` | `sp vendor` |

```
// deps.txt — in the root of the application and in the root of each library
module github.com/me/app
safe 0.4
require github.com/acme/json v1.4.0
require codeberg.org/bob/log v0.3.1
mirror  github.com/acme/json https://codeberg.org/acme-mirror/json    // optional
```

**What we change: integrity and availability without a proxy**

- **Integrity is git itself.** Git is content-addressed: a commit hash uniquely defines the whole file tree.
  `deps.lock` stores `path version commit-hash`; a rewritten tag or a substituted repository gives a
  hash mismatch and a build error. A separate checksum database is not needed. An honest caveat: the first addition
  of a dependency is trust on first use (in Go `sum.golang.org` insures against this).
- **Availability — any instance with the same hash is equivalent.** Since the content is verified by hash, a "proxy"
  is not needed: any mirror will do. Lookup order: local cache → `vendor/` → the original address → `mirror`
  lines → the Software Heritage archive (it stores public git repositories and finds them by commit hash).
  For applications `vendor/` in the repository is recommended: then the build works offline and ten years from now.
- **Transport is the command-line `git`.** It is available everywhere; Go in `GOPROXY=direct` mode does the same thing.

**Pascal specifics**

- A library is a repository with modules in the root (or in `src/`) and its own `deps.txt`. The build adds
  `-Fu` for each dependency; for those who need the "file alongside" variant (§2), `sp vendor --flat`
  puts the modules next to the sources.
- Module names with an owner prefix (`Acme.Json`; FPC supports dotted module names),
  otherwise two libraries with a `Json` module will not build together.
- **Unsafe audit (an analogue of cargo-geiger, for free).** The marks `// UNSAFE:` and `// UNSAFE-UNIT:` are found by grep,
  so `sp unsafe` shows the unsafe surface of each dependency even before it is included.
  The line `deny-unsafe github.com/acme/json` in `deps.txt` stops the build if unsafe code has appeared in a new version
  of the dependency.

**First step (2026-11-04).** What exists is what a library on an amateur's GitHub needs, with no hosting of ours:
`tools/bp get [DIR]` reads `DIR/deps.txt` (`module`, `safe`, `require path vX.Y.Z`, `mirror path URL`, `dirs`; `//`
comments), mirrors each repository once into `${BP_CACHE:-~/.cache/bp}/mod/<path>.git` (`git clone --mirror`, later
`git fetch`; the `mirror` lines when the first URL fails; a path that starts with `/` or `file://` is a local
repository), selects the versions by MVS (the greatest of the versions required by the modules reached; no solver, no
ranges) and writes `DIR/deps.lock`, one `path version commit` per selected module, sorted by path. A recorded commit
wins: a tag that now points elsewhere stops `bp get` with both commits named, until its line is deleted from the lock.
Each selected version is extracted once, read-only, into `mod/<path>@<version>/` (`git archive`, never a checkout).
`tools/bp build` and `bp fix` read `deps.lock` and add the `dirs` of each module (from its own `deps.txt`, default
`. src`) as `-Fu` and `-Fi`, from `vendor/<path>/` when it is there, else from the cache (fetched when missing, so a
clone with a lock builds without `bp get`); `tools/bp vendor` fills `vendor/` (listed in `vendor/modules.txt`) for a
build offline and in ten years; `vendor/` is not checked by `bpvet` as a part of the program. The tool is
`tools/bpget/bpget.pas`, a program of the dialect that `bp build` checks before it builds it; the test is
`tests/deps.sh`. This repository is a module itself (`deps.txt`: `module github.com/unxed/bp`, `dirs . safe ext`).
Not yet: the Software Heritage archive as the last fallback, `bp unsafe` and `deny-unsafe`, `bp vendor --flat`, major
versions as new unit names (nothing checks them yet), the repositories fetched in parallel by goroutines.

## §16. What else to take from Go and Rust (plan)

### The `sp` tool: one command, like `go`

The main convenience of Go is not the language but one command for everything. Each `sp` subcommand is a thin wrapper over
what is already shipped with FPC (verified: `ptop`, `fpdoc`, `data2inc`, `bin2obj`, `h2pas` are installed together with
`fp-compiler`), so each subcommand is small:

| `sp` | Analogue | Built on |
|---|---|---|
| `sp build [-release]` | `go build` | `fpc` + `-Fu` of the dependencies + a check profile (§6): debug `-Cr -Co -CR -Sa -gh -gt`, release without `-Cr -Co -CR`. **The first part exists: `tools/bp build [--release] [fpc options] FILE`** runs `bpvet --strict --typed` over the directory of `FILE` and calls `fpc` (debug adds `-Cr -Co`) only when the check passes, so unsafe code is built only where it is declared (`// UNSAFE:`, `// borrow:`, `// root:`); bpvet and the RTL stubs are cached by content (`~/.cache/bp`), and a cached check takes about 30 ms (`tests/bp.sh`) |
| `sp test` | `go test` | a generalized `tests/run.sh`: `test_*.pas` (return code = number of failures) and `compile/*.pas` with `// EXPECT:` (an analogue of trybuild in Rust); `examples/*.pas` are built too (an analogue of Rust doc tests) |
| `sp vet` | `go vet`, clippy | a linter on `fcl-passrc`: S3–S14 |
| `sp fix` | `go fix`, `cargo fix` | **exists as `tools/bp fix [fpc options] FILE`**: `bpvet --fix` over the directory of `FILE`: the header from the file name (S21), reserved words in lower case (S22), the `// root:` marks of exported routines (S17); the rest is listed, nothing is built |
| `sp fmt` | `gofmt` | `ptop` with a single fixed config from this repository: one style, no settings; reserved words in lower case (S22) |
| `sp doc` | `go doc` | `fpdoc` |
| `sp get / vendor / unsafe` | `go get`, `go mod vendor`, cargo-geiger | §15. **`tools/bp get` and `tools/bp vendor` exist** (`tools/bpget/bpget.pas`, a program of the dialect): MVS over git tags, `deps.lock` with the commits, the module cache, `vendor/`; `bp build` reads `deps.lock`. `unsafe` is a plan |
| `sp embed files` | `//go:embed` | `data2inc`: files are turned into a module with constant arrays |
| `sp fuzz` | `go test -fuzz` | below |

`sp` is written in Safe Pascal itself as a single file (dependencies are downloaded in parallel by goroutines §14):
the tool also serves as an example project.

### The tools are as fast as the compiler (a rule)

FPC builds a module in milliseconds, and that is a reason to choose Pascal. A tool of Better Pascal that runs on every build
or save (`bpvet` in every mode, `--fix`, `sp fmt`, the stub generator, the steps of `sp build` and `sp test`) must not take
it away. Go (`go vet` on the build cache), ruff (a cache by file content, written in Rust for speed) and rust-analyzer
(incremental queries) show what users now expect; a linter that makes the build feel slow is turned off.

- **Budget.** On a whole project a tool takes no longer than `fpc` takes to build it from nothing; after an edit, no longer
  than `fpc` takes to rebuild: a few milliseconds for a changed module, close to nothing for an unchanged one.
- **Cached by content.** The result for a file is kept under the hash of its text, of the interfaces of the units it uses
  (what a `.ppu` records), of the options and of the version of the tool; an unchanged file is not checked again. The cache
  lives outside the repository (`${XDG_CACHE_HOME:-~/.cache}`), as the stub generator already keeps its `ppudump` output by
  the hash of each `.ppu`.
- **Work done once.** The typed mode resolves the interface of a unit once per run, not once per file that uses it, and
  keeps it across runs as FPC keeps a `.ppu`. Independent files are checked in parallel.
- **Measured.** CI prints the time of each tool on this repository next to the time of `fpc`; a tool over its budget is a
  bug, as a wrong finding is.

Today (2026-11-04, 114 files, 6.8k lines, one core): `bpvet` 0.13 s (`fpc` builds `tests/safe/test_safe.pas` in 0.14 s),
the typed mode 0.27 s, the stub generator 0.3 s with a warm cache. The typed mode took 2.4 s while it read every used unit
again, implementation included, for each file; now a used unit is read once per run, up to its implementation. Next: a
cache across runs, and timings in CI.

### Fuzzing almost for free

In C a fuzzer needs sanitizers, otherwise memory corruption goes unnoticed. In Safe Pascal a memory error is already
turned into an exception (`ESafety`, `ERangeError` with `-Cr`, `EAccessViolation`), so the very
simplest fuzzer suffices: `fuzz_*.pas` declares `procedure Fuzz(const Data: array of Byte)`, `sp fuzz` feeds
random and mutated inputs from a corpus folder, and an input that caused an exception is saved as a new test.
This is a few dozen lines on top of `sp test`.

### Sum types and exhaustive matching (enum and match from Rust)

Tagged variant records have existed in Pascal since 1970. Two checks are missing, and both are the linter's job, not the library's:

```pascal
uses Safe;

type
  TShapeKind = (skCircle, skRect);
  TShape = record
    Name: String;                      // managed fields — in the common part
    case Kind: TShapeKind of
      skCircle: (R: Double);
      skRect:   (W, H: Double);
  end;

function Circle(const AName: String; const AR: Double): TShape;   // create only this way
begin
  Result := Default(TShape); Result.Name := AName; Result.Kind := skCircle; Result.R := AR;
end;

function Area(const S: TShape): Double;
begin
  case S.Kind of                       // all values of the enumeration, no else
    skCircle: Result := Pi * S.R * S.R;
    skRect:   Result := S.W * S.H;
  end;
end;
```

- **S13 (exhaustiveness).** A `case` over an enumeration lists all values and has no `else`; when `skTriangle`
  is added, the linter will show every place that must be completed. FPC 3.2.2 itself does not warn
  about this (verified).
- **S13 (tag).** A variant field (`S.R`) is read only inside the branch of `case S.Kind of` with its tag.
- Errors remain exceptions plus `TryX` (§0); an enumeration of failure causes (§12) is
  `Result<T, E>` without a new type.

### Immutability by default (`let` versus `let mut`)

**S14:** parameters are `const` by default; `var`/`out` only when the caller must see the change;
constants are `const`, not variables that nobody changes. The compiler already forbids writing to a
`const` parameter. `bpvet` errors on by-value strings, records, open arrays (except `array of const`)
and dynamic arrays without `const`/`constref`/`var`/`out`, because the callee receives a copy. For
other by-value types, it warns when the routine body does not syntactically write to the parameter;
it also warns on typed `var` parameters without a detected write. Assignment targets, call arguments,
method receivers, address-taking, `for`, `with`, and nested routines count as writes. This conservative
scan does not resolve callee signatures or types. Overrides, procedures without bodies, untyped `var`
parameters, and procedures whose address is taken in the module are excluded. `// UNSAFE: <why>` on
or above the parameter suppresses its S14 finding.

### What we deliberately do not take

| In Go/Rust | Why we do not take it |
|---|---|
| borrow checker | impossible without changing the compiler; replaced by the rules S5/S11, the runtime (§4, §8) and, for the region style, the root analysis of Goose in `bpvet` (S17, §20): a reference has one root and does not outlive it, with no lifetime annotations |
| `?` and `Result<T, E>` | in Pascal exceptions with guaranteed finalization (`TOwned`, `TDefer`) give the same more briefly |
| the `-race` race detector | races are prevented by S11 (ownership is passed into a task, not shared access); the open cases (arrays, shared objects, globals) are closed by §21.2 |
| a central registry (crates.io), the Go proxy | no infrastructure; in the "hash + mirrors" model (§15) they are not needed |
| M:N scheduler | reconsidered: the stacks of `BPThreads` make it small (§21.3, plan) |

## §17. Version history

| Version | What was added |
|---|---|
| v0.1 | core: UTF-8 by default, `TOwned/TShared/TWeak/TSlice/TArena`, shadowing of dangerous primitives (S1–S4), rules S5–S10 for the linter, R1–R4 |
| v0.2 | ideas from Zig (§12): `TDefer`, `SafeLiveCount`/`SafeCheckNoLeaks` (R5); `-dSAFE_NO_CWSTRING` for static Linux without libc; a measurement on real code (DOS Navigator, `unxed/dn`): the `object`/`class` gap |
| v0.3 | FFI (§13, S12, `TCResource`), goroutines (§14: `TGroup/TTask/TChan/Select`, R6–R8, S11) |
| v0.3.1 | table of verified targets (§2): x86_64/i386/aarch64 Linux, DOS, Windows; R8 on targets without threads (DOS) instead of hanging; the §0 card extended (defer, tests, old style, targets) |
| v0.5.1 | `.Free` is a compile error (a helper with a stub parameter); CI: static audit, Alpine/Debian/Ubuntu 16.04/CentOS 7, `SAFE_LIBC` mode, i386 and aarch64 under qemu |
| v0.5 | §18: Linux without libc by default (fpwidestring, a thread manager on clone/futex), `-dSAFE_LIBC`, verification on x86_64/i386/aarch64 and Alpine; the decision on GC |
| v0.5.1 | §2 aligned with v0.5: a matrix of verified targets on v0.5 code (i386 and aarch64 without libc pass all tests without switches); `test_threads` is skipped on DOS |
| v0.5.2 | §0 "What actually exists and what is only a plan so far"; §19 (Turbo Pascal style code) |
| v0.6 | Better Pascal: the safe layer (`safe/`, `unit Safe`) and the ext layer (`ext/`: UTF-8, goroutines, `BPThreads`); `unit BP` gives both |
| v0.6.1 (design) | §20 memory styles: several safe styles in one program, the region style from Goose with the root analysis S17, the current region (the Goose scope made implicit), the GC style (a heap per goroutine), style boundaries S18 and `// BP-STYLES:`; §18: the GC decision reconsidered |
| v0.7 (design) | §21 concept v3: one scope object (region + defer + held objects; `TArena` and a local `TOwned` fold into it), Send and Sync inferred by `bpvet` (H14–H16 found and listed), goroutines M:N on the stacks of `BPThreads` with deadlock detection and a seeded scheduler, the `TComponent` tree as an owner; what is reused from which language |
| v0.8 (design) | §22 final touches: what the users of Go, Rust, Zig, Swift, Kotlin, Gleam and Deno love and Better Pascal lacks (mostly tooling), each on something FPC already ships; what is not taken now and why |
| v0.8.1 (design) | §22: interpolation on the existing syntax (`Fmt` + `--fix` + S20); nil as a guarantee (§22.9: H19 found, S26a-c); hot reload of routine bodies (§22.10) |
| v0.9 (design) | §23 systems programming and the world of C: four profiles (S, U, H, F), bindings as tables of names bound at run time with no versioned import, the measurements on FPC binaries, kernels and drivers (hardware as types, inferred contexts) |
| v0.10 (design) | §24 concept v4: one sentence for all lifetimes; marks of fact written by the machine, marks of intent by hand; `BP` last everywhere (`-FaBPThreads`, measured); what FPC 3.2 ships and the dialect had not used (nested procedure variables, type helpers, CORBA interfaces, all measured); `// raises:` inferred; the holes of §8 the table missed (an unchecked class cast, an untyped parameter, an uninitialised variable: H17–H19, S24, S25, `-Sew`); README rows for deploy, C, the standard library and models |
| v0.11 | §21 step 1: S11m (Send = move), S11s (Sync = frozen or `// sync:`) and S19 (`static mut`) in the typed `bpvet`; S17 counts only the values whose type can hold one of a region; R17 at `Send` in `SAFE_DEBUG`; S19 on the globals of a program reached by a task |
| v0.12 (plan) | §25: one order for the plans of §21–§24 (bugs first, then the holes of §8, then what the next steps stand on); the goal of speed against C, Rust, Go and Goose; H17 used twice (the uninitialised variable is H19), S21a-c renumbered S26a-c (S21 is the header), §22.9 and §22.10 moved back into §22 |
| v0.13 | §24.8 steps 1–2: `tools/bp build` adds `-FaBPThreads` and `-Sew`; `BP` is last in the program file too (S7 an error there); CI builds the tests with `-Cr -Co -Sew` |
| v0.14 | §22.8 step 0: S26a (definite assignment of class references) and S26b (a class under 64 KiB) in the typed `bpvet`; H19 closed |
| v0.15 | §24 step 3: S24 (a class downcast is `as`, `--fix` writes it) and S25 (an untyped parameter, a typecast of one, `absolute`) in the typed `bpvet`; H17 and H18 checked; the claims row of H19 said H17 |
| v0.16 | §25.1 step 3: the benchmark suite `tests/bench/compare.sh` (binary trees, n-body, fannkuch, word count in Bp, C, Rust and Go; Goose not installed) and the baseline of §25.2; a non-failing CI step |
| v0.4 (plan) | §15 dependencies like Go without a proxy (a git hash instead of a checksum database, mirrors, `vendor/`, unsafe audit); §16 the `sp` tool, fuzzing, sum types (S13), parameter immutability (S14) |

## §18. Portability like Go: Linux without libc by default (v0.5)

- **The default on Linux is a static binary without libc**: strings — `fpwidestring` + `unicodeducet` (Unicode in Pascal, case and sorting work even with `LANG=C`), threads — `ext/bpthreads.pas` (an FPC thread manager on `clone` + `futex` + `mmap`, like the Go runtime). One file works on any distribution: verified on an Ubuntu host (glibc) and in an Alpine 3.20 chroot (musl); a libc build does not run on Alpine at all.
- **A program with goroutines**: `uses ..., BP;` last, as in every unit; `tools/bp build` adds `-FaBPThreads` (instead of `cthreads`) on all targets (§24.3).
- **`-dSAFE_LIBC`** (an analogue of cgo): `cwstring` + `cthreads`; needed only for FFI with C libraries. If libc is loaded and the switch is absent, the first `BeginThread` stops the program with an explanation (code 232) rather than giving a silent race (`tests/ext/compile/mf_libc_guard.pas`).
- Verified (FPC 3.2.2, cross-compilers built from the official sources): x86_64 natively and in Alpine; i386 natively and under qemu-i386; aarch64 under qemu-aarch64 — `test_safe`, `test_go`, `test_threads` (1500 tasks: heap, strings, exceptions, recursive locks, `TThread`, events) — 0 failures, 10 repeats without crashes.
- Design: the current thread is found by the stack pointer (the stack region is aligned to its own size, at its start is the thread record with the threadvar block; the main thread is the range `[stack limit, argv)`), without assembler TLS; assembler only for `clone` (≈20 lines per architecture).
- In the terms of `unxed/static-everywhere` the default is "Profile S"; `SAFE_LIBC` is "Profile H" (the baseline glibc version = the version on the build machine). CI checks that the binaries have no INTERP/NEEDED (`readelf`) and runs them in Alpine, Debian, Ubuntu 16.04 and CentOS 7 containers. Plan: host data (CA certificates, time zones) to be read from the host rather than embedded.

**GC — reconsidered on 2026-11-04 (owner decision): an optional style, §20.** The paragraph below was the v0.5 decision.
Its argument against a conservative scanner of the whole heap (Boehm) still stands; §20 scans conservatively only the
stack of one goroutine, the heap is precise (edges are the published fields, read from the VMT), and every goroutine has
its own heap, so there is no stop-the-world. The default rule for an LLM below stays: the GC style is for graphs where
ownership is unnatural, not "when in doubt".

**GC — weighed, not adopted (v0.5).** For an LLM the difference from Go is choosing the owner of an object and two "holes": `TShared` cycles and a borrow that outlives its owner. Values (strings, arrays, records) are managed automatically anyway. Cycles are caught by `SafeCheckNoLeaks` in tests (R5), a dangling borrow by the debug build `-gh -CR` + `HEAPTRC=keepreleased` (memory is not reused, a method call on a dead object is caught). The ARC + weak + arenas model is the Swift model, and a great deal of application code is written on it without a GC. A tracing GC without compiler support would be a conservative scanner of stacks and heap (Boehm) — a large unsafe component with non-deterministic destructors: overengineering. The default rule for an LLM: "if you do not know what to choose — TShared; back references — TWeak; trees and graphs — TArena".

## §19. Turbo Pascal style code (`object`): plan

Rationale: a measurement on real code (DOS Navigator, `unxed/dn`): `New(` 843+103, `Dispose(` 421+39, `object` types 230+75 versus one `class`, `ShortString`/`String[N]` about 300.
`TOwned<T: class>` does not cover such code, and shadowing `New/Dispose` gives thousands of S1 errors that are not defects.

| Option | Essence | Decision |
|---|---|---|
| (c) an unsafe layer with a safe facade | old code is marked `// UNSAFE-UNIT:`, new code is written per SPEC | **first**: zero risk, gives measurements (a violation counter) |
| (a) extend Safe Pascal to `object` | an owner over an `object` type: a pointer + a "lifetime lock" with a release procedure (`Done` + `Dispose`); for `object`, `New/Dispose` are not shadowed | **second**: a narrow prototype on a small slice, a checkpoint by the numbers |
| (b) move the code to `class` | `Init/Done` → `Create/Destroy`, ~1400 call sites | **fallback**: only for a slice where (a) did not give guarantees |

The order (the RUP method: from simple to complex, atomic steps with tests, something to try at every step) and steps S0–S10 are kept in `unxed/dn`, `PLAN.md`, the section "Safe Pascal as the DN code style". The license is MIT.

## §20. Memory styles: one language, several safe styles (design, plan)

Status: design only, nothing of this section is implemented yet. The plan by steps: unxed/bp#108.

### The principle

Better Pascal does not pick one memory model for the whole program. The style is picked by the data structure (§0, §4),
several styles live in one program, and `bpvet` accepts every safe style and rejects only unsafe code that is not marked
(§7). Object-oriented code is not forced into a style that does not suit it: class objects use the owner, arena or GC
style, flat data uses the region style, and the two meet only through copied values.

| Style | Types | Cost | Freed when | Guaranteed by |
|---|---|---|---|---|
| values | `record`, `String`, `TArray<T>` | as in FPC | automatically | the compiler |
| owner | `TOwned`, `TShared`, `TWeak` | one atomic counter | owner leaves its scope / last reference | runtime construction + `bpvet` S5, S10, S15 |
| arena | `TArena`, `TArenaRef` | a list of objects | `FreeAll` / scope exit | runtime (R10) + `bpvet` S17 (plan) |
| region (from Goose) | `TRegion`, `TRegionObject`, `TGrowArray<T>` | **zero** in a release build: a bump pointer, release is one store (+ finalizers only for types with managed fields) | the region leaves its scope | `bpvet` S17 (static); `SAFE_DEBUG` R12 as a second net |
| GC | `TGcObject` classes, `TGcList<T>` | mark and sweep per goroutine, no barrier | by the collector of the goroutine | the collector + `bpvet` S18 |

**The decision tree** (the same as §0, the first that fits wins): a value → values; one owner → `TOwned`; several owners →
`TShared` + `TWeak`; data that dies together at the end of a step (a request, a frame, a compiler pass) → region; class
objects with one fate → arena; a graph with cycles and no natural owner → GC. An LLM that does not know what to choose takes
the earlier branch: a wrong early choice is a compile or lint error, never a memory error.

**Style boundaries (S18).** Between styles only values are copied (`record`, `String`, `TArray<T>`, `Copy`). A region
object, an element of a `TGrowArray`, a borrow and a GC reference never go into a place of another style (a field of a class owned by
`TOwned`/`TShared`, a global, a task field, a channel message). The rule is the same as S11 for tasks and generalizes it.

**`// BP-STYLES:` allow-list.** A program file may restrict the styles of the whole program, for example
`// BP-STYLES: values owner region` in a latency-critical service: `bpvet` then rejects GC classes in every module of the
program. Without the line all styles are allowed. "No hidden pauses" (unxed/bp#56) is thus a property a project can
demand and `bpvet` can check, not a property of the language.

### Why a linter gives the guarantee of a checker in the compiler

Goose checks its roots in its own compiler; Rust checks lifetimes in rustc. A check is a pass over the typed syntax tree:
it does not have to live inside the code generator. `bpvet` runs the same pass over the same sources, and FPC keeps doing
what it does well: compiling fast, to one static binary, without a C toolchain. The guarantee is equal under four
conditions, and the plan treats each one as a requirement:

1. **Typed.** The analysis works on resolved types (`PasResolver` of `fcl-passrc`, shipped with FPC), not on names. The
   rules S3–S16 today read names and lines; S17 cannot.
2. **Sound.** What the analysis cannot prove is an error, not a silence. The way out is `// UNSAFE: <why>` (§7), visible
   to grep and to `sp unsafe`.
3. **Mandatory.** A program is built by `sp build` (§16), which runs `bpvet` before `fpc`, and CI runs `bpvet --strict`.
   Code compiled by a bare `fpc` without `bpvet` is not checked: this is the price of not forking the compiler, and it is
   stated here rather than hidden.
4. **Modular.** A routine is checked against the signatures of the routines it calls, never their bodies, so `bpvet`
   stays as fast as the compiler and a module is checked once.

"Zero cost" means that the safety of the region style adds nothing to the release binary: no counter, no check, no
header. It does not mean the code generator of FPC equals LLVM; the benchmark of the plan compares honestly.

### Spike 1 result: a typed `bpvet` on `PasResolver` (2026-11-04, FPC 3.2.2)

A driver (`tools/spikes/resolver/`) runs `PasResolver` of `fcl-passrc` over every module of `safe/`, `ext/` and `tests/`.
Verdict: **it works, with three conditions.**

- **Resolved in full:** `tests/safe/test_safe.pas` with `Safe` (`TOwned`, `TShared`, `TWeak`, `TSlice`, `TArenaRef` are
  specialized, method bodies of the generics included), `safe/safe.pas`, `tests/bench/bench_arena.pas`, the compile tests
  that must compile. The seven compile tests that must **not** compile (`mf_new`, `mf_getmem`, `mf_move`, ...) are rejected
  by the resolver as by FPC. The rest failed only on stub coverage (below), not on the code.
- **Condition 1: a small fix of the resolver.** `PasResolver` (3.2.2 and main alike) rejects the ObjFPC idiom
  `class function TOwned.Own(AObj: T): TOwned;`: the bare name of a generic inside the implementation of its own method.
  FPC accepts it, and `safe/core.impl.inc` uses it throughout. The exemption in `TPasResolver.CheckUseAsType` covers only
  elements inside the declaration of the type; it must also cover a method implementation whose procedure scope belongs to
  that type. With that one condition extended (about 20 lines) the whole of `test_safe` resolves. The method is not
  virtual, so a subclass cannot do it: `bpvet` must build with a patched `pasresolver.pp`, and the fix should be offered
  to FPC. How the patched file is obtained (fetched and patched at build time, or kept in the repository) is a licence
  question for the owner: `fcl-passrc` is under the FPC licence (LGPL with a linking exception).
- **Condition 2: the RTL is read from stubs, and the stubs are generated.** The real `System` cannot be parsed by
  `fcl-passrc` (`{$if declared(...)}`, compiler-internal declarations, constructs the resolver does not implement). A stub
  unit with the declarations only works; hand-written stubs were enough for `test_safe`. They need not be hand-written:
  `ppudump -Fj` of FPC 3.2.2 exports the full interface of a compiled unit as JSON (`system.ppu`: 1839 symbols, routines
  with parameters, classes with fields), so a generator turns the `.ppu` files of the installed FPC into exact stubs.
- **Condition 3: the resolver only resolves, FPC checks.** Where the resolver (made for pas2js) is stricter than FPC
  (a class or a pointer cast to an integer, `PChar` assigned to `String`), `bpvet` accepts: its overrides of
  `CheckTypeCastRes` and `CheckAssignCompatibilityCustom` are virtual. Type errors are the compiler's job; `bpvet` needs the
  types, not a second opinion on them. Compiler magic with variable arguments (`WriteLn`, `SizeOf`, ...) is registered as
  built-in routines that accept any arguments.
- **Found on the way:** `for V in Ch` over a channel uses a record enumerator, which the resolver of 3.2.2 rejects
  ("expected result class"); this needs a second small fix or a class enumerator.

### The typed `bpvet` (step 6 of #108, 2026-11-04)

`bpvet --typed --rtl DIR` resolves every checked file with the units it uses (`tools/bpvet/bpvettyped.pas`); a file that
does not resolve is a Fatal with the position. The conditions of Spike 1 are met as follows.

- **The resolver is patched at build time.** The owner's decision: the repository keeps only the patches
  (`tools/bpvet/resolver/*.patch`, under the licence of `fcl-passrc`); `resolver/get.sh` takes `pasresolver.pp`,
  `pparser.pp` and `fcl-passrc.inc` of FPC 3.2.2 (from the installed FPC sources, else from the release tag), checks their
  SHA-256 and applies the patches (`pastree`, `pparser`, `pasresolver`; each header lists its changes); `build.sh`
  builds `bpvet` with the result. They make the resolver accept what FPC accepts and Better Pascal uses: the bare name of
  a generic in its own method, a record enumerator, `String[N]` in a variable, the operators of a record (`Implicit`, and
  the management operators `Initialize`/`Finalize`/`Copy` of `TRegion`), a typed pointer for a `Pointer` var argument, a
  pointer to a member type of a generic declared after it; and they let a used unit be read up to its implementation.
  FPC main has most of them; the rest are offered upstream when `bpvet` moves to the next FPC release.
- **The stubs are generated.** `resolver/genstubs.py OUT SRC...` writes the RTL stubs from `ppudump -Fj` of the installed
  units (fp-utils): only the closure of what the sources name, so one run for the checked tree gives 13 units and a few
  hundred symbols. The used units are found in the stub directory first, then in `-Fu`, `-Fi` and the directory of the
  file; `-FaUNIT` adds an implicit unit, as for `fpc`.
- **The resolver only resolves**, as in Spike 1 (permissive casts, compiler magic with any arguments).
- **CI** (`tests/typed.sh`, job `lint`): every module of `bp.pas`, `safe/`, `ext/` and `tests/` resolves; the only files that
  do not are the seven compile tests that must fail. The output of the rules is unchanged (`tests/lint.sh`). On the way
  the typed mode found three lint tests that FPC itself rejects (a nested procedure passed as a plain procedure, a
  `var` parameter as a loop counter, a declaration with a different parameter mode); they were made valid Pascal.

### Early S17 result: the root analysis on code of the region style (step 8 of #108, early, 2026-11-04)

Before the runtime (steps 4 and 12) is built on the root analysis, a first S17 (`tools/bpvet/bpvets17.pas`, in the typed
mode) was run on the code of the style, to see whether it proves real code with few marks or buries it in findings.
Verdict: **it works; one form was missing and is added to rule 4 (below).**

- **What it checks:** rules 1-4 inside a routine and through the signatures of the routines it calls. Roots are a bit set:
  the caller's current region, each region object or region parameter (incomparable with each other), each local `TRegion`
  in the order of creation (a later one is inner). Stores go into locals (the root is replaced), fields of records and
  region objects (the roots must outlive the target), `Result` and `var` parameters, globals, fields and methods of other
  styles, channels; `Reset`, `Release` and a second `TRegion.Create` free what the region and the regions created after it
  hold, and a later read is rule 3. Loops are walked twice, branches are joined. Nested routines read the locals of the
  routine they are in as the caller's region and write them as `var` parameters. 2-5 % of the time of the typed run.
- **Measured.** The spike-2 tests (`tools/spikes/region/regiontest.pas`, 300 lines, 14 routines) and the examples of this
  section (`tests/lint/s17_ok.pas`): no finding, no mark. A calculator written in the style as a user would write it
  (`tests/lint/s17_calc_ok.pas`: a lexer, a recursive-descent parser into a tree of region objects, an evaluator,
  definitions kept across lines in a region of the run, a region per evaluated line; 280 lines, 15 routines): 3 findings,
  all of one kind, and no `// UNSAFE:`. Building a tree by returning new nodes (`Result := TExpr.Create;
  Result.Left := A`) needs nothing: the parameters outlive the caller's current region.
- **The missing form: a routine that keeps a new value in an object it is given.** `TExpr.AddArg(A)` (append to a list of
  `Self`) and `TCalc.Define` (push a new `TDef` into `Self.Defs`) store a value of the caller's current region into `Self`.
  Without more information that is an error by rule 1, and a true one: called on an object of an outer region while an
  inner one is current, the outer object would point into the inner region. Rust says the same with a lifetime bound
  (`fn add<'a>(&'a mut self, a: &'a Node)`), Go and C# do not need it (a collector). **Added to rule 4:** `// root: Self, A`
  on the header of a routine without a `TRegion` parameter says that `Self` and `A` are in the caller's current region:
  the body may keep values of that region in them, and **every call is checked** to pass them in the current region. The
  calculator needs 3 such marks (`AddArg`, `Define`, and `RunLine`, which calls `Define` on its parameter): about one per
  90 lines, on each routine that adds to an existing structure.
- **Not elided by default.** Making every method of a region class bound to the current region (as Rust elides lifetimes
  of `&self` methods) would turn every read of an outer object inside an inner region (a lookup in a table of the run
  while a scratch region is current) into a finding at the call. An elision for the methods whose body stores into `Self`
  is possible inside one unit; it waits for more code of the style (the editor of `dn`, step 12).
- **The untyped rules do not know the style.** Without `--typed`, S6 reports every allocation of a region object (25 on
  `regiontest.pas`) and S5 every field of a region class; the typed mode drops those that S17 answers. Code of the region
  style is checked with `--typed`.
- **Found for the runtime (step 4).** A `TRegion` global assigned in the main block of a program is copied by FPC (the
  result goes through a temporary), and the `Copy` operator of the spike raises: a region is a local of a routine, and
  S17 is to report a `TRegion` global. `tools/bpvet/resolver/genstubs.py` drops `class` from a class property
  (`TEncoding.Default` when the sources name `Default`).
- **Not in the early S17:** `with` (a field without a base loses its root), goroutines and `TChan` beyond `Send`, S17a (a
  destructor), S17d (`// borrow: arena`), allocation in an explicit region (`Create(var R)`, not in the spike). Lint tests:
  `tests/lint/s17_*.pas`.

### S17 v2 (concept v2 of #108, 2026-11-04)

- **`// root:` is inferred inside a module:** the names a routine keeps values of the caller's current region in (`Self`,
  parameters, `^local` of the enclosing routine for a nested one) grow by a fixpoint over the bodies of the module, and
  calls are checked with them. Only an exported routine writes its marks (a contract for other units); a missing one is
  an error, and `bpvet --typed --fix` appends it to the header. The calculator (`tests/lint/s17_calc_ok.pas`) now passes
  with **0 marks** (3 in the early S17).
- **Holes closed:** a nested routine that keeps values of the current region in locals of its parent is not taken as a
  procedure value (`s17_callback_bad`); a direct call sets the roots of those locals to the current region of the call; a
  `var`/`out` argument that is not a local is a store of a value of the current region (`s17_varfield_bad`).
- **A `TRegion` is a local of a routine:** a global, a threadvar or a field is an error (`s17_global_region_bad`).

### Regions: scopes, speed, the debug net, a look at real code (2026-11-04; unxed/bp#124, #125)

- **The unit of a region is the connection or the loop, not the request** (unxed/bp#146, `examples/httpd`). A region
  per request costs an `mmap`/`munmap` pair per request through the FPC heap (a 4 KiB block taken and given back):
  throughput fell from 33 to 16 thousand requests per second. A region per connection, `Reset` after each request,
  keeps its block.

- **Scopes like Goose without block variables.** FPC 3.2 has none, but `for ... in` is a real scope, so the runtime
  gives two enumerators that own a region: `for R in Scope do begin ... end` (a region for the block) and
  `for Line in Each(Lines)` / `for P in A.Each` (a region per iteration, reset by each `MoveNext`). Measured: blocks nest
  exactly; an exception and `Exit` release in order; 200 iterations of 1000 objects peak at 60 KiB. FPC copies the
  enumerator once, before the first `MoveNext`, so the region is created there. A `Break` releases the region late, out
  of order with a `TRegion` created after it (R14): **S17 forbids `Break` out of a region loop**, and roots what the body
  allocates in the region of the loop, so a use after the block or in the next iteration is rule 3. With them the region
  style has three scopes: a routine (`TRegion` local), a block (`Scope`), an iteration (`Each`).
- **Strings** leave a region as copies: built in a region object in every iteration of `Each`, kept outside, they are
  intact after each reset (UTF-8 included) with one reference. S17 gives strings no root.
- **Iteration speed** (x86_64, 2·10^7 reads, ms): dynamic array 49 / 25 (-O1 / -O2), `At` 90 / 49, `for P in A` 43 / 63,
  `for C in A.Chunks` with `C.Data[I]` 47 / **17**. The loop over chunks is as fast as a plain array or faster; the element
  enumerator is compiled worse at -O2 than at -O1 by FPC 3.2.2 (a code generation issue of that shape). The fast form of
  the style is `for C in A.Chunks`; `At` (about 2x) is for random access.
- **`SAFE_DEBUG` (R12)** works: each block is pages of its own (`mmap`), and a reset or a release removes all access
  (`mprotect`, never reused), so a use after `Reset` stops with `EAccessViolation` at once. Nothing at access; unix only (no
  `mmap` on DOS). CI runs spike 2 with it.
- **Real code, a first look (not a port):** the highlighter of tve (`tve/src/tvehl.pas`) allocates little per line, and
  its results and language data live as long as the document. Regions fit the scratch work of an operation; the document
  stays in the owner or the GC style (concept v2). Parsers, AST builders and per-request work are the niches of the style.

### Spike 3 result: GC roots from the stack of the goroutine (2026-11-04, FPC 3.2.2)

A prototype collector (`tools/spikes/gcroots/`, run by CI on x86_64, aarch64 and i386 at -O1 and -O2): a heap per thread
(`TGcObject.NewInstance`), roots from a conservative scan of `[Sptr, SafeStackHigh)` after the callee-saved registers are
written to the stack, edges from the field table of the VMT, mark and sweep. Verdict: **it works on all three targets.**

- An object held only by a local survives, and so does an object held **only in one callee-saved register** (its other copy
  is masked, so the scan cannot see it there); a masked-only object is collected. Built without the register spill, the
  register check fails at -O1 (`r15` on x86_64): the spill is needed, and with it the scan is enough.
- 500 cycles of 2 and a ring of 1000 are collected once unreferenced, in the main thread and in a goroutine; the edges are
  read from the field table on all three targets (aarch64 aligns the entries).
- `BPThreads.SafeStackHigh` gives the end of the stack of the current thread (the region of a thread; `argv` for the main
  thread), so the range is exact.
- **Found: garbage can live as long as a stale word.** On i386 at -O2 a ring dropped by `R := nil` stayed alive: an old
  copy of its address was still in a slot of the same live frame. This is the known price of conservative roots: never a
  live object freed, but an unreferenced one may wait until the frame that held it returns. So `GcCollect` frees "what no
  live frame can still see", not "what the program no longer names"; a test or `SafeCheckNoLeaks` must drop references in
  a routine that has returned. Decided by the owner on 2026-11-04: this is the documented rule of the GC style
  ("When garbage is freed", below).

### Spike 2 result: the region style (2026-11-04, FPC 3.2.2)

A prototype (`tools/spikes/region/`, run by CI on x86_64, aarch64 and i386 at -O1 and -O2) of `TRegion`, `TRegionObject`
and `TGrowArray<T>`. Verdict: **the surface of §20 works as designed**, and one part of the design can be simpler.

- `R := TRegion.Create` with management operators (`Initialize`, `Finalize`, `Copy`): the region is released exactly once,
  when its variable leaves its scope, and the result of `Create` is never copied (FPC builds it in place). A `Copy` operator
  that raises catches an accidental second owner.
- `N := TNode.Create` of a `TRegionObject` class: objects lie one after another (32 bytes apart for a small class),
  `N.Next.X := 5` works through ordinary class references, `Free` releases nothing. Strings in objects and in array
  elements are finalized at `Release` (a string held 102 times is back to 1), and the heap does not grow over the run.
- `A.At(I).X := 42` with `{$modeswitch autoderef}` writes in place; `A[I]` reads by value; an array of region objects needs
  no modeswitch (`A[I].X := 7`).
- The current region: a routine without a `TRegion` allocates its result in the caller's region; regions nest; R14 and R15
  are raised; `Reset` in a loop keeps the region small (peak 60 KiB over 100 rounds of 1000 objects); a goroutine starts
  with no region and has a stack of its own.
- **Simpler than planned: no reserved range of addresses.** The prototype needs no `mmap` reservation at all: a region is a
  bump pointer in a list of blocks that double in size, and a `TGrowArray` keeps its elements in chunks of 16, 32, 64, ...
  elements (the chunk of an index is its highest bit). Nothing ever moves, and growth is limited only by memory, so the
  same code runs on x86_64, i386 and DOS and R11 is not needed. 10^6 elements of 8 bytes took 16 MiB of region (the doubling
  of chunks and of blocks). Decided by the owner on 2026-11-04: no reservation, no R11 (below).
- **Cost of `At`:** in a tight loop of 2·10^7 reads, `A.At(I).X` took about 3 times as long as `D[I].X` on a dynamic array
  (63 against 18 ms at -O2 on x86_64: the bounds check and the highest-bit lookup); under qemu 3 times on aarch64 and 7
  times on i386, where `BsrQWord` is a 64-bit routine (a lookup of the width of `SizeUInt` is the fix). Decided by the
  owner on 2026-11-04: `At` keeps its bounds check in release, and loops get the speed of a plain array from `for P in A`
  (below).
- A `TGrowArray` is a record that holds one pointer to its header in the region, so a copy of the record refers to the same
  array: no value-copy surprise.

### Region style (an idea from Goose)

[Goose](https://github.com/aardappel/goose) (Wouter van Oortmerssen) has no general heap: memory is the stack, static data
and data stacks with a bump pointer; everything allocated in a scope is freed at once when the scope ends; a growable value
never moves, so references into it stay valid; every reference has a statically known root (the variable that bounds the
life of its target) and must not outlive it; a function writes its result straight into a region of its caller; threads
exchange only flat values. This gives the speed of manual memory without lifetime annotations.

What Better Pascal takes: the bump region freed at once, the growable array that never moves, the root rule, results built in
the caller's region, flat messages between goroutines (already S11 and `TChan`). What it does not take: a new language and
compiler, the C backend, the static computation of the number of data stacks (here every region grows by blocks of its
own), the ban on dynamic dispatch (classes and virtual methods work in the region style too, below).

API sketch (names may change in the spike steps of the plan):

```pascal plan
TRegion = record                          // a bump pointer in blocks that double in size; a managed record
  class function Create: TRegion; static; // the new region becomes the current one of the goroutine
  procedure Reset;                        // rewind to empty, keep the largest block: one region per loop iteration
  procedure Release;                      // everything allocated in it, at once; also when it leaves its scope
end;

TRegionObject = class                     // a class whose objects live in the current region
  class function NewInstance: TObject; override;  // a bump in the current region instead of the heap
  procedure FreeInstance; override;                // nothing: the region frees its objects at once
end;

generic TGrowArray<T> = record            // grow-only, never moves: chunks of 16, 32, 64, ... elements in the region
  class function Create: TGrowArray; static;                // in the current region (below)
  class function Create(var R: TRegion): TGrowArray; static; // in a region named explicitly
  function Push(const V: T): SizeInt;     // index of the new element
  function Len: SizeInt;
  function At(I: SizeInt): PT;            // in-place access: A.At(I).X := 1 (needs {$modeswitch autoderef}, below)
  property Items[I: SizeInt]: T; default; // read and write by value: A[I] := V; bounds checked (R2) as TSlice
  function GetEnumerator: TEnumerator;    // for P in A: P is PT, chunk by chunk, no bounds check per element
  function ToArray: specialize TArray<T>; // a contiguous copy (for TSlice, FFI)
end;
```

**Objects in a region are ordinary classes.** A single value in a region is an object of a class that descends from
`TRegionObject`: `N := TNode.Create` allocates it in the current region (the class overrides `NewInstance`), and `N.X`,
methods, inheritance and virtual methods work as for any class. There is no reference wrapper, no `^`, no `.Get`: a class
reference in Pascal already is an implicit reference with dot access, and the root analysis gives it a root. This also
removes a limit of Goose: dynamic dispatch works in the region style. The price is the header of a class object (a VMT
pointer, one machine word); bulk data without a header goes into a `TGrowArray` of records.

- `TFoo.Create` of a region class is the allocation itself, so S6 does not ask for an owner; `Own/Share/Adopt` of a region
  object raises `ESafety` R16 (one `is` check at `Own`, not at access), and `bpvet` reports it statically.
- A region class has no destructor (S17a): the region never calls `Destroy`. What must be closed is held by `TOwned` +
  `TDefer` in another style.

**Elements of a `TGrowArray` in place.** `A.At(I)` returns a typed pointer, and with `{$modeswitch autoderef}` in the
module the call reads like a field access: `A.At(I).X := 42`, `WriteLn(A.At(I).Name)`. The module of the user never writes
`^`; the pointer type cannot be named there without `^`, so it cannot be stored (S4 still applies), and S17 roots the result
in the array. The modeswitch is needed in each module that does in-place access (it is per module in FPC), and the machine writes it,
not the user: `bpvet --fix` inserts `{$modeswitch autoderef}` after the mode line of such a module, as `goimports` adds an
import, and `sp build` and fpide (on save) run the fix before compiling. A compiler switch cannot do it instead:
`-Mautoderef` on the command line is reset by the `{$mode objfpc}` line of the module (verified on FPC 3.2.2). Without it the array is used by value: `R := A[I]; ...; A[I] := R`. An array
of region objects (`TGrowArray<TNode>`) needs no modeswitch: `A[I].X := 1` goes through the class reference.

**Strings and other managed fields are allowed.** A region object or a record in a `TGrowArray` may hold `String`, dynamic
arrays, interfaces, `TOwned`. At allocation the region checks, at compile time for a record (`IsManagedType`) and through the
class RTTI for an object, whether the type has managed fields; only such allocations go into a finalizer list of the
region, and `Release`/`Reset` finalizes them (`CleanupInstance` for an object, `FinalizeArray` for the used part of an array)
before the one store that frees the memory. So:

- flat data stays at zero cost: release is one store, as in Goose;
- a type with strings pays exactly what its strings cost anyway (they live in the ordinary heap with a counter), plus one
  list entry per object or per array, not per element;
- a `String` read out of a region object is an ordinary counted copy (`S := N.Name`): it outlives the region safely, and the
  root analysis has nothing to check for it; strings never need a root.

For text that must not touch the heap at all, a later step may add a region string (bytes in the region + a length,
compared and converted to `String` through operators); this is an optimisation, not a requirement of the style.

The prototype of all three (a region class with `NewInstance`, `At(I).X` with `autoderef`, finalization of strings at
release) was compiled and run on FPC 3.2.2 on 2026-11-04: objects are placed one after another in the region, and `heaptrc`
reports 0 unfreed blocks after the release.

**The current region (the Goose scope, made implicit).** In Goose a scope is a region and the compiler picks where a value
goes; nobody passes a region around. Better Pascal gets close to that without a new syntax:

- Every goroutine has a stack of regions (a threadvar). `TRegion.Create` pushes the region, leaving its scope or `Release`
  pops it. Regions are strictly nested, as the scopes of Goose are; releasing a region that is not the innermost one raises
  `ESafety` R14 (one comparison at `Release`, not at access).
- `TFoo.Create` of a region class and `TGrowArray.Create` without an argument allocate in the **current** region: the
  innermost one of the goroutine. With none, they raise `ESafety` R15; `bpvet` reports it statically where it can.
- **A routine that declares no `TRegion` allocates in the region of its caller.** This is how a result is "built in the
  caller's destination" in Goose: no region parameter, no copy.

  ```pascal plan
  type
    TFields = class(TRegionObject)
      Key, Value: String;
    end;

  function ParseLine(const S: String): TFields;  // no region here: the result lives in the caller's region
  begin
    Result := TFields.Create;
    ...
  end;

  procedure ProcessFile(const Name: String);
  var Scratch: TRegion; Fields: TFields; Line: String;
  begin
    Scratch := TRegion.Create;              // the scope of ProcessFile is now a region
    for Line in ReadLines(Name) do
    begin
      Fields := ParseLine(Line);            // allocated in Scratch, rooted in Scratch
      Emit(Fields.Key, Fields.Value);
      Scratch.Reset;                        // one region per iteration, as `for` scopes in Goose
    end;
  end;                                      // Scratch is released here
  ```

- A routine that needs scratch memory of its own declares a `TRegion`; what it returns to the caller is then allocated
  explicitly in the caller's region (`Create(var R)` with a region parameter, rule 4 below) or in a nested routine called
  before the local region is created. FPC 3.2 has no block-scoped variables, so the scope of a region is a routine; a loop
  uses `Reset` or a nested routine per iteration.
- Cost: pushing and popping at `Create`/`Release`, one threadvar read per allocation (`BPThreads` finds threadvars by the
  stack pointer); nothing at access.
- The explicit form `Create(var R)` stays for the cases where the current region is not the right one; S17 treats both
  forms alike.

- **No reserved range of addresses: the same on every target.** A region is a bump pointer in a list of blocks that double
  in size (from 4 KiB); a block that is full is left as it is, and the next one is taken from the heap. `Reset` keeps the
  largest block, so the next iteration of a loop usually allocates nothing (as `bump-scope` in Rust). A `TGrowArray` keeps
  its elements in chunks of 16, 32, 64, ... elements; the chunk of an index is its highest bit (as `SegmentedList` in
  Zig), found with a lookup of the width of `SizeUInt`. Nothing ever moves, growth is limited only by memory, and x86_64,
  aarch64, i386 and DOS behave alike: no fixed limit, no R11, no `mmap` reservation (the earlier design). Verified by spike 2.
- **Elements are not contiguous.** A `TGrowArray` cannot be passed as a `TSlice` or to FFI as one block; `ToArray` makes a
  contiguous copy, and data that must be one block is a dynamic array (`TArray<T>`, `TSlice`). Zig makes the same trade.
- **The cost of access.** `At(I)` and `A[I]` check the bounds in every build (R2, as `TSlice`, as Go and Rust do); in a
  tight loop they cost about 3 times a plain array index (spike 2). `for P in A` walks chunk by chunk and gives the speed
  of a plain array: the bounds are checked once per chunk, `P^.X` (or `P.X` with `autoderef`) is the element in place.
- **Goroutines.** A region belongs to one goroutine; S18 keeps its references there; data leaves through a channel by value.

**Root analysis (S17), the core of the style.** The root of a region object, of a `TGrowArray` and of the result of its
`At` is the `TRegion` variable or parameter it was made in. An allocation in the current region is rooted in the
innermost `TRegion` of the routine created before it; in a routine without one, in the caller's current region: such a
value may be returned, and at the call site it is rooted in the caller's innermost region (so a call inside an inner region
cannot be stored into a variable of an outer one). The rules:

1. A rooted value is stored only where it lives no longer than its root: a local of the same or an inner scope, or a field
   of an object or a record that is itself in the same region.
2. It is never stored into a global, a field of a class of another style, a task field, a channel or another style (S18).
3. `Release` or `Reset` of a region, or the end of its scope, while a value rooted in it is used later in the routine is an
   error.
4. A routine that takes one region parameter and returns a rooted value roots the result in that parameter: the result is
   built in the caller's region. With several region parameters the routine names the root with `// root: <parameter>`
   on its header line. A routine without a region parameter that keeps values of the current region in an object it is
   given names it the same way, `// root: Self, A`: those objects are in the caller's current region, and each call is
   checked to pass them so (the early S17 result, above). The signature is the contract; bodies of other routines are not
   read (modularity).
5. Unproven is an error (soundness); `// UNSAFE: <why>` drops it.

The same engine also checks `// borrow: arena` references against their arena (H3 statically), and the borrow-escape part
of S5 (H1) may move onto it: a borrow of `Owner.Get` is a value rooted in `Owner`.

`SAFE_DEBUG` keeps a second net for errors of `bpvet` itself, with no code at access: the blocks of a region are taken by
`mmap` in this build, a released block is not reused and its pages lose all access (`mprotect`), so a use after `Release`/`Reset` stops with `EAccessViolation` at once (R12) instead of
reading memory of another object. A release build reuses the memory.

### GC style

The aim is the surface of Go: no wrapper, no `.Get`, no owner to choose. A GC object is an ordinary class:

```pascal plan
type
  TNode = class(TGcObject)      // references first: the collector follows them
    Next, Child: TNode;
  public
    X: Integer;
    Name: String;
  end;

N := TNode.Create;  N.Next := TNode.Create;  N.Next.X := 1;   // nobody frees anything
```

- **Allocation.** `TGcObject` overrides `NewInstance`, as `TRegionObject` does: the object goes into the heap of the current
  goroutine. A goroutine has its own GC heap (as in Erlang): S11 already forbids sharing objects between tasks, S18 extends
  it to GC objects. The collector of one goroutine stops only that goroutine, for a time bounded by its own heap; there is
  no stop-the-world, no write barrier, no signals.
- **Edges: published fields.** `TGcObject` is compiled with `{$M+}`, so in a descendant the fields declared before any
  visibility section are `published`, and FPC lists published class fields with their offsets in the field table of the
  VMT. The collector walks that table up the class chain: the class needs no hand-written `Trace`. FPC allows only class
  types in `published`, which is exactly the set of references; other fields go after `public`. Verified on FPC 3.2.2 on
  2026-11-04 (`TNode.Next @8`, `TNode.Child @16`, read from the VMT; an `Integer` there is a compile error). The machine
  keeps this order for the user: `bpvet --fix` moves the reference fields of a GC class to its start and the others after
  `public` (S18), so nobody has to remember it.
- **Collections of references** are GC classes too (`TGcList<T>`, `TGcMap<K, V>`): their items are traced by the class
  itself. A dynamic array, a record or a class of another style that holds a GC reference is an error of S18: the collector
  would not see that reference.
- **Roots: the stack of the goroutine, scanned conservatively; the heap is precise.** Locals and parameters are plain class
  references, as everywhere in Better Pascal ("locals borrow"). At a collection the goroutine spills its registers to its
  stack (a few lines of assembler per architecture, as `clone` in §18 already has) and the collector scans that one stack
  range, which `BPThreads` knows exactly (§18): a word that points into an object of this heap keeps it alive. The heap
  itself is never scanned conservatively: edges come only from the field tables. This is the scheme of JavaScriptCore
  (conservative stack, precise heap), not of Boehm: the unsafe part is one scanner of one stack, a few hundred lines, and
  the §18 argument against a conservative scanner of the whole heap does not apply. A word that only looks like a pointer
  can keep garbage alive a little longer; it can never free a live object.
- **When garbage is freed (the rule).** `GcCollect` frees what no live frame can still see, which is not always everything
  the program no longer names: a stale copy of an address in a slot of a frame that has not returned (or an integer that
  happens to equal an address) keeps its object until that frame returns. A collection is not prompt and not guaranteed for
  a given object, and a program cannot tell: a GC object has no destructor, no finalizer and no weak reference (S18), so the
  moment it is freed is not observable, only the amount of memory is. The retention is bounded twice: by the life of the
  frame, and by the life of the goroutine, whose whole heap is dropped when it exits (no GC reference leaves it, S18), so
  nothing can leak past a goroutine. The one real risk is a long loop in a long-lived frame (the main loop of a server)
  holding an old address of a large graph; the idiom is the same as for regions: the work of one iteration goes into a
  nested routine. Prior art: D scans its whole heap conservatively too, and its known trouble is false pointers from heap
  data into large blocks, worst on 32-bit; here the heap is precise and only the stack of one goroutine is conservative,
  so the words that can hold garbage are few and short-lived (JavaScriptCore and Mono SGen accept the same for their
  stacks).
- **Mark and sweep, objects never move** (conservative roots require it). A collection starts when the heap has grown by a
  factor since the last one (like `GOGC` in Go, 100% by default) or on `GcCollect`.
- **Where a GC reference may live (S18):** a local, a parameter, a result, a published field of a GC object, an item of a GC
  collection. Not a `TWeak` (it would make the moment of freeing observable). Not a global (a long-lived object is held by
  a local of the main routine or of the task), not a field of a
  record or of a class of another style, not a dynamic array, not a task field, not a channel. `bpvet` checks it with types
  (§20, the spike), so the rule is not left to the programmer.
- **No resources in GC objects.** A destructor of a GC object never runs; a file, a socket or a lock is held by `TOwned` +
  `TDefer` in a local. `bpvet` reports a destructor in a GC class (S18).
- **Leaks.** The heap of a goroutine is dropped as a whole when the goroutine exits, without a scan. `SafeCheckNoLeaks`
  (R5) runs the collector of the goroutine first, then counts what is left; a test checks the GC heap after the routines
  that used it have returned (make and drop the objects in a nested routine), since a stale word in a live frame may still
  hold them.
- `SAFE_DEBUG`: `GcStats` reports the stack words that keep the most memory (the address of the word, so its frame, and
  the bytes reachable from it), to find the long-lived frame when memory grows.
- `SAFE_DEBUG`: swept memory is not reused and its pages lose access, so a reference the collector did not see (a hole in
  S18 or unsafe code) stops with `EAccessViolation` at once; a GC object used on another goroutine raises `ESafety` R13.
- **Targets.** The stack bounds come from `BPThreads` (the default on Linux) and from the main thread; with `-dSAFE_LIBC`
  the thread stacks of libc are not known yet, so the GC style is limited to the main thread there until the stack bounds
  are read from the thread attributes. DOS has one thread and works.

Considered and not chosen: a `TGc<T>` record with an interface field (references counted by the compiler, cycles collected
by trial deletion, as in CPython). It needs no stack scan and frees acyclic garbage at once, but every access is
`X.Get.Field`: the surface of `TShared`, not of Go. It stays the fallback if the stack scan proves unreliable on a target.

### New codes

| Code | Meaning |
|---|---|
| S17 | root analysis of the region style: S17a no destructor in a region class, S17b inside a routine, S17c across routines by signature (`// root:`), S17d `// borrow: arena` |
| S18 | style boundaries: rooted values and GC references stay in their style and goroutine; where a GC reference may live; reference fields first in a GC class (`--fix` reorders); a destructor in a GC class; `TWeak` or any other observer of the life of a GC object; the `// BP-STYLES:` allow-list |
| R11 | not used (it was a growth past a fixed reservation; regions and `TGrowArray` have no reservation, spike 2) |
| R12 | `SAFE_DEBUG`: access to a released region (its pages lose access: `EAccessViolation`) |
| R13 | `SAFE_DEBUG`: a GC object used on another goroutine |
| R14 | `Release` of a region that is not the innermost one of the goroutine (regions are nested) |
| R15 | an allocation in the current region when the goroutine has no region |
| R16 | `Own/Share/Adopt` of a region object (it belongs to its region) |
| R17 | `SAFE_DEBUG`: `TChan.Send` of a dynamic array that another variable also holds (the receiver would share it, H14) |

## §21. Concept v3: fewer things, fewer holes (design, plan)

Status: design; done are step 1 (§21.2) and the spike of the M:N switch (§21.3), the plan by steps is §21.7. A fresh look at the whole
concept against the table of the README (Rust, Go, Goose, Zig, Mojo) and the languages it does not name (Swift, Odin, Nim,
Pony, D, C#, Hylo, Erlang). Four changes. Each one reuses a mechanism that Better Pascal or FPC already has, so each one is
small; two of them remove concepts rather than add them.

### 21.1 One scope object: region + defer + held objects

Four parts of Better Pascal answer one question, "what is undone when this scope ends": `TRegion` (memory), `TArena`
(objects with one fate), `TDefer` (an action) and a local `TOwned` (one object). Go answers it with `defer`, Zig with
`defer` and arenas, C++ with destructors, Odin with the context allocator; underneath it is always one list of things to
undo. The region of §20 already keeps that list (the finalizers of objects with managed fields), so it can hold the other
three:

```pascal plan
for S in Scope do                       // or a TRegion local for the whole routine
begin
  S.Hold(Lines, TStringList.Create);    // any existing class: Destroy is called when the scope ends
  Lines.LoadFromFile(Name);             // a plain class reference: no .Get, no type alias
  S.Defer(@Term.Restore);               // an action: run when the scope ends, also on an exception
  N := TNode.Create;                    // a TRegionObject: a bump allocation, as in §20
end;                                    // undone in reverse order: Restore, Lines.Destroy, then the memory
```

- `Hold(out V; Obj: TObject)` takes an untyped `out`. The compiler cannot type it; the typed `bpvet` does: `V` is a local
  of a class type and `Obj` is a constructor call of that class or of a descendant (S6 accepts `Hold` as it accepts
  `Own/Share/Adopt`). Then S17 roots `V` in the scope: it is not stored into a field, a global, a task or a channel, and it is
  not read after the scope. The trick is legitimate for the reason of §20 ("Why a linter gives the guarantee"): the guarantee
  is the one of `bp build`.
- It replaces the most frequent idiom of Pascal, `X := TFoo.Create; try ... finally X.Free end`, with one line, for every
  class of every package (the LCL included), with no wrapper type.
- The loop variable of `for S in Scope` is a handle of the region (`TScopeRef`: a pointer, no ownership; S17 roots it too).
  The spike returns an `Integer` there today.
- `TOwned` stays the owner of a **field** (ownership that is not lexical, moved with `.Move`); a local `TOwned` is no longer
  needed. `TArena` keeps its API on the list of a region without bump memory (`Adopt` = `Hold`), and `// borrow: arena` is
  S17d with no engine of its own. `TDefer` stays for code without a scope; `S.Defer` adds to the same list. An exception in a
  destructor or a deferred action is counted as in `TDefer` (`SafeDeferFailures`), and the rest of the list still runs.
- Cost: one list entry per `Hold` or `Defer` (the list exists anyway), nothing at access.

### 21.2 Data races: Send and Sync, inferred

Three ways to share mutable memory between goroutines are open today (§8, H14–H16):

- **H14, a dynamic array is a reference.** `Ch.Send(A)` keeps the same array in the buffer (`FBuf[...] := V` in
  `ext/go.impl.inc`), and a `TArray` field of a task shares the array with the caller (§0 allowed it until v0.7). Both sides
  may write `A[I]`. A string does not have the problem: a write to a shared string copies it first.
- **H15, an object behind `TShared` is mutable.** S11 sends the programmer to `TShared` for an object two tasks need; two
  goroutines may then change it at once.
- **H16, a global is visible to every goroutine.** Nothing checks a write to it.

Rust closes all three with two auto traits checked by the compiler: `Send` (may move to another thread) and `Sync` (may be
shared). Pony closes them with reference capabilities (`iso` is moved, `val` is immutable and shared freely), Swift 6 with
`Sendable`. All of them reduce to three rules that the typed `bpvet` checks over one module:

1. **Send = move.** A value that holds a dynamic array (a `TArray`, a `TSlice`, a record with one: the typed `bpvet` knows the
   type) goes into a channel, a task field or a `Go` argument only as the last use of a local variable (a move: the variable
   is not read again until it is assigned) or as `Copy(X)`. A parameter is not moved (the caller still holds it): it is
   copied. The engine is the one of S5 that already reports `Local` used after `Owner.Reset`. `SAFE_DEBUG` adds a net:
   `Send` checks that the array it gets has at most one holder (R17), so an alias S11m cannot see (through a field, a
   container, another variable) fails at the send. Not at `Recv`: a moved local still holds its reference until its routine
   returns, so an unbuffered `Recv` would always see two.
2. **Sync = frozen or declared.** A class may be shared by goroutines (`TShared` in a task field or a message) when it is
   frozen: every field is written only in its constructors, and the type of every field is frozen too (values, `String`,
   `TChan`, `TShared` of a frozen class). Frozenness is inferred over the module, as `// root:` is (§20, S17 v2), not
   declared. Any other class says how it stays safe, `// sync: <the lock or the protocol>` on its declaration: the analogue of
   `unsafe impl Sync`, found by grep and by the unsafe audit of dependencies (§15).
3. **`static mut` is unsafe.** A global of a unit is written only in its `initialization` (it is frozen after that, and all
   initializations run before the first goroutine), or it is a `threadvar`; any other write needs `// UNSAFE:`, as `static mut`
   does in Rust. The globals of a program file are locals of the main goroutine: a routine that a task can reach in that file
   (a fixpoint over the module, as for S17) does not name them.

`String` needs nothing: copy on write with an atomic counter is Send and Sync already. `TChan` is Sync by construction,
`TOwned` moved with `.Move` is Send. After the three rules the claim of §14, "races are prevented, not detected", holds
without exceptions; until then §0 tells the programmer what the rules will check.

**Step 1 done (2026-11-04): S11m, S11s and S19** (`tools/bpvet/bpvetrace.pas`, in the typed mode after S17; the rows of
§6). What the first run found and what it changed:

- **The runtime itself.** S19 found 11 writes to globals in `safe/core.impl.inc` and `ext/go.impl.inc`: the live counter
  `GLive` and the failure counters through `InterlockedIncrement`/`Decrement` (atomic: S19 accepts the `Interlocked*`
  calls), and the debug list `GLives` under the spin lock `SafeLockLives` (3 marks `// UNSAFE: under SafeLockLives`). The
  tests that switch `SafeDebugChecks` from a routine got a mark each: the switch is set before goroutines start.
- **S17 was too wide.** It took the result of every call for a value of the caller's current region, so `FBox :=
  TBoxOwner.Own(TBox.Create)` in a plain class was "a value of the caller's region stored into an object of another style",
  and `Ch.Send(A)` of an `array of Integer` was "a value of a region sent to a channel" (22 such warnings on `bp.pas`,
  `safe/` and `tests/`). Now a value is in a region only when its type can hold one: a region class, `TObject`, a pointer,
  a `TGrowArray`, or a record or an array with one of them inside.
- **The time:** the typed run of `tests/typed.sh` (152 files) stays 0.7 s.
- **R17 and the globals of a program (the rest of step 1).** `Send` of a dynamic array with a second holder raises
  `SAFE-R17` under `SAFE_DEBUG` (`test_go`, `SharedArray`); the reference count is read from the header of the array
  (`SafeDynArrayRefs`). S19 follows the calls and overrides from each task of a program and found 7 uses in `test_go` and
  `test_threads`: 4 are safe by construction and are now accepted (an `Interlocked*` argument, a `TRTLCriticalSection`),
  3 got a mark that says why (one writer, a lock, a write only while no task runs). S11m also took a value parameter for a
  local: a dynamic array passed by value is the caller's array, and it is an error now.
- **Open:** a record with a dynamic array inside is not checked by R17 (only a top-level array); a class of another unit
  is frozen only when its unit marks it `// sync:` (its writes are not seen).

### 21.3 Goroutines M:N on the stacks that `BPThreads` already has

`BPThreads` finds the current thread from the stack pointer (`Sptr and not (R - 1)`: a stack is aligned to its size, and the
thread record with its threadvar block is at its start; §18). So **a switch of the stack is a switch of the thread** for the
RTL: the threadvars, the exception frames, `IOResult`, the region stack of §20 and the free lists of the heap follow the
goroutine with no extra code. A green thread is a stack and a saved stack pointer, and the scheduler sits behind the hooks of
`TThreadManager` that `BPThreads` already implements:

| Hook | 1:1 today | M:N |
|---|---|---|
| `BeginThread` | `clone` | a new stack in the run queue |
| `RTLEventWaitFor`, a contended `EnterCriticalSection`, `WaitForThreadTerminate` | `futex` wait | park the goroutine, run the next one |
| `RTLEventSet`, `LeaveCriticalSection`, the end of a thread | `futex` wake | put the parked goroutine into the run queue |

- **Carriers:** one OS thread per CPU. The switch is about ten lines of assembler per architecture (save the callee-saved
  registers, swap the stack pointer), next to the `clone` code of §18.
- **Blocking system calls** pin their carrier; a monitor thread adds a carrier when none has made progress for about 10 ms
  (the handoff of `sysmon` in Go). There is no preemption: a goroutine in a long loop keeps its carrier, as in Go before 1.14,
  and the monitor covers it the same way. A netpoller (`epoll`) is a later step.
- **Every `TThread` of every FPC package** becomes a green thread unchanged: `TThread` goes through the same hooks.
- **Deadlock detection** comes free with the scheduler: all goroutines parked and none in a system call stops the program
  with the stacks of the parked ones ("all goroutines are asleep" of Go; §14 lists it as missing).
- **A seeded deterministic mode** comes almost free: `BP_SCHED_SEED=N` runs one carrier and switches at every channel
  operation in an order drawn from the seed; a failing test prints its seed and replays it. The idea of `shuttle` in Rust and
  of the deterministic simulation of FoundationDB, at the cost of a random-number generator.
- **`Select` becomes atomic and gains send cases**, as in Go: lock the channels of the cases in address order (`sellock` of
  Go), commit one case. A received value goes into a `var` given with its case (`A.RecvCase(V)`, `B.SendCase(X)`); its address
  lives only during the call (an open array parameter cannot be stored), so the surface stays safe.
- **The GC style** (§20) gets the exact stack range of a parked goroutine: `[saved stack pointer, top of the stack)`.
- **The price, to be measured by a spike.** The threadvar block of the RTL (it holds `Input` and `Output`, among others) is a
  few KiB per goroutine, plus at least one page of stack: about 10^5 goroutines per GiB, not the 10^6 of Go. All stacks have
  one size (the mask is global), reserved and touched on demand. A guard page makes a stack two mappings, and
  `vm.max_map_count` (65530 by default) then caps the goroutines at about 32 thousand; the spike decides between guard pages
  and the stack check of the compiler (`-Ct`, one compare in each prologue) for stacks carved out of one reservation.
- `-dSAFE_LIBC` stays 1:1 (libc keeps state of its own in each kernel thread); a define keeps 1:1 in the default mode until
  M:N is proven.

#### Spike 4 result: the M:N switch (2026-11-05, FPC 3.2.2)

A prototype (`tools/spikes/mn/`, run by CI on x86_64, aarch64 and i386 at -O1, -O2 and -O2 -Ct): a goroutine is a region
of the size and layout of a `BPThreads` stack (the head of the thread record at its start), carved out of one reservation;
a switch is about ten instructions per architecture (push the callee-saved registers, swap the stack pointer, pop); one
carrier thread runs a FIFO run queue; the hooks `RTLEventWaitFor`/`RTLEventSetEvent` park and wake a goroutine and a
contended `EnterCriticalSection` yields. Verdict: **worth it; step 5 goes on**, with the changes listed below.

- **It works on all three targets with no change to `TChan`:** two goroutines on one kernel thread (the same `gettid`)
  exchange values over unbuffered channels of `ext/go`; threadvars (an `Integer`, a `String`, `ThreadID` of the RTL) follow
  each goroutine; `try/finally` and `except` run on the goroutine's own stack, and an exception of one goroutine stays live
  across switches while another one raises and handles its own (a re-raise gives the right one); `ESafety` of `TChan` is
  caught in a goroutine; 2 x 10^4 strings and objects made in one goroutine are freed in another, and the heap of the
  producer does not grow over a second round; 1:1 threads keep working under the same hooks. Deadlock detection comes
  free: when no goroutine is ready the scheduler returns with the parked ones.
- **The numbers** (-O2; the GitHub runner, i386 natively there too; aarch64 only under qemu, so its times are not those of
  hardware):

  | | x86_64 | i386 | aarch64 (qemu) |
  |---|---|---|---|
  | a switch, with the scheduler loop | 18 ns | 13 ns | 450 ns |
  | a round trip over two unbuffered `TChan`, M:N on one carrier | 0.45 us | 0.41 us | 26 us |
  | the same between two threads, 1:1 (futex) | 20 us | 17 us | 97 us |
  | a parked goroutine, the default heap of the RTL | 44.5 KiB | 77 KiB | 44 KiB |
  | goroutines per GiB, the default heap | 23 thousand | 13.6 thousand | 23 thousand |
  | a parked goroutine, `growheapsizesmall = 4096` | 12 KiB | 16 KiB | 12 KiB |
  | goroutines per GiB, `growheapsizesmall = 4096` | 86 thousand | 65 thousand | 90 thousand |
  | a region (addresses only) | 8 MiB | 1 MiB | 8 MiB |

  So a round trip is 30-45 times faster on one carrier; with `-Ct` over all of `BP` it is 0.8 us. Of a parked goroutine
  the record and the threadvar block share 8 KiB (the threadvars are 5624 bytes on 64 bits, 5380 on i386), and the stack
  in use at a park is 0.6-1.6 KiB (one page). The largest part is the heap of the RTL: a thread's first chunk for small
  blocks of one size is 32 KiB (`growheapsizesmall`), the RTL cuts it into blocks at once, so all of it is touched, and on
  i386 the two events of a goroutine fall into two sizes (two chunks). Set before a goroutine starts, a 4 KiB first chunk
  gives the second row.
- **The start of a goroutine** takes 40-50 us on a new region and 17-26 us on a reused one: `InitThread` of the RTL
  makes six system calls (`getrlimit`, `isatty` four times, the `mmap` of the heap chunk) and `DoneThread` one more, and
  each page is a fault. A start without them (copy the text records of the carrier, set the stack bounds directly, keep
  the heap chunk) is work for step 5.
- **Guard areas against `-Ct`.** A guard (`PROT_NONE`, 64 KiB as in `BPThreads`, so no frame jumps over it) makes 2
  mappings per goroutine: about 32 thousand goroutines under the default `vm.max_map_count` of 65530 (Ubuntu 24.04 ships
  1048576, the GitHub runner 262144); an endless recursion stops the process with SIGSEGV. Without a guard the regions
  merge into one mapping (0 per goroutine) and `-Ct` raises `EStackOverflow` in the goroutine, which can be caught while
  the others go on. But `-Ct` is not a guarantee: code built without it (the RTL, C) is not checked and only has the 16 KiB
  margin of the RTL plus the unused 64 KiB area above the record; and `StackError` of the RTL is one global, so after one
  overflow the check is off in every thread until something resets it. **Decision (the owner, 2026-11-05): guard areas by default** (exact
  for every piece of code); no guard with `-Ct` stays an option for more than 32 thousand goroutines.
- **32 bits:** a region is 1 MiB there, so the address space caps the goroutines at about 3 thousand. M:N on i386 needs a
  smaller region (the mask is global: the stacks of all threads shrink with it).
- **Found and fixed in `BPThreads`:** with `-Ct` the thread manager recursed without end (the stack check reads the
  threadvar `StackBottom` through `RawRelocateThreadVar`, which checked the stack again): `{$S-}` now; on i386 a new thread
  started with the stack 4 bytes off the 16-byte alignment that FPC expects (`-Ct` checks it).
- **What step 5 changes** (the runtime, not the spike): the goroutine record and the carving of regions move into
  `BPThreads` (the spike repeats its layout and checks it at start); the threadvar block lies in the record page (no `mmap`
  of its own, no `munmap` in `ReleaseThreadVars`); `BeginThread`, `CloseThread` and `WaitForThreadTerminate` serve
  goroutines, so `TGroup.Go` and every `TThread` become green; the run queue is per carrier and a wake from another carrier
  is atomic; a timer list for `RTLEventWaitForTimeout` (`Select` with a timeout); the event of a goroutine (`MyEvent` of
  `ext/go`) can live in its record instead of the heap; the switch saves the FPU control words (MXCSR and x87, FPCR) or a
  goroutine that changes the rounding mode changes it for the others; `StackError` is reset per goroutine.

### 21.4 The tree of `TComponent` is an owner

Delphi and Lazarus have had an ownership tree since 1995: `TButton.Create(Form)` gives the button to the form, which
destroys it. Better Pascal takes it as it is:

- S6 accepts `TFoo.Create(AOwner)` of a `TComponent` descendant when the owner argument is not `nil`: the owner is the
  component.
- The result is a borrow rooted in the owner (a root kind of S17). A `published` field of a component whose type is a
  component (the `Button1: TButton` that the form designer writes and the streaming system fills, with the form as the
  owner) needs no `// borrow:`; elsewhere the rules of S5 hold.
- `.Free` of an owned component stays a compile error (S3); `TOwned` or `S.Hold` holds the root of a tree, and a form owned
  by `Application` needs nothing.

The README says the LCL is not yet tested with `bp build`; this rule is what lets the code of a Lazarus form pass without
marks. Cost: one exception of S6 and one root kind of S17.

### 21.5 The decision tree after §21

1. A value: `record`, `String`, `TArray<T>`.
2. Lives as long as a scope (a block, an iteration, a routine): the scope. `S.Hold` for an existing class, a `TRegionObject`
   class for new data, `S.Defer` for an action.
3. Owned by a field: `TOwned`; by a component tree: `TFoo.Create(AOwner)`.
4. Several owners: `TShared` + `TWeak`.
5. A graph with cycles and no natural owner: GC.

Five branches instead of seven (§0), and the most frequent case, a local object, becomes a plain class reference. §0 and
§4 change when the steps of §21.7 are done, not before.

### 21.6 Against the other languages, and what is reused from where

| Language | Where it stands against Better Pascal | What §21 takes |
|---|---|---|
| Swift | the owner style is its model (ARC + `weak`); Swift 6 checks `Sendable` in the compiler; no regions, no static binary without libc | `Sendable`, as rule 2 of §21.2 |
| Odin, Jai | the implicit `context.allocator` is the current region of §20; lifetimes are not checked | nothing more: the current region already is it |
| Nim | ORC: counting plus a cycle collector over the whole heap | nothing: cycles are forbidden (S15) or go to the GC style of one goroutine |
| Pony | reference capabilities in the type system: the strongest race freedom | `iso` (moved) and `val` (frozen), inferred instead of written |
| D | `@safe`/`@trusted`/`@system` and `scope`: a safe subset checked by a pass of the compiler | the same shape, done by `bpvet` (§7, S17) |
| C# | `ref struct` and `scoped`: a value that cannot escape to the heap | the root rule of S17 is the same idea |
| Hylo | mutable value semantics (`let`, `inout`, `sink`) | nothing new: Pascal has had `const`, `var` and records since 1970, S14 makes them the default |
| Vale | generational references | not taken: a cost at every access (unxed/bp#108) |
| Erlang | a heap per process | already in the GC style (§20) |

| Better Pascal | Idea from | FPC mechanism it rests on |
|---|---|---|
| poisoned primitives | Rust `#![forbid(unsafe_code)]`, D `@safe` | name shadowing by the last unit of `uses`; a helper method with a stub parameter type (`.Free`) |
| owner style | Swift | an interface field in a record: the compiler counts |
| scope (§21.1) | Goose regions, Zig `defer` and arenas, C++ destructors, Odin context | management operators of a record; `for ... in` as a block |
| root analysis | Goose roots, Rust lifetimes (elided), C# `scoped` | `PasResolver` of `fcl-passrc`; stubs from `ppudump -Fj` |
| region objects | Goose | `NewInstance`/`FreeInstance` overrides |
| GC style | Erlang, JavaScriptCore (conservative stack, precise heap), `GOGC` of Go | `{$M+}`: the field table of the VMT gives the edges |
| Send and Sync (§21.2) | Rust auto traits, Pony capabilities, Swift `Sendable` | the typed `bpvet`, a fixpoint over one module |
| goroutines M:N (§21.3) | Go (scheduler, `sysmon`, `sellock`), Rust `shuttle`, FoundationDB | the hooks of `TThreadManager`; the thread found from the stack pointer |
| component tree (§21.4) | Delphi and Lazarus, Qt parents | `TComponent.Owner`, published component fields |
| Linux without libc | Go | `clone` + `futex` + `mmap` as an FPC thread manager; `fpwidestring` |
| sum types | Rust `enum` + `match` | variant records + S13 |
| dependencies | Go modules (MVS), Rust editions | git hashes, Software Heritage (§15) |
| leak check in tests | the testing allocator of Zig | the R5 counter |
| in-place access | (none needed) | `{$modeswitch autoderef}`, written by `bpvet --fix` |

### 21.7 Plan by steps

One step is one PR from a fresh `main`, with a criterion of done; a spike may end with "not worth it", written here with its
data.

1. **H14–H16 in `bpvet`** (S11m Send = move, S11s Sync, S19 globals) and R17 in `SAFE_DEBUG`. *Done:* ok/bad lint tests for
   each rule; the rows of §8 updated. First, because it closes a hole of a claim made today. *Status:* **done** for S11m,
   S11s, S19 and R17, with the globals of a program reached by a task (§21.2, step 1 done).
2. **Spike 4: the M:N switch** (`tools/spikes/mn/`): two goroutines exchange values over a channel on one carrier with a
   stack switch; threadvars, exceptions and the heap work across switches. *Done:* CI green on x86_64, aarch64 and i386; the
   time of a switch, the memory of a goroutine, the goroutines per GiB, guard pages against `-Ct`; a verdict in §21.3.
   Independent of step 1. *Status:* **done** (§21.3, Spike 4 result): worth it; guard areas by default (the owner's decision, 2026-11-05).
3. **The scope** on the region runtime (step 4 of unxed/bp#108): `Hold`, `Defer`, `TScopeRef`, `TArena` on the list; S6
   accepts `Hold`, S17 roots it. *Done:* `test_region` covers the order of destruction, an exception in the scope and in a
   destructor; lint tests.
4. **The `TComponent` owner** (S6 and a root kind of S17). *Done:* lint tests on a form-like unit (a stub `TComponent` is
   enough).
5. **The M:N runtime** after step 2: the scheduler behind the hooks, the monitor, deadlock detection, `BP_SCHED_SEED`.
   *Done:* `test_go` and `test_threads` pass under M:N and under a seed; a deadlock test.
6. **Atomic `Select` with send cases.** *Done:* `test_go` covers a send case and a race between two ready cases.
7. **The summary:** §0, §4, the README, the statuses at the top: what exists, nothing else.

## §22. Final touches: what users love in the languages of the niche (design, plan)

Status: design, except `bp run`, `--watch` and `bp new` (§22.1), which exist; the plan by steps is §22.8. The question: what do the
users of Go, Rust, Zig, Swift, Kotlin, Gleam and Deno praise most, and which of it Better Pascal still lacks. The answer is
almost all tooling, not the language: one command from a script to a cross build, a checker that teaches, tests that catch
leaks, derived boilerplate, a profiler, a page to try the language in. Each item rests on something FPC already ships, so
each is small. The `sp` tool of §15 and §16 is `bp` (`tools/bp`); the names below use `bp`.

### 22.1 One command, from a script to a cross build

| Loved in | Better Pascal | Rests on | Cost |
|---|---|---|---|
| `go run`, `cargo run`, Deno scripts | `bp run FILE.pas [args]`: check, build into the cache by the hash of the sources, run. With `#!/usr/bin/env -S bp run` on its first line a Pascal file is a script (fpc does not take the `#!` line, so `bp` checks and builds a copy with that line blank: line numbers stay, findings name the script) | the caches of `tools/bp build`; the idea of `instantfpc`, shipped with FPC | **exists** (`tools/bp`, `tests/bp.sh`): the binary is cached by the hash of the sources, the fpc version and the options; a second run takes about 30 ms |
| `cargo watch`, `deno --watch`, `zig build --watch` | `bp run --watch`, `bp build --watch`: check and rebuild on save (an mtime poll every 200 ms; a cached check takes about 30 ms); the running program is stopped (SIGTERM, SIGKILL after 2 s) before it runs again, and a failed check keeps the watch | the same caches | **exists** (`tools/bp`, `tests/bp.sh`) |
| the `toolchain` line of Go 1.21, `rust-toolchain.toml` | an `fpc 3.2.2` line in `deps.txt` (§15): `bp` fetches that release once, checks its SHA-256, keeps it in the cache and builds with it; a project builds the same in ten years | the official FPC release archives | a download and a checksum |
| `GOOS=linux GOARCH=arm64 go build`, `zig build -Dtarget=` | `bp build --target aarch64-linux`: the cross compiler and its RTL are built once from the sources of the same release and cached | `make crossall` of FPC, which the CI of this repository already runs for i386 and aarch64 | a few minutes per target, once |
| `cargo new`, `gleam new` | `bp new NAME`: a directory with `deps.txt`, `NAME.pas` (`uses BP`; the file is named after the program, S21), `tests/test_NAME.pas` and a three-line `README.md` | | **exists** (`tools/bp`, `tests/bp.sh` builds and tests the generated project) |

The hard part of cross compiling elsewhere is the sysroot: the headers and the libc of the target. The default Linux
binary of Better Pascal has no libc (§18), so a Linux target needs no sysroot at all, only the binutils of the target (`as`,
`ld`: a distribution package); a Windows target needs nothing more (FPC has its own assembler and linker for it). Zig sells
this as its main feature; here it is a side effect of §18.

### 22.2 A checker that teaches

- **Readable output** (Rust, Elm): on a terminal `bp build` prints the source line, a caret under the column, the rule, the
  fix that `bpvet` already knows, and `help: bp explain S17`. The one-line FPC format stays for pipes and IDEs (chosen by
  `isatty`), so fpide (bpide after unxed/bp#128) keeps showing the findings as compiler messages.
- **`bp explain CODE`** (`rustc --explain`): every S and R code prints its section of this specification with a wrong and a
  right example. The examples are the lint tests (`tests/lint/<code>_bad.pas`, `<code>_ok.pas`), so an explanation cannot
  drift from the checker.
- **Format strings are checked** (the printf check of `go vet`): `Format('%d items', [Name])` raises `EConvertError` at run
  time in FPC. The typed `bpvet` checks a constant format string against the types of the `array of const` before the build
  (S20; `Format`, `FmtStr`, `Exception.CreateFmt` and the like). This removes the part of string interpolation that hurts
  without a new syntax (§22.7).
- **Interpolation on the existing syntax.** `Fmt('Loaded {N} files in {T:0:2} s', [N, T])`: an ordinary literal with names
  in braces and an ordinary `array of const`. The user writes only the literal; `bpvet --fix` writes the list from the names
  (as it writes `{$modeswitch autoderef}` and `// root:`), and S20 checks on every build that the list is exactly the names
  of the literal, in their order. A renamed variable is then a finding with its fix, never a wrong text, and nothing can
  disagree. A brace holds a name or an expression (`{Count * 2}`, `{Node.Name}`) and the widths of `Write` (`{X:8}`,
  `{T:0:2}`); `{{` writes a brace. `Fmt` reads the literal at run time and formats each value by its type (`TVarRec`). The
  literal reads as in Swift or Kotlin, and the machine writes the rest. About 60 lines of runtime, plus the check and the fix.
- **The editor: `bp lsp`.** A proxy between the editor and an existing Pascal language server (built on the CodeTools of
  Lazarus), in a separate process, so nothing is linked. It passes everything through and adds the findings of `bpvet` on
  save (from the cache, about 30 ms), and the fixes of `bpvet --fix` as code actions: add `// root:`, add
  `{$modeswitch autoderef}`, wrap a sent array in `Copy`, reorder the fields of a GC class. These are the quick fixes of
  rust-analyzer, for the cost of a message filter.

### 22.3 Tests that catch leaks by default

- **`bp test`** finds `test_*.pas` (the convention of `tests/run.sh`) and runs, in each of them, the published methods
  `Test*` of the descendants of `TTest`, found through RTTI as fpcunit finds them (Go finds `TestXxx` by name the same way).
  `bp test -run REGEX`; files run in parallel.
- **Every test is a leak test** (the testing allocator of Zig):
  after each test method the runner checks that nothing it made is still alive: `SafeCheckNoLeaks` (R5: owners, regions,
  the GC heap of the goroutine) and the used heap of FPC before and after (`GetFPCHeapStatus`). A failure names the types of
  what is left. A test that keeps something on purpose says so, `// keeps: <what and why>`.
- **Benchmarks** (`testing.B` of Go): `procedure BenchParse(var B: TBench)` with `for I := 1 to B.N do ...`; the runner picks
  `N` for about a second and prints ns/op and allocations/op (from the heap status). The `bench_*.pas` of `tests/bench` move
  to it.
- **Fuzzing** (§16) runs in the same runner: `Fuzz*` methods.
- **Doc tests** (Rust): the Pascal examples of the documents are compiled and linted in CI today (`tools/doctest.py`; the
  info string `pascal plan` marks a design that does not compile yet, `pascal sketch` an illustration that is not a program
  of its own), and `bp test --doc` will run them, so the examples cannot rot.
- **Concurrency by seed**: `bp test --seed N` (§21.3) replays a failing interleaving.

### 22.4 Derived code instead of boilerplate

`// derive: Eq, Hash, Show, Json` on a record (Kotlin data classes, `derive` and serde of Rust). `bp gen`, which `bp build`
also runs, reads the fields with `fcl-passrc` and writes two include files next to the unit, `name.derive.intf.inc` (the
headers of the global operators `=` and `<>`, `Hash`, `ToString`, `ToJson`, `FromJson`) and `name.derive.impl.inc` (their
bodies; JSON through `fpjson` of FCL), the same interface and implementation split as the parts of `bp.pas`. `bpvet --fix`
adds the two `{$I}` lines. A generated file starts with `Generated by tools/...` and CI generates it again to compare (the
rule of generated files in tv3). A variant record compares and writes its tag first and then only the fields of the branch
of that tag (the semantics of S13). A class needs no generator for JSON: `fpjsonrtti` of FCL already streams its published
properties.

The general form is `// gen: PROGRAM.pas > OUT.inc`: `bp gen` runs the program with `bp run` before `fpc` and the unit
includes its output (tables, parsers, bindings), checked in CI the same way. Derive is one such program, shipped with `bp`.

### 22.5 A profiler in the runtime

`BP_PROF=cpu.folded ./app` (pprof of Go): `setitimer(ITIMER_PROF)` and a `SIGPROF` handler that records the program counter
and the chain of frame pointers into a ring per thread, with no allocation in the handler. `BPThreads` knows the bounds of
every stack (§18), so the walk is bounded and cannot fault. At exit the addresses are resolved with the line information of
FPC (`-gl`, the backtrace code of the RTL) and written as collapsed stacks, which speedscope and `flamegraph.pl` open. With
M:N (§21.3) a sample also names its goroutine. About 200 lines, Linux; a spike checks the walk at -O1 and -O2 on three
targets, as spike 3 checked the GC roots.

### 22.6 Try it in the browser

`bpvet` is built on `fcl-passrc`, the parser of pas2js, and pas2js compiles its own compiler to JavaScript (its web
compiler). So the checker can run in a static page: the code is checked as it is typed, the findings show inline, and the
code lives in the fragment of the URL, so a link shares it with no server (no infrastructure of our own, §15). Running the
code in the page is a later step (the WebAssembly target of FPC main, or pas2js for code without threads). It starts as a
spike: does `bpvet` build with pas2js; if not, the page is not made.

### 22.7 Considered and not taken now, and why

Each of these is loved for something concrete. Below: what users get from it, what Better Pascal already has for that, and
what stops the rest. Three of the five turn out to be taken in another form, on the existing syntax.

- **Closures and iterator chains** (Rust, Swift, Kotlin). FPC 3.2 has no anonymous functions; FPC main has them and
  function references. `G.Go(procedure ...)` and `Filter`/`Map` come when a release with them is the base (§14).
- **String interpolation** (Swift, Kotlin, the f-strings of Python): taken on the existing syntax, `Fmt('{N} files', [N])`
  with the list written by `bpvet --fix` and checked by S20 (§22.2). Only the compiler-made list is not taken: it is a new
  syntax, and the machine writes the list instead.
- **Null safety** (Kotlin, Swift): taken as a guarantee of `bpvet` without `TFoo?` in the type system (§22.9), on the
  pattern of S17 v2 and §21.2: inferred inside a module, written at its boundary by `--fix`. On the way a real hole was
  found (H19: an uninitialized local class reference is garbage, not nil).
- **`comptime` (Zig), macros (Rust, Nim).** They do three jobs. Code generic over types and constants: FPC has generics, with
  constant parameters since 3.2. Code chosen at compile time: `{$if}`, constant expressions, `inline` (dead branches are
  removed). Code written by code: `// derive:` (§22.4), and in general a Pascal program that `bp` runs before `fpc` and whose
  output is included (`// gen:`, §22.4; `go generate`, a step of `build.zig`); `bp run` makes such a program one file with
  no build of its own. What is missing is code that runs inside the compiler on its types (`@typeInfo`, procedural macros);
  without a fork the generator reads the types with `fcl-passrc`, as derive does. So `comptime` is taken as a build step,
  not as a feature of the language.
- **Hot reload** (V, Elixir, Flutter). The VMT does not block it; it blocks only a change of a layout. Reloading the bodies of
  routines is possible with a jump at the entry of the old routine (§22.10); the cost is a small relocator in debug builds,
  so it waits until the fast restart of `bp run --watch` proves not enough.

### 22.8 Plan by steps (cheapest first)

One step is one PR from a fresh `main`, with a criterion of done.

0. **S26a and S26b** (§22.9; they close H19, so they go first): definite assignment of class references, the size of a class.
   *Done:* ok/bad lint tests; the rows of §8 updated. **Done** (`tools/bpvet/bpvetnil.pas`; over the repository one real
   finding, a read after `for J := 1 to 1000`, which taught S26a the `for` with constant bounds).
1. `bp run`, `--watch`, `bp new` in `tools/bp` (**done**). *Criterion:* `tests/bp.sh` runs a script with a shebang, and a second run comes
   from the cache.
2. `bp explain` and the readable output. *Done:* every code of §6 and §20 has an entry and an example from `tests/lint`.
3. The format check and `Fmt` (S20, §22.2) in the typed `bpvet` and the runtime. *Done:* ok/bad lint tests; `--fix` writes the
   list of a `Fmt` literal.
4. `bp test`: discovery, the leak check after each test, benchmarks, doc tests. *Done:* `tests/run.sh` becomes a call of
   `bp test`, and CI shows the same results.
5. The `fpc` line and `--target`. *Done:* CI builds and runs `test_safe` for aarch64 through `bp build --target` (qemu).
6. `// derive:`. *Done:* a generated record round-trips through JSON; CI regenerates the files to compare.
7. Spike: the profiler. *Done:* a flame graph of `tests/bench` on three targets, or a verdict.
8. `bp lsp`. *Done:* an editor shows a finding of S17 on save and applies its fix.
9. Spike: `bpvet` under pas2js, then the page. *Done:* the page checks `tests/lint/s17_calc_ok.pas` in a browser, or a
   verdict.
10. Spike: S26c (§22.9) on the calculator and on one unit of tve. *Done:* the tests and marks per 100 lines; a verdict:
    error, warning or not taken.
11. Spike: hot reload of bodies (§22.10), only if the fast restart is not enough: a `-dSAFE_LIBC` build with exported
    symbols, the patch as a shared object bound by the host `dlopen`. *Done:* a changed routine of a running program is
    patched on x86_64, a changed layout restarts it; or a verdict.

### 22.9 Nil: from a safe crash to a guarantee

Three layers, the cheapest first.

1. **H19, a real hole: garbage, not nil.** FPC initializes only managed types: the fields of an object are zeroed
   (`InitInstance`), but a local variable of a class type, a function result and an `out` parameter hold whatever was on
   the stack, and so does a class field of a local record. A call through such a reference is undefined behaviour, the one
   memory hole of this area. FPC warns ("does not seem to be initialized"), but `bp build` does not fail on a warning of
   `fpc` (now it does: `-Sew`, §24.8 step 2). **S26a** (done): the typed `bpvet` proves that such a reference is assigned on every path before every read (the
   dataflow of S17: loops walked twice, branches joined; a `var` argument and a nested routine count as writes); unproven is
   an error. `Default(TRec)` assigns a record.
2. **A nil dereference is always an exception.** On every target of §2 except DOS the lowest pages are not mapped: nothing
   below `vm.mmap_min_addr` on Linux and a static FPC binary starts at 4 MiB on x86_64 and aarch64; on Windows the first 64
   KiB are reserved. So `nil.Field` faults (`EAccessViolation` with a backtrace) as long as the field is near the start of
   the object. **S26b** (done): a class whose instance is larger than 64 KiB is an error (a large buffer goes into a dynamic array).
   With S26a and S26b "a nil dereference is a safe crash" is a proven property, not an assumption.
3. **No nil dereference at all** (the guarantee of Kotlin), **S26c**, without `TFoo?`: inferred inside a module and written at
   its boundary by `--fix`, the pattern of S17 v2 (`// root:`) and §21.2 (frozen classes).
   - A value is **never nil** when it comes from a constructor, from `Hold`, from a never-nil field, from a routine of safe
     code (a routine never returns nil: absence is `TryX`), or from a local tested by `if X <> nil`, `Assigned(X)` or
     `while X <> nil`. A local cannot change behind the test: Pascal has no aliases of a local except a `var` argument and a
     nested routine, and `bpvet` sees both.
   - A field is never nil when every allocation of its class in the module sets it before the object escapes (the Pascal
     idiom `Result := TExpr.Create; Result.Left := A` included) and nothing assigns it nil later. Otherwise it is **maybe
     nil**, and an exported class says so on its declaration, `// nil: Next` (written by `--fix`), as an exported routine
     writes `// root:`.
   - A value from code that is not checked (an FPC package: `FindComponent` returns nil) is maybe nil.
   - Dereferencing a maybe-nil value is an error. The fix is the smart cast of Kotlin, in Pascal: copy into a local and test
     it (`M := N.Next; if M <> nil then ...`); the walk of a list, `while N <> nil do N := N.Next`, already has this form.
   - `if TryFind(K, V) then V.Use`: `V` is never nil in the branch where the call returned True; S26c checks in the body of
     every `Try` routine of the module that each path that sets `Result := True` gives `V` a never-nil value.
   - The expected noise is a tree whose child is nil in some kinds of nodes (a leaf). As with the early S17, a spike measures
     it first (§22.8, step 10) and decides whether S26c is an error, a warning or not taken.

### 22.10 Hot reload of routine bodies (later, optional)

The VMT does not block hot reload; it blocks only a change of a layout. Live++ (C++), `subsecond` (Rust) and the hot patching
of Windows patch bodies: the new code of a changed routine is loaded beside the old one, and a jump written at the entry of
the old routine sends every call there, whichever way it comes (a direct call, a VMT slot, a procedure variable). Old code is
never unloaded, so a routine that is still running on some stack finishes in its old body. A changed layout (a field, a
virtual method, a global or a threadvar added, removed or moved; the typed `bpvet` knows the layouts and compares them) falls
back to a restart, which takes a fraction of a second (§22.1). An inlined routine changes its callers, so they are patched
too, or a debug build does not inline. No object ever meets a layout other than its own, so the guarantees hold.

The loader costs less than it seems, because a build for hot reload does not have to be static. A static binary without
libc has no `dlopen` (static-everywhere draws the same line: its Profile S has none, its Profile H loads from the host), and
two answers exist in the fork of goffi (unxed/goffi): Profile U, shipped, which strips `PT_INTERP` and re-executes the binary
through the host's own `ld.so` at startup, and ADR-001, a userspace ELF loader of its own, still a proposal. Hot reload needs
neither: it is a development mode, so its build is a `-dSAFE_LIBC` build (Profile H) whose symbols are exported (`-k-E`),
and the patch is the object of the changed unit compiled position-independent (`-Cg`) and linked as a shared object with
its symbols left unresolved. The host `dlopen` then binds those symbols to the running program, to its globals, its heap
and its RTL, not to copies; `bp` writes the jumps. What remains of our own is the comparison of layouts and the writing of
the jumps. A relocator of our own is the fallback only for a static build, and it is not planned. A release build stays
static. The spike checks the chain on x86_64: an FPC unit built with `-Cg` and linked with `ld -shared` binds against an FPC
program linked with `-k-E`. It stays the last spike of §22.8, done only if the fast restart proves not enough, for
example for a text-mode program with a lot of state on the screen.

## §23. Systems programming and the world of C (design, plan)

Status: design only; the measurements in §23.3 were made on 2026-11-04 (FPC 3.2.2, glibc 2.39, x86_64); the plan by
steps is §23.7. Two questions:

- what Better Pascal needs to write a kernel, a microkernel, a memory manager or a driver;
- how it talks to C without being tied to the versions of the system C libraries.

The language must be fit for this to compete with Rust and Zig in their niche.

### 23.1 The principle: the boundary is a module, the hardware is a type

Every hard part of systems code is one of three things:

- memory that no allocator owns (MMIO, page tables, DMA buffers, C memory);
- code that must not do something (block, allocate, raise) in a context (an interrupt, a spin lock, a C callback);
- an ABI defined by someone else (the CPU, a device, the C library).

Better Pascal already has the boundary for all three: a `// UNSAFE-UNIT:` module with a safe facade (§7, §13). This
section adds three things:

- typed views of hardware memory instead of pointers;
- inferred contexts instead of `unsafe` sprinkled through the code;
- C bindings that are bound at run time by name, so the binary depends on no version of a C library.

Pascal brings something C and Rust lack. `bitpacked record` gives bit fields with a defined layout. A `set of` an
enumeration is a flag word. Subrange types (`0..511`) state the width of an index. Enumerations have explicit values.
A register block or a page table entry is written down as data, not as shifts and masks.

### 23.2 Problems of systems code and their answers

| Problem | Rust / Zig / C | Better Pascal |
|---|---|---|
| No OS under the program: no heap, no threads, no files | `no_std`, `-ffreestanding`, Zig `freestanding` | **profile F** (§23.4): a minimal `System` unit (FPC supports a custom RTL: `-Tembedded`, `-Tfreertos`; the Ultibo and Toro projects boot FPC code on bare metal); the kernel installs its page allocator as the memory manager (`SetMemoryManager`) once, and from then on `String`, dynamic arrays and the memory styles of §20 work |
| Memory with no owner: MMIO registers, page tables | `volatile`, `read_volatile`, crates like `tock-registers` | `TMmio<TRegs>`: a typed view of a `bitpacked record` at an address that one line of a `// UNSAFE-UNIT:` module gives once; `Regs.Load`/`Regs.Store` (volatile accesses through a non-inlined accessor, or the `volatile` intrinsic where the FPC version has it), `ReadBarrier`/`WriteBarrier` of FPC for ordering. No pointer leaves the binding module |
| Physical and virtual addresses mixed up | newtypes (`PhysAddr`, `VirtAddr` of the `x86_64` crate) | `TPhysAddr`, `TVirtAddr`: records around a `QWord`: distinct types, zero cost, arithmetic only through their methods |
| An interrupt handler that blocks, allocates or raises | lints by convention (`might_sleep` in Linux), nothing in the type system of Rust | **contexts, inferred** (S23): `// context: irq` on a handler; `bpvet` computes over the call graph (a fixpoint over the module, as for S17) which routines may allocate, block (a lock that sleeps, a channel, `Sleep`) or raise; an `irq` routine that reaches one of them is an error with the call chain. Function colouring with no colours written, except at the roots |
| Interrupts on and off, locks | RAII guards | a scope object (§21.1): `G := Cpu.NoIrq;` restores the flag at the end of the scope, also on an exception; `TSpinLock.Hold` the same way |
| DMA: a buffer the device writes while the program may free it | `Pin`, ownership moved into the driver | Send = move (§21.2): a buffer goes into the device queue as a `TOwned` by `.Move` and comes back with the completion; a region that holds a DMA buffer is not released while the buffer is out (S17: the queue is a root) |
| Concurrency inside the kernel | `Send`/`Sync`, `spin`, atomics | the rules of §21.2; `TAtomic<T>` over `InterlockedXxx` of FPC with an explicit order |
| Assembler: `cli`, `cr3`, port I/O, context switch | `asm!` / inline asm | `asm` blocks of FPC, only in `// UNSAFE-UNIT:` architecture modules, with a facade of plain routines (`Cpu.LoadPageTable(const T: TPageTable)`) |
| Layout, sections, entry point, boot header | linker scripts, `#[link_section]` | `section` of FPC variables, a linker script of the profile, a multiboot2 header as a constant record |
| A microkernel: IPC between address spaces | seL4, Zircon channels with handles | `TChan` of §14: a message is a value (Send rules), a handle is a typed capability (`THandle<TPort>`), the M:N scheduler of §21.3 is the scheduler of the kernel |
| A memory manager (a user allocator) | `GlobalAlloc` | the allocator is an `// UNSAFE-UNIT:` core over `mmap` (or pages), small and audited; regions (§20) already are an allocator for most needs |
| Drivers in user space (Linux) | `libusb`, `libfuse`, `vfio` crates | the kernel ABI, not C libraries: `usbfs`, `/dev/fuse`, `uinput`, `evdev`, DRM/KMS and ALSA ioctls as bp units over syscalls (Layer 3 of static-everywhere: a protocol, not a `.so`) |
| Testing a kernel | QEMU, `cargo test` on the host | **hosted mode:** the same units built as a Linux program with simulated devices (`TMmio` over a buffer); the seeded scheduler of §21.3 (`BP_SCHED_SEED`) makes races reproducible; QEMU in CI for the real boot |

Linux kernel modules are not a goal: the kernel ABI for modules is unstable and Kbuild is a C toolchain. Better Pascal
targets its own kernels, unikernels, firmware and user-space drivers.

### 23.3 C without versions: what was measured

Facts (2026-11-04, FPC 3.2.2, glibc 2.39, x86_64):

1. **FPC ties a dynamic binary to the glibc it was built on.** A program with one `external 'c'` routine links against
   `libc.so.6` and imports `__libc_start_main@GLIBC_2.34` from the startup code of FPC. Built on Ubuntu 24.04, it does
   not start on glibc older than 2.34 or on musl. This is the problem of §2.1 of static-everywhere ("glibc's symbol
   versioning is forward-only"), and every `external` of a binding adds one more versioned import.
2. **A static binary cannot reach the host libc.** The default Better Pascal binary (profile S, §18) started by the
   loader of the host (`ld.so --preload libc.so.6 ./prog`) runs, but no shared object is mapped: the loader does not
   treat an image without `PT_DYNAMIC` as dynamic.
3. **An image without `DT_NEEDED`, but with `PT_INTERP`, binds to the libc of the host.** The same FPC program with its
   `DT_NEEDED` entry removed runs as `ld.so --preload libc.so.6 ./prog` and as `LD_PRELOAD=libc.so.6 ./prog`. The versioned
   symbols bind against the preloaded libc. Without `PT_INTERP` the glibc loader binds nothing, as unxed/goffi
   documents for its Profile U.

So the design of unxed/goffi (Profile U: no `PT_INTERP`, no `DT_NEEDED`, a re-exec through the loader of the host with
its libc preloaded) applies to FPC binaries, with two changes that Better Pascal can make because it owns the build
(`tools/bp build`) and the startup:

- **No versioned import at all.** The binary imports nothing; after the loader has run, the runtime finds `dlopen` and
  `dlsym` itself:
  - `DT_DEBUG` of its own dynamic section points to `r_debug`;
  - `r_debug.r_map` walks the link map to the libc;
  - the libc's `.dynsym` gives the address.

  This is the "loader-agnostic symbol resolution" that the notes of goffi describe. Every other C symbol comes from
  `dlsym` by name, unversioned, so it binds to the default version of whatever libc the host has: glibc of any age or
  musl.
- **One startup for both cases.** The entry point is a bridge in Pascal on raw syscalls:
  - Without a known host loader, or with `ld.so.preload` failing the probe that goffi does, it runs as profile S: FFI is
    unavailable, `CLib.Available` is `False`, everything else works.
  - With one, it re-executes itself through the loader: `--preload` on glibc 2.30 and newer and on musl, `LD_PRELOAD`
    on older glibc, and a `memfd` copy with `PT_INTERP` restored where the glibc loader needs it. This is the start of
    profile U.

  `__libc_start_main` is never called. Threads: when libc is present, the thread manager creates carriers with
  `pthread_create` (resolved by `dlsym`), so a C call on any carrier finds a libc thread. A goroutine pins its carrier
  for the duration of a C call, as in Go. Without libc, carriers stay `clone` (§18).

### 23.4 Four profiles, one source

| Profile | Binary | C | For |
|---|---|---|---|
| **S** (default, exists, §18) | static, no `PT_INTERP`, no `DT_NEEDED` | none: syscalls and protocols | CLI, servers, Marwin (#129), anything headless |
| **U** (plan) | the same image plus an empty `PT_DYNAMIC` | the libc and libraries of the host, bound at run time by name, any version | GUI, GPU, audio, plugins: the irreducible host contract of static-everywhere (`libGL`, `libvulkan`, `libasound` and a few more) |
| **H** (exists, `-dSAFE_LIBC`) | dynamic, `DT_NEEDED libc.so.6`, versions of the build machine | `external` | compatibility with existing bindings and Lazarus packages that link C |
| **F** (plan) | freestanding: a custom `System`, no OS | none | kernels, microkernels, firmware |

The program does not change between S, U and H. A binding is written once (§23.5). `CLib.Available` is a constant in S
and F, so the branch to a pure Pascal fallback costs nothing there.

### 23.5 Bindings: a table of names, not `external`

```pascal plan
type
  TZlib = record                                    // a binding module, // UNSAFE-UNIT:
    zlibVersion: function: PChar; cdecl;
    compress2: function(Dst: PByte; var DstLen: CULong; Src: PByte; SrcLen: CULong; Level: CInt): CInt; cdecl;
  end;

var
  Zlib: TZlib;

initialization
  CLib.Bind(['libz.so.1', 'libz.so'], Zlib, ['zlibVersion', 'compress2']);  // the first name found wins
end.
```

- `CLib.Bind` fills the procedure variables by `dlsym`. The calling convention is the one of FPC itself. A call costs as
  much as an indirect call: no trampoline in assembler as in purego and goffi, because the Pascal compiler speaks the C
  ABI natively.
- A list of library names covers the sonames of different versions (Nim's `dynlib: "libssl.so(.3|.1.1)"`). A missing
  symbol leaves the field `nil` and `CLib.Has(Zlib.compress2)` says so. The facade decides: a fallback, an error, or a
  feature switched off. Nothing fails at load time for a symbol the program does not call.
- In profile H the same table can be filled by the static linker (`external`). S12 accepts a binding table in a
  `// UNSAFE-UNIT:` module exactly as it accepts `external` today, and F1–F5 of §13 still hold for the facade.
- **Layer 1 C code** (zlib, sqlite, a codec: code that computes) is not taken from the host at all: it is compiled
  freestanding (`zig cc -target x86_64-linux-musl -ffreestanding -c`) and linked statically (`{$L}`). It runs against a
  small C runtime written in Pascal over the bp RTL: `malloc`/`free` on the heap of FPC, `memcpy`, `strlen`, `qsort`, and
  for sqlite a VFS over the bp file units. The binary stays profile S.
- **Headers:** `tools/bp bind header.h --lib 'libfoo.so.1|libfoo.so'` generates the table and a facade skeleton from the
  JSON AST of clang (`-Xclang -ast-dump=json`; h2pas does not follow modern headers). A model writes the facade, and
  `bp build` checks it.
- **The other direction:** a bp `library` with `cdecl` exports for C programs. C sees opaque handles and flat records,
  never Pascal objects or strings: the facade rules F1–F5 turned around.

### 23.6 Other languages: what is taken

| Language | How it meets C | What Better Pascal takes |
|---|---|---|
| Go (cgo) | a C toolchain in every build, a costly call, `LockOSThread` | the boundary rules (§13), pinning a goroutine for a C call |
| Go (purego, unxed/goffi) | `dlopen` without cgo, assembler trampolines; Profile U | Profile U, the bridge, the probe of `ld.so.preload`, the audit "no `PT_INTERP`, no `DT_NEEDED`" |
| Zig | `@cImport`, bundled libc headers for many glibc versions, `x86_64-linux-gnu.2.28` targets, `zig cc` | `zig cc` as the C compiler of Layer 1 code; versions avoided rather than pinned |
| Rust | `extern "C"`, `bindgen`, the `libc` crate, `libloading`, `crt-static` and musl targets | the generator of bindings; `libloading` is the shape of `CLib.Bind` |
| Nim | `{.importc, dynlib: "lib(|.so.1)".}`: bound at load time by a pattern of names | the list of sonames |
| Java (Panama, FFM) | `Linker`, `SymbolLookup`, `MemorySegment` with arenas and bounds | C memory as a bounded segment in a region of §20 (`TCSegment`, plan): a C buffer is read with bounds checks and dies with its scope |
| .NET | `DllImport`/`LibraryImport`, `NativeLibrary.TryLoad`, resolvers by version | `CLib.Has` instead of an exception at load |
| Swift | the Clang importer, `UnsafePointer`, `Span` | nothing new: the facade rules already keep pointers out of safe code |
| Cosmopolitan | one binary for several OSes | not taken now: §5.9 of static-everywhere calls it the extreme end |

### 23.7 Plan by steps

Each step is one PR from a fresh `main` with a criterion of done. The FFI steps come before the systems steps:
Marwin (#129) runs in profile S, and GUI showcases need profile U.

1. **`CLib.Bind` in profile H** (`dynlibs` of FPC). `tests/ffi_libc.pas` is rewritten as a table, and S12 accepts tables.
   *Done:* `test_ffi` passes with the table; a missing symbol is `nil`.
2. **Spike 5: profile U on x86_64.** The bridge, the re-exec, `dlopen`/`dlsym` from the link map, carriers on
   `pthread_create`. *Done:*
   - one binary calls `strlen` and `zlibVersion` on Debian 11, Ubuntu 16.04, Ubuntu 24.04, CentOS 7 (glibc 2.17,
     `LD_PRELOAD`) and Alpine (musl);
   - it runs without FFI where no loader is known;
   - `readelf` shows no `PT_INTERP` and no `DT_NEEDED`;
   - a verdict here.
3. **Layer 1 C code:** zlib compiled freestanding and linked statically against the Pascal C runtime. *Done:* a
   compress/decompress test in profile S on all CI targets.
4. **`tools/bp bind`** on the clang JSON AST. *Done:* the tables of zlib and of `libasound` are generated and build.
5. **Spike 6: profile F.** A toy kernel boots in QEMU (multiboot2), prints over the serial port through `TMmio` or a
   port facade, has a page allocator installed as the memory manager, and has regions over pages and a timer interrupt.
   *Done:* CI boots it in QEMU and reads the serial output; a verdict here.
6. **S23 contexts** in `bpvet` (`// context: irq`: no allocation, no blocking, no raise, reached through calls). *Done:*
   ok/bad lint tests, among them a chain of three calls.
7. **Hardware types:** `TMmio<T>`, `TPhysAddr`/`TVirtAddr`, `TAtomic<T>`, `Cpu.NoIrq`. *Done:* used by the kernel of
   step 5, and tested in hosted mode over a buffer.

## §24. Concept v4: one sentence, marks by the machine, what FPC already ships (design, plan)

Status: design only; the facts below were measured on 2026-11-04 (FPC 3.2.2, x86_64, scratch programs of about ten
lines each, built with `fpc -Cr -Co`; they become the compile and lint tests of the steps in §24.8). A fresh look at the
whole concept after §21–§23, against the table of the README and against what the users of Rust, Go, Zig, Swift and
Kotlin praise. Seven changes. Two of them shorten the concept, one removes its last exception, three take what FPC 3.2
already ships and the dialect had not used, and one closes holes that the honest table of §8 did not list. Each one is
small, and none adds a syntax.

### 24.1 One sentence for all lifetimes

Every memory rule of Better Pascal that is not "the compiler does it" is one sentence: **a reference never outlives its
root.** What differs between the rules is only what the root is:

| Reference | Root | Rule that checks it today |
|---|---|---|
| a parameter or a local of a class type (a borrow) | the call, or the owner it was read from (`Owner.Get`) | S5 |
| a `TOwned` or `TShared` field | the object that holds the field; `TOwned` is moved, never copied | S5, S10 |
| a region object, a `TGrowArray` element, a scope handle, a held object (`S.Hold`) | the region or the scope | S17 |
| a `// borrow: arena` reference | the arena | S17d |
| a component | its `Owner` (§21.4) | S6, S17 |
| a task field, a channel message | the task: it may outlive the caller, so only a value or a moved owner has a root there | S11, S18 |
| a GC object | the heap of its goroutine | S18 |
| an interface value (§24.4) | the object behind it | S5 |
| a nested procedure value (§24.4) | the frame of the routine it is nested in | S17 |

Nothing changes in the checks. What changes is how they are explained: `bp explain` (§22.2) prints this sentence and the
root of the reference first, and the rule number second; the REFERENCES block of §0 shrinks to the sentence and this
table when the steps of §21 are done. `// borrow: <who owns it>` is the root written by hand where inference stops at the
boundary of a unit, the same shape as `// root:`; when S5 moves onto the engine of S17 (§20), the mark becomes
`// root: <owner>` and `bp fix` rewrites the old one.

### 24.2 Marks of fact are written by the machine, marks of intent by hand

Every mark of Better Pascal is one of two kinds, and the kinds are treated differently:

| Kind | Marks | Who writes it |
|---|---|---|
| **fact**: something `bpvet` can compute from the code | the header from the file name (S21), reserved words in lower case (S22), `// root:` on exported routines (S17 v2), `// raises:` (§24.5), `{$modeswitch autoderef}` (§20), `{$modeswitch nestedprocvars}` and `{$modeswitch typehelpers}` (§24.4), the order of the fields of a GC class (S18), the `{$I}` lines of `// derive:` (§22.4), `as` for a class cast (§24.6) | `bp fix`; a human or a model never types it, and `bp build` names the fix when it is missing |
| **intent**: something only the author knows | `// UNSAFE: <why>`, `// UNSAFE-UNIT: <why>`, `// borrow: <who>` (until §24.1), `// sync: <how>` (§21.2), `// keeps: <what>` (§22.3), `// context: irq` (§23), `// BP-STYLES:` (§20), `// derive:`, `// gen:` (§22.4) | the author, with a reason after the colon; found by grep and by the unsafe audit (§15) |

The rule is what makes the concept short for a model: it writes plain Pascal, `bp fix` writes the facts, and §0 lists
only the marks of intent. The analogue is `gofmt` and `goimports` in Go, where nobody formats by hand or writes an import
line, extended to everything the typed `bpvet` can infer. A mark of fact that disagrees with the code is a finding with
the fix, never a silent truth of its own.

### 24.3 `BP` last everywhere: the program file is no exception

The one exception of the header rule, "`BP` first in the program file, last in every unit" (§14, §18, H9), exists
because the thread manager must be installed before `SysUtils` initializes, and it costs a warning of S7 and an
`// UNSAFE:` mark on every test program. `fpc -Fa<unit>` inserts a unit at the start of the `uses` of a **program**
(and only of a program, §2), which is exactly where the exception lives. Measured: `tests/ext/test_go.pas` with
`uses SysUtils, BP;` built with `-FaBPThreads` passes all its tests (0 failed); built without the switch it stops with
code 211 as §14 says. So:

- `tools/bp build` adds `-FaBPThreads`; the rule becomes one line, **`BP` goes last in the `uses` of every module**, the
  program file included; S7 reports a unit after `BP` in a program as an error, as it does in a unit, and the
  `// UNSAFE:` marks on the test programs go.
- With a bare `fpc` the user adds `-FaBPThreads` (one line of `fpc.cfg`), or keeps writing `BP` first: it still works.
- H9 leaves the register; step 2b of unxed/bp#56 is answered.

### 24.4 What FPC 3.2 already ships and the dialect has not used

Three features of FPC 3.2.2 give what users of Swift, Kotlin and Go praise, with no new code in `BP` and no syntax of
our own; each is a `{$modeswitch}` or a directive that `bp fix` writes, as it writes `autoderef` (§20). All three were
run on 2026-11-04.

- **Closures that cannot escape: `{$modeswitch nestedprocvars}`.** `type TVisit = procedure(X: Integer) is nested;` makes
  a nested routine a value: `ForEach(A, @Add)` where `Add` is nested in the caller and writes the caller's local `Total`
  (measured: `sum=10`). It captures the frame of the enclosing routine, so it is a borrow of that frame and has a root
  (§24.1): passed down a call, never stored, never given to a task. S17 already rejects a nested routine kept as a
  callback (`tests/lint/s17_callback_bad.pas`); S11 gains one line, a field of a nested procedure type in a task. These are the
  non-escaping closures of Swift (its default) and the `FnMut` borrow of Rust, and they cover what §22.7 wanted closures
  for inside a scope: `Filter`, `Map`, a comparator for `Sort`, `Retry(@Step)`, `WithLock(@Body)`. A goroutine still takes a
  `TTask` (it may outlive the frame). The anonymous functions of FPC main add the escaping kind and the inline syntax, not
  the capability.
- **Extension methods: `{$modeswitch typehelpers}`.** A `type helper for String` adds methods to a type that is not a
  class, as Kotlin extension functions and Swift extensions do. `SysUtils` already ships `TStringHelper`:
  `S.Trim`, `S.Split([','])`, `S.StartsWith('a')`, `(42).ToString` work on the UTF-8 `String` of §3 with byte lengths
  (measured: `S.Trim.Length` and `Length(S.Trim)` are both 20 for a Cyrillic text of 11 code points). `BP` adds one
  helper with the code point view (`S.CPLength`, `for Ch in S.CodePoints`). Caveats: `Chars[I]` and `IndexOf` of
  `TStringHelper` are byte based, as `S[I]` is (§3), and `ToUpper` of a non-ASCII text goes through the §3 limitation. This
  is the same mechanism that poisons `.Free` (§6): a helper on `TObject`.
- **Interfaces as borrows: `{$interfaces corba}`.** A CORBA interface is a plain reference with no counter: any class
  implements it (`TConsole = class(TObject, IWriter)`, no `TInterfacedObject`), and passing it is a borrow (measured:
  `Emit(C)` with `W: IWriter`, then `still alive`, then `destroyed` at the owner's `Free`). This is the interface of Go,
  polymorphism without inheritance, and without the ownership entanglement of COM (R3, "hold the object only through the
  interface", §0 item 5). Its root is the object behind it (§24.1), so an interface local is a borrow for S5 and an
  interface field needs a root like any class field. `bp new` (§22.1) writes the directive into a new module; a COM
  interface stays available for the code that needs it (`IInterface`, the LCL), and the typed `bpvet` tells the two
  apart by the directive of the module. Caveat: `as` and `Supports` on a CORBA interface need a GUID in its declaration.

### 24.5 Errors visible in the interface, without checked exceptions

Zig's error sets and Rust's `Result` are loved for one thing: what can fail stands in the signature. Pascal exceptions
hide it, and §16 keeps exceptions (`?` and `Result<T, E>` are not taken). The engine of §23 (a fixpoint over the call
graph: which routines may allocate, block or raise) computes the set of exception classes a routine may raise: its
`raise` statements and the sets of its callees, minus what its `except on E: X` handlers catch. Inside a module nothing
is written; on an exported routine `bp fix` writes `// raises: EInOutError, EParseError`, a mark of fact (§24.2), and
`bp explain` and `bp lsp` (§22.2) show it on a call. Nothing forces a caller to handle it: this is Zig's `!T` as
documentation, not Java's checked exceptions. Two findings come with it: an `except` block with an empty body and no
comment (an error swallowed, the `_ = err` of Go lints), and a `raise Exception.Create(...)` of the base class in a unit
(a routine's errors should be a class of its own, so that `// raises:` says something).

### 24.6 The holes the honest table of §8 missed

Three programs that compile with `fpc -Cr -Co` without a warning and are memory-unsafe, found by reading §8 again:

1. **An unchecked class cast.** `TB(O).Y[100]` where `O` holds a `TA` (the parent, without the array) read a word past
   the object (measured: `1302401528`, garbage). `O as TB` raises `EInvalidCast` instead. **S24:** in safe code a class
   typecast `TFoo(X)` to a descendant is written `X as TFoo` (`bp fix` rewrites it; the typed `bpvet` knows a downcast
   from an upcast, which is free and stays); a cast from `Pointer` or from an integer to a class or a pointer is S4.
2. **An untyped parameter with a variable typecast.** `procedure Poke(var Buf; N: Integer)` with `TBig(Buf)[N] := 1`
   wrote 100000 bytes past a `Byte` (measured: runtime error 216; it could as well have been silent). **S25:** an untyped
   `var`/`const`/`out` parameter, a variable typecast to an array or record type (`TBig(X)`) and the `absolute`
   directive are unsafe outside a `// UNSAFE:` mark. `Hold(out V; Obj)` of §21.1 lives inside `BP`, unsafe inside with a
   safe facade, as `TCResource` does.
3. **An uninitialised variable.** `var F: TFoo; WriteLn(F.X)` dereferences a garbage pointer, not `nil`. FPC says
   `Warning: Local variable "F" does not seem to be initialized` (and `Function result does not seem to be set` for a
   result never assigned), and `-Sew` makes a warning an error. **`tools/bp build` adds `-Sew`:** the flow analysis of
   the compiler itself does the check, and the whole test suite of this repository builds with it today with 0 warnings
   (measured on `test_safe`, `test_sumtype`, `test_go`, `test_utf8`, `test_threads`). Caveat: a result assigned in one
   branch only is not reported by FPC 3.2.2; it is `nil` or garbage at the use, and §22.7 covers the `nil` half.

Two more rows of the same kind, cheaper: `with` (S17 cannot root a field without a base, §20; `bp fix` expands it, the
CodeTools of Lazarus do that already), and `goto`/`label` (a style finding of S22's kind). The rows H17–H19 of §8 record
the three holes until the steps close them.

### 24.7 Against the other languages, once more

| Loved in | Was in Better Pascal | After §24 |
|---|---|---|
| Swift non-escaping closures, Kotlin lambdas | "no closures in FPC 3.2" (§14, §22.7) | `nestedprocvars`: the non-escaping kind, today |
| Kotlin and Swift extensions, Rust `impl` on a foreign type | not used | `typehelpers`, shipped by FPC |
| Go interfaces | COM interfaces with ownership | `{$interfaces corba}`: an interface is a borrow |
| Zig error sets, Rust `Result` in the signature | hidden exceptions | `// raises:` inferred and written |
| Rust: no unchecked downcast, no `transmute` outside `unsafe`; Zig: no silent cast | not listed in §8 | S24, S25 |
| Rust, Zig, Go: a read of an uninitialised variable does not compile | an FPC warning | `-Sew` in `bp build` |
| `gofmt` and `goimports`: nobody writes what the machine can | `--fix` for five marks | the rule of §24.2 for every mark of fact |
| Rust lifetimes explained as one idea | eight rules | one sentence and a table of roots (§24.1) |

### 24.8 Plan by steps (cheapest first)

One step is one PR from a fresh `main`, with a criterion of done.

1. **`-FaBPThreads` in `tools/bp`;** S7 reports a unit after `BP` in a program as an error; the test programs lose their
   `// UNSAFE:` on `uses`. *Done:* `tests/ext/compile/mf_s07_bp_first.pas` becomes an ok test; CI green in every mode.
   *Status:* **done** (`mf_bp_last.pas`, `s07_program_bp.pas` an error; httpd, bpget and the template of `bp new` end
   their uses with `BP`).
2. **`-Sew` in `tools/bp build`.** *Done:* a compile test `mf_uninit.pas` with an uninitialised local does not build;
   the suite builds.
   *Status:* **done.** CI builds every layer with `-Cr -Co -Sew`. `-Sew` found a warning in every build of `BP` (the
   poisoned `PByte` in `SafeDynArrayRefs`, written `System.PByte` now) and two results never set in the region runtime.
3. **S24 and S25** in the typed `bpvet`, with `--fix` writing `as`. *Done:* ok/bad lint tests; H17 and H18 leave §8. *Status:*
   **done (2026-11-05)** (`tools/bpvet/bpvetcast.pas`, after S19 in `VetResolve`; the rows of §6). Decisions: S24 reads the static type of the
   operand, so `TButton(Sender)` and `TSquare(S)` are errors and an upcast is free; a cast between classes of different
   branches is an error as well (no fix: `as` would not compile); S25 takes a typecast of an untyped parameter to any
   type (not only an array or a record: `Byte(Buf)` reads the same memory), and the mark on the parameter does not excuse
   its casts. `--fix` writes the downcast in place and leaves a line where the text and the tree do not match to the
   finding. What it found in the repository: 2 downcasts in `safe/core.impl.inc` (`TSafeLife(Life)` and
   `TSafeLife(C.AcquireLife)`, both from `TObject`; now `as`: a walk up the chain of ancestors); the 5 untyped
   parameters of the repository (`RawInitCS` and its siblings) are in `ext/bpthreads.pas`, a `// UNSAFE-UNIT:`. The typed run of `tests/typed.sh` stays 0.9 s (173 files).
4. **Nested procedure values:** S17 roots one in its frame; `bp fix` writes the modeswitch; `tests/` gets a `ForEach` and
   a `Sort` with a nested comparator. *Done:* lint tests, the example builds with `bp build`.
5. **The `String` helper of `BP`** (`CPLength`, `CodePoints`); `bp fix` writes `typehelpers`. *Done:* `test_utf8`.
6. **CORBA interfaces:** S5 treats an interface local as a borrow and an interface field as a class field; `bp new`
   writes the directive. *Done:* lint tests; §0 item 5 rewritten.
7. **`// raises:`** on the engine of §23, the two findings of §24.5. *Done:* lint tests; `bp explain` shows the set.
8. **§0 rewritten** around §24.1 and §24.2, after the steps of §21.7 that change the decision tree; not before.
## §25. The order of the work and the goal of speed (plan, 2026-11-05)

The plans of §21.7, §22.8, §23.7 and §24.8 were written one concept at a time; this section puts them in one order. A step
keeps its number in its own section, where its criterion of done is. The rule of the order: **bugs that users meet first,
then the holes of the honest table (§8), then what the next steps stand on, then the rest, cheapest first**; the summary
of the documents comes last, when the decisions under it are made. Before each step the open issues of unxed/bp are read:
a bug found by a program built with `bp build` goes ahead of the plan.

### 25.1 The order

| # | what | where | why here |
|---|---|---|---|
| — | **done:** the typed `bpvet` (S17 v2), S21/S22, `bp run`, `--watch`, `bp new`; Send and Sync (S11m, S11s, S19, R17); spike 4 (M:N switch, guard areas by default) | §20, §21.7 steps 1–2, §22.8 step 1 | |
| 1 | **#146:** `Select` under `-Co` (done, #151); the false findings of the typed `bpvet`, stubs without `cdecl`, the crash on a long path (items 2–8); S4 on `@` of a record for the socket RTL and the note "a region per connection, not per request" (item 9, §13, §20) | unxed/bp#146 | the first real programs met them: every user meets them |
| 2 | **The cheap holes of §8:** `-FaBPThreads` and `-Sew` in `tools/bp build` (done, #156); S26a and S26b (definite assignment, the size of a class; done); S24 and S25 (a checked class cast, untyped parameters: H17, H18) | §24.8 steps 1–3, §22.8 step 0 | claims made today must hold before new features; each is a small step on the typed `bpvet` that exists |
| 3 | **The benchmark suite against C, Rust, Go and Goose** (§25.2): measured, report only (done for four programs and four languages, v0.16: the baseline is in §25.2; Goose, channels and `httpd` follow) | §25.2 | the runtime steps below change the speed: they are measured against a baseline taken before them |
| 4 | **The M:N runtime** (guard areas by default, the list of changes in the spike 4 result), then the atomic `Select` with send cases | §21.7 steps 5–6 | spike 4 says worth it; `Select` with a timeout needs the timers of step 5 |
| 5 | **The scope** (`Hold`, `Defer`) on the region runtime, then the `TComponent` owner | §21.7 steps 3–4 | the memory styles that the editor of `dn` (step 12 of #108) and fpide need |
| 6 | **The speed work** that the numbers of step 3 point to (§25.2) | §25.2 | after the runtime: it changes what is measured |
| 7 | **The tools,** cheapest first: `bp explain`, S20 and `Fmt`, `bp test`, `--target`, `// derive:`, the profiler, `bp lsp`, the browser, S26c, hot reload | §22.8 steps 2–11 | each stands alone; the ones users ask for first go first |
| 8 | **The language from FPC 3.2:** nested procedure values, the `String` helper, CORBA interfaces, `// raises:` | §24.8 steps 4–7 | after the runtime and S17, which they extend |
| 9 | **Systems and C:** `CLib.Bind`, profile U, zlib in Layer 1, `bp bind`, profile F, S23 contexts, hardware types | §23.7 steps 1–7 | `CLib.Bind` first when a program needs a C library; the kernel work after the runtime is stable |
| 10 | **The summary:** §0 rewritten around §24.1 and §24.2, README, the statuses at the top | §21.7 step 7, §24.8 step 8 | last: it describes the decisions above, not plans |

### 25.2 The goal of speed: competitive with C, Rust and Goose

The author of Goose says that Goose is faster than C and Rust. Better Pascal must be competitive with them: a program
written in the style of the dialect (regions where they fit, `const` parameters, a release build) runs about as fast as
the same algorithm in C, Rust, Go and Goose. Today this is a goal, not a measurement. The work, in the order of §25.1:

- **Measure first (step 3).** A suite in `tests/bench/` of small programs written the same way in each language:
  - an allocation-heavy tree (binary trees: the region style against `malloc`, `Box` and the Go collector);
  - floating point (n-body);
  - integers and arrays (fannkuch);
  - strings (a word count over a file);
  - channels (a ping-pong between goroutines, after step 4);
  - a small HTTP server (`examples/httpd`).

  Each is run with the release build of each language (`bp build --release`, `gcc -O2`, `rustc -O`, `go build`, Goose's
  release mode), on the same machine. CI reports the table and does not fail on it. The table goes here, with the
  machine and the versions.
- **The baseline (step 3, 2026-11-05).** `tests/bench/compare.sh` builds and runs the four programs of
  `tests/bench/suite/NAME/` (`NAME.pas`, `.c`, `.rs`, `.go`) in every language it finds, prints the table below and
  checks that every language prints the same line. The channel and `httpd` items wait for the M:N runtime (step 4;
  `examples/httpd/bench/run.sh` measures the server against Go and Rust meanwhile). CI runs it for Bp, C (gcc) and Go
  and never fails on it (`continue-on-error`).

  **Baseline (2026-11-05, Intel Core i5-6300U @ 2.40GHz, 4 logical CPUs, Linux 6.8.0-147-generic).**

  - Bp: `tools/bp build --release -O2` over fpc 3.2.2. `--release` only drops `-Cr -Co`; it adds no `-O`, so the suite
    passes `-O2`.
  - C: gcc 13.3.0 `-O2` (the reference of the ratios) and clang 18.1.3 `-O2`; Rust: rustc 1.85.1 `-O`; Go: go1.22.2
    `go build`. No target CPU option anywhere.
  - Goose: **not installed.** The owner picks the Goose version and installs it; its column is filled by the same
    script then.

  Median wall time of 5 runs (the runs of the languages alternate), in seconds, and the ratio to C (gcc); lower is better:

  | program | Bp | C (gcc -O2) | C (clang -O2) | Rust (rustc -O) | Go | Goose |
  |---|---|---|---|---|---|---|
  | binary trees | 0.656 s (1.43x) | 0.456 s (1.00x) | 0.552 s (1.21x) | 0.482 s (1.05x) | 0.946 s (2.07x) | not installed |
  | n-body | 0.832 s (1.91x) | 0.435 s (1.00x) | 0.454 s (1.04x) | 0.553 s (1.26x) | 0.596 s (1.36x) | not installed |
  | fannkuch | 0.303 s (1.37x) | 0.221 s (1.00x) | 0.238 s (1.07x) | 0.244 s (1.10x) | 0.252 s (1.13x) | not installed |
  | word count | 0.560 s (2.61x) | 0.214 s (1.00x) | 0.244 s (1.14x) | 0.376 s (1.75x) | 0.357 s (1.66x) | not installed |

  The sizes: binary trees of depth 16 (14,985,902 nodes made, walked and dropped); n-body with 5 bodies and 5,000,000
  steps; fannkuch with n = 10; a word count over a generated text of 4,000,000 words (28 MB, 30,000 different words).
  Each program prints one line and the script stops on a difference. The machine is a laptop that other work shares:
  repeated runs differ by 10-20% of one cell, so read the ratios to one decimal, not two.

  How each language writes the program:

  - **Binary trees.** Bp uses the **region style**: the nodes are `TRegionObject`s, a loop of trees has one `TRegion`
    that is `Reset` after each walk, and the long-lived tree has a region of its own. `BP` does not export the region
    yet, so the program uses the unit `Region` of `tools/spikes/region` (spike 2), as `examples/httpd` does. C calls
    `malloc` and `free` for every node, Rust owns the nodes with `Box`, Go lets its collector free them (it also uses
    a second core: its CPU time is about twice its wall time).
  - **N-body, fannkuch.** The same loops and the same order of operations in every language, so that the floating
    point results are equal bit for bit (the line holds the energies in millionths). Rust indexes with bounds checks,
    as written; Bp is built without them.
  - **Word count.** Bp makes a `String` of every word (`Copy`) and counts in a table of its own (FNV-1a of 32 bits,
    open addressing, a size fixed for this text), because `TDictionary` is not usable under the typed `bpvet` (below). C counts
    the words in place in a table of the same kind. Rust and Go slice the text without copying and use their standard
    maps. The four are not the same work, which is the point of a strings item: it measures what the natural program
    of each language costs.

  What the numbers say, for step 6 to check (no cause is diagnosed here): Bp is 1.4-1.9x of C on binary trees, n-body
  and fannkuch, where the code generator of FPC and the region allocator are the candidates, and 2.6x on the word
  count, where a `String` per word (a reference count and a heap block) is the candidate. Go is the slowest on binary
  trees. Bp is slower than C on all four, and nowhere by an order of magnitude: the goal of this section is not met yet.

  Found on the way, in the typed `bpvet` (it refuses a valid program with a Fatal, so the programs avoid it; none is
  fixed by this change): `Round(X)` and `Trunc(X)` ("not yet implemented: TParamsExpr"; the suite uses `Floor64` of
  `Math`), a literal above the Int64 range as in `QWord($CBF29CE484222325)` (the same Fatal; the hash uses 32 bits),
  `QWord($CBF29CE4) or $84222325` (TBinaryExpr), and a unit with a dot in its name such as `Generics.Collections`
  (`genstubs.py` does not read it from a `uses` clause: "can't find unit"). An untyped real constant is `Extended` in
  FPC: `Dt = 0.001` made n-body print another energy than C, Rust and Go (the three agree) until it was written
  `Dt = Double(0.001)`.

- **Then the levers the numbers point to (step 6),** each measured on its own:
  - the cost of reference counting (`String`, dynamic arrays, `TShared`): `const` parameters (S14) already avoid most of
    it;
  - the region allocator (one bump per object, nothing at the end of a region);
  - the checks a release build keeps (R1–R4 of the runtime);
  - inlining of generics and of small routines;
  - `-O3` and the target CPU (`-Cp`, `-Cf`);
  - the code generator: FPC's own against the LLVM back end of FPC main, where it builds the dialect.

  A lever that needs a compiler fork is out (§0: `bp` works over the stock `fpc`).
