// EXPECT: clean
// ARGS: -Fu@lint@
{ S14: copy-heavy String, array and record parameters use const, constref, var or out, or are marked // UNSAFE:;
  other by-value parameters are const unless their body writes to them. }
unit s14_ok;

{$mode objfpc}{$H+}

interface

uses
  s14_lib,
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

function Greet(const Name: String; const Times: Integer): String;
function Same(constref A, B: AnsiString): Boolean;
procedure Append(var S: String; const Tail: String);
procedure Fill(out S: String);
function Len2(const P: TPoint2): Double;
procedure Move2(var P: TPoint2; const DX: Double);
function Sum(const Values: array of Integer; var Total: TInts): Integer;
function Count(const Fmt: String; Args: array of const): Integer;
function LibRecLen(const R: TLibRec): Integer;
function LibPackedLen(const R: TLibPacked): Integer;
function LibArrayLen(var Values: TLibInts): Integer;
function FixedLen(F: TLibFixed): Integer;
function QualifiedRecLen(const Q: s14_lib.TLibRec): Integer;
function CountDown(N: Integer): Integer;
// UNSAFE: the body changes its own copy of the text on purpose
function Upper(S: String): String;

implementation

function TGreeter.Greet(const Name: String): String;
begin
  Result := 'Hello, ' + Name;
end;

function Greet(const Name: String; const Times: Integer): String;
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

procedure Move2(var P: TPoint2; const DX: Double);
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

function LibRecLen(const R: TLibRec): Integer;
begin
  Result := R.X;
end;

function LibPackedLen(const R: TLibPacked): Integer;
begin
  Result := R.X;
end;

function LibArrayLen(var Values: TLibInts): Integer;
begin
  Result := Length(Values);
end;

function FixedLen(F: TLibFixed): Integer;
begin
  Result := Length(F);
end;

function QualifiedRecLen(const Q: s14_lib.TLibRec): Integer;
begin
  Result := Q.X;
end;

function CountDown(N: Integer): Integer;
begin
  while N > 0 do
    N := N - 1;
  Result := N;
end;

function Upper(S: String): String; // UNSAFE: the body changes its own copy of the text on purpose
begin
  S := S + '!';
  Result := S;
end;

end.
