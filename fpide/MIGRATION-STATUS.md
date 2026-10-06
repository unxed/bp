# Migration status: Free Vision → tv3, objects → classes

Updated: 2026-10-06 (fp links and RUNS; acceptance tests in fpide/tests/accept)

**Owner rule:** complete transfer without breaking functionality. See `.cursor/rules/fpide-full-port.mdc`.

## Current state

- **Compiler:** real FPC `compiler/` @ same pin as IDE (`upstream.env`). **Not in git** — `fpide/bootstrap/ensure-compiler.sh` → `build/bootstrap-fpide/staging-compiler`. CI bootstrap diffs only `fpide/src`.
- **Build flags:** match upstream IDE fpmake (GDB/MI, BrowserCol, …).
- **Preflight:** smoke OK; next IDE error is `object` vs `class` (`wutils.pas`) — class-migrate UI units.
- **Objects shim:** `MaxBytes` via `manual/objects.inc`.

## Next session

1. Class-migrate IDE units inheriting TV types (`WUtils`, …).
2. Full link with compiler+debugger; PTY acceptance vs vanilla `fp`.

## 2026-10-06: where the build stands

`tools/fpide-autofix.sh` builds `fp.pas` and applies three mechanical fixers driven by the FPC log
(`fpide-nested-cast.py`, `fpide-ptrcast.py`, `fpide-derefcast.py`), then you fix the rest by hand.
`tools/fpide-streamrec-migrate.py` moved the 43 `TStreamRec` constants to tv3-style factories.

Done this session: `-Ur` removed from `fpide-env.sh` (it froze stale `.ppu` files); `autoderef` +
`nestedprocvars` in every unit; CP437 box characters lost as U+FFFD restored from upstream;
`CharStr` takes a string (UTF-8 box characters); topic callbacks in `wwinhelp` are nested procvars;
`var S: TStream` parameters became value parameters; `TListBox.Get/SetFocusedItem` added to tv3.

Reached: everything before `fpcompil.pas`. Open there (and probably in later units):
- FV APIs that tv3 lacks: `GetKeyEvent` (poll for Esc during compile), `CtrlBreakHit`, `ShrinkPath`, `PPalette`.
- `Desktop.ForEach(@Nested)` is reported as "address of ... is nested" although the types are equal
  (reproduces only inside `fpcompil.pas`; a stand-alone program with the same shims compiles).
- Four units are still not valid UTF-8 (`fpide`, `wconsts`, `whtml`, `wini`: CP437 bytes).
- Known simplification: the saved video mode of the desktop file is ignored (a terminal cannot switch size).
- `CharStr` caps the result at 255 bytes (shortstring): a 255-column `─` line is cut to 85 columns.
- Typed `New(X, Init(...))` conversions picked wrong classes in a few ambiguous places; they surface as compile errors.

## 2026-10-06 (later): the IDE runs

`tools/build-fpide.sh linux64` links `fp`; it starts, draws, and the whole menu bar works.
Tests (tmux-driven, `tools/fpide-accept.sh [fp]`, CI `.github/workflows/fpide-accept.yml`):
- `fpide/tests/accept/test_accept.py`: start, menus, editor, Save as, Options>Directories, Make, Run (35 checks, green);
- `fpide/tests/accept/test_menu_sweep.py`: every menu item activated, the IDE must survive (last manual sweep: no crash).
NOT yet run after the last edits (interrupted): the new test runner and CI workflow, `test_menu_sweep.py` as a file.

Fixed on the way: virtual->override (561 methods), `Video.ScreenWidth` shadowing `Drivers.ScreenWidth`, string palettes,
stack-object search key (wresourc), `ListBoxOwnsList:=False`, dialog focus (`SelectNext(false)`), UnixInit/UnixDone in fp.pas,
tv3: `TListBox.Get/SetFocusedItem`, `;`-separated masks in `TFileList`.

Known issues / next: after a failed Alt+F9 the compiler keeps state (use F9); file dialog date shows 2033;
stale repaint after some dialogs; tv3 far2l clipboard query waits 30 s on terminals that do not answer (tests set TV_FAR2L=0);
Run does not use UnixSuspend (user screen output not shown); Edit-menu items, Tile/Cascade/Zoom/Next not yet checked in detail;
Debug (GDB) paths only smoke-tested; the 4 non-UTF-8 sources; DbgLog calls (FP_DEBUG_LOG) left in fpide.pas/fpviews.pas/fpmrun.inc.
