{ SPDX-License-Identifier: MIT }
{ Safe Pascal, poisoned primitives (interface). Included LAST in the interface. }
type
  { ---------- Poisoned primitives (SPEC §6) ----------
    A stub type with the same name hides the procedure from System/SysUtils:
    the call turns into an invalid typecast (compile error),
    and the deprecated message explains what to write instead. }
  TSafeForbidden = record end;

  GetMem     = TSafeForbidden deprecated 'SAFE-S1: raw allocation. Use TOwned/TShared/TArena or TArray<T>; in unsafe code write System.GetMem with // UNSAFE: comment';
  AllocMem   = TSafeForbidden deprecated 'SAFE-S1: raw allocation. Use TOwned/TShared/TArena or TArray<T>; in unsafe code write System.AllocMem';
  ReallocMem = TSafeForbidden deprecated 'SAFE-S1: raw allocation. Use TArray<T> + SetLength; in unsafe code write System.ReallocMem';
  FreeMem    = TSafeForbidden deprecated 'SAFE-S1: raw deallocation. Owners free memory; in unsafe code write System.FreeMem';
  New        = TSafeForbidden deprecated 'SAFE-S1: raw allocation. Use a record value or TOwned; in unsafe code write System.New';
  Dispose    = TSafeForbidden deprecated 'SAFE-S1: raw deallocation. Owners free memory; in unsafe code write System.Dispose';
  Move       = TSafeForbidden deprecated 'SAFE-S2: raw memory copy. Use assignment or Copy(); in unsafe code write System.Move';
  FillChar   = TSafeForbidden deprecated 'SAFE-S2: raw memory fill. Use X := Default(TType); in unsafe code write System.FillChar';
  FreeAndNil = TSafeForbidden deprecated 'SAFE-S3: manual destruction. Use TOwned.Reset; in unsafe code write SysUtils.FreeAndNil';

  { The types are left working (migration), but every use is a warning. }
  Pointer   = System.Pointer   deprecated 'SAFE-S4: raw pointer. Use TOwned/TSlice/open array; in unsafe code write System.Pointer';
  PByte     = System.PByte     deprecated 'SAFE-S4: raw pointer. Use TSlice<Byte> or array of Byte; in unsafe code write System.PByte';
  PChar     = System.PChar     deprecated 'SAFE-S4: raw pointer. Use String; at OS boundary write System.PChar in unsafe code';
  PAnsiChar = System.PAnsiChar deprecated 'SAFE-S4: raw pointer. Use String; at OS boundary write System.PAnsiChar in unsafe code';
  PWideChar = System.PWideChar deprecated 'SAFE-S4: raw pointer. Use String; at OS boundary write System.PWideChar in unsafe code';

  { Free is a TObject method; it is hidden by a helper with the same name but with a mandatory
    parameter that cannot be created in safe code. So Obj.Free is a compile ERROR
    without any options, and the explanation of the rule is the parameter's type name, which the
    compiler prints in the line "Found declaration: Free(const SAFE_S3_...)".
    In unsafe code use Obj.Destroy with // UNSAFE:. Limitation: another helper for TObject
    included after Safe will override this one (S7). }
  SAFE_S3_NoFree_UseTOwnedReset_or_UnsafeDestroy = record end;
  TSafeObjectHelper = class helper for TObject
  public
    procedure Free(const Forbidden: SAFE_S3_NoFree_UseTOwnedReset_or_UnsafeDestroy);
  end;
