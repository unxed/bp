// EXPECT: clean
{ S14: passing a var parameter to a routine may mutate it; this conservative analysis does not warn. }
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
