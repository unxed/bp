// EXPECT: error SAFE-S14
{ S14: a String parameter by value of a method, in the class and in the body. The file breaks S14 only: one
  finding. }
unit s14_method_bad;

{$mode objfpc}{$H+}

interface

uses
  Safe;

type
  TGreeter = class
  public
    function Greet(Name: String): String;
  end;

implementation

function TGreeter.Greet(Name: String): String;
begin
  Result := 'Hello, ' + Name;
end;

end.
