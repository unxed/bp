// EXPECT: error SAFE-S14
{ S14: a parameter of a record of the module by value. The file breaks S14 only: one finding. }
unit s14_record_bad;

{$mode objfpc}{$H+}

interface

uses
  Safe;

type
  TPoint2 = record
    X, Y: Double;
  end;

function Len2(P: TPoint2): Double;

implementation

function Len2(P: TPoint2): Double;
begin
  Result := P.X * P.X + P.Y * P.Y;
end;

end.
