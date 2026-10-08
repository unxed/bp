{ SPDX-License-Identifier: MIT }
{ Better Pascal: one unit that gives everything.
    1) safe (safe/): ownership, slices, arena, defer, FFI, poisoned dangerous primitives;
    2) ext  (ext/):  UTF-8 by default, goroutines/channels/Select, the thread manager.
  Usage: `uses BP, ...;` FIRST in the program, `uses ..., BP;` LAST in every other unit. No compiler options.
  The safe layer alone, without the extensions: unit Safe (safe/safe.pas).

  Linux by default is the portable mode without libc (like Go): strings use fpwidestring
  (Unicode in Pascal), threads use BPThreads on system calls; one binary
  runs on Debian and on Alpine alike. -dSAFE_LIBC is the mode with libc (cwstring, cthreads),
  needed only for FFI with C libraries (like cgo). }
unit BP;

{$mode objfpc}{$H+}
{$if defined(linux) and not defined(SAFE_LIBC)}{$define SAFE_PORTABLE}{$endif}
{$modeswitch advancedrecords}

interface

uses
  BPThreads, // the thread manager (goroutines); first in uses, so it is installed before the other units
  {$ifdef SAFE_PORTABLE}
  unicodeducet, fpwidestring, // Unicode without libc; unicodeducet first: fpwidestring needs its collation table at startup
  {$else}
  {$if defined(unix) and not defined(SAFE_NO_CWSTRING)}cwstring,{$endif} // UTF-8 <-> UTF-16 and letter case through libc
  {$endif}
  {$ifdef windows}Windows,{$endif}
  SysUtils;

{$I safe/core.intf.inc}
{$I ext/go.intf.inc}
{$I ext/utf8.intf.inc}
{$I safe/poison.intf.inc}

implementation

{$I safe/core.impl.inc}
{$I ext/go.impl.inc}
{$I ext/utf8.impl.inc}
{$I safe/poison.impl.inc}

initialization
{$I ext/utf8.init.inc}
end.
