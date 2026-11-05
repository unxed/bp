// EXPECT: error SAFE-S24
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S24: TSquare(S) reads a TShape that is not a square as one (H17); write S as TSquare. }
unit s24_bad;

{$mode objfpc}{$H+}

interface

uses
  Safe;

type
  TShape = class
  public
    Sides: Integer;
  end;

  TSquare = class(TShape)
  public
    Edge: Integer;
  end;

function EdgeOf(S: TShape): Integer;

implementation

function EdgeOf(S: TShape): Integer;
begin
  Result := TSquare(S).Edge;
end;

end.
