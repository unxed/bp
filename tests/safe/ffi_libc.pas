// UNSAFE-UNIT: libc bindings for test_ffi, an example of FFI per SPEC §13
{ The binding layer: external declarations (like a file with import "C" in Go) and a safe
  facade over them. Only String, open array, TArray, TOwned go out. }
unit ffi_libc;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Safe;

type
  TCBox = specialize TOwned<TCResource>;
  TInts = specialize TArray<Integer>;

{ The length of a UTF-8 string in bytes, through C. The string is borrowed for the call (F1). }
function CStrLen(const S: string): SizeInt;
{ A copy of the string in C memory: the owner frees it with free (F3). }
function CStrDup(const S: string): TCBox;
{ Back to Pascal: a copy (F3, like C.GoString). }
function CBoxToString(const B: TCBox): string;
{ Sorting through qsort with a callback in Pascal (F4). }
procedure CSortInts(var A: TInts);

var
  CFreeCalls: LongInt = 0; // for the test: how many times C memory was returned with free

implementation

const
  libc = {$ifdef windows}'msvcrt'{$else}'c'{$endif};

type
  TCCompare = function(A, B: System.Pointer): LongInt; cdecl;

function c_strlen(S: System.PChar): SizeUInt; cdecl; external libc name 'strlen';
function c_strdup(S: System.PChar): System.Pointer; cdecl; external libc name {$ifdef windows}'_strdup'{$else}'strdup'{$endif};
procedure c_free(P: System.Pointer); cdecl; external libc name 'free';
procedure c_qsort(Base: System.Pointer; N, Size: SizeUInt; Cmp: TCCompare); cdecl; external libc name 'qsort';

procedure CountingFree(P: System.Pointer); cdecl;
begin
  InterlockedIncrement(CFreeCalls);
  c_free(P);
end;

function CStrLen(const S: string): SizeInt;
begin
  // UNSAFE: PChar(S) lives as long as S (a const parameter); C does not keep it (F1)
  Result := c_strlen(System.PChar(S));
end;

function CStrDup(const S: string): TCBox;
begin
  // UNSAFE: strdup returns malloc memory; it goes at once to an owner with the matching free (F3)
  Result := TCBox.Own(TCResource.Create(c_strdup(System.PChar(S)), @CountingFree));
end;

function CBoxToString(const B: TCBox): string;
begin
  // UNSAFE: Ptr is a zero-terminated C string; the assignment copies it (F3)
  Result := System.PChar(B.Get.Ptr);
end;

function CompareInts(A, B: System.Pointer): LongInt; cdecl;
begin
  // F4: an exception must not cross C frames; there are none here (only reading and comparing)
  // UNSAFE: qsort passes pointers to the elements of an array that lives for the call
  if PInteger(A)^ < PInteger(B)^ then Result := -1
  else if PInteger(A)^ > PInteger(B)^ then Result := 1
  else Result := 0;
end;

procedure CSortInts(var A: TInts);
begin
  if Length(A) > 1 then
    // UNSAFE: @A[0] and Length(A) describe the same array (F1, F2)
    c_qsort(@A[0], Length(A), SizeOf(Integer), @CompareInts);
end;

end.
