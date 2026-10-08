{ SPDX-License-Identifier: MIT }
{ Safe Pascal v0.1 — safe-by-default Free Pascal (the "safe" layer only).
  Specification: SPEC.md. Usage: `uses ..., Safe;` LAST in every module.
  No compiler options needed.

  What the module does (and only this):
  - TOwned/TShared/TWeak/TSlice/TArena, TDefer, FFI (TCResource), leak counter (SPEC §4–5, §13);
  - "poisons" dangerous primitives by name shadowing (SPEC §6): GetMem(...) in a module
    where Safe is last in uses will not compile. The full name (System.GetMem) is an explicit unsafe.

  UTF-8 by default and goroutines are not included here: they live in ext/, and everything together is unit BP (bp.pas).
  The layer's sources are the include files safe/*.inc: the same files are built into unit BP. }
unit Safe;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}
{$define BP_LAYER_SAFE}

interface

uses
  SysUtils;

{$I core.intf.inc}
{$I poison.intf.inc}

implementation

{$I core.impl.inc}
{$I poison.impl.inc}

end.
