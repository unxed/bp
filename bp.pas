{ SPDX-License-Identifier: MIT }
{ Better Pascal — один юнит, который сразу даёт всё:
    1) safe  (safe/):  владение, срезы, арена, defer, FFI, отравленные опасные примитивы;
    2) ext   (ext/):   UTF-8 по умолчанию, горутины/каналы/Select, менеджер потоков;
  Подключение: `uses ..., BP;` ПОСЛЕДНИМ в каждом модуле. Опции компилятора не нужны.
  Только безопасность без расширений — unit Safe (safe/safe.pas).

  Linux по умолчанию — переносимый режим без libc (как Go): строки — fpwidestring
  (Unicode на Паскале), потоки — BPThreads на системных вызовах; один бинарник
  работает и на Debian, и на Alpine. -dSAFE_LIBC — режим с libc (cwstring, cthreads),
  нужен только для FFI с C-библиотеками (аналог cgo). }
unit BP;

{$mode objfpc}{$H+}
{$if defined(linux) and not defined(SAFE_LIBC)}{$define SAFE_PORTABLE}{$endif}
{$modeswitch advancedrecords}

interface

uses
  BPThreads, // менеджер потоков (горутины); сам первый в uses, чтобы стать менеджером до остальных
  {$ifdef SAFE_PORTABLE}
  unicodeducet, fpwidestring, // Unicode без libc; unicodeducet раньше: его таблица сортировки нужна fpwidestring при старте
  {$else}
  {$if defined(unix) and not defined(SAFE_NO_CWSTRING)}cwstring,{$endif} // UTF-8 <-> UTF-16 и регистр через libc
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
