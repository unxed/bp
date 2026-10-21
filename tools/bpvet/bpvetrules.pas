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
             SPEC §14, and the units after it shadow it in the program file).
    A warning is not reported when the uses unit it points at is marked // UNSAFE: <why> (a trailing comment on its
    line, or a comment line above it; blank lines, comment lines and the line with the word uses between them keep
    the mark): the shadowing is then a known, explained exception (safe/SPEC.md §7). An error has no mark: the unit
    can always move. }
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
             above (one comment covers a block of such lines right below it) or at the end of the line.
             Comments and string literals are skipped. }
procedure VetCheckS8(const Src: TVetSource; const Module: TPasModule; var Report: TVetReport);

{ S3: manual destruction (safe/SPEC.md §7). A module marked // UNSAFE-UNIT: is not checked.
    Error    a call Obj.Destroy without a // UNSAFE: <why> comment on the line above (one comment covers a block of
             such lines right below it) or at the end of the line. A destructor declaration or heading
             (destructor TFoo.Destroy) and inherited Destroy are not calls of it. }
procedure VetCheckS3(const Src: TVetSource; const Module: TPasModule; var Report: TVetReport);

{ S6: a new object that nobody owns (safe/SPEC.md §6). A module marked // UNSAFE-UNIT: is not checked.
    Error    a call TFoo.Create whose result does not go at once into Own(...), Share(...), Adopt(...), Go(...)
             or raise, without a // UNSAFE: <who owns it> comment on the line above or at the end of the line.
             Not calls: constructor TFoo.Create, class function TFoo.Create, inherited Create. The value types of
             Safe and BP (TArena, TChan, TGroup, TDefer, and a type of the module = specialize TChan<...>) are
             records, not objects, so their Create is not a finding. bpvet has no types: an object that goes
             into an interface reference needs the // UNSAFE: mark. }
procedure VetCheckS6(const Src: TVetSource; const Module: TPasModule; var Report: TVetReport);

{ S4: raw pointers (safe/SPEC.md §6, register H4). A module marked // UNSAFE-UNIT: is not checked.
    Error    a pointer type ^T or the address operator @ without a // UNSAFE: <why> comment on the line above (one
             comment covers a block of such lines right below it) or at the end of the line. A dereference P^ is
             not a finding (the pointer it needs is). Comments and string literals are skipped.
             @Proc and @Obj.Method, where the last name is a procedure or method declared in the module (and not
             also a variable, parameter, field, property or constant of it), are a procedural value (TDefer.Call,
             TGroup.Go, a TProcedure parameter), not a raw address, and are not findings; @ followed by ^, [ or (
             still is. The check is by name over the whole module, not by scope: @ of a routine of another unit
             stays a finding.
    Error    pointer arithmetic without such a mark: Inc(P), Dec(P, N), P + N, N + P, P - Q, where P is a variable,
             parameter or field declared in the module with a pointer type (^T, Pointer, PChar and the like, or a
             pointer type of this module). Inc(P^) and P^ + 1 change the value, not the pointer, and are not
             findings. The check is by name over the whole module, not by scope. }
procedure VetCheckS4(const Src: TVetSource; const Module: TPasModule; var Report: TVetReport);

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

{ The S7 warning at the uses unit U is marked: // UNSAFE: ends the line of U, or stands on a line above it with only
  blank lines, comment lines and the line `uses` in between. }
function S7Marked(const Src: TVetSource; const U: TPasUsesUnit): Boolean;
var
  Row, I: Integer;
  L: String;
begin
  Result := False;
  if (U.SourceFilename <> '') and not SameText(ExtractFileName(U.SourceFilename), ExtractFileName(Src.FileName)) then
    Exit;
  Row := U.SourceLinenumber;
  if Pos('// UNSAFE:', VetLine(Src, Row)) > 0 then
    Exit(True);
  for I := Row - 1 downto 1 do
  begin
    L := Trim(VetLine(Src, I));
    if Pos('// UNSAFE:', L) = 1 then
      Exit(True);
    if (L = '') or (Pos('//', L) = 1) or SameText(L, 'uses')
      or ((Pos('{', L) = 1) and (Pos('{$', L) <> 1) and (L[Length(L)] = '}')) then
      Continue;
    Exit;
  end;
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
  begin
    if not S7Marked(Src, Units[P]) then
      AddAt(Src, Units[P], vsWarning, 'S7',
      'the units after BP in the uses of the program (' + After + ') shadow it in this file, '
      + 'so SysUtils.FreeAndNil compiles here; BP stays first for the thread manager (safe/SPEC.md, section 14): '
      + 'keep the program file thin and put the code into units whose uses end with BP, or mark it '
      + '// UNSAFE: <why> if the program file does need SysUtils', Report);
  end
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
  if S7Marked(Src, Impl[0]) then
    Exit;
  Name := Intf[P].Name;
  AddAt(Src, Impl[0], vsWarning, 'S7',
    'the implementation uses (' + NamesFrom(Impl, 0) + ') come after ' + Name + ' of the interface and shadow it '
    + 'in the implementation; move these units into the interface uses before ' + Name + ', or move ' + Name
    + ' into the implementation uses if the interface does not need it, or mark it // UNSAFE: <why>', Report);
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

procedure VetCheckS8(const Src: TVetSource; const Module: TPasModule; var Report: TVetReport);
var
  I, Col: Integer;
  InBrace, InParen, Covered: Boolean;
  Code, Tail, Name: String;
begin
  if IsUnsafeUnit(Src) then
    Exit;
  if not ModuleUsesPoison(Module) then
    AddAtElement(Src, Module, vsError, 'S8',
      'the module uses neither Safe nor BP and is not marked unsafe: end its uses with Safe (or BP), '
      + 'or put // UNSAFE-UNIT: <why> before its header if the whole module is unsafe (safe/SPEC.md, section 7)',
      Report);
  { A // UNSAFE: comment covers the lines with unsafe full names right below it (blank and comment lines
    between them keep it); any other line of code ends it. }
  InBrace := False;
  InParen := False;
  Covered := False;
  for I := 0 to High(Src.Lines) do
  begin
    Code := CodeOf(Src.Lines[I], InBrace, InParen, Tail);
    Col := PoisonFullName(Code, Name);
    if Col = 0 then
    begin
      if IsMarkComment(Src.Lines[I]) then
        Covered := True
      else if Trim(Code) <> '' then
        Covered := False;
      Continue;
    end;
    if not Covered and not IsMarkComment(Tail) then
      VetAdd(Report, Src.FileName, I + 1, Col, vsError, 'S8',
        'unsafe ' + Name + ' without a mark: put a comment // UNSAFE: <why this is safe> on the line above, '
        + 'or use an owner instead (TOwned, TArray, assignment; safe/SPEC.md, section 7)');
  end;
end;

{ S3 }

{ The column of the first call .Destroy in Code (Code is a line without comments and strings), or 0. }
function DestroyCall(const Code: String): Integer;
var
  I, K: Integer;
  L: String;
begin
  Result := 0;
  L := LowerCase(Code);
  if Pos('destructor', TrimLeft(L)) = 1 then
    Exit;
  I := 1;
  while I <= Length(L) do
  begin
    if L[I] = '.' then
    begin
      K := I + 1;
      while (K <= Length(L)) and (L[K] = ' ') do
        Inc(K);
      if (Copy(L, K, 7) = 'destroy') and ((K + 7 > Length(L)) or not IsWordChar(L[K + 7])) then
        Exit(I + 1);
    end;
    Inc(I);
  end;
end;

procedure VetCheckS3(const Src: TVetSource; const Module: TPasModule; var Report: TVetReport);
var
  I, Col: Integer;
  InBrace, InParen, Covered: Boolean;
  Code, Tail: String;
begin
  if IsUnsafeUnit(Src) then
    Exit;
  InBrace := False;
  InParen := False;
  Covered := False;
  for I := 0 to High(Src.Lines) do
  begin
    Code := CodeOf(Src.Lines[I], InBrace, InParen, Tail);
    Col := DestroyCall(Code);
    if Col = 0 then
    begin
      if IsMarkComment(Src.Lines[I]) then
        Covered := True
      else if Trim(Code) <> '' then
        Covered := False;
      Continue;
    end;
    if not Covered and not IsMarkComment(Tail) then
      VetAdd(Report, Src.FileName, I + 1, Col, vsError, 'S3',
        'manual destruction .Destroy: own the object by TOwned and call Reset, or put a comment '
        + '// UNSAFE: <why nobody else refers to it> on the line above (safe/SPEC.md, section 7)');
  end;
end;

{ S6 }

const
  S6ValueTypes = ' tarena tchan tgroup tdefer ';

{ The value types of the module: the names declared as NAME = specialize TArena|TChan|TGroup|TDefer<...>,
  each as ' name '. }
function S6ModuleValueTypes(const Src: TVetSource): String;
var
  I, Eq, K: Integer;
  L, Name, Rest: String;
begin
  Result := ' ';
  for I := 0 to High(Src.Lines) do
  begin
    L := LowerCase(Src.Lines[I]);
    Eq := Pos('=', L);
    if Eq = 0 then
      Continue;
    Name := Trim(Copy(L, 1, Eq - 1));
    Rest := TrimLeft(Copy(L, Eq + 1, Length(L)));
    if Pos('specialize ', Rest) <> 1 then
      Continue;
    Rest := TrimLeft(Copy(Rest, 12, Length(Rest)));
    K := Pos('<', Rest);
    if K = 0 then
      Continue;
    if (Name <> '') and (Pos(' ' + Trim(Copy(Rest, 1, K - 1)) + ' ', S6ValueTypes) > 0) then
      Result := Result + Name + ' ';
  end;
end;

{ True when the text before Start (the class name of a Create call) hands the new object to an owner:
  ...Own( ...Share( ...Adopt( ...Go( or raise. }
function S6Owned(const L: String; const Start: Integer): Boolean;
var
  K, B: Integer;
  W: String;
begin
  K := Start - 1;
  while (K >= 1) and (L[K] = ' ') do
    Dec(K);
  if K < 1 then
    Exit(False);
  if L[K] = '(' then
  begin
    Dec(K);
    while (K >= 1) and (L[K] = ' ') do
      Dec(K);
    B := K;
    while (B >= 1) and IsWordChar(L[B]) do
      Dec(B);
    W := Copy(L, B + 1, K - B);
    Exit((W = 'own') or (W = 'share') or (W = 'adopt') or (W = 'go'));
  end;
  B := K;
  while (B >= 1) and IsWordChar(L[B]) do
    Dec(B);
  Result := Copy(L, B + 1, K - B) = 'raise';
end;

{ The column of the first call TFoo.Create in Code (a line without comments and strings) that is not handed to an
  owner, or 0. ValueTypes: the names of the value types of the module (' name '). }
function S6Call(const Code, ValueTypes: String): Integer;
var
  I, K, B: Integer;
  L, T, Name: String;
begin
  Result := 0;
  L := LowerCase(Code);
  T := TrimLeft(L);
  if (Pos('constructor ', T) = 1) or (Pos('destructor ', T) = 1) or (Pos('class ', T) = 1)
    or (Pos('function ', T) = 1) or (Pos('procedure ', T) = 1) then
    Exit;
  I := 1;
  while I <= Length(L) do
  begin
    if L[I] = '.' then
    begin
      K := I + 1;
      while (K <= Length(L)) and (L[K] = ' ') do
        Inc(K);
      if (Copy(L, K, 6) = 'create') and ((K + 6 > Length(L)) or not IsWordChar(L[K + 6])) then
      begin
        B := I - 1;
        while (B >= 1) and IsWordChar(L[B]) do
          Dec(B);
        Name := Copy(L, B + 1, I - 1 - B);
        if (Name <> '') and (Pos(' ' + Name + ' ', S6ValueTypes) = 0) and (Pos(' ' + Name + ' ', ValueTypes) = 0)
          and not S6Owned(L, B + 1) then
          Exit(B + 1);
      end;
    end;
    Inc(I);
  end;
end;

procedure VetCheckS6(const Src: TVetSource; const Module: TPasModule; var Report: TVetReport);
var
  I, Col: Integer;
  InBrace, InParen, Covered: Boolean;
  Code, Tail, ValueTypes: String;
begin
  if IsUnsafeUnit(Src) then
    Exit;
  ValueTypes := S6ModuleValueTypes(Src);
  InBrace := False;
  InParen := False;
  Covered := False;
  for I := 0 to High(Src.Lines) do
  begin
    Code := CodeOf(Src.Lines[I], InBrace, InParen, Tail);
    Col := S6Call(Code, ValueTypes);
    if Col = 0 then
    begin
      if IsMarkComment(Src.Lines[I]) then
        Covered := True
      else if Trim(Code) <> '' then
        Covered := False;
      Continue;
    end;
    if not Covered and not IsMarkComment(Tail) then
      VetAdd(Report, Src.FileName, I + 1, Col, vsError, 'S6',
        'a new object that nobody owns: pass TFoo.Create at once to TOwned.Own, TShared.Share, TArena.Adopt, '
        + 'TGroup.Go or raise, or put a comment // UNSAFE: <who owns it> on the line above (safe/SPEC.md, section 6)');
  end;
end;

{ S4 }

{ The first non-space position at or after I, or Length(Code) + 1. }
function SkipSpaces(const Code: String; I: Integer): Integer;
begin
  Result := I;
  while (Result <= Length(Code)) and (Code[Result] = ' ') do
    Inc(Result);
end;

{ Adds the last part of the (dotted: TFoo.Bar) name Name, lower case, to the ';'-separated set S. }
procedure AddName(var S: String; const Name: String);
var
  P: Integer;
  N: String;
begin
  N := LowerCase(Name);
  P := LastDelimiter('.', N);
  if P > 0 then
    N := Copy(N, P + 1, Length(N) - P);
  if (N <> '') and (Pos(';' + N + ';', S) = 0) then
    S := S + N + ';';
end;

procedure CollectNames(const E: TPasElement; var Routines, Vars: String); forward;

procedure CollectList(const L: TFPList; var Routines, Vars: String);
var
  I: Integer;
begin
  if L = nil then
    Exit;
  for I := 0 to L.Count - 1 do
    CollectNames(TPasElement(L[I]), Routines, Vars);
end;

{ The names of the routines (procedures, functions, methods, nested ones too) and of the variables (variables,
  constants, fields, properties, parameters) declared in E and below it, into two ';'-separated sets. }
procedure CollectNames(const E: TPasElement; var Routines, Vars: String);
var
  P: TPasProcedure;
begin
  if E = nil then
    Exit;
  if E is TPasOverloadedProc then
  begin
    AddName(Routines, E.Name);
    CollectList(TPasOverloadedProc(E).Overloads, Routines, Vars);
  end
  else if E is TPasProcedure then
  begin
    P := TPasProcedure(E);
    AddName(Routines, P.Name);
    if P.ProcType <> nil then
      CollectList(P.ProcType.Args, Routines, Vars);
    if P.Body <> nil then
      CollectList(P.Body.Declarations, Routines, Vars);
  end
  else if (E is TPasArgument) or (E is TPasVariable) then
    AddName(Vars, E.Name)
  else if E is TPasMembersType then
    CollectList(TPasMembersType(E).Members, Routines, Vars)
  else if E is TPasDeclarations then
    CollectList(TPasDeclarations(E).Declarations, Routines, Vars);
end;

procedure ModuleNames(const Module: TPasModule; out Routines, Vars: String);
begin
  Routines := ';';
  Vars := ';';
  if Module is TPasProgram then
    CollectNames(TPasProgram(Module).ProgramSection, Routines, Vars)
  else if Module is TPasLibrary then
    CollectNames(TPasLibrary(Module).LibrarySection, Routines, Vars)
  else
  begin
    CollectNames(Module.InterfaceSection, Routines, Vars);
    CollectNames(Module.ImplementationSection, Routines, Vars);
  end;
end;

{ The @ at position I of Code takes the address of a routine of the module: the designator after it (Name,
  Obj.Method, A.B.Name; spaces around the dots allowed) ends with a name from Routines that is not in Vars, and no
  ^, [ or ( follows it. }
function IsRoutineAddress(const Code: String; const I: Integer; const Routines, Vars: String): Boolean;
var
  J, K: Integer;
  Name: String;
begin
  Result := False;
  K := SkipSpaces(Code, I + 1);
  repeat
    if (K > Length(Code)) or not IsWordChar(Code[K]) or (Code[K] in ['0'..'9']) then
      Exit;
    J := K;
    while (J <= Length(Code)) and IsWordChar(Code[J]) do
      Inc(J);
    Name := ';' + LowerCase(Copy(Code, K, J - K)) + ';';
    K := SkipSpaces(Code, J);
    if (K <= Length(Code)) and (Code[K] = '.') then
      K := SkipSpaces(Code, K + 1)
    else
      Break;
  until False;
  if (K <= Length(Code)) and (Code[K] in ['^', '[', '(']) then
    Exit;
  Result := (Pos(Name, Routines) > 0) and (Pos(Name, Vars) = 0);
end;

{ The column of the first pointer type ^T or address operator @ in Code (a line without comments and strings), or 0;
  What gets '^T' or '@'. A ^ right after a name, ) or ] is a dereference (P^, F(X)^, A[I]^), except after the
  keyword of (array of ^T). An @ of a routine of the module (IsRoutineAddress) is a procedural value, not a finding. }
function PointerOp(const Code, Routines, Vars: String; out What: String): Integer;
var
  I, J, K: Integer;
  Prev: String;
begin
  What := '';
  for I := 1 to Length(Code) do
  begin
    if Code[I] = '@' then
    begin
      if IsRoutineAddress(Code, I, Routines, Vars) then
        Continue;
      What := '@';
      Exit(I);
    end;
    if Code[I] <> '^' then
      Continue;
    J := I - 1;
    while (J >= 1) and (Code[J] = ' ') do
      Dec(J);
    if (J >= 1) and (Code[J] in [')', ']', '^']) then
      Continue;
    if (J >= 1) and IsWordChar(Code[J]) then
    begin
      K := J;
      while (K > 1) and IsWordChar(Code[K - 1]) do
        Dec(K);
      Prev := LowerCase(Copy(Code, K, J - K + 1));
      if Prev <> 'of' then
        Continue;
    end;
    What := '^T';
    Exit(I);
  end;
  Result := 0;
end;

{ The word that ends right before position I of Code (spaces skipped), lower case; Start gets its first column. }
function WordBefore(const Code: String; I: Integer; out Start: Integer): String;
var
  J: Integer;
begin
  J := I - 1;
  while (J >= 1) and (Code[J] = ' ') do
    Dec(J);
  Start := J + 1;
  while (Start > 1) and IsWordChar(Code[Start - 1]) do
    Dec(Start);
  Result := LowerCase(Copy(Code, Start, J - Start + 1));
end;

{ Names (lower case, ';'-separated) of the variables, parameters and fields of the module declared with a pointer
  type: A, B: ^T, P: PChar, Q: PNode (a pointer type of the module). }
function PointerVarNames(const Src: TVetSource; const ModulePointers: String): String;
var
  I, C, K, Start: Integer;
  InBrace, InParen, IsPtr: Boolean;
  Code, Tail, W: String;
begin
  Result := ';';
  InBrace := False;
  InParen := False;
  for I := 0 to High(Src.Lines) do
  begin
    Code := CodeOf(Src.Lines[I], InBrace, InParen, Tail);
    for C := 1 to Length(Code) do
    begin
      if (Code[C] <> ':') or ((C < Length(Code)) and (Code[C + 1] = '=')) then
        Continue;
      K := SkipSpaces(Code, C + 1);
      if K > Length(Code) then
        Continue;
      if Code[K] = '^' then
        IsPtr := True
      else
      begin
        W := '';
        while (K <= Length(Code)) and IsWordChar(Code[K]) do
        begin
          W := W + Code[K];
          Inc(K);
        end;
        W := ';' + LowerCase(W) + ';';
        IsPtr := (W <> ';;') and ((Pos(W, SystemPointers) > 0) or (Pos(W, ModulePointers) > 0));
      end;
      if not IsPtr then
        Continue;
      K := C;
      repeat
        W := WordBefore(Code, K, Start);
        if W = '' then
          Break;
        Result := Result + W + ';';
        K := Start - 1;
        while (K >= 1) and (Code[K] = ' ') do
          Dec(K);
        if (K < 1) or (Code[K] <> ',') then
          Break;
      until False;
    end;
  end;
end;

{ The column of the first pointer arithmetic in Code over the pointer names Names, or 0; What gets the text. }
function PointerArith(const Code, Names: String; out What: String): Integer;
var
  I, J, K, Start: Integer;
  W, X: String;
begin
  What := '';
  I := 1;
  while I <= Length(Code) do
  begin
    if not IsWordChar(Code[I]) or ((I > 1) and IsWordChar(Code[I - 1])) or (Code[I] in ['0'..'9']) then
    begin
      Inc(I);
      Continue;
    end;
    J := I;
    while (J <= Length(Code)) and IsWordChar(Code[J]) do
      Inc(J);
    W := LowerCase(Copy(Code, I, J - I));
    K := SkipSpaces(Code, J);
    if ((W = 'inc') or (W = 'dec')) and (K <= Length(Code)) and (Code[K] = '(') then
    begin
      K := SkipSpaces(Code, K + 1);
      J := K;
      while (J <= Length(Code)) and IsWordChar(Code[J]) do
        Inc(J);
      X := LowerCase(Copy(Code, K, J - K));
      K := SkipSpaces(Code, J);
      if (X <> '') and (Pos(';' + X + ';', Names) > 0)
        and ((K > Length(Code)) or not (Code[K] in ['^', '.', '[', '('])) then
      begin
        What := Copy(Code, I, J - I) + ')';
        Exit(I);
      end;
    end
    else if Pos(';' + W + ';', Names) > 0 then
    begin
      if (K <= Length(Code)) and (Code[K] in ['+', '-']) then
      begin
        What := Copy(Code, I, J - I) + ' ' + Code[K];
        Exit(I);
      end;
      if not ((K <= Length(Code)) and (Code[K] in ['^', '.', '[', '('])) then
      begin
        WordBefore(Code, I, Start);
        K := Start - 1;
        while (K >= 1) and (Code[K] = ' ') do
          Dec(K);
        if (K >= 1) and (Code[K] in ['+', '-']) then
        begin
          What := Code[K] + ' ' + Copy(Code, I, J - I);
          Exit(I);
        end;
      end;
    end;
    I := J;
  end;
  Result := 0;
end;

function ModulePointerTypes(const Module: TPasModule): String;
begin
  if Module is TPasProgram then
    Result := PointerTypeNames(TPasProgram(Module).ProgramSection)
  else if Module is TPasLibrary then
    Result := PointerTypeNames(TPasLibrary(Module).LibrarySection)
  else
    Result := PointerTypeNames(Module.InterfaceSection) + PointerTypeNames(Module.ImplementationSection);
end;

procedure VetCheckS4(const Src: TVetSource; const Module: TPasModule; var Report: TVetReport);
var
  I, Col: Integer;
  InBrace, InParen, Covered, Arith: Boolean;
  Code, Tail, What, Names, Routines, Vars: String;
begin
  if IsUnsafeUnit(Src) then
    Exit;
  Names := PointerVarNames(Src, ModulePointerTypes(Module));
  ModuleNames(Module, Routines, Vars);
  InBrace := False;
  InParen := False;
  Covered := False;
  for I := 0 to High(Src.Lines) do
  begin
    Code := CodeOf(Src.Lines[I], InBrace, InParen, Tail);
    Col := PointerOp(Code, Routines, Vars, What);
    Arith := False;
    if Col = 0 then
    begin
      Col := PointerArith(Code, Names, What);
      Arith := Col > 0;
    end;
    if Col = 0 then
    begin
      if IsMarkComment(Src.Lines[I]) then
        Covered := True
      else if Trim(Code) <> '' then
        Covered := False;
      Continue;
    end;
    if Covered or IsMarkComment(Tail) then
      Continue;
    if Arith then
      VetAdd(Report, Src.FileName, I + 1, Col, vsError, 'S4',
        'pointer arithmetic ' + What + ': index an array, TArray or TSlice instead, or put a comment '
        + '// UNSAFE: <why the pointer stays inside its block> on the line above (safe/SPEC.md, section 7)')
    else if What = '@' then
      VetAdd(Report, Src.FileName, I + 1, Col, vsError, 'S4',
        'raw address @: pass the variable as a var or const parameter, or borrow it through an owner '
        + '(TOwned.Get, TSlice), or put a comment // UNSAFE: <why the address does not outlive the variable> '
        + 'on the line above (safe/SPEC.md, section 7)')
    else
      VetAdd(Report, Src.FileName, I + 1, Col, vsError, 'S4',
        'raw pointer type ^T: use an owner (TOwned, TShared, TWeak), a class reference, TArray or TSlice, '
        + 'or put a comment // UNSAFE: <why> on the line above (safe/SPEC.md, section 7)');
  end;
end;

procedure VetRunRules(const Src: TVetSource; const Module: TPasModule; var Report: TVetReport);
begin
  VetCheckS3(Src, Module, Report);
  VetCheckS4(Src, Module, Report);
  VetCheckS6(Src, Module, Report);
  VetCheckS7(Src, Module, Report);
  VetCheckS8(Src, Module, Report);
  VetCheckS12(Src, Module, Report);
end;

end.
