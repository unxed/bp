// EXPECT: error SAFE-S24
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ A helper method is a method: an unchecked downcast in a class helper is S24 (the typed mode). }
unit helper_cast_bad;

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

  TShapeHelper = class helper for TShape
    function EdgeOf: Integer;
  end;

implementation

function TShapeHelper.EdgeOf: Integer;
begin
  Result := TSquare(Self).Edge;
end;

end.
