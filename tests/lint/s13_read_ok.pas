// EXPECT: clean
{ S13: a variant field is written outside a case over its tag (that builds the value) and read only in its branch. }
unit s13_read_ok;

{$mode objfpc}{$H+}

interface

uses
  Safe;

type
  TShapeKind = (skCircle, skRect);
  TShape = record
    Name: String;
    case Kind: TShapeKind of
      skCircle: (R: Double);
      skRect: (W, H: Double);
  end;

function Area(const S: TShape): Double;

implementation

function Area(const S: TShape): Double;
var
  C: TShape;
begin
  C := S;
  C.Kind := skCircle;
  C.R := 1;
  Result := 0;
  case S.Kind of
    skCircle: Result := Pi * S.R * S.R;
    skRect: Result := S.W * S.H;
  end;
end;

end.
