// EXPECT: clean
// ARGS: --typed --rtl @rtl@ -Fu@root@/tools/spikes/region -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S17 on a program in the region style (the measure of the early S17, safe/SPEC.md §20): a calculator. Each line is
  parsed into a tree in a region of its own, evaluated and printed; definitions live in a region of the whole run,
  and the names leave it as copies (Strings). }
program s17_calc_ok;

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, Region, Safe;

type
  TKind = (nkNum, nkVar, nkNeg, nkBin, nkCall);

  TExpr = class(TRegionObject)
    Kind: TKind;
    Value: Double;
    Name: String;
    Op: Char;
    Left, Right: TExpr;
    Args, Next: TExpr;  // the arguments of a call: a list through Next
    procedure AddArg(const A: TExpr);
    function ArgCount: Integer;
  end;

  TDef = class(TRegionObject)
    Name: String;
    Params: array of String;
    Body: TExpr;
  end;

  TDefs = specialize TGrowArray<TDef>;

  TLexer = record
    Text: String;
    Pos: Integer;
    Tok: Char;      // '0' a number, 'a' a name, #0 the end, else the character
    Num: Double;
    Id: String;
  end;

  { The state of a run: the definitions live in the region of Run. }
  TCalc = class(TRegionObject)
    Defs: TDefs;
    Lines, Errors: Integer;
    function Find(const Name: String): TDef;
    procedure Define(const Name: String; const Params: array of String; const Body: TExpr);
  end;

procedure TExpr.AddArg(const A: TExpr);
var
  P: TExpr;
begin
  if Args = nil then
    Args := A
  else
  begin
    P := Args;
    while P.Next <> nil do
      P := P.Next;
    P.Next := A;
  end;
end;

function TExpr.ArgCount: Integer;
var
  P: TExpr;
begin
  Result := 0;
  P := Args;
  while P <> nil do
  begin
    Inc(Result);
    P := P.Next;
  end;
end;

function TCalc.Find(const Name: String): TDef;
var
  I: Integer;
begin
  for I := 0 to Defs.Len - 1 do
    if Defs[I].Name = Name then
      Exit(Defs[I]);
  Result := nil;
end;

procedure TCalc.Define(const Name: String; const Params: array of String; const Body: TExpr);
var
  D: TDef;
  I: Integer;
begin
  D := Find(Name);
  if D = nil then
  begin
    D := TDef.Create;
    D.Name := Name;
    Defs.Push(D);
  end;
  SetLength(D.Params, Length(Params));
  for I := 0 to High(Params) do
    D.Params[I] := Params[I];
  D.Body := Body;
end;

procedure Next(var L: TLexer);
var
  Start: Integer;
begin
  while (L.Pos <= Length(L.Text)) and (L.Text[L.Pos] = ' ') do
    Inc(L.Pos);
  if L.Pos > Length(L.Text) then
  begin
    L.Tok := #0;
    Exit;
  end;
  Start := L.Pos;
  case L.Text[L.Pos] of
    '0'..'9', '.':
      begin
        while (L.Pos <= Length(L.Text)) and (L.Text[L.Pos] in ['0'..'9', '.']) do
          Inc(L.Pos);
        L.Num := StrToFloat(Copy(L.Text, Start, L.Pos - Start));
        L.Tok := '0';
      end;
    'a'..'z', 'A'..'Z':
      begin
        while (L.Pos <= Length(L.Text)) and (L.Text[L.Pos] in ['a'..'z', 'A'..'Z', '0'..'9']) do
          Inc(L.Pos);
        L.Id := Copy(L.Text, Start, L.Pos - Start);
        L.Tok := 'a';
      end;
  else
    L.Tok := L.Text[L.Pos];
    Inc(L.Pos);
  end;
end;

function ParseExpr(var L: TLexer): TExpr; forward;

function Num(const V: Double): TExpr;
begin
  Result := TExpr.Create;
  Result.Kind := nkNum;
  Result.Value := V;
end;

function Bin(const Op: Char; const A, B: TExpr): TExpr;
begin
  Result := TExpr.Create;
  Result.Kind := nkBin;
  Result.Op := Op;
  Result.Left := A;
  Result.Right := B;
end;

function ParsePrimary(var L: TLexer): TExpr;
begin
  case L.Tok of
    '0':
      begin
        Result := Num(L.Num);
        Next(L);
      end;
    'a':
      begin
        Result := TExpr.Create;
        Result.Name := L.Id;
        Result.Kind := nkVar;
        Next(L);
        if L.Tok = '(' then
        begin
          Result.Kind := nkCall;
          Next(L);
          while (L.Tok <> ')') and (L.Tok <> #0) do
          begin
            Result.AddArg(ParseExpr(L));
            if L.Tok = ',' then
              Next(L);
          end;
          Next(L);
        end;
      end;
    '-':
      begin
        Next(L);
        Result := TExpr.Create;
        Result.Kind := nkNeg;
        Result.Left := ParsePrimary(L);
      end;
    '(':
      begin
        Next(L);
        Result := ParseExpr(L);
        Next(L);
      end;
  else
    raise EConvertError.CreateFmt('unexpected "%s"', [L.Tok]);
  end;
end;

function ParseTerm(var L: TLexer): TExpr;
var
  Op: Char;
begin
  Result := ParsePrimary(L);
  while L.Tok in ['*', '/'] do
  begin
    Op := L.Tok;
    Next(L);
    Result := Bin(Op, Result, ParsePrimary(L));
  end;
end;

function ParseExpr(var L: TLexer): TExpr;
var
  Op: Char;
begin
  Result := ParseTerm(L);
  while L.Tok in ['+', '-'] do
  begin
    Op := L.Tok;
    Next(L);
    Result := Bin(Op, Result, ParseTerm(L));
  end;
end;

function Eval(const C: TCalc; const E: TExpr; const Env: TStringList): Double;
var
  D: TDef;
  Inner: specialize TOwned<TStringList>;
  A: TExpr;
  I: Integer;
begin
  case E.Kind of
    nkNum:
      Result := E.Value;
    nkVar:
      Result := StrToFloat(Env.Values[E.Name]);
    nkNeg:
      Result := -Eval(C, E.Left, Env);
    nkBin:
      case E.Op of
        '+': Result := Eval(C, E.Left, Env) + Eval(C, E.Right, Env);
        '-': Result := Eval(C, E.Left, Env) - Eval(C, E.Right, Env);
        '*': Result := Eval(C, E.Left, Env) * Eval(C, E.Right, Env);
      else
        Result := Eval(C, E.Left, Env) / Eval(C, E.Right, Env);
      end;
    nkCall:
      begin
        D := C.Find(E.Name);
        if (D = nil) or (Length(D.Params) <> E.ArgCount) then
          raise EConvertError.CreateFmt('no function %s/%d', [E.Name, E.ArgCount]);
        Inner := specialize TOwned<TStringList>.Own(TStringList.Create);
        A := E.Args;
        for I := 0 to High(D.Params) do
        begin
          Inner.Get.Values[D.Params[I]] := FloatToStr(Eval(C, A, Env));
          A := A.Next;
        end;
        Result := Eval(C, D.Body, Inner.Get);
      end;
  end;
end;

{ "def f(x, y) = x * y" keeps its tree in the region of the run; any other line is evaluated in Scratch. }
procedure RunLine(const C: TCalc; const Line: String; const Env: TStringList);
var
  L: TLexer;
  Name: String;
  Params: array of String;
begin
  L := Default(TLexer);
  L.Text := Line;
  L.Pos := 1;
  Next(L);
  if (L.Tok = 'a') and (L.Id = 'def') then
  begin
    Next(L);
    Name := L.Id;
    Params := nil;
    Next(L);
    Next(L);
    while L.Tok = 'a' do
    begin
      Insert(L.Id, Params, Length(Params));
      Next(L);
      if L.Tok = ',' then
        Next(L);
    end;
    Next(L);
    Next(L);
    C.Define(Name, Params, ParseExpr(L));
  end
  else
    WriteLn(Line, ' = ', FloatToStr(Eval(C, ParseExpr(L), Env)));
  Inc(C.Lines);
end;

procedure EvalLine(const C: TCalc; const Line: String; const Env: TStringList);
var
  Scratch: TRegion;
  L: TLexer;
begin
  Scratch := TRegion.Create;
  L := Default(TLexer);
  L.Text := Line;
  L.Pos := 1;
  Next(L);
  WriteLn(Line, ' = ', FloatToStr(Eval(C, ParseExpr(L), Env)));
  Inc(C.Lines);
end;

const
  Script: array[0..4] of String = ('def sq(x) = x * x', 'def hyp(a, b) = sq(a) + sq(b)', '1 + 2 * 3',
    'hyp(3, 4)', '-(2 - 5) / 2');

{ A TRegion is a local: FPC copies a function result into a global (the spike raises on a copy of a region). }
procedure Main;
var
  Run: TRegion;
  C: TCalc;
  Env: specialize TOwned<TStringList>;
  Line: String;
begin
  Run := TRegion.Create;
  C := TCalc.Create;
  C.Defs := TDefs.Create;
  Env := specialize TOwned<TStringList>.Own(TStringList.Create);
  for Line in Script do
    try
      if Copy(Line, 1, 4) = 'def ' then
        RunLine(C, Line, Env.Get)
      else
        EvalLine(C, Line, Env.Get);
    except
      on E: EConvertError do
      begin
        WriteLn(Line, ': ', E.Message);
        Inc(C.Errors);
      end;
    end;
  WriteLn(C.Lines, ' line(s), ', C.Errors, ' error(s)');
  Run.Release;
end;

begin
  Main;
end.
