// EXPECT: warn SAFE-S7
{ S7: the implementation uses (StrUtils) come after Safe of the interface and shadow it in the implementation. }
unit s07_impl;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Safe;

function Twice(const S: String): String;

implementation

uses
  StrUtils;

function Twice(const S: String): String;
begin
  Result := DupeString(S, 2);
end;

end.
