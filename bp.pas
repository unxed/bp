{ SPDX-License-Identifier: MIT }
{ Better Pascal: one unit that gives everything.
    1) safe (safe/): ownership, slices, arena, regions, defer, FFI, poisoned dangerous primitives;
    2) ext  (ext/):  UTF-8 by default, goroutines/channels/Select, the thread manager.
  Usage: `uses ..., BP;` LAST in every module, the program included; build with tools/bp build or fpc -FaBPThreads,
  which installs the thread manager before any other unit (SPEC §24.3). For debug builds, compile
  modules using BP with -Cr -Co (safe/SPEC.md §6); release builds may omit these checks.
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
  fpwidestring, // Unicode without libc; the collation of Unicode only on request: `unicodeducet` before BP in the uses
  {$else}
  {$if defined(unix) and not defined(SAFE_NO_CWSTRING)}cwstring,{$endif} // UTF-8 <-> UTF-16 and letter case through libc
  {$endif}
  {$ifdef windows}Windows,{$endif}
  {$if defined(SAFE_DEBUG) and defined(unix)}BaseUnix,{$endif} // R12: the pages of a released region lose all access
  SysUtils;

{$I safe/core.intf.inc}
{$I safe/region.intf.inc}
{$I safe/map.intf.inc}
{$I ext/go.intf.inc}
{$I ext/utf8.intf.inc}
{$I safe/poison.intf.inc}

implementation

{$I safe/atomic.inc}

{$I safe/core.impl.inc}
{$I safe/region.impl.inc}
{$I safe/map.impl.inc}
{$I ext/go.impl.inc}
{$I ext/utf8.impl.inc}
{$I safe/poison.impl.inc}

initialization
{$I ext/utf8.init.inc}
end.
