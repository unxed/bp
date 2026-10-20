// EXPECT: clean
{ S7: Safe is the last unit of the only uses clause of the unit. }
unit s07_ok;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Safe;

type
  TListBox = specialize TOwned<TStringList>;

function NewList: TListBox;

implementation

function NewList: TListBox;
begin
  Result := TListBox.Own(TStringList.Create);
end;

end.
