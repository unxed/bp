// EXPECT: clean
{ S13: every variant field is read only in the branch of case S.Kind of with its tag. }
unit s13_variant_ok;

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
begin
  Result := 0;
  case S.Kind of
    skCircle: Result := Pi * S.R * S.R;
    skRect: Result := S.W * S.H;
  end;
end;

end.
