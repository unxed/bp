// EXPECT: error SAFE-S14
{ S14: a String parameter by value, in the interface declaration and in the body of one routine. The file breaks S14
  only: one finding. }
unit s14_bad;

{$mode objfpc}{$H+}

interface

uses
  Safe;

function Greet(Name: String): String;

implementation

function Greet(Name: String): String;
begin
  Result := 'Hello, ' + Name;
end;

end.
