// EXPECT: error SAFE-S10
{ S10: a copy of a TOwned owner; two owners of one object. The file breaks S10 only: one finding. }
unit s10_bad;

{$mode objfpc}{$H+}

interface

uses
  Classes, Safe;

type
  TListBox = specialize TOwned<TStringList>;

procedure Twice;

implementation

procedure Twice;
var
  A, B: TListBox;
begin
  A := TListBox.Own(TStringList.Create);
  B := A;
end;

end.
