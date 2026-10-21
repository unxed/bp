{ SPDX-License-Identifier: MIT }
{ The rules of bpvet (safe/SPEC.md §6). A rule is a procedure over one parsed module that adds findings to the
  report; VetRunRules calls every rule. A new rule: a procedure VetCheckSxx here, a call in VetRunRules, and
  a pair of lint tests tests/lint/sxx_ok.pas and sxx_bad.pas (tests/lint.sh). }
unit BpvetRules;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, PasTree, BpvetCore, Safe;

procedure VetRunRules(const Src: TVetSource; const Module: TPasModule; var Report: TVetReport);

{ S7: Safe/BP is the last unit in scope of the module, so that its names shadow the poisoned routines (register H9).
    Error    a unit follows Safe/BP in the same uses clause;
    Warning  the implementation uses come after Safe/BP of the interface (they shadow it in the implementation);
    Warning  units follow BP that is first in the uses of a program (BP goes first there for the thread manager,
             SPEC §14, and the units after it shadow it in the program file). }
procedure VetCheckS7(const Src: TVetSource; const Module: TPasModule; var Report: TVetReport);

{ S12: FFI lives in binding modules (safe/SPEC.md §13). A binding module is marked by a comment
  // UNSAFE-UNIT: <why> before its header; its public API is a safe facade.
    Error    an external routine or variable in a module without // UNSAFE-UNIT:;
    Error    a routine of the interface of a binding module (an UNSAFE-UNIT unit with external declarations)
             takes or returns a pointer (^T, Pointer, PChar and the like, or a pointer type of this module). }
procedure VetCheckS12(const Src: TVetSource; const Module: TPasModule; var Report: TVetReport);

{ S8: unsafe code is marked (safe/SPEC.md §7). A module marked // UNSAFE-UNIT: is not checked.
    Error    a module uses neither Safe nor BP and is not marked // UNSAFE-UNIT:;
    Error    a full name of a poisoned routine or type (System.GetMem, System.Move, SysUtils.FreeAndNil,
             System.Pointer and the rest of safe/poison.intf.inc) without a // UNSAFE: <why> comment on the line
             above or at the end of the line. Comments and string literals are skipped. }
procedure VetCheckS8(const Src: TVetSource; const Module: TPasModule; var Report: TVetReport);

implementation

type
  TUnitRefs = array of TPasUsesUnit;

function IsPoisonUnit(const Name: String): Boolean;
begin
  Result := SameText(Name, 'Safe') or SameText(Name, 'BP');
end;

{ The units the source lists, in order. The parser also puts the implicit System into the clause: it has no name
  expression. }
function Listed(const Clause: TPasUsesClause): TUnitRefs;
var
  I, N: Integer;
begin
  Result := nil;
  SetLength(Result, Length(Clause));
  N := 0;
  for I := 0 to High(Clause) do
    if Clause[I].Expr <> nil then
    begin
      Result[N] := Clause[I];
      Inc(N);
    end;
  SetLength(Result, N);
end;

function PoisonIndex(const Units: TUnitRefs): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to High(Units) do
    if IsPoisonUnit(Units[I].Name) then
      Exit(I);
end;

function NamesFrom(const Units: TUnitRefs; const First: Integer): String;
var
  I: Integer;
begin
  Result := '';
  for I := First to High(Units) do
  begin
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + Units[I].Name;
  end;
end;

{ A finding at the name of the unit U. The position of an element is the file and the line the parser saw it in;
  the column is that of the name in the line (fcl-passrc keeps only the line). }
procedure AddAt(const Src: TVetSource; const U: TPasUsesUnit; const Severity: TVetSeverity; const Rule, Msg: String;
  var Report: TVetReport);
begin
  if (U.SourceFilename = '') or SameText(ExtractFileName(U.SourceFilename), ExtractFileName(Src.FileName)) then
    VetAdd(Report, Src.FileName, U.SourceLinenumber,
      VetWordColumn(VetLine(Src, U.SourceLinenumber), U.Name), Severity, Rule, Msg)
  else
    VetAdd(Report, U.SourceFilename, U.SourceLinenumber, 1, Severity, Rule, Msg);
end;

procedure CheckClause(const Src: TVetSource; const Clause: TPasUsesClause; const InProgram: Boolean;
  var Report: TVetReport);
var
  Units: TUnitRefs;
  P: Integer;
  Name, After: String;
begin
  Units := Listed(Clause);
  P := PoisonIndex(Units);
  if (P < 0) or (P = High(Units)) then
    Exit;
  Name := Units[P].Name;
  After := NamesFrom(Units, P + 1);
  if InProgram and (P = 0) and SameText(Name, 'BP') then
    AddAt(Src, Units[P], vsWarning, 'S7',
      'the units after BP in the uses of the program (' + After + ') shadow it in this file, '
      + 'so SysUtils.FreeAndNil compiles here; BP stays first for the thread manager (safe/SPEC.md, section 14): '
      + 'keep the program file thin and put the code into units whose uses end with BP', Report)
  else
    AddAt(Src, Units[P], vsError, 'S7',
      Name + ' is not last in uses: ' + After + ' come after it and shadow the poisoned routines '
      + '(SysUtils.FreeAndNil compiles); move ' + Name + ' to the end of this uses clause', Report);
end;

procedure VetCheckS7(const Src: TVetSource; const Module: TPasModule; var Report: TVetReport);
var
  Intf, Impl: TUnitRefs;
  P: Integer;
  Name: String;
begin
  if Module is TPasProgram then
  begin
    if TPasProgram(Module).ProgramSection <> nil then
      CheckClause(Src, TPasProgram(Module).ProgramSection.UsesClause, True, Report);
    Exit;
  end;
  if Module is TPasLibrary then
  begin
    if TPasLibrary(Module).LibrarySection <> nil then
      CheckClause(Src, TPasLibrary(Module).LibrarySection.UsesClause, False, Report);
    Exit;
  end;
  if Module.InterfaceSection <> nil then
    CheckClause(Src, Module.InterfaceSection.UsesClause, False, Report);
  if Module.ImplementationSection <> nil then
    CheckClause(Src, Module.ImplementationSection.UsesClause, False, Report);
  if (Module.InterfaceSection = nil) or (Module.ImplementationSection = nil) then
    Exit;
  Intf := Listed(Module.InterfaceSection.UsesClause);
  Impl := Listed(Module.ImplementationSection.UsesClause);
  P := PoisonIndex(Intf);
  if (P < 0) or (Length(Impl) = 0) then
    Exit;
  Name := Intf[P].Name;
  AddAt(Src, Impl[0], vsWarning, 'S7',
    'the implementation uses (' + NamesFrom(Impl, 0) + ') come after ' + Name + ' of the interface and shadow it '
    + 'in the implementation; move these units into the interface uses before ' + Name + ', or move ' + Name
    + ' into the implementation uses if the interface does not need it', Report);
end;

{ S12 }

{ The module is marked // UNSAFE-UNIT: on a line before its header (unit, program or library). }
function IsUnsafeUnit(const Src: TVetSource): Boolean;
var
  I: Integer;
  L: String;
begin
  Result := False;
  for I := 0 to High(Src.Lines) do
  begin
    L := LowerCase(Trim(Src.Lines[I]));
    if (Pos('unit ', L) = 1) or (Pos('program ', L) = 1) or (Pos('library ', L) = 1) then
      Exit;
    if Pos('// unsafe-unit:', L) = 1 then
      Exit(True);
  end;
end;

{ A finding at the element E: its line, the column of its name in the line. }
procedure AddAtElement(const Src: TVetSource; const E: TPasElement; const Severity: TVetSeverity;
  const Rule, Msg: String; var Report: TVetReport);
begin
  if (E.SourceFilename = '') or SameText(ExtractFileName(E.SourceFilename), ExtractFileName(Src.FileName)) then
    VetAdd(Report, Src.FileName, E.SourceLinenumber,
      VetWordColumn(VetLine(Src, E.SourceLinenumber), E.Name), Severity, Rule, Msg)
  else
    VetAdd(Report, E.SourceFilename, E.SourceLinenumber, 1, Severity, Rule, Msg);
end;

function IsExternal(const E: TPasElement): Boolean;
begin
  if E is TPasProcedure then
    Result := pmExternal in TPasProcedure(E).Modifiers
  else if E is TPasVariable then
    Result := vmExternal in TPasVariable(E).VarModifiers
  else
    Result := False;
end;

{ Declarations: a borrow of the list of a section of the module. }
procedure CollectExternals(const Decls: TPasDeclarations; var Found: array of TPasElement; var N: Integer);
var
  I: Integer;
  E: TPasElement;
begin
  if Decls = nil then
    Exit;
  for I := 0 to Decls.Declarations.Count - 1 do
  begin
    E := TPasElement(Decls.Declarations[I]);
    if IsExternal(E) and (N <= High(Found)) then
    begin
      Found[N] := E;
      Inc(N);
    end;
  end;
end;

{ Names of the pointer types (type PFoo = ^TFoo) declared in the section, lower case, ';'-separated. }
function PointerTypeNames(const Decls: TPasDeclarations): String;
var
  I: Integer;
  E: TPasElement;
begin
  Result := '';
  if Decls = nil then
    Exit;
  for I := 0 to Decls.Declarations.Count - 1 do
  begin
    E := TPasElement(Decls.Declarations[I]);
    if E is TPasPointerType then
      Result := Result + ';' + LowerCase(E.Name);
  end;
  Result := Result + ';';
end;

const
  { the pointer types of the System unit that a binding most often takes from a C header }
  SystemPointers = ';pointer;pchar;pansichar;pwidechar;punicodechar;pbyte;pword;pinteger;plongint;pcardinal;'
    + 'pdword;pint64;pqword;psingle;pdouble;psizeint;psizeuint;pptrint;pptruint;ppchar;ppansichar;ppointer;'
    + 'psmallint;pshortint;plongword;pboolean;';

function IsPointerType(const T: TPasType; const ModulePointers: String): Boolean;
begin
  if T = nil then
    Exit(False);
  if T is TPasPointerType then
    Exit(True);
  Result := (T.Name <> '') and ((Pos(';' + LowerCase(T.Name) + ';', SystemPointers) > 0)
    or (Pos(';' + LowerCase(T.Name) + ';', ModulePointers) > 0));
end;

{ The pointer in the signature of P (a parameter or the result), '' when there is none. }
function PointerInSignature(const P: TPasProcedure; const ModulePointers: String): String;
var
  I: Integer;
  A: TPasArgument;
  R: TPasType;
begin
  Result := '';
  if P.ProcType = nil then
    Exit;
  for I := 0 to P.ProcType.Args.Count - 1 do
  begin
    A := TPasArgument(P.ProcType.Args[I]);
    if IsPointerType(A.ArgType, ModulePointers) then
      Exit('parameter ' + A.Name);
  end;
  if (P.ProcType is TPasFunctionType) and (TPasFunctionType(P.ProcType).ResultEl <> nil) then
  begin
    R := TPasFunctionType(P.ProcType).ResultEl.ResultType;
    if IsPointerType(R, ModulePointers) then
      Exit('result');
  end;
end;

procedure VetCheckS12(const Src: TVetSource; const Module: TPasModule; var Report: TVetReport);
var
  Found: array[0..255] of TPasElement;
  N, I: Integer;
  Intf: TPasDeclarations;
  Pointers, Where: String;
  E: TPasElement;
begin
  N := 0;
  if Module is TPasProgram then
    CollectExternals(TPasProgram(Module).ProgramSection, Found, N)
  else if Module is TPasLibrary then
    CollectExternals(TPasLibrary(Module).LibrarySection, Found, N)
  else
  begin
    CollectExternals(Module.InterfaceSection, Found, N);
    CollectExternals(Module.ImplementationSection, Found, N);
  end;
  if N = 0 then
    Exit;
  if not IsUnsafeUnit(Src) then
  begin
    for I := 0 to N - 1 do
      AddAtElement(Src, Found[I], vsError, 'S12',
        'external ' + Found[I].Name + ' outside a binding module: move the external declarations into a unit marked '
        + '// UNSAFE-UNIT: <why> (a *_c.pas file or the unsafe/ folder) and call them through its safe facade '
        + '(safe/SPEC.md, section 13)', Report);
    Exit;
  end;
  if (Module is TPasProgram) or (Module is TPasLibrary) or (Module.InterfaceSection = nil) then
    Exit;
  Intf := Module.InterfaceSection;
  Pointers := PointerTypeNames(Intf) + PointerTypeNames(Module.ImplementationSection);
  for I := 0 to Intf.Declarations.Count - 1 do
  begin
    E := TPasElement(Intf.Declarations[I]);
    if not (E is TPasProcedure) then
      Continue;
    Where := PointerInSignature(TPasProcedure(E), Pointers);
    if Where <> '' then
      AddAtElement(Src, E, vsError, 'S12',
        'the public API of a binding module takes or returns a pointer (' + E.Name + ', ' + Where + '): '
        + 'keep the external declaration with pointers in the implementation and export a facade with String, '
        + 'TBytes, records or an owner (TCResource) instead (safe/SPEC.md, section 13)', Report);
  end;
end;

{ S8 }

const
  { the names that safe/poison.intf.inc hides; a full name (System.X, SysUtils.X) bypasses the hiding }
  PoisonNames = ';getmem;allocmem;reallocmem;freemem;new;dispose;move;fillchar;freeandnil;pointer;pchar;pansichar;'
    + 'pwidechar;pbyte;';

function UsesPoison(const Clause: TPasUsesClause): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to High(Clause) do
    if (Clause[I].Expr <> nil) and IsPoisonUnit(Clause[I].Name) then
      Exit(True);
end;

function ModuleUsesPoison(const Module: TPasModule): Boolean;
begin
  if Module is TPasProgram then
    Exit((TPasProgram(Module).ProgramSection <> nil) and UsesPoison(TPasProgram(Module).ProgramSection.UsesClause));
  if Module is TPasLibrary then
    Exit((TPasLibrary(Module).LibrarySection <> nil) and UsesPoison(TPasLibrary(Module).LibrarySection.UsesClause));
  Result := ((Module.InterfaceSection <> nil) and UsesPoison(Module.InterfaceSection.UsesClause))
    or ((Module.ImplementationSection <> nil) and UsesPoison(Module.ImplementationSection.UsesClause));
end;

function IsMarkComment(const S: String): Boolean;
begin
  Result := Pos('// UNSAFE:', TrimLeft(S)) = 1;
end;

{ The code of a line without comments and string literals (replaced by spaces, so the columns stay), and the
  trailing // comment. InBrace / InParen: a {...} or (*...*) comment goes on from the line before. }
function CodeOf(const Line: String; var InBrace, InParen: Boolean; out Tail: String): String;
var
  I, N: Integer;
  InStr: Boolean;
begin
  Result := Line;
  Tail := '';
  N := Length(Line);
  InStr := False;
  I := 1;
  while I <= N do
  begin
    if InBrace then
    begin
      if Line[I] = '}' then
        InBrace := False;
      Result[I] := ' ';
    end
    else if InParen then
    begin
      if (Line[I] = '*') and (I < N) and (Line[I + 1] = ')') then
      begin
        InParen := False;
        Result[I + 1] := ' ';
        Result[I] := ' ';
        Inc(I);
      end
      else
        Result[I] := ' ';
    end
    else if InStr then
    begin
      if Line[I] = '''' then
        InStr := False;
      Result[I] := ' ';
    end
    else if Line[I] = '''' then
    begin
      InStr := True;
      Result[I] := ' ';
    end
    else if Line[I] = '{' then
    begin
      InBrace := True;
      Result[I] := ' ';
    end
    else if (Line[I] = '(') and (I < N) and (Line[I + 1] = '*') then
    begin
      InParen := True;
      Result[I] := ' ';
      Result[I + 1] := ' ';
      Inc(I);
    end
    else if (Line[I] = '/') and (I < N) and (Line[I + 1] = '/') then
    begin
      Tail := Copy(Line, I, N - I + 1);
      Result := Copy(Result, 1, I - 1);
      Exit;
    end;
    Inc(I);
  end;
end;

function IsWordChar(const C: Char): Boolean;
begin
  Result := C in ['A'..'Z', 'a'..'z', '0'..'9', '_'];
end;

{ The first full name System.X / SysUtils.X of a poisoned X in Code: its column, or 0; Name gets it. }
function PoisonFullName(const Code: String; out Name: String): Integer;
var
  I, J, K: Integer;
  Qual, Ident: String;
begin
  Name := '';
  I := 1;
  while I <= Length(Code) do
  begin
    if IsWordChar(Code[I]) and ((I = 1) or not IsWordChar(Code[I - 1])) and not (Code[I] in ['0'..'9']) then
    begin
      J := I;
      while (J <= Length(Code)) and IsWordChar(Code[J]) do
        Inc(J);
      Qual := LowerCase(Copy(Code, I, J - I));
      K := J;
      while (K <= Length(Code)) and (Code[K] = ' ') do
        Inc(K);
      if ((Qual = 'system') or (Qual = 'sysutils')) and (K <= Length(Code)) and (Code[K] = '.') then
      begin
        Inc(K);
        while (K <= Length(Code)) and (Code[K] = ' ') do
          Inc(K);
        J := K;
        while (J <= Length(Code)) and IsWordChar(Code[J]) do
          Inc(J);
        Ident := Copy(Code, K, J - K);
        if (Ident <> '') and (Pos(';' + LowerCase(Ident) + ';', PoisonNames) > 0) then
        begin
          Name := Copy(Code, I, K - I) + Ident;
          Exit(I);
        end;
      end;
      I := J;
    end
    else
      Inc(I);
  end;
  Result := 0;
end;

{ The line above Row (1-based), skipping blank lines, is a // UNSAFE: comment. }
function MarkedAbove(const Src: TVetSource; const Row: Integer): Boolean;
var
  R: Integer;
begin
  R := Row - 1;
  while (R >= 1) and (Trim(VetLine(Src, R)) = '') do
    Dec(R);
  Result := (R >= 1) and IsMarkComment(VetLine(Src, R));
end;

procedure VetCheckS8(const Src: TVetSource; const Module: TPasModule; var Report: TVetReport);
var
  I, Col: Integer;
  InBrace, InParen: Boolean;
  Code, Tail, Name: String;
begin
  if IsUnsafeUnit(Src) then
    Exit;
  if not ModuleUsesPoison(Module) then
    AddAtElement(Src, Module, vsError, 'S8',
      'the module uses neither Safe nor BP and is not marked unsafe: end its uses with Safe (or BP), '
      + 'or put // UNSAFE-UNIT: <why> before its header if the whole module is unsafe (safe/SPEC.md, section 7)',
      Report);
  InBrace := False;
  InParen := False;
  for I := 0 to High(Src.Lines) do
  begin
    Code := CodeOf(Src.Lines[I], InBrace, InParen, Tail);
    Col := PoisonFullName(Code, Name);
    if (Col > 0) and not IsMarkComment(Tail) and not MarkedAbove(Src, I + 1) then
      VetAdd(Report, Src.FileName, I + 1, Col, vsError, 'S8',
        'unsafe ' + Name + ' without a mark: put a comment // UNSAFE: <why this is safe> on the line above, '
        + 'or use an owner instead (TOwned, TArray, assignment; safe/SPEC.md, section 7)');
  end;
end;

procedure VetRunRules(const Src: TVetSource; const Module: TPasModule; var Report: TVetReport);
begin
  VetCheckS7(Src, Module, Report);
  VetCheckS8(Src, Module, Report);
  VetCheckS12(Src, Module, Report);
end;

end.
