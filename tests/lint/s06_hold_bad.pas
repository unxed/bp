// EXPECT: error SAFE-S6
{ S6: the second argument of a routine other than Hold is not an owner. }
unit s06_hold_bad;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Safe;

procedure Run;

implementation

procedure Keep(out V: TStringList; const L: TStringList);
begin
  V := L;
end;

procedure Run;
var
  Lines: TStringList;
begin
  Keep(Lines, TStringList.Create);
  Lines.Add('x');
end;

end.
