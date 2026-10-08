# fpc-utf8: UTF-8 Everywhere for Free Pascal

The idea: `string` is always UTF-8, and everything works out of the box, with no change of the sources.
This is a separate variant for existing code that does not use `BP`; `BP` gives the same UTF-8 defaults itself.

FPC 3.x already has strings with a code page (`AnsiString(CP_UTF8)`); only the defaults are in the way:
`string` = `ShortString` in the default mode, the string encoding comes from the locale,
Unix needs `cwstring`, the Windows console is in OEM. All of this is fixed in one place:

- `utf8everywhere.pas`: a unit that hides `cwstring` inside itself and in `initialization`
  sets `DefaultSystemCodePage`, `DefaultFileSystemCodePage`, `DefaultRTLFileSystemCodePage`
  and the encoding of `Input/Output/StdErr` to `CP_UTF8` (on Windows also `SetConsoleOutputCP`).
  Plus `for Ch in CodePoints(S)` (a character is a `string` too) and `CPLength(S)`.
- `utf8.cfg`: `-Mobjfpc -Sh -FaUTF8Everywhere`. The main trick: the `-Fa` option
  makes the compiler insert the unit first into the `uses` of every program.
  The lines of `utf8.cfg` can be appended to the system `fpc.cfg` to make UTF-8 the default everywhere.

Build: `fpc @fpc-utf8/utf8.cfg -Fufpc-utf8 program.pas`.

The principle: `Length(S)` and `S[i]` are in bytes (as in Go and Rust). `Pos/Copy/Delete` on byte indexes
are correct because UTF-8 is self-synchronizing. Characters are rarely needed; `CodePoints` is there for them.

## Tests

`test_utf8.pas` (the unit is not in its `uses`; `-Fa` inserts it): lengths, `Pos/Copy`, conversion to
`UnicodeString` and back, `AnsiUpperCase/AnsiLowerCase` of Cyrillic, `Format`, the walk by characters
(including an emoji and a truncated character), a file with a UTF-8 name and UTF-8 contents, console output.
Exit code 0 means all checks passed. Run: `tests/run.sh fpc-utf8` (part of `tests/run.sh all`); CI job `fpc-utf8`.

## Limitations

- Letter case (`AnsiUpperCase`) on Unix goes through `towupper` of libc and depends on the locale:
  with `LANG=C` Cyrillic is not upper-cased. The test runs under `C.UTF-8`. `BP` has no such limitation on Linux
  (it uses `fpwidestring` without libc).
- Windows is not checked in CI. `ParamStr` on Windows in FPC 3.2 may return strings
  in the ANSI code page.
- `-Fa` applies to programs only (not to units and libraries). For a program this is enough:
  the `initialization` of the unit runs before the main code.
- No `-FcUTF8` in `utf8.cfg`: with it string literals become `UnicodeString` (code page 1200),
  and `Pos('ве', S)` returns 0. Without it literals are stored as bytes with the `CP_ACP` encoding, which at run time
  equals `DefaultSystemCodePage` = UTF-8.
