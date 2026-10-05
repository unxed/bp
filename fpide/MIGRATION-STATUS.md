# Migration status: Free Vision → tv3, objects → classes

Updated: 2026-10-05 (compiler fetched, not vendored)

**Owner rule:** complete transfer without breaking functionality. See `.cursor/rules/fpide-full-port.mdc`.

## Current state

- **Compiler:** real FPC `compiler/` @ same pin as IDE (`upstream.env`). **Not in git** — `fpide/bootstrap/ensure-compiler.sh` → `build/bootstrap-fpide/staging-compiler`. CI bootstrap diffs only `fpide/src`.
- **Build flags:** match upstream IDE fpmake (GDB/MI, BrowserCol, …).
- **Preflight:** smoke OK; next IDE error is `object` vs `class` (`wutils.pas`) — class-migrate UI units.
- **Objects shim:** `MaxBytes` via `manual/objects.inc`.

## Next session

1. Class-migrate IDE units inheriting TV types (`WUtils`, …).
2. Full link with compiler+debugger; PTY acceptance vs vanilla `fp`.
