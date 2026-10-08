# Safe Pascal in DOS Navigator: migration plan (RUP S0–S10)

> **Better Pascal:** `safe.pas` has been split into `safe/`, `ext/` and `bp.pas`; for DN, either `unit Safe` (safety only) or `unit BP` (plus UTF-8 and goroutines) fits. The text below is historical.


Moved from `PLAN.md` of the [`unxed/dn`](https://github.com/unxed/dn) repository (2026-10-03); continue from here. The status of S1–S10 is kept here; `dn/PLAN.md` only has a link.

Concept: this repository (`SPEC.md`, `bp.pas`, `safe/`, `ext/`, tests, CI; "ground truth", refined by experience).
A single file `safe.pas` and `uses Safe` last in a module, no compiler options: UTF-8 everywhere, `TOwned/TShared/TWeak/TSlice/TArena`, dangerous primitives
(`GetMem/FreeMem/New/Dispose/Move/FillChar/FreeAndNil`, `.Free`, raw pointers) are shadowed and give an error or warning with code `SAFE-S1..S4`; unsafe code is written with the full
name (`System.GetMem`) with a `// UNSAFE:` comment. The author's first CI run (2026-10-03, 12:13) is green: the shadowing hypotheses were confirmed; there is no linter for rules S5–S10 yet.

Owner's decision: move DN to this style as the **final refactoring step** (or earlier, if that turns out to be beneficial) as a live showcase and a test of the concept on real code.

**Measurement (2026-10-03), what is in the sources today** (`dn/src`, 161 files; `tv/src`, 45 files): `New(` 843 / 103, `Dispose(` 421 / 39, `GetMem` 45 / 25, `FreeMem` 63 / 26, `Move(` 137 / 46,
`FillChar(` 95 / 49, `PChar/PByte/PAnsiChar` 150 / 83, `Pointer` 421 / 125; `object` types 230 / 75 versus `class` 1 / 0; `ShortString` and `String[N]` 299 / 296.

**The main discrepancy to resolve before mass edits:** Safe Pascal is built around `class` (`TOwned<T: class>`, `uses Safe` shadows `New/Dispose`), while DN and TV are written in the Turbo Pascal style:
`object`, `New(P, Init(...))`, `Dispose(P, Done)`, `ShortString`, `Move/FillChar` over stream and resource records. A straightforward "just one more `uses Safe` line" would produce thousands of S1 errors, and none of them would be about a real defect.

**Stages (each is a separate iteration with tests and an entry in `dn/TODO-later.md`; measure first, edit afterwards):**
1. **Re-verify the concept on our side.** Copy `safe.pas` to a working directory (not into `dn/src`!), build a `tv/tests`-like example and a new unit with `uses Safe` using our `fpc` 3.2.2 (go32v2, i386-linux, x86_64, aarch64,
   Windows): the goals are whether shadowing and UTF-8 initialization work on all our targets (especially DOS: `cwstring` and `SetTextCodePage` are not needed there, `DefaultSystemCodePage` is meaningless; `SAFE_NO_UTF8`).
   **Result of stage 1 (2026-10-03):** `safe.pas` v0.2 and `tests/test_safe.pas` (with `TDefer` and leak counter tests) with our FPC 3.2.2 cross-compilers: **x86_64 Linux** (this repository's CI) is green;
   **i386-linux** and **aarch64-linux** (static, no libc; aarch64 under qemu): 0 failures, but only with `-dSAFE_NO_CWSTRING` (otherwise `cwstring` pulls in libc and linking fails; the switch was added to `safe.pas` and SPEC §2). **Update (v0.5):** on Linux `safe.pas` is now libc-free by default (`fpwidestring`, own threads in `safethreads.pas`), `-dSAFE_NO_CWSTRING` is not needed for static builds; i386 and aarch64 under qemu are run by this repository's CI;
   **go32v2 (DOS, DOSBox-X):** 0 failures, `cwstring` is not used there; **win64:** builds (running not verified: no wine). Conclusion: the concept is portable to all our targets; the only change needed was for static Linux.
2. **Census script** `tools/safe-census.py`: for each unit it counts S1–S10 violations (textually, without compiling) and prints a table and a total; CI writes the number to the log. This is a progress metric, not a gate.
3. **Pilot on new code** that has no Turbo Pascal objects: `dnutf8.pas`, `tvutf8`, the terminal emulator core (`tvvt*`), new utilities. We write per §0 of the SPEC, `uses Safe` last, everything else as is;
   we measure the cost (lines, tests) and find holes in the concept itself (what was missing, what gets in the way). The results go to `docs/` and back to the concept's author (issues/PRs in this repository).
4. **Decision on `object` (taken by the order of S1–S10 below: (c) → (a) → (b) as a fallback).** Options: (a) extend Safe Pascal to `object` (an owner `TOwned` over `object` types, `Init/Done` instead of `Create/Destroy`); (b) convert TV and DN from `object` to `class` (as magiblot did,
   but this revisits the whole API that DN relies on: stream `Load/Store`, `PView`, `TStreamRec`); (c) keep TV as an "unsafe layer" (`// UNSAFE-UNIT:`) with a safe facade for new code. We choose after stages 1–3, by the numbers.
5. **The DN body, leaf by leaf:** first units with no dependency on the `object` hierarchy (strings, names, settings, file formats), one per commit, tests green before and after; then the rest. Strings: `ShortString` → UTF-8 `String` only where it does not break
   DN's binary file formats (`DN.INI`, `.DLG`, histories, `DN.DSK`), which are read with `String[N]` records: a "file format" layer is needed.
6. **Showcase:** a documentation page "DN before and after" with metrics (`safe-census`), and a separate CI run that fails if the number of violations in the "safe" units has grown.

**Ideas from Zig worth trying in the concept itself (the owner allowed refining it; verify on our code, not in theory):**
- *Explicit allocator as a parameter.* In Zig, any function that allocates memory receives an allocator. Our `TArena` is already like that; the rule "a function that creates objects in a safe module takes a `TArena` or returns a `TOwned`"
  gives the same thing: it is visible who is responsible for the memory. Pilot: the new `tvvt*` units (terminal history, screen lines) take an arena.
- *A test allocator that catches leaks* (`std.testing.allocator`). `TOwned/TShared/TArena` count live objects; `SafeLeakCheck` at the end of a test fails if the counter is non-zero, with class names in the message. Cheap (one counter
  by class name under `{$IFDEF SAFE_DEBUG}`) and immediately useful for our 230 `object`s: it finds leaks without `heaptrc` and without `-gh`.
- *`defer` / `errdefer`.* In Pascal this is `try/finally`, but in safe code, instead of `try/finally` with `Free`, a variant without manual release is needed: a `TDefer` record (an interface with a closure, fires on leaving the scope,
  including on an exception) for non-memory resources: close a handle, restore the terminal mode, release a lock. DN has many such places (terminal, file locks, mouse cursor).
- *Errors as values (`!T`) and `try` propagation.* The SPEC adopts the idiomatic `TryX(out V): Boolean`; only one thing from Zig is suitable: an enumerated reason type (`TFileError`) instead of Boolean where there is more than one reason
  (no file / no permissions / disk full). We do not introduce new syntax.
- *Integer overflow is an error in safe mode.* In FPC this is `-Co`; the SPEC already recommends it for debugging. For DN, where file size and position arithmetic is done on 32-bit integers, enabling `-Co` in the test build (lint mode) is
  a useful step of its own, even without the rest of Safe Pascal.
- *Not adopting:* `comptime` (FPC has none), option types `?T` (the SPEC deliberately rejected them), strings as non-owning slices (we have reference-counted `String`).

**Decision on the order (the owner asked to choose by RUP, 2026-10-03): from simple to complex, in atomic steps with tests, so that at every step the user has something to try.**
The chosen path is "(c) → (a) → (b) if needed": first the variant with no rewriting of old code and no risk, which also provides measurements; then a narrow experiment with variant (a) on a small slice of TV with a decision point;
(b) (conversion to `class`) stays as a fallback and is applied only to the slice where (a) did not provide the needed guarantees. Reason for the choice: each next step relies on the numbers from the previous one, and rolling back any step is cheap.
Rules for all steps: DN behavior does not change (the `tv/`, `dn/` tests and `tools/dn-linux-ops.py` are green before and after), the build passes on all targets (linux64, linux, aarch64, dos, win64, win32), one step is one commit or one short series,
everything doubtful is recorded in `dn/TODO-later.md`, `dist/` is updated on noticeable steps. Decision points are marked **[owner's decision]**.

*Phase "Start" (removing risks, changing nothing in DN code):*
- **S0 [done 2026-10-03].** The concept in this repository, the result of verification on our targets (SPEC §2). *To try:* `tests/run.sh`, the table of targets.
- **S1. Violation census `tools/safe-census.py`.** Reads `dn/src` and `tv/src`, counts S1–S4, S9 (and the `object`/`class` share) per unit, prints a table and a total, saves JSON. *Tests:* python tests on small samples and a check of the totals against the measurement from this section (843/421/230...).
  *To try:* `python3 tools/safe-census.py` shows which units are closest to "safe" and how many places each option affects. CI prints the total (not a gate).
- **S2. License and wiring up `safe.pas`.** **Decided (owner, 2026-10-03): MIT** (MIT is compatible with moving into FPC/Lazarus). Recorded in `LICENSE` and the `safe.pas` header (`SPDX-License-Identifier: MIT`).
  Next: `safe.pas` is placed in `dn/third_party/` (or `tv/`) together with a provenance note (`dn/PROVENANCE.md`, `check-layout.sh`). *To try:* `tools/build.sh linux64` with `DN_SAFE=1` builds DN where only the units from the list (empty for now) are compiled in Safe mode.

*Phase "Development" (variant (c): safe new code next to the old):*
- **S3. The first unit in Safe mode.** A dependency leaf without `object`: `dnutf8.pas` (strings, widths, proxies). `uses Safe` last, permissive mode, then strict. *Tests:* `dn/tests/t_dnutf8.pas` as is, plus R-code checks if the unit allocates anything.
  *To try:* DN under DN_SAFE=1 behaves the same (`dn-linux-ops.py`), `safe-census` shows the first "clean" unit.
- **S4. The "no worse" gate.** CI compares the `safe-census` output with `tools/safe-baseline.json`: the number of violations in units from the "safe" list does not grow. *To try:* deliberately add `GetMem` to a "safe" unit, and CI will show what and where.
- **S5. Batches of leaf units** of 3–5 (file formats with a "format layer" boundary, settings, names, key parsing), each batch in a separate commit; units that do not pass without `object` stay on the "waiting" list. *To try:* the `safe-census` progress table grows, DN stays the same.
- **S6. A new feature written per the SPEC** (showcase): for example, gluing the built-in terminal (`dnrun.pas`, `dnutil`) or the user screen after an external program (the DOS remainder), with `TOwned`, `TDefer` and `SafeCheckNoLeaks` in tests.
  *To try:* the feature itself in DN + a "what it looks like in Safe Pascal" section in the documentation.

*Decision point:* **[owner's decision]** after S6, by the `safe-census` numbers and the experience of S3–S6: is (c) enough, or do we move to (a)?

*Phase "Development, variant (a): `object` under Safe Pascal":*
- **S7. Owner prototype for `object`** (`TOwnedObj`: a pointer + a "lifetime lock" with a release procedure `Done`+`Dispose`) in this repository, with tests on `object` types from TV. No DN changes.
  *To try:* `tests/test_object.pas` in Safe Pascal; an example "TV window under `TOwnedObj`".
- **S8. A TV slice on (a).** 3–5 units from the very bottom (`tvobjs`, `tvgeom`, `tvutil`, part of `tvviews`): `New/Dispose` for `object` are not shadowed, owners at the boundaries, `safe-census` counts them as safe. *Tests:* all `tv/tests` on all targets.
  *To try:* `tvdemo` built with these units in Safe mode, the same interface visible.
- **Checkpoint (a):** **[owner's decision]** — which guarantees (a) really holds on the slice (measurement: how many boundaries with a raw `PView`, how many `// borrow:`), and whether to spread it further, or the rest of the slice needs (b).

*Phase "Construction":*
- **S9. Spreading leaf by leaf upward** (TV, then DN units by dependencies), in batches, the S4 gates grow. At each step `dist/` is updated if anything visible changed. For a slice where (a) did not fit — (b), point by point, by the same "leaf by leaf" principle.
- **S10. Showcase "DN before and after":** a documentation page with `safe-census` metrics, a list of remaining `unsafe` places with reasons, speed and memory measurements on DOS and Linux (not measured so far). SPEC update from experience: refinements go straight to `main` of this repository (another dialog may edit the same specification: pull `main` before editing).

**What we consider done:** the share of units in Safe mode and the list of remaining `unsafe` places with reasons are public; new code is written per the SPEC; DN works on all targets; the decision on `object` is made by the numbers, not by reasoning.

**Doubts (recorded, to discuss with the owner):** (1) scale: ~30 thousand affected lines, this is months of work, not one session; (2) `New(P, Init)` must not be shadowed until item 4 is resolved; (3) DN's binary formats are tied to `String[N]`
and `Move` over records; (4) the DOS target: `Safe` is designed for UTF-8 everywhere, while DOS stays on a code page (plan, milestone 6); (5) `TOwned` on reference counting and uniqueness as a "linter contract": there is no linter yet;
(6) performance on 386/DOS (atomic interface counters). For each — a measurement, not reasoning.
