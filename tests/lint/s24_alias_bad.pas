// EXPECT: error SAFE-S24
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S24: a type alias of a class, a cast written inside a call and in a method of a class. }
unit s24_alias_bad;

{$mode objfpc}{$H+}

interface

uses
  Safe;

type
  TShape = class
  public
    function Probe(S: TShape): Integer;
  end;

  TSquare = class(TShape)
  public
    Edge: Integer;
  end;

  TBox = TSquare;

implementation

function Twice(const N: Integer): Integer;
begin
  Result := 2 * N;
end;

function TShape.Probe(S: TShape): Integer;
begin
  Result := Twice(TBox(S).Edge);
end;

end.
