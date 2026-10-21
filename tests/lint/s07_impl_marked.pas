// EXPECT: clean
{ S7: the implementation uses (StrUtils) come after Safe of the interface, but they are marked // UNSAFE: <why>
  (a trailing comment), so the warning is a known exception and bpvet reports nothing. }
unit s07_impl_marked;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Safe;

function Twice(const S: String): String;

implementation

uses
  StrUtils; // UNSAFE: the implementation only calls DupeString, nothing here frees objects

function Twice(const S: String): String;
begin
  Result := DupeString(S, 2);
end;

end.
