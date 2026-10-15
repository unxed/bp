# Better Pascal in fpide: compatibility inventory (step 2 of unxed/bp#3)

This document is the result of step 2 of [unxed/bp#3](https://github.com/unxed/bp/issues/3): a read-only inventory of `fpide/` against
the rules of this repository (`SPEC.md`, `ext/README.md`). No source file was changed. Every decision below names the evidence
(file, line, count, or SPEC section) on which it rests; what could not be shown without a build is marked **unverified** and is
given to the step that can verify it in CI.

- Baseline: `stable-fpide-20261015`, commit `c449177e5904722a5f3e6c8b321ea8b9bac8d349` (inventory taken 15-10-2026).
- Scope: the files directly in `fpide/src` (65 `.pas`, 15 `.inc`, about 65,100 lines), plus `fpide/compat` and `fpide/tools`
  where they decide how the IDE is built. `fpide/tv` (tv3) and `fpide/tve` are separate projects; the pinned tv3 `9f153cb`
  was searched for threads and libc units only (none found, see D3).
- Method: counts are textual (comments stripped, `Obj.Move(...)` methods excluded from the `Move` count). They show the shape
  of the code, not exact defect numbers, and are not a CI gate. Patterns: `GetMem|FreeMem|ReallocMem|AllocMem|Move|FillChar|FillByte|FillWord|FillDWord` as
  procedure calls, `\.Free\b|FreeAndNil\(`, `New(|Dispose(`, `\bobject\b`, `ShortString|string\[N\]`,
  `PChar|PAnsiChar|PByte|Pointer`, `external`, `TProcess|fpSelect|Terminate(|Exec(`.

## 1. Decisions

| # | Decision | Evidence |
|---|---|---|
| D1 | Steps 3 and 4 use the **safe layer (`unit Safe`)**, not `BP`. | Section 6: `BP` rewrites the global string encodings and drops libc; fpide has its own UTF-8 path in tv3 and links libc through `gdbpty.pas`. |
| D2 | `unit Safe` is supplied by one extra `-Fu` in `fpide/tools/fpide-env.sh` (`-Fu$here/../safe`); the units are not copied and no submodule is added. | Section 6; SPEC §2 ("copy alongside" or `-Fu`); `fpide/` lives in the same repository as `safe/`. |
| D3 | `BP` (goroutines) is adopted only in step 5, and only after the libc question of `gdbpty.pas` is decided (keep libc with `-dSAFE_LIBC`, or replace the four `external 'c'` imports). | Section 6; SPEC §13, §14, §18; `gdbpty.pas:36-39`. |
| D4 | The first pilot module is `fplang.pas` (390 lines). | Section 8. |
| D5 | The first structured-concurrency candidate is the external compiler run, `CompileExternal` in `fpintf.pas:382`. | Section 9. |
| D6 | Modules that use `{$H-}` or no mode switch (56 of 64 units) are **not** flipped to `{$H+}` wholesale. They are migrated one at a time, or marked `// UNSAFE-UNIT:` with a safe facade. | Section 5. |
| D7 | The help-viewer family, `fpusrscr.pas`, `wresourc.pas`, the Windows debugger glue and `fpredir.pas` are unsafe units; they get a marker and a facade, not a rewrite. | Section 4. |
| D8 | Code under `{$ifdef EMBED_COMPILER}` (40 places in 8 files) is not touched until the `FPIDE_EMBED=1` build is covered by a CI job. | Section 7: no workflow builds it. |
| D9 | The unit tests in `fpide/tests/unit` (`t_fplang.pas`, `t_fpdlv.pas`) were run by no workflow or script. They are wired into CI (job `unit` of `fpide.yml`, step 3a) before step 3 relies on them. | Section 10. |

## 2. What fpide is made of

| Measure (files directly in `fpide/src`) | Count |
|---|---|
| `class` types / `destructor`s | 480 / 206 |
| `object` types | 0 (the class migration is done; SPEC §19 does not apply to fpide) |
| `.Free` calls / `FreeAndNil` | 364 / 13 |
| `New(` / `Dispose(` | 19 / 18 |
| `GetMem` / `FreeMem` / `ReallocMem`+`AllocMem` | 64 / 66 / 1 |
| `Move` / `FillChar` family | 44 / 62 |
| `ShortString`, `string[N]` | 186 |
| `Pointer`, `PChar`, `PAnsiChar`, `PByte` | 495 |
| `external` declarations | 12 (`fpmingw.pas` 7, `gdbpty.pas` 4, `fpcompil.pas` 1) |
| threads (`BeginThread`, `TThread`, `cthreads`, critical sections) | 0, also none in tv3 `9f153cb` |
| `{$ifdef}` groups for DOS / Windows / Unix | 32 / 93 / 94 |
| `EMBED_COMPILER` | 40 places in `fp`, `fpide`, `fpviews`, `fpintf`, `fpdebug`, `fpcompil`, `browcol`, `fpswitch` |

Compared with the Turbo Pascal-style code measured in DN (SPEC §12, §19), fpide has no `object` types and 37 `New`/`Dispose`
calls (DN: about 1,260): the typical S1 flood does not happen here. The raw-memory code is concentrated in a few units (section 4).

## 3. Ownership patterns

| Pattern | Where | Safe-layer mapping |
|---|---|---|
| Locals created and released with `try ... finally X.Free` (`TStringList`, `TStringStream`, `TProcess`, parser objects) | `fplang.pas:334-377`, `fpsrcbrw.pas:59-84, 360-421`, most `.Free` calls in `fpswitch`, `fpdesk`, `fpdlv` | `TOwned<T>` (SPEC §0 rule 2) |
| A global registry of objects freed in `finalization` | `fplang.pas:79, 383-388` (`Backends: TList` of `TLangBackend`) | `TArena`; lookups return borrows marked `// borrow: arena` |
| A class that owns one process | `gdbmiproc.pas:31` (`FProcess: TProcess`), `fpdlv.pas:44` (`FProc`) | a `TOwned` field plus a `TDefer` that terminates the child (section 9) |
| Views inserted into tv3 groups | `fpviews.pas` (60 classes), `wviews.pas`, `fpdebug.pas`, `browcol.pas`, `fpsymbol.pas` | not owned by fpide: the tv3 group frees them. Fields get `// borrow: tv3 group` (S5); `TOwned` is wrong here and a double free would result. |
| Collections of records or objects handed to tv3 lists (`ListBoxOwnsList`, streams, `TStreamRec` factories) | `fpviews`, `fpswitch`, `wresourc` | stay as they are until the owner is shown; classify per unit in step 4 |
| fcl-passrc tree elements | `fpsrcbrw.pas` | **unverified**: the tree elements use their own reference counting, so `TOwned` over an element would be wrong; the pilot of that unit must read the fcl-passrc source of FPC 3.2.2 first |

## 4. Raw memory, pointers, unsafe units

Units with eight or more raw-memory calls (`GetMem`, `FreeMem`, `Move`, `FillChar` family), 10,417 lines in total:

| Unit | Lines | Raw calls | Pointer types | What it does |
|---|---|---|---|---|
| `wwinhelp.pas` | 1698 | 34 | 31 | Windows Help (`.HLP`) support: record buffers, phrase tables |
| `fpusrscr.pas` | 1619 | 27 | 2 | user-screen buffers (`VIDEBuffer`, `GraphBuffer`) |
| `whelp.pas` | 1041 | 24 | 30 | help topics and the `.HLP` reader objects |
| `wtphwrit.pas` | 280 | 16 | 2 | help file writer |
| `whtmlhlp.pas` | 1871 | 15 | 3 | HTML help |
| `woahelp.pas` | 581 | 15 | 1 | help format reader (`WoaHelp`) |
| `wos2help.pas` | 615 | 12 | 1 | OS/2 `.INF` help support |
| `wresourc.pas` | 808 | 12 | 10 | resource file objects |
| `fpregs.pas` | 1738 | 9 | 12 | register debug routines of the IDE (also 12 `ShortString`) |
| `windebug.pas` | 166 | 8 | 2 | debugger unit for Windows |

Decision D7: these are the "format layer" and OS-boundary units of SPEC §12 and §19. They are marked `// UNSAFE-UNIT: <why>` with a
safe facade where one is cheap; they are not rewritten in this migration. `MIGRATION-STATUS.md` already lists the help viewer
(byte counting, 255-byte lines) as an open limit of the product, so rewriting it would also widen the scope of the product.

OS boundary units outside that list: `gdbpty.pas` (four libc imports, pty relay), `fpredir.pas` (`Dos.Exec`, `SwapVectors`, 6 `New`/`Dispose`),
`fpcatch.pas` (signals), `fpmingw.pas` and `fpcygwin.pas` (Windows only, not verified in CI).

## 5. Strings and compile modes

`fpide/tools/fpide-env.sh` compiles with `-Mobjfpc -Sh- -Se1 -Sg`. `-Sh-` makes `String` a `ShortString` in every unit that does
not say otherwise. Of the 64 units found under `fpide/src` (including `fakegdb/` and `compiler/`): **8 say `{$H+}`**, 36 say `{$H-}`, 20 say nothing (so they are `{$H-}`).

The `{$H+}` units are `fpextcomp`, `gdbmiproc`, `gdbpty`,
`fplang`, `fpsrcbrw`, `gdbmiwrap`, `fpgodbg`, `fpdlv` (3,370 lines together). They have almost no legacy unsafety (at most 3 pointer
type uses and at most 3 `ShortString` uses each, no `GetMem`) and are the natural targets of steps 3 and 4.

The `{$H-}` units hold the 186 `ShortString` uses and the 255-byte limits that
`MIGRATION-STATUS.md` records (`CharStr`, help lines). Flipping them to `{$H+}` changes record layouts and limits, which
is a product change, not a safety change (SPEC §0, rule S9, requires `ShortString` to stay behind an unsafe boundary). So:

- a `{$H-}` unit is migrated only after its own decision (flip it with its tests, or mark it `// UNSAFE-UNIT:`);
- `uses ..., Safe` in a `{$H-}` unit is **unverified**: the API of `Safe` is compiled in `{$H+}`, so `String` parameters should
  accept a `ShortString` through an implicit conversion; step 3 shows it on one `{$H-}` unit in CI before step 4 relies on it.

## 6. Which layer, and how it is supplied

| | `unit Safe` (`safe/`) | `unit BP` (`bp.pas`) |
|---|---|---|
| What it adds | ownership, slices, arena, defer, FFI, poisoned primitives (SPEC §4-§7) | the same plus UTF-8 defaults and goroutines (SPEC §3, §14) |
| Global effects | none (`Safe` leaves the encodings as they are, `safe/README.md`) | `initialization` sets the default encodings to UTF-8; Linux build is static without libc by default (SPEC §18) |
| Position in `uses` | last in every module | first in the program file, last elsewhere |
| fpide | usable now | blocked by libc (`gdbpty.pas:36-39`) and by the encoding change, until step 5 |

Reasons for D1-D3:

1. fpide's text path is tv3's own UTF-8 handling; the single-byte mode exists only for go32v2 (`MIGRATION-STATUS.md`). A change of
   `DefaultSystemCodePage` by `BP` is a behavior change that has nothing to do with ownership and would have to be tested across
   all 147 `test_functions.py` checks on its own.
2. fpide is not static and not libc-free: `gdbpty.pas` imports `posix_openpt`, `grantpt`, `unlockpt`, `ptsname` with `external 'c'`. SPEC §13
   says `external 'c'` does not link in the static no-libc build that `BP` gives by default; `-dSAFE_LIBC` (cwstring + cthreads) or
   replacing the four imports is needed before `BP` can be used. The Unix branch of that unit also names a BSD/Darwin flag value
   (`O_NOCTTY_`), so a replacement by direct system calls needs a per-OS check.
3. Goroutines need `BP` first in `fp.pas` (SPEC §14). fp has no thread manager today.

Supplying the units (D2): `fpide-env.sh` builds the option string `FPIDE_OPTS`; one more `-Fu$here/../safe` there serves
all three builds (`fpide-setup-build.sh`, `build-fpide.sh`, CI). `safe.pas` includes `core.*.inc` and `poison.*.inc` from its own directory, so no `-Fi` is
needed (**unverified** with this option string; step 3 shows it). `Safe` is added last in `uses`; migration starts in permissive mode
(warnings), and each migrated unit then turns warnings into errors for itself with `{$WARN SYMBOL_DEPRECATED ERROR}` (SPEC §6).
`-Se1` of the IDE build stops at the first error and does not affect warnings.

## 7. Target-specific code and build modes

| Variant | Where it lives | CI coverage |
|---|---|---|
| Linux x86_64 (external `fpc` and `gdb`) | default | `fpide`, `fpide-accept` on Ubuntu 24.04: the only verified target |
| Embedded compiler, `FPIDE_EMBED=1` | 40 `EMBED_COMPILER` places (section 2) | **none**: no workflow builds it (`grep FPIDE_EMBED .github` is empty) |
| DOS go32v2 | 32 `{$ifdef}` groups, `fp.pas` (`dpmiexcp`, `TvUtf8`), `Dos.Exec` in `fpredir.pas` | none |
| Windows | 93 groups, `fpmingw`, `fpcygwin`, `windebug`, `gdbmi*` CRLF handling | none |
| other Unix (BSD, Darwin) | `O_NOCTTY_` in `gdbpty.pas`, 94 groups | none |

Consequences:

- D8: the issue requires `FPIDE_EMBED=1` to stay intact. With no CI coverage, a change to the 40 embedded-compiler places cannot be
  proven harmless. Either a manual (`workflow_dispatch`) job builds `FPIDE_EMBED=1` (the download is about 400 MB, `README.md`), or those
  places stay unchanged and the final gate (step 7) lists the mode as "not verified".
- The `compat/fpc` units (about 6,500 lines of compiler units, kept in the repository) and the `compiler/` tree of the embedded build
  never get `Safe`; they are outside the migration.
- DOS and Windows cannot be claimed: new code must keep the `{$ifdef}` branches compiling in principle, but only Linux is tested.

## 8. First pilot (step 3): `fplang.pas`

Why this unit (D4): it is `{$H+}`; 390 lines; four importers; depends only on `SysUtils`, `Classes`, `Process`, `TvPath`; has three kinds of ownership
risk in a small space (the global registry, the `FormatFile` process with three locals, the `initialization` registration); has a unit test
(`tests/unit/t_fplang.pas`) and an acceptance section (`test_functions.py <fp> golang`); and no part of it is a tv3 view.

Target shape (decisions, not code): the registry becomes an arena (`TArena.Adopt(TGoBackend.Create) as TLangBackend`), `Backends` holds borrows
(`// borrow: arena`), `FormatFile` holds `P`, `Args`, `S` in `TOwned`, the unit says `uses ..., Safe;` last and `{$WARN SYMBOL_DEPRECATED ERROR}`.
Anything that needs `System.GetMem` or a raw pointer stays out of the unit (`Buf: array[0..4095] of Byte` is not a pointer).

Second and third pilots, in order: `gdbmiproc` + `gdbmiwrap` (one ownership boundary: the gdb process), then `fpdlv` + `fpgodbg` (the dlv process and its socket),
then `fpsrcbrw` + `fpextcomp` (after the fcl-passrc question of section 3 is answered).

## 9. Process I/O, cancellation, shutdown

| Workflow | Where | How it runs | Cancellation / shutdown today |
|---|---|---|---|
| External compiler (and language tools) | `fpintf.pas:382-` | `TProcess` with pipes; the UI thread polls `NumBytesAvailable` with `Sleep(10)` (line 465-479) | Esc through `do_status`, then `P.Terminate(1)` (line 478); then waits for the exit. No timeout. `P.Free` in `finally` closes the pipes but is not shown to terminate the child (**unverified**: the step-5 test must show it). |
| Format tool | `fplang.pas:334-377` | blocking read loop, `WaitOnExit` | none, no timeout |
| gdb | `gdbmiproc.pas:62-115` | `TProcess` with pipes; blocking one-byte `Read`, preceded by `PtyWait` on gdb's output (`gdbpty.pas`) | none: no `Terminate` in `gdbmi*.pas`; the session ends when gdb exits or the pipe closes |
| Debuggee terminal | `gdbpty.pas` | pty master relayed by `PtyWait` | `PtyClose` |
| dlv (Delve, DAP) | `fpdlv.pas` | `TProcess` + TCP socket, `fpSelect` with a time slice (line 325), `Sleep(10/20/50)` | `Stop` (line 874): deadline loop, then `FProc.Terminate(0)` (line 898) |
| User program (Ctrl+F9) | `fpredir.pas:772-825` | `Dos.Exec` between `SwapVectors`, synchronous | none (the program owns the terminal) |

The IDE is single-threaded and polls; it does not block the UI for the compiler. This means a goroutine adds little to the compiler flow by itself.
What the flow lacks is **structure**: terminate-on-every-exit (also on an exception), a timeout, and one place that decides how a child dies.

Decision D5 for step 5: do it in two parts. (a) a process guard (`TDefer`-based, `TOwned<TProcess>` inside) that terminates and waits on every exit path, used by the
compiler run first; no threads, so DOS keeps the synchronous path unchanged (SPEC §14: DOS has no goroutines, `TGroup.Go` raises R8). (b) only if a
concrete need remains, a `TGroup` task that reads the pipe and sends lines through a `TChan<String>` that the UI loop drains; UI drawing and
state stay on the UI thread, a blocking `Read` must be replaced by polling plus `Done` in `Select`. (b) needs D3 first.

## 10. Test inventory and gaps

| Tests | What they cover | Wired into CI |
|---|---|---|
| `fpide/tests/accept/test_accept.py` (35), `test_functions.py` (147), `test_menu_sweep.py`, `test_esc_sweep.py`, `test_config.py` | whole IDE through tmux: menus, editor, compile, run, debug, UTF-8 | `fpide-accept.yml` |
| tv3 unit and pty tests | tv3 | `fpide.yml` |
| `fpide/tests/unit/t_fplang.pas`, `t_fpdlv.pas` | the language backend, the dlv session (skips without dlv/go) | run by the job `unit` of `fpide.yml` (`fpide/tools/unit-test.sh`; step 3a) |
| `tests/safe`, `tests/ext` | the Safe/BP layers themselves | `ci.yml` |

Gaps that decide the plan: no leak test exists for any fpide module (`SafeCheckNoLeaks`, SPEC R5, needs the unit under test to use `Safe`); the unit tests
need a runner first (D9); the embedded-compiler mode is not built (D8); the text policy (`tools/text-policy.py`, job `text-policy`) applies to new
documents, comments and messages: English only.

## 11. Steps for the plan (atomic, each for a simpler model)

Each item is one PR from current `main`; the required `ci`, `fpide`, `fpide-accept` runs must be green on the exact SHA; record PR, SHA and result in the issue.

3a. **Run the fpide unit tests in CI.** A job (or a step of `fpide.yml`) builds `tests/unit/t_fplang.pas` with the `FPIDE_OPTS` of `fpide-env.sh` and runs it; `t_fpdlv` is built and runs (it skips without dlv).
    Ready when: the job is green on the PR SHA and fails when a check in `t_fplang.pas` is broken (show it once on a temporary branch, then delete the branch).
3b. **Supply `Safe`.** Add `-Fu$here/../safe` to `fpide-env.sh`. Ready when: the default build and `fpide-accept` are unchanged and green; no source file changed.
3c. **Migrate `fplang.pas`** as in section 8, add `Safe` to `t_fplang.pas` and end it with `SafeCheckNoLeaks`. Ready when: `t_fplang` passes with the leak check, the unit builds with
    `{$WARN SYMBOL_DEPRECATED ERROR}`, `fpide-accept` section `golang` passes, and the PR description lists every remaining `System.`-qualified call with its `// UNSAFE:` reason (or states there is none).
3d. **One `{$H-}` probe.** Add `Safe` last to the smallest `{$H-}` unit that has no views (`gdbcon` in `fakegdb` is not built by default; `fpevalw` or `wconsole`) in a throw-away branch, build it in CI, and record in the issue
    whether the API accepts `ShortString` values. Ready when: the result (accepted or the exact error) is written in the issue and section 5 here is updated.
4.1. `gdbmiproc` + `gdbmiwrap` (the gdb process boundary); 4.2. `fpdlv` + `fpgodbg`; 4.3. `fpsrcbrw` + `fpextcomp`; 4.4. per-unit decision for each `{$H-}` unit with `.Free` locals but no views (`fptemplt`, `fpkeys`, `fpcalc`, `fpevalw`): flip with tests or mark unsafe; 4.5. add `// UNSAFE-UNIT:` markers and facades to the units of section 4; 4.6. mark borrows (`// borrow: tv3 group`) in the view units.
    Each is separate; ready when its units compile with `Safe`, every exception is documented, and `SafeCheckNoLeaks` passes in the unit test where one exists.
4.0. (optional, before 4.4) a census script that prints the section 2 table per unit, so the counts here can be reproduced; only a progress metric.
D8-job. (before any change to an `EMBED_COMPILER` place) a manual job for `FPIDE_EMBED=1`, or an explicit "not verified" line in the final gate.
5a. Process guard for the compiler run (section 9, decision D5): tests for normal exit, partial output, abort (`Terminate`), a child that ignores the signal, a timeout, an exception while reading, and "no child process remains" (check by pid).
5b. Only if still needed: the task + channel form; first decide D3.
6.  The remaining process I/O in small PRs: gdb, format tool, dlv `Stop`, in that order, keeping the synchronous path for DOS.
7.  The final gate as in the issue: `ci`, `fpide`, `fpide-accept` on the final SHA, the pinned tv3/tve unchanged, and a list of supported targets and of the unsafe boundaries.
