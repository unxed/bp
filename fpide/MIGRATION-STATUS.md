# Migration status: Free Vision → tv3, objects → classes

Updated: 2026-10-05 (real fpc-compiler wired)

**Owner rule:** complete transfer without breaking functionality. See `.cursor/rules/fpide-full-port.mdc`.

## Current state

- **Compiler:** `fpide/fpc-compiler/` = FPC `compiler/` @ `release_3_2_2` (same pin as IDE). Bootstrap stages IDE + compiler; CI diffs both.
- **Build flags:** match upstream IDE fpmake (`-dGDB -dGDBMI -dBrowserCol -dNOCATCH -dx86_64`, `-Fu` compiler/cpu/targets/systems/x86).
- **Preflight:** smoke OK; `fp.pas` now finds `FInput`. Next hard error: IDE still uses `object(TCollection)` while tv3 `TCollection` is `class` (`wutils.pas`) — **object→class migration of IDE UI units** is the critical path (not stubs).
- **Objects shim:** `manual/objects.inc` provides FV `MaxBytes` etc.

## Next session

1. Class-migrate IDE units that inherit TV types (`WUtils`, `WViews`, `WEditor`, `fpviews`, …) DN-style, keeping behaviour.
2. Keep compiling; fix boundary issues without dropping compiler/debugger.
3. Full link + PTY acceptance vs vanilla `fp`.
