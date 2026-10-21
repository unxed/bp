// EXPECT: error SAFE-S6
{ S6: the result of TFoo.Create goes into a plain variable, nobody owns it. The file breaks S6 only: one finding. }
unit s06_bad;

{$mode objfpc}{$H+}

interface

uses
  Safe;

procedure MakeTemp;

implementation

procedure MakeTemp;
var
  O: TObject;
begin
  O := TObject.Create;
end;

end.
