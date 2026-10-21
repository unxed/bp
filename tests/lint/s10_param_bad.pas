// EXPECT: error SAFE-S10
{ S10: a TOwned parameter by value copies the owner. The file breaks S10 only: one finding. }
unit s10_param_bad;

{$mode objfpc}{$H+}

interface

uses
  Classes, Safe;

type
  TListBox = specialize TOwned<TStringList>;

function Count(Box: TListBox): Integer;

implementation

function Count(const Box: TListBox): Integer;
begin
  Result := Box.Get.Count;
end;

end.
