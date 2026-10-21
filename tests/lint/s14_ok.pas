// EXPECT: clean
{ S14: String parameters are const, constref, var or out, or marked // UNSAFE:; a parameter of another type by value
  is not checked yet. }
unit s14_ok;

{$mode objfpc}{$H+}

interface

uses
  Safe;

type
  TGreeter = class
  public
    function Greet(const Name: String): String;
  end;

function Greet(const Name: String; Times: Integer): String;
function Same(constref A, B: AnsiString): Boolean;
procedure Append(var S: String; const Tail: UnicodeString);
procedure Fill(out S: String);
// UNSAFE: the body changes its own copy of the text on purpose
function Upper(S: String): String;

implementation

function TGreeter.Greet(const Name: String): String;
begin
  Result := 'Hello, ' + Name;
end;

function Greet(const Name: String; Times: Integer): String;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Times do
    Result := Result + Name;
end;

function Same(constref A, B: AnsiString): Boolean;
begin
  Result := A = B;
end;

procedure Append(var S: String; const Tail: UnicodeString);
begin
  S := S + String(Tail);
end;

procedure Fill(out S: String);
begin
  S := 'x';
end;

function Upper(S: String): String; // UNSAFE: the body changes its own copy of the text on purpose
begin
  S := S + '!';
  Result := S;
end;

end.
