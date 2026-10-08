{ Tests of FFI (SPEC §13): a safe facade over libc. Exit code = number of failures. }
program test_ffi;

{$mode objfpc}{$H+}

uses
  SysUtils, ffi_libc, Safe;

var
  Failed: Integer = 0;

procedure Check(Cond: Boolean; const What: string);
begin
  if Cond then
    WriteLn('ok   ', What)
  else
  begin
    WriteLn('FAIL ', What);
    Inc(Failed);
  end;
end;

procedure Owned;
var
  B: TCBox;
begin
  B := CStrDup('привет, C');
  Check(CBoxToString(B) = 'привет, C', 'ffi: string round trip through C memory');
  Check(CFreeCalls = 0, 'ffi: C memory alive while owned');
end;

var
  A: TInts;
begin
  Check(CStrLen('aё😀') = 7, 'ffi: strlen of UTF-8 string = bytes');
  Owned;
  Check(CFreeCalls = 1, 'ffi: C memory freed by its own free at scope exit');
  A := [5, 3, 9, 1];
  CSortInts(A);
  Check((A[0] = 1) and (A[1] = 3) and (A[2] = 5) and (A[3] = 9), 'ffi: qsort with Pascal callback');
  try
    SafeCheckNoLeaks;
    Check(True, 'leaks: nothing left (R5)');
  except
    on E: ESafety do Check(False, 'leaks: ' + E.Message);
  end;
  WriteLn(Failed, ' failed');
  Halt(Failed);
end.
