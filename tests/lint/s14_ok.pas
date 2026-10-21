// EXPECT: clean
{ S14: String, array and record parameters are const, constref, var or out, or marked // UNSAFE:; a Double, an
  Integer or an array of const by value is not checked. }
unit s14_ok;

{$mode objfpc}{$H+}

interface

uses
  Safe;

type
  TPoint2 = record
    X, Y: Double;
  end;

  TInts = array of Integer;

  TGreeter = class
  public
    function Greet(const Name: String): String;
  end;

function Greet(const Name: String; Times: Integer): String;
function Same(constref A, B: AnsiString): Boolean;
procedure Append(var S: String; const Tail: String);
procedure Fill(out S: String);
function Len2(const P: TPoint2): Double;
procedure Move2(var P: TPoint2; DX: Double);
function Sum(const Values: array of Integer; var Total: TInts): Integer;
function Count(const Fmt: String; Args: array of const): Integer;
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

procedure Append(var S: String; const Tail: String);
begin
  S := S + Tail;
end;

procedure Fill(out S: String);
begin
  S := 'x';
end;

function Len2(const P: TPoint2): Double;
begin
  Result := P.X * P.X + P.Y * P.Y;
end;

procedure Move2(var P: TPoint2; DX: Double);
begin
  P.X := P.X + DX;
end;

function Sum(const Values: array of Integer; var Total: TInts): Integer;
begin
  Result := Length(Values) + Length(Total);
end;

function Count(const Fmt: String; Args: array of const): Integer;
begin
  Result := Length(Fmt) + Length(Args);
end;

function Upper(S: String): String; // UNSAFE: the body changes its own copy of the text on purpose
begin
  S := S + '!';
  Result := S;
end;

end.
