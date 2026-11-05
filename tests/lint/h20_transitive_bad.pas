// EXPECT: error SAFE-S17
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ H20 (unxed/bp#207) through a second nested routine: Print calls Reset, which writes the local Names of the parent
  while the const parameter A of Print is bound to it. }
unit h20_transitive_bad;

{$mode objfpc}{$H+}

interface

uses
  BP;

function Outer: SizeInt;

implementation

type
  TNames = array of String;

function Outer: SizeInt;
var
  Names: TNames;

  procedure Reset;
  begin
    SetLength(Names, 0);
  end;

  function Print(const A: TNames): SizeInt;
  begin
    Reset;
    Result := Length(A);
  end;

begin
  SetLength(Names, 2);
  Result := Print(Names);
end;

end.
