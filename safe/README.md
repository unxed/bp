# safe/ — Safe Pascal: memory safety

Layer 1 of 3 in Better Pascal. Only what makes code memory-safe, and nothing more:
`TOwned/TShared/TWeak/TSlice/TArena`, `TDefer`, FFI (`TCResource`), a leak counter and "poisoning"
of dangerous primitives (`GetMem`, `New`, `Move`, `FillChar`, `FreeAndNil`, `Obj.Free`...) by name shadowing.

| File | What it is |
|---|---|
| `safe.pas` | `unit Safe`: pulls in this layer only; `uses ..., Safe;` goes last in the module |
| `core.intf.inc`, `core.impl.inc` | ownership, slices, arena, defer, FFI; the same files are included by `unit BP` |
| `poison.intf.inc`, `poison.impl.inc` | poisoned primitives and the `Free` helper; included last |
| `SPEC.md` | the specification of Better Pascal (both layers); §0 is the rules card, §13 FFI, §14 goroutines, §15–16 plan |
| `DN-ADOPTION.md` | plan for migrating DOS Navigator (`unxed/dn`) to Safe Pascal: stages S0–S10 |

The layer does not depend on `ext/` or `fpide/`. If you also need UTF-8 by default and goroutines, do not use `Safe`;
use `BP` instead (see the [root README](../README.md)): it contains the same code.

The layer's tests are in `tests/safe/` (runtime and `compile/mf_*.pas`: the dangerous does not compile, `System.X` does).
The runner runs them twice: with `unit Safe` and with `unit BP`.

## Status

Iteration 1: code written, the first run of the `ci` workflow is green (the shadowing hypotheses were confirmed).
Iteration 2 (v0.2, ideas from Zig, SPEC §12): `TDefer`, `SafeLiveCount`/`SafeCheckNoLeaks` (R5), a "lessons from practice" section from the DOS Navigator port (`object` versus `class`). Verified by the same workflow.
Iteration 3 (v0.3): goroutines (SPEC §14) and FFI (SPEC §13). Built and run locally (FPC 3.2.2, Linux): all tests green, `test_go` 30 runs in a row without failures. Finding: the thread manager cannot be installed by a unit listed last (it must be initialized before SysUtils), so goroutines need `BP` first in the program file (SPEC §14, §18).
Iteration 4 (v0.3.1): verification on the `unxed/dn` targets (x86_64, i386 and aarch64 Linux statically, DOS go32v2, Windows): table in SPEC §2; on DOS `TGroup.Go` raises R8 instead of hanging.
Iteration 5 (v0.5): Linux without libc by default (threads on `clone`/`futex`, `fpwidestring`), `-dSAFE_LIBC` for FFI; `-dSAFE_NO_CWSTRING` is no longer needed for static builds.
Iteration 6 (v0.6): Better Pascal: UTF-8, goroutines and the thread manager moved to `ext/`; `unit BP` gives both layers. What is implemented and what is only a plan: SPEC, "What actually exists and what is only a plan".

## Hypotheses of the first CI run (historical section, all confirmed)

1. A stub type named `GetMem/New/Move/...` in the module listed last in `uses` hides the
   System procedure/intrinsic, and a call gives a compile error with the text `deprecated` (`SAFE-S1`).
   The `New/Dispose` intrinsics are especially doubtful.
2. `deprecated` is allowed on a type alias declaration (`Pointer = System.Pointer deprecated '...'`).
3. A `TObject` helper with a method `Free(const X: <stub type>)` overrides `TObject.Free`: `Obj.Free` is a compile error (confirmed, `tests/safe/compile/mf_free.pas`).
4. Inside a generic record, its name without parameters (`TOwned`) denotes the current specialization.
5. Generic bodies specialized in the user's module see the private fields and interface
   symbols of `Safe` and do not trip over the poisoned names.
6. `specialize TArray<T>` from System is available in FPC 3.2.2.

If any of this is not confirmed, the fallbacks are: (1) an ordinary procedure with `deprecated` and
`{$WARN SYMBOL_DEPRECATED ERROR}`; (2,3) linter only; (4) a nested type alias.

## Doubtful decisions (recorded, for discussion)

- `TOwned` is reference-counted, uniqueness is a linter contract (rationale: SPEC §4).
- `BP` changes the global encodings in `initialization`; turned off with `-dSAFE_NO_UTF8` (`Safe` leaves them as they are).
- License: **MIT** (file `LICENSE`; owner's decision 2026-10-03). It is compatible with moving into FPC/Lazarus: the code can be taken into the RTL under its modified LGPL without changing anything on our side.

## Next iterations

A linter on `fcl-passrc` (rules S3–S10), a Lazarus package for OPM, Windows in CI (SPEC §11).
