# Migration status: Free Vision → tv3, objects → classes

Updated: 2026-10-06 (fp runs, edits UTF-8, compiles and debugs through external fpc/gdb; acceptance tests in fpide/tests/accept)

**Owner rule:** complete transfer without breaking functionality. See `.cursor/rules/fpide-full-port.mdc`.

## Current state

- **Build:** `tools/fpide-setup-build.sh [test]` — one command on Ubuntu (apt packages, `tv/` submodule, ~15 s build, tests). The compiler and
  the debugger are the system `fpc` and `gdb` (external programs); the FPC compiler sources are not needed (a handful of compiler units
  the IDE itself uses are vendored in `compat/fpc/`). `FPIDE_EMBED=1` keeps the original embedded-compiler build.
- **Editor:** UTF-8 end to end (open/edit/save). A column is a character (valid UTF-8 sequence or a stray byte), wide characters take two
  cells, drawing goes through tv3 cells; `TvUStr` (tv3) has the helpers. Single byte mode only for go32v2 (`TvUtf8.Utf8Enabled`).
- **Sources** are UTF-8; the box/frame characters are Unicode.
- **Debugger:** gdb through GDB/MI (`gdbmi*.pas`); Run with a breakpoint stops on it (the program is rebuilt with `-g` for that),
  Call stack, Step/Trace, Watches, Evaluate, Continue to the exit are checked by the tests.
- **Clipboard:** one Cut/Copy/Paste in the Edit menu, as in the original IDE. Copy/Cut fill the clipboard window and the system clipboard (tv3: tools wl-copy/xsel/xclip/pbcopy/WSL, far2l, OSC 52, internal buffer, as magiblot's tvision does); Paste takes what another program put on the system clipboard since the last Copy (it also becomes the newest text of the clipboard window), else the clipboard window (which the user may have edited). Text that the terminal pastes (bracketed paste, Ctrl+Shift+V) is inserted as it is, in one undo step. Tests: `clipboard`, `syscb` (fake xsel).
- **Browser** (Search > Objects/Modules/Globals/Symbol): built from the sources with fcl-passrc (`fpsrcbrw.pas`), no compiler tables needed.
- **Debuggee terminal:** the program run by gdb gets a pty of its own (`gdbpty.pas`) that the IDE relays (output to the screen, keys to the program) — gdb's "Failed to set controlling terminal" is gone.
- **User screen** (Ctrl+F9 and the debuggee): `UnixSuspend/UnixResume` of tv3 give the real terminal and take it back.
- **Tests:** `test_accept.py` (35), `test_functions.py` (147: edit, search, window, tools, options, files, compile, unicode, debug),
  `test_menu_sweep.py` (every menu item); `tools/fpide-accept.sh` runs all three; CI `.github/workflows/fpide-accept.yml`.

## Open

- The help viewer (`whlpview`) still counts bytes; a line is at most 255 bytes (shortstring): longer lines are split on load, as in the original, between characters (a message tells so).
- `fp.ans` (desktop background, CP437 data) is read as CP437 by `wansi.pas` and shown correctly; the build copies it and the other data files (templates, tool descriptions) next to `fp`.
- The symbol browser reads declarations only (no cross references of uses: they need the compiler); unsaved edits are not seen (the files on disk are parsed).
- Wide characters in horizontally scrolled lines are approximated.

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
(all of these were fixed later the same day: see Current state).

## 2026-10-06 (night): lost `override`s

FPC's "An inherited method is hidden by ..." warnings are real bugs here: the old virtual->override fixer missed 78 methods
(`Destroy`, `Store`, `Update`, `Draw`, `DoSelectSourceLine`, ...). `DoSelectSourceLine` was never called (the base stub returned garbage,
the debugger kept resuming); many destructors were skipped. All restored; the only remaining warning is the deliberate
`Update(AMaxWidth)` overload in `fpdebug.pas`. Keep the build free of this warning.

## 2026-10-08: navigation guidelines of vtui

`wviews.pas` (the three copies of `Execute` of the menu views): `Esc` closes the drop-down and keeps the menu bar, the second `Esc` leaves it; `Left`/`Right` in the bar
open the next drop-down (`UxMenuEsc`, `UxMenuAutoOpen` of tv3, guarded by `{$IF DECLARED}` so that it builds with an older tv3). The rest of the rules is in the dialogs and
views of tv3 (radio buttons keep the cursor and the selection apart, `Ctrl+Tab` walks the windows, arrows leave buttons and fields, far2l word rules in input fields).
The table with every rule, the open gaps and the conflicts with the Borland / Free Pascal IDE habits (`F9` is Make, `Home`/`End` in lists, `Enter` on a check box) is
`tv/docs/UX-CONFORMANCE.md`. Tests: the section `ux` of `tests/accept/test_functions.py` and `tests/accept/test_esc_sweep.py` (every dialog of the menu bar closes with one `Esc`).
These need tv3 62900cc or later: the pin of `tv` in sp has to be moved to it.
