// EXPECT: error SAFE-S24
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S24: classes of different branches: the object is never the other class, and `as` would not compile. }
unit s24_branch_bad;

{$mode objfpc}{$H+}

interface

uses
  Safe;

type
  TShape = class
  end;

  TSquare = class(TShape)
  public
    Edge: Integer;
  end;

  TCircle = class(TShape)
  public
    Radius: Integer;
  end;

function RadiusOf(Q: TSquare): Integer;

implementation

function RadiusOf(Q: TSquare): Integer;
begin
  Result := TCircle(Q).Radius;
end;

end.
