// EXPECT: error SAFE-S13
{ S13: the variant field R of skCircle is read outside any case over S.Kind. The file breaks S13 only: one finding. }
unit s13_read_bad;

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
  Result := S.R;
  case S.Kind of
    skCircle: Result := Pi * S.R * S.R;
    skRect: Result := S.W * S.H;
  end;
end;

end.
