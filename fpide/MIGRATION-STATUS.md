# Migration status: Free Vision → tv3, objects → classes

Updated: 2026-10-06 (class-port autofix loop; compile reaches fpcompil.pas)

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
