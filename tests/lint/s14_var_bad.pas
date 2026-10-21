// EXPECT: warn SAFE-S14
{ S14: a var parameter used only as input is a warning. }
unit s14_var_bad;

{$mode objfpc}{$H+}

interface

uses
  Safe;

procedure Show(var N: Integer);

implementation

procedure Show(var N: Integer);
begin
  WriteLn(N);
end;

end.
