{ The sum type example of SPEC §16 (S13): must build and run as it is. Exit code = number of failures. }
program test_sumtype;
{$mode objfpc}{$H+}
uses SysUtils, Safe;
type
  TShapeKind = (skCircle, skRect);
  TShape = record
    Name: String;
    case Kind: TShapeKind of
      skCircle: (R: Double);
      skRect:   (W, H: Double);
  end;
function Circle(const AName: String; AR: Double): TShape;
begin
  Result := Default(TShape); Result.Name := AName; Result.Kind := skCircle; Result.R := AR;
end;
function Area(const S: TShape): Double;
begin
  case S.Kind of
    skCircle: Result := Pi * S.R * S.R;
    skRect:   Result := S.W * S.H;
  end;
end;
begin
  if Abs(Area(Circle('c', 1.0)) - Pi) > 1e-9 then begin WriteLn('FAIL area'); Halt(1) end;
  WriteLn('ok   sum type: constructor + exhaustive case'); WriteLn('0 failed');
end.
