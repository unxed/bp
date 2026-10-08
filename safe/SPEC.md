# Better Pascal — specification v0.6

Safe-by-default Free Pascal. Not a fork, not a new syntax: **one unit `BP` and one line in every module**:
`uses BP, ...;` first in the program file, `uses ..., BP;` last in every other unit.
Works on stock FPC 3.2+ with no compiler options.

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
| Go-style package manager: `deps.txt`, `deps.lock`, MVS, `vendor`, mirrors, Software Heritage, unsafe audit | **specification only (plan), no code** | §15 |
| The `sp` tool (`build/test/vet/fmt/doc/get/vendor/unsafe/embed/fuzz`) | **plan only** | §16 |
| Linter for rules S3, S5–S14 (`fcl-passrc`) | **plan only** | §6, §11 |
| Fuzzing (`fuzz_*.pas`, `sp fuzz`) | **plan only** | §16 |
| Immutability by default (S14) | **plan only** (linter check) | §16 |
| Lazarus package (OPM), Windows in CI | **plan** | §11 |
| CI: "no INTERP/NEEDED" check, Alpine/Debian/Ubuntu 16.04/CentOS 7 in containers, i386 and aarch64 under qemu | **implemented** (`.github/workflows/ci.yml`) | §18 |
| Support for `object` (Turbo Pascal) | **plan** | §19 |
| GC heap | **deliberately not adopted** | §18 |

---

## §0. Rule card (for the model and for the reviewer)

```
HEADER OF EVERY MODULE
  {$mode objfpc}{$H+}                 // this is what Lazarus writes into a new module anyway
  uses ..., SysUtils, ..., Safe;      // Safe goes LAST in uses (S7)

STRINGS                                (UTF-8 everywhere)
  The only string type is String, always UTF-8.
  Length(S) and S[i] are BYTES. Pos/Copy/Delete on byte indices are correct.
  Characters are rarely needed: for Ch in CodePoints(S) (Ch: String), CPLength(S).
  UnicodeString/WideString/ShortString/PChar — only at the OS boundary, in unsafe code.
  Binary data — specialize TArray<Byte>, not String.

DATA AND LIFETIME                      (chosen by data structure, not by project)
  1. By default — values: record, String, specialize TArray<T>. No lifetime problems.
  2. An object with one owner         → specialize TOwned<TFoo>.Own(TFoo.Create(...))
  3. An object with several owners    → specialize TShared<TFoo>.Share(TFoo.Create(...))
     back reference / cache / observer → TWeak<TFoo> from Shared.Weak (Shared cycles are forbidden)
  4. Many objects with the same fate  → TArena: A := TArena.Create; X := A.Adopt(TFoo.Create) as TFoo
  5. COM interfaces (TInterfacedObject) — a ready-made Shared; hold the object ONLY through the interface.

REFERENCES
  Fields own, locals borrow:
    field/global variable of a class type  → TOwned/TShared/TWeak/interface
    parameter/local variable of a class type → borrow, lives no longer than the call
    a borrow field is allowed only with a comment  // borrow: <who owns it>   (S5)
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
  DOS: no threads, TGroup.Go raises R8. Windows: builds, run not verified.

UNSAFE
  Unsafe things are written with full names (System.GetMem, SysUtils.FreeAndNil, System.Pointer)
  and on the line above — a comment  // UNSAFE: <why this is safe>.
  A whole unsafe module: lives in unsafe/, first line  // UNSAFE-UNIT: <why>.
  Raw pointers do not leave unsafe code into the safe API.

GOROUTINES                             (§14; "do not communicate by sharing memory — share memory by communicating")
  G := TGroup.Create;  G.Go(TWorker.Create(Args, Ch));  ...  G.Wait;   // the group waits for everyone, also on leaving the scope
  A task = a class descending from TTask: arguments are fields set in the constructor, the code is Run.  Simple case: G.Go(@Proc).
  Task fields: values, String, TArray, TChan, TShared, TOwned via Move. Not borrows, not shared objects (S11).
  Channels: Ch := specialize TChan<T>.Create(Cap); Send / Recv(out V): Boolean / TryRecv / Close; for V in Ch.
  select: case Select([A.Sel, B.Sel, Done], TimeoutMs) of ... — then TryRecv; -1 = timeout.
  Cancellation: G.Cancel → Done is closed; in a task — Cancelled or Done in Select. A task error → G.Wait raises R7.
  IN THE PROGRAM FILE, as the first unit  uses BP, ...  (it installs the thread manager: on Linux threads without libc, §18;
  with -dSAFE_LIBC and on other Unixes — cthreads). BP not first → the first Go stops the program (code 211).

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
| Windows x86_64 (cross-compiler) | builds | builds | builds | builds | builds; run not verified (no wine) |

Conclusion: after v0.5 (Linux without libc by default) the core, goroutines, threads and sum types work on all verified Linux targets, including static i386 and aarch64 without libc, without any switches;
FFI depends on libc/the OS. To check your own set: `tests/run.sh` with `FPC`/`FPCOPTS`/`RUN` of a cross-compiler (qemu-user); the repository CI runs Linux x86_64, i386 and aarch64.

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
| `GCHeap` | outside the MVP (§11) | |
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

Thread safety in v0.1: the counters are atomic, so `TShared` can be copied between threads;
`TWeak.TryLock` from different threads concurrently with the last `Reset` is a race (§11).

## §6. What enforces each rule

| Rule | What is forbidden | What catches it now |
|---|---|---|
| S1 | `GetMem/FreeMem/ReallocMem/AllocMem/New/Dispose` | **compiler**: shadowed by a stub type → an error + the message `SAFE-S1` |
| S2 | `Move/FillChar` | **compiler**: the same, `SAFE-S2` |
| S3 | `.Free`, `FreeAndNil`, `.Destroy` | `FreeAndNil` and `.Free` are a compiler error. `.Free` is closed off by a `TObject` helper with the method `Free(const X: SAFE_S3_NoFree_UseTOwnedReset_or_UnsafeDestroy)`: without an argument the call does not compile, and the type name in the "Found declaration" message explains the rule. `.Destroy` — linter |
| S4 | `Pointer, PByte, PChar, PAnsiChar, PWideChar`, `^T`, `@`, pointer arithmetic | the types — warning `SAFE-S4`; `^T`, `@` — linter |
| S5 | a field/global variable of a class type without `// borrow:` | linter |
| S6 | `TFoo.Create` not immediately into `Own/Share/Adopt`/an interface/`raise` | linter; partly at runtime (R3) |
| S7 | `Safe` is not last in `uses` | linter (otherwise `FreeAndNil` from SysUtils is not shadowed, the helper may be overridden) |
| S8 | unsafe code without `// UNSAFE:` / a module without `uses Safe` and without `// UNSAFE-UNIT:` | linter |
| S9 | `UnicodeString/WideString/ShortString` outside unsafe | linter |
| S10 | a copy of `TOwned` not via `.Move`; `TOwned` by value in a parameter | linter; the runtime is safe in any case (§4) |
| S11 | a field of a `TTask` task is a borrow or a mutable object accessible to other threads | linter |
| S12 | `external` outside a `// UNSAFE-UNIT:` module; a binding's public API with pointers | linter |
| S13 | a `case` over an enumeration does not list all values or has `else`; a variant field is read outside the branch of its tag (§16) | linter (FPC 3.2.2 does not warn) |
| S14 | a parameter without `const`/`var`/`out`; `var` although the caller does not need the change (§16) | linter |

Warnings are turned into errors with one directive in a module, `{$WARN SYMBOL_DEPRECATED ERROR}`,
or with the switch `-Sew` for the whole project. Migration modes: **permissive** — warnings;
**strict** — errors.

Recommended FPC checks for a debug build (in Lazarus — the Debug build mode):
`-Cr -Co -CR -Sa -gh -gt` (ranges, overflow, object checks, assert, heaptrc, garbage
in local variables). In a release you can drop `-Cr -Co -CR`; the R1–R4 checks remain.

## §7. Unsafe

```pascal
// UNSAFE: Buf is allocated for Len bytes on the line above and freed in the finally of this same procedure
System.GetMem(Buf, Len);
```

- Inside a safe module: full names (`System.GetMem`, `System.Move`, `System.Pointer`,
  `SysUtils.FreeAndNil`, `Obj.Destroy`) and a `// UNSAFE:` comment on the line above.
- Whole modules (WinAPI bindings, terminal, allocators, C libraries): the `unsafe/` folder,
  first line `// UNSAFE-UNIT: <why>`, `uses Safe` may be omitted.
- Boundary: the public API of an unsafe module uses only the types from §4–5; raw pointers do not leave it.

## §8. An honest table of guarantees

| Guarantee | Level |
|---|---|
| No `GetMem/FreeMem/New/Dispose/Move/FillChar/FreeAndNil` outside unsafe | compiler |
| Double free through `TOwned/TShared/TArena` is impossible | runtime construction (counter) |
| Access to an empty owner, going out of slice bounds | runtime (ESafety) |
| A dangling `TSlice`, a dangling `TWeak` | impossible by construction |
| `.Free` outside unsafe | compiler (error) |
| raw pointers outside unsafe | compiler warning + linter |
| A borrow (parameter/local) does not outlive the owner | linter (S5) + programmer |
| No `TShared` cycles | programmer + linter (heuristic) |
| Arena objects are not used after `FreeAll` | programmer; in debug `-gh` |

We do not claim this is Rust. We claim: in safe code there is no **syntactic**
way to make the typical memory errors, and the remaining holes are listed above.

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

- **Linter** on `fcl-passrc` (the Pascal parser shipped with FPC): rules S3–S14, output in the format of
  FPC messages so that the IDE shows them as compiler errors.
- **Lazarus package** `safepascal.lpk` in OPM: one-click installation.
- **GC heap** as a tracing arena: objects declare `procedure Trace(V: TVisitor)`,
  roots are `TShared` to the heap; `Collect` instead of `FreeAll`. Only for graphs where ownership is unnatural.
- `TWeak.TryLock` between threads (a lock in the cell).
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

## §14. Goroutines: like Go, better in places

The Go principle — "share memory by communicating" — maps onto the Safe Pascal ownership model: ownership
passes into the task (fields, `Move`), and values come back through a channel.

| Go | Safe Pascal | Better or worse how |
|---|---|---|
| `go f(x)` | `G.Go(TF.Create(X))` / `G.Go(@Proc)` | worse: no closures in FPC 3.2 (in 3.3+ an overload with an anonymous procedure can be added) |
| `chan T`, `make(chan T, n)` | `specialize TChan<T>`, `TChan.Create(N)`; a copy of the record is the same channel | the same: a reference type, `N = 0` — rendezvous |
| `v, ok := <-ch`, `for v := range ch` | `Ch.Recv(V)`, `for V in Ch` | the same |
| `select` | `Select([A.Sel, B.Sel], TimeoutMs)` + `TryRecv` | worse: receive only, not atomic with the receive (retry on failure) |
| `sync.WaitGroup`, `errgroup` | `TGroup` | **better**: the group waits for the tasks on leaving the scope (structured concurrency), a goroutine leak is impossible |
| a panic in a goroutine kills the process | error → group cancellation → `Wait` raises R7 with the original text | **better** |
| `context.Context` | `G.Cancel`, `Done` (a closed channel) in `Select`, `Cancelled` | the same in meaning, without an extra parameter |
| races are caught by `-race` | races are prevented by S11: only values, channels, `TShared`, `Move` go into a task | different: a prohibition instead of a detector |
| M:N scheduler, millions of goroutines | one task = one OS thread | worse: thousands, not millions; honestly "conditional" goroutines |

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
no deadlock detection ("all goroutines are asleep"); `TWeak.TryLock` between threads is a race (§11).

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

## §16. What else to take from Go and Rust (plan)

### The `sp` tool: one command, like `go`

The main convenience of Go is not the language but one command for everything. Each `sp` subcommand is a thin wrapper over
what is already shipped with FPC (verified: `ptop`, `fpdoc`, `data2inc`, `bin2obj`, `h2pas` are installed together with
`fp-compiler`), so each subcommand is small:

| `sp` | Analogue | Built on |
|---|---|---|
| `sp build [-release]` | `go build` | `fpc` + `-Fu` of the dependencies + a check profile (§6): debug `-Cr -Co -CR -Sa -gh -gt`, release without `-Cr -Co -CR` |
| `sp test` | `go test` | a generalized `tests/run.sh`: `test_*.pas` (return code = number of failures) and `compile/*.pas` with `// EXPECT:` (an analogue of trybuild in Rust); `examples/*.pas` are built too (an analogue of Rust doc tests) |
| `sp vet` | `go vet`, clippy | a linter on `fcl-passrc`: S3–S14 |
| `sp fmt` | `gofmt` | `ptop` with a single fixed config from this repository: one style, no settings |
| `sp doc` | `go doc` | `fpdoc` |
| `sp get / vendor / unsafe` | `go get`, `go mod vendor`, cargo-geiger | §15 |
| `sp embed files` | `//go:embed` | `data2inc`: files are turned into a module with constant arrays |
| `sp fuzz` | `go test -fuzz` | below |

`sp` is written in Safe Pascal itself as a single file (dependencies are downloaded in parallel by goroutines §14):
the tool also serves as an example project.

### Fuzzing almost for free

In C a fuzzer needs sanitizers, otherwise memory corruption goes unnoticed. In Safe Pascal a memory error is already
turned into an exception (`ESafety`, `ERangeError` with `-Cr`, `EAccessViolation`), so the very
simplest fuzzer suffices: `fuzz_*.pas` declares `procedure Fuzz(const Data: array of Byte)`, `sp fuzz` feeds
random and mutated inputs from a corpus folder, and an input that caused an exception is saved as a new test.
This is a few dozen lines on top of `sp test`.

### Sum types and exhaustive matching (enum and match from Rust)

Tagged variant records have existed in Pascal since 1970. Two checks are missing, and both are the linter's job, not the library's:

```pascal
type
  TShapeKind = (skCircle, skRect);
  TShape = record
    Name: String;                      // managed fields — in the common part
    case Kind: TShapeKind of
      skCircle: (R: Double);
      skRect:   (W, H: Double);
  end;

function Circle(const AName: String; AR: Double): TShape;   // create only this way
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
`const` parameter, and the linter finds parameters without a modifier.

### What we deliberately do not take

| In Go/Rust | Why we do not take it |
|---|---|
| borrow checker | impossible without changing the compiler; replaced by the rules S5/S11 and the runtime (§4, §8) |
| `?` and `Result<T, E>` | in Pascal exceptions with guaranteed finalization (`TOwned`, `TDefer`) give the same more briefly |
| the `-race` race detector | races are prevented by S11 (ownership is passed into a task, not shared access) |
| a central registry (crates.io), the Go proxy | no infrastructure; in the "hash + mirrors" model (§15) they are not needed |
| M:N scheduler | honestly "conditional" goroutines (§14) |

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
| v0.4 (plan) | §15 dependencies like Go without a proxy (a git hash instead of a checksum database, mirrors, `vendor/`, unsafe audit); §16 the `sp` tool, fuzzing, sum types (S13), parameter immutability (S14) |

## §18. Portability like Go: Linux without libc by default (v0.5)

- **The default on Linux is a static binary without libc**: strings — `fpwidestring` + `unicodeducet` (Unicode in Pascal, case and sorting work even with `LANG=C`), threads — `ext/bpthreads.pas` (an FPC thread manager on `clone` + `futex` + `mmap`, like the Go runtime). One file works on any distribution: verified on an Ubuntu host (glibc) and in an Alpine 3.20 chroot (musl); a libc build does not run on Alpine at all.
- **A program with goroutines**: `uses BP, ...` — FIRST in the program file (instead of `cthreads`) on all targets.
- **`-dSAFE_LIBC`** (an analogue of cgo): `cwstring` + `cthreads`; needed only for FFI with C libraries. If libc is loaded and the switch is absent, the first `BeginThread` stops the program with an explanation (code 232) rather than giving a silent race (`tests/ext/compile/mf_libc_guard.pas`).
- Verified (FPC 3.2.2, cross-compilers built from the official sources): x86_64 natively and in Alpine; i386 natively and under qemu-i386; aarch64 under qemu-aarch64 — `test_safe`, `test_go`, `test_threads` (1500 tasks: heap, strings, exceptions, recursive locks, `TThread`, events) — 0 failures, 10 repeats without crashes.
- Design: the current thread is found by the stack pointer (the stack region is aligned to its own size, at its start is the thread record with the threadvar block; the main thread is the range `[stack limit, argv)`), without assembler TLS; assembler only for `clone` (≈20 lines per architecture).
- In the terms of `unxed/static-everywhere` the default is "Profile S"; `SAFE_LIBC` is "Profile H" (the baseline glibc version = the version on the build machine). CI checks that the binaries have no INTERP/NEEDED (`readelf`) and runs them in Alpine, Debian, Ubuntu 16.04 and CentOS 7 containers. Plan: host data (CA certificates, time zones) to be read from the host rather than embedded.

**GC — weighed, not adopted.** For an LLM the difference from Go is choosing the owner of an object and two "holes": `TShared` cycles and a borrow that outlives its owner. Values (strings, arrays, records) are managed automatically anyway. Cycles are caught by `SafeCheckNoLeaks` in tests (R5), a dangling borrow by the debug build `-gh -CR` + `HEAPTRC=keepreleased` (memory is not reused, a method call on a dead object is caught). The ARC + weak + arenas model is the Swift model, and a great deal of application code is written on it without a GC. A tracing GC without compiler support would be a conservative scanner of stacks and heap (Boehm) — a large unsafe component with non-deterministic destructors: overengineering. The default rule for an LLM: "if you do not know what to choose — TShared; back references — TWeak; trees and graphs — TArena".

## §19. Turbo Pascal style code (`object`): plan

Rationale: a measurement on real code (DOS Navigator, `unxed/dn`): `New(` 843+103, `Dispose(` 421+39, `object` types 230+75 versus one `class`, `ShortString`/`String[N]` about 300.
`TOwned<T: class>` does not cover such code, and shadowing `New/Dispose` gives thousands of S1 errors that are not defects.

| Option | Essence | Decision |
|---|---|---|
| (c) an unsafe layer with a safe facade | old code is marked `// UNSAFE-UNIT:`, new code is written per SPEC | **first**: zero risk, gives measurements (a violation counter) |
| (a) extend Safe Pascal to `object` | an owner over an `object` type: a pointer + a "lifetime lock" with a release procedure (`Done` + `Dispose`); for `object`, `New/Dispose` are not shadowed | **second**: a narrow prototype on a small slice, a checkpoint by the numbers |
| (b) move the code to `class` | `Init/Done` → `Create/Destroy`, ~1400 call sites | **fallback**: only for a slice where (a) did not give guarantees |

The order (the RUP method: from simple to complex, atomic steps with tests, something to try at every step) and steps S0–S10 are kept in `unxed/dn`, `PLAN.md`, the section "Safe Pascal as the DN code style". The license is MIT.
