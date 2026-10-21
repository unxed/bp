{ SPDX-License-Identifier: MIT }
{ The rules of bpvet (safe/SPEC.md §6). A rule is a procedure over one parsed module that adds findings to the
  report; VetRunRules calls every rule. A new rule: a procedure VetCheckSxx here, a call in VetRunRules, and
  a pair of lint tests tests/lint/sxx_ok.pas and sxx_bad.pas (tests/lint.sh). }
unit BpvetRules;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, PasTree, BpvetCore, Safe;

var
  { Directories (-FuDIR of bpvet) where S5 also looks for the files of used units, after the directory of the
    checked file. }
  VetUnitDirs: array of String;

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

{ S9: legacy string types (safe/SPEC.md §6, register H8). A module marked // UNSAFE-UNIT: is not checked.
    Error    the type name UnicodeString, WideString or ShortString, or a sized string String[N] (a ShortString),
             without a // UNSAFE: <why> comment on the line above (one comment covers a block of such lines right
             below it) or at the end of the line. The safe dialect uses String (UTF-8, mode $H+); a conversion for an
             API that needs UTF-16 or a fixed-size record field is the exception that the mark explains. }
procedure VetCheckS9(const Src: TVetSource; const Module: TPasModule; var Report: TVetReport);

{ S5: fields own, locals borrow (safe/SPEC.md §0, §6, register H1). A module marked // UNSAFE-UNIT: is not checked.
    Error  a global variable of the module, or a field of a class, object or record, whose type is a class: a class
           declared in this module or a well-known class of the RTL (S5ClassTypes). Such a reference is a borrow
           that can outlive its owner; hold the object through TOwned/TShared/TWeak or an interface instead, or put
           a comment // borrow: <who owns it> at the end of the line or on the line above.
    Error  the result of .Get is saved into a global variable or a field of a class of the module
           (Name := Owner.Get; or Self.Name := Owner.Get;): the borrow escapes and can outlive its owner; keep it
           in a local variable, or put a comment // borrow: <who owns it> at the end of the line or on the line above.
    Error  Owner.Reset or Owner.Move in a routine after Local := Owner.Get; while Local is still used later in
           the same routine (before a new Local := ...): the object is freed or moved under the borrow; finish with
           the borrow first, or put a comment // UNSAFE: <why> on the line above or at the end of the line.
    Closures (anonymous procedures, reference to) are not checked: FPC 3.2.2 does not compile them, although
    fcl-passrc 3.2.2 parses them (for pas2js).
    The classes known are those of the module, S5ClassTypes, and the classes declared in the interface of the units
    it uses whose files lie next to it (name.pas in the same directory, read as text) or in a directory given to
    bpvet with -FuDIR. }
procedure VetCheckS5(const Src: TVetSource; const Module: TPasModule; var Report: TVetReport);

{ S15: no TShared cycles (safe/SPEC.md §6, register H2). A module marked // UNSAFE-UNIT: is not checked.
    Warning  a field of a class of the module whose type is TShared of a class of the module (specialize TShared<X>
             or a module alias NAME = specialize TShared<X>), when X leads back to the class of the field through
             such fields (X is the class itself, or a field of X, or of a class it holds this way, is a TShared of
             it): the objects of the cycle keep each other alive and leak. A back reference is TWeak (Shared.Weak).
             A // UNSAFE: <why> comment on the line above or at the end of the line drops the warning for the field
             (the program breaks the cycle itself). The check is a heuristic by names over one module: the type of
             a field is read from the text of its line, classes of other units are not followed. }
procedure VetCheckS15(const Src: TVetSource; const Module: TPasModule; var Report: TVetReport);

{ S10: TOwned is unique (safe/SPEC.md §6, register H5). A module marked // UNSAFE-UNIT: is not checked.
    Error    a parameter of a TOwned type (TOwned<...> or a module alias NAME = specialize TOwned<...>) passed by
             value: without const, var, out or constref;
    Error    a copy X := Y where Y is a variable, field or parameter of a TOwned type (move it with Y.Move);
    unless a // UNSAFE: <why> comment stands on the line above (one comment covers a block of such lines right below
    it) or at the end of the line. bpvet has no types: it knows the names declared with a TOwned type before the
    first routine header of the file and in the current routine (a later declaration of the name with another type
    hides it); a routine header is read from its first line only. }
procedure VetCheckS10(const Src: TVetSource; const Module: TPasModule; var Report: TVetReport);

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

{ S5 }

const
  { classes of the RTL that a module often keeps in a field or a global }
  S5ClassTypes = ' tobject exception tstrings tstringlist tlist tfplist tobjectlist tstream tmemorystream '
    + 'tfilestream tstringstream tthread tcomponent tpersistent tcollection ';

{ The names of the classes declared in Decls and in classes nested in them, as ' tfoo tbar '. }
procedure S5CollectClasses(const L: TFPList; var Names: String);
var
  I: Integer;
  E: TPasElement;
begin
  if L = nil then
    Exit;
  for I := 0 to L.Count - 1 do
  begin
    E := TPasElement(L[I]);
    if (E is TPasClassType) and (TPasClassType(E).ObjKind = okClass) and (E.Name <> '') then
      Names := Names + LowerCase(E.Name) + ' ';
    if E is TPasClassType then
      S5CollectClasses(TPasClassType(E).Members, Names)
    else if E is TPasRecordType then
      S5CollectClasses(TPasRecordType(E).Members, Names);
  end;
end;

{ The type name of a variable without a unit prefix, in lower case; '' for an anonymous type (specialize, array). }
function S5TypeName(const V: TPasVariable): String;
var
  I: Integer;
begin
  Result := '';
  if (V.VarType = nil) or (V.VarType.Name = '') then
    Exit;
  Result := LowerCase(V.VarType.Name);
  I := LastDelimiter('.', Result);
  if I > 0 then
    Result := Copy(Result, I + 1, Length(Result));
end;

{ The line Row has a // borrow: comment at its end, or the line above is a // borrow: comment. }
function S5Marked(const Src: TVetSource; const Row: Integer): Boolean;
begin
  Result := (Pos('// borrow:', LowerCase(VetLine(Src, Row))) > 0)
    or (Pos('// borrow:', LowerCase(TrimLeft(VetLine(Src, Row - 1)))) = 1);
end;

procedure S5CheckList(const Src: TVetSource; const L: TFPList; const ClassNames, Kind: String;
  var Report: TVetReport);
var
  I: Integer;
  E: TPasElement;
  T: String;
begin
  if L = nil then
    Exit;
  for I := 0 to L.Count - 1 do
  begin
    E := TPasElement(L[I]);
    if E.ClassType = TPasVariable then
    begin
      T := S5TypeName(TPasVariable(E));
      if (T <> '') and (Pos(' ' + T + ' ', ClassNames) > 0) and not S5Marked(Src, E.SourceLinenumber) then
        AddAtElement(Src, E, vsError, 'S5',
          Kind + ' ' + E.Name + ' of the class type ' + TPasVariable(E).VarType.Name + ' is a borrow that can '
          + 'outlive its owner: hold the object through TOwned, TShared, TWeak or an interface, or put a comment '
          + '// borrow: <who owns it> at the end of the line or on the line above (safe/SPEC.md, section 6)', Report);
    end
    else if E is TPasClassType then
      S5CheckList(Src, TPasClassType(E).Members, ClassNames, 'the field', Report)
    else if E is TPasRecordType then
      S5CheckList(Src, TPasRecordType(E).Members, ClassNames, 'the field', Report);
  end;
end;

{ The classes declared in the interface of a unit file: lines Name = class ... before the word implementation
  (not class of, comments and strings skipped), added to Names as ' tfoo '. A missing file adds nothing. }
procedure S5FileClasses(const FileName: String; var Names: String);
var
  U: TVetSource;
  I, P, J: Integer;
  InBrace, InParen, Word: Boolean;
  Code, Tail, L, N, R, Err: String;
begin
  if not FileExists(FileName) or not VetReadSource(FileName, U, Err) then
    Exit;
  InBrace := False;
  InParen := False;
  for I := 0 to High(U.Lines) do
  begin
    Code := CodeOf(U.Lines[I], InBrace, InParen, Tail);
    L := LowerCase(Trim(Code));
    if (L = 'implementation') or (Pos('implementation ', L) = 1) then
      Break;
    P := Pos('=', L);
    if P = 0 then
      Continue;
    N := Trim(Copy(L, 1, P - 1));
    R := Trim(Copy(L, P + 1, Length(L)));
    if (N = '') or (Pos('class', R) <> 1) or ((Length(R) > 5) and IsWordChar(R[6])) then
      Continue;
    if Pos('of ', TrimLeft(Copy(R, 6, Length(R)))) = 1 then
      Continue;
    Word := True;
    for J := 1 to Length(N) do
      if not IsWordChar(N[J]) then
        Word := False;
    if Word and (Pos(' ' + N + ' ', Names) = 0) then
      Names := Names + N + ' ';
  end;
end;

{ The classes of the units listed in Clause whose files (name.pas, lower case) lie next to the checked file or in
  a directory of VetUnitDirs. }
procedure S5UsedClasses(const Src: TVetSource; const Clause: TPasUsesClause; var Names: String);
var
  I, J: Integer;
  Dir, N: String;
begin
  Dir := ExtractFilePath(Src.FileName);
  for I := 0 to High(Clause) do
    if (Clause[I].Expr <> nil) and (Clause[I].Name <> '') then
    begin
      N := LowerCase(Clause[I].Name) + '.pas';
      if FileExists(Dir + N) then
        S5FileClasses(Dir + N, Names)
      else
        for J := 0 to High(VetUnitDirs) do
          if FileExists(IncludeTrailingPathDelimiter(VetUnitDirs[J]) + N) then
          begin
            S5FileClasses(IncludeTrailingPathDelimiter(VetUnitDirs[J]) + N, Names);
            Break;
          end;
    end;
end;

{ The names of the global variables of Decls and of the fields of the classes declared there, as ' a b '. }
procedure S5CollectStores(const L: TFPList; const InClass: Boolean; var Names: String);
var
  I: Integer;
  E: TPasElement;
begin
  if L = nil then
    Exit;
  for I := 0 to L.Count - 1 do
  begin
    E := TPasElement(L[I]);
    if (E.ClassType = TPasVariable) and (E.Name <> '') then
      Names := Names + LowerCase(E.Name) + ' '
    else if (E is TPasClassType) and (TPasClassType(E).ObjKind = okClass) then
      S5CollectStores(TPasClassType(E).Members, True, Names);
  end;
end;

{ The column of a statement Name := X.Get; or Self.Name := X.Get; in Code whose Name is in Stores, or 0. }
function S5GetEscape(const Code, Stores: String; out Name: String): Integer;
var
  P, I: Integer;
  L, R: String;
begin
  Result := 0;
  Name := '';
  P := Pos(':=', Code);
  if P = 0 then
    Exit;
  L := LowerCase(Trim(Copy(Code, 1, P - 1)));
  if Pos('self.', L) = 1 then
    L := Trim(Copy(L, 6, Length(L)));
  if L = '' then
    Exit;
  for I := 1 to Length(L) do
    if not IsWordChar(L[I]) then
      Exit;
  R := LowerCase(Trim(Copy(Code, P + 2, Length(Code))));
  if (R <> '') and (R[Length(R)] = ';') then
    R := TrimRight(Copy(R, 1, Length(R) - 1));
  if (Length(R) > 2) and (Copy(R, Length(R) - 1, 2) = '()') then
    R := TrimRight(Copy(R, 1, Length(R) - 2));
  if (Length(R) < 5) or (Copy(R, Length(R) - 3, 4) <> '.get') then
    Exit;
  if Pos(' ' + L + ' ', Stores) = 0 then
    Exit;
  Name := L;
  Result := Length(Code) - Length(TrimLeft(Code)) + 1;
end;

{ The names of the parameters of a class type (a name in ClassNames) in a routine header on one line of Code,
  as ' a b '; '' when Code is not a routine header. }
function S5HeaderParams(const Code, ClassNames: String; out IsHeader: Boolean): String;
var
  L, Seg, T, W, Rest: String;
  P, Q, C, I: Integer;
begin
  Result := ' ';
  L := LowerCase(Trim(Code));
  if Pos('class ', L) = 1 then
    L := Trim(Copy(L, 7, Length(L)));
  IsHeader := (Pos('procedure ', L) = 1) or (Pos('function ', L) = 1) or (Pos('constructor ', L) = 1)
    or (Pos('destructor ', L) = 1);
  if not IsHeader then
    Exit;
  P := Pos('(', L);
  Q := Pos(')', L);
  if (P = 0) or (Q < P) then
    Exit;
  Rest := Copy(L, P + 1, Q - P - 1) + ';';
  while Rest <> '' do
  begin
    I := Pos(';', Rest);
    Seg := Copy(Rest, 1, I - 1);
    Delete(Rest, 1, I);
    C := Pos(':', Seg);
    if C = 0 then
      Continue;
    T := Trim(Copy(Seg, C + 1, Length(Seg)));
    I := Pos('=', T);
    if I > 0 then
      T := Trim(Copy(T, 1, I - 1));
    if Pos(' ' + T + ' ', ClassNames) = 0 then
      Continue;
    W := Trim(Copy(Seg, 1, C - 1));
    if (Pos('const ', W) = 1) or (Pos('var ', W) = 1) or (Pos('out ', W) = 1) or (Pos('constref ', W) = 1) then
      W := Trim(Copy(W, Pos(' ', W) + 1, Length(W)));
    W := StringReplace(W, ' ', '', [rfReplaceAll]);
    Result := Result + StringReplace(W, ',', ' ', [rfReplaceAll]) + ' ';
  end;
end;

{ The column of a statement Name := Param; or Self.Name := Param; in Code whose Name is in Stores and Param in
  Params, or 0. }
function S5ParamEscape(const Code, Stores, Params: String; out Name: String): Integer;
var
  P, I: Integer;
  L, R: String;
begin
  Result := 0;
  Name := '';
  P := Pos(':=', Code);
  if (P = 0) or (Params = ' ') then
    Exit;
  L := LowerCase(Trim(Copy(Code, 1, P - 1)));
  if Pos('self.', L) = 1 then
    L := Trim(Copy(L, 6, Length(L)));
  R := LowerCase(Trim(Copy(Code, P + 2, Length(Code))));
  if (R <> '') and (R[Length(R)] = ';') then
    R := TrimRight(Copy(R, 1, Length(R) - 1));
  if (L = '') or (R = '') then
    Exit;
  for I := 1 to Length(L) do
    if not IsWordChar(L[I]) then
      Exit;
  if (Pos(' ' + L + ' ', Stores) = 0) or (Pos(' ' + R + ' ', Params) = 0) then
    Exit;
  Name := L;
  Result := Length(Code) - Length(TrimLeft(Code)) + 1;
end;

{ Owner when Code is a statement Local := Owner.Get; with Local a plain name not in Stores; Local gets the name. }
function S5LocalBorrow(const Code, Stores: String; out Local: String): String;
var
  P, I: Integer;
  R: String;
begin
  Result := '';
  Local := '';
  P := Pos(':=', Code);
  if P = 0 then
    Exit;
  Local := LowerCase(Trim(Copy(Code, 1, P - 1)));
  if (Local = '') or (Pos(' ' + Local + ' ', Stores) > 0) then
    Exit;
  for I := 1 to Length(Local) do
    if not IsWordChar(Local[I]) then
      Exit;
  R := LowerCase(Trim(Copy(Code, P + 2, Length(Code))));
  if (R <> '') and (R[Length(R)] = ';') then
    R := TrimRight(Copy(R, 1, Length(R) - 1));
  if (Length(R) > 2) and (Copy(R, Length(R) - 1, 2) = '()') then
    R := TrimRight(Copy(R, 1, Length(R) - 2));
  if (Length(R) < 5) or (Copy(R, Length(R) - 3, 4) <> '.get') then
    Exit;
  R := Copy(R, 1, Length(R) - 4);
  if Pos('self.', R) = 1 then
    R := Copy(R, 6, Length(R));
  if R = '' then
    Exit;
  for I := 1 to Length(R) do
    if not IsWordChar(R[I]) then
      Exit;
  Result := R;
end;

{ The column of the word W (lower case) in Code, or 0. }
function S5WordAt(const Code, W: String): Integer;
var
  L: String;
  P, From: Integer;
begin
  Result := 0;
  L := LowerCase(Code);
  From := 1;
  repeat
    P := Pos(W, Copy(L, From, Length(L)));
    if P = 0 then
      Exit;
    P := P + From - 1;
    if ((P = 1) or not IsWordChar(L[P - 1])) and ((P + Length(W) > Length(L)) or not IsWordChar(L[P + Length(W)]))
    then
      Exit(P);
    From := P + 1;
  until False;
end;

{ The column of Owner.Reset or Owner.Move (Self. allowed) in Code, or 0; What gets 'Reset' or 'Move'. }
function S5Release(const Code, Owner: String; out What: String): Integer;
var
  P, E: Integer;
  L: String;
begin
  Result := 0;
  What := '';
  L := LowerCase(Code);
  P := S5WordAt(L, Owner);
  while P > 0 do
  begin
    E := P + Length(Owner);
    if (Copy(L, E, 6) = '.reset') and ((E + 6 > Length(L)) or not IsWordChar(L[E + 6])) then
      What := 'Reset'
    else if (Copy(L, E, 5) = '.move') and ((E + 5 > Length(L)) or not IsWordChar(L[E + 5])) then
      What := 'Move';
    if What <> '' then
      Exit(P);
    L[P] := ' ';
    P := S5WordAt(L, Owner);
  end;
end;

{ The row (1-based) after Row where Local is still used in the same routine (before the next routine header or a
  new assignment Local := ...), or 0. }
function S5LaterUse(const Codes: array of String; const Row: Integer; const Local: String): Integer;
var
  I, P: Integer;
  IsHeader: Boolean;
  L: String;
begin
  Result := 0;
  for I := Row to High(Codes) do
  begin
    S5HeaderParams(Codes[I], ' ', IsHeader);
    if IsHeader then
      Exit;
    L := LowerCase(Codes[I]);
    P := Pos(':=', L);
    if (P > 0) and (LowerCase(Trim(Copy(L, 1, P - 1))) = Local) then
    begin
      if S5WordAt(Copy(L, P + 2, Length(L)), Local) > 0 then
        Exit(I + 1);
      Exit;
    end;
    if S5WordAt(L, Local) > 0 then
      Exit(I + 1);
  end;
end;

function S5UnsafeMarked(const Src: TVetSource; const Row: Integer): Boolean;
begin
  Result := (Pos('// UNSAFE:', VetLine(Src, Row)) > 0) or IsMarkComment(VetLine(Src, Row - 1));
end;

procedure S5CheckEscapes(const Src: TVetSource; const Stores, ClassNames: String; var Report: TVetReport);
var
  I, J, Col, Later: Integer;
  InBrace, InParen, IsHeader: Boolean;
  Code, Tail, Name, Params, HeaderParams, Owner, What: String;
  Codes, BorrowLocal, BorrowOwner: array of String;
begin
  InBrace := False;
  InParen := False;
  Params := ' ';
  SetLength(Codes, Length(Src.Lines));
  for I := 0 to High(Src.Lines) do
    Codes[I] := CodeOf(Src.Lines[I], InBrace, InParen, Tail);
  SetLength(BorrowLocal, 0);
  SetLength(BorrowOwner, 0);
  for I := 0 to High(Src.Lines) do
  begin
    Code := Codes[I];
    HeaderParams := S5HeaderParams(Code, ClassNames, IsHeader);
    if IsHeader then
    begin
      Params := HeaderParams;
      SetLength(BorrowLocal, 0);
      SetLength(BorrowOwner, 0);
      Continue;
    end;
    for J := 0 to High(BorrowOwner) do
    begin
      Col := S5Release(Code, BorrowOwner[J], What);
      if Col = 0 then
        Continue;
      Later := S5LaterUse(Codes, I + 1, BorrowLocal[J]);
      if (Later > 0) and not S5UnsafeMarked(Src, I + 1) then
        VetAdd(Report, Src.FileName, I + 1, Col, vsError, 'S5',
          BorrowOwner[J] + '.' + What + ' while the borrow ' + BorrowLocal[J] + ' := ' + BorrowOwner[J]
          + '.Get is alive (used on line ' + IntToStr(Later) + '): the object is freed or moved under it; '
          + 'finish with the borrow first, or put a comment // UNSAFE: <why> on the line above '
          + '(safe/SPEC.md, section 6)');
    end;
    Owner := S5LocalBorrow(Code, Stores, Name);
    if Name <> '' then
      for J := High(BorrowLocal) downto 0 do
        if BorrowLocal[J] = Name then
        begin
          BorrowLocal[J] := BorrowLocal[High(BorrowLocal)];
          BorrowOwner[J] := BorrowOwner[High(BorrowOwner)];
          SetLength(BorrowLocal, Length(BorrowLocal) - 1);
          SetLength(BorrowOwner, Length(BorrowOwner) - 1);
        end;
    if Owner <> '' then
    begin
      SetLength(BorrowLocal, Length(BorrowLocal) + 1);
      SetLength(BorrowOwner, Length(BorrowOwner) + 1);
      BorrowLocal[High(BorrowLocal)] := Name;
      BorrowOwner[High(BorrowOwner)] := Owner;
    end;
    Col := S5GetEscape(Code, Stores, Name);
    if (Col > 0) and not S5Marked(Src, I + 1) then
      VetAdd(Report, Src.FileName, I + 1, Col, vsError, 'S5',
        'the result of .Get is saved into the field or global ' + Name + ': the borrow escapes and can outlive '
        + 'its owner; keep it in a local variable or a parameter, or put a comment // borrow: <who owns it> at the '
        + 'end of the line or on the line above (safe/SPEC.md, section 6)');
    Col := S5ParamEscape(Code, Stores, Params, Name);
    if (Col > 0) and not S5Marked(Src, I + 1) then
      VetAdd(Report, Src.FileName, I + 1, Col, vsError, 'S5',
        'a parameter of a class type is saved into the field or global ' + Name + ': the borrow escapes and can '
        + 'outlive its owner; take an owner (TShared, TWeak) instead, or put a comment // borrow: <who owns it> at '
        + 'the end of the line or on the line above (safe/SPEC.md, section 6)');
  end;
end;

procedure VetCheckS5(const Src: TVetSource; const Module: TPasModule; var Report: TVetReport);
var
  Sections: array[0..1] of TPasDeclarations;
  I: Integer;
  ClassNames, Stores: String;
begin
  if IsUnsafeUnit(Src) then
    Exit;
  Sections[0] := nil;
  Sections[1] := nil;
  if Module is TPasProgram then
    Sections[0] := TPasProgram(Module).ProgramSection
  else if Module is TPasLibrary then
    Sections[0] := TPasLibrary(Module).LibrarySection
  else
  begin
    Sections[0] := Module.InterfaceSection;
    Sections[1] := Module.ImplementationSection;
  end;
  ClassNames := S5ClassTypes;
  for I := 0 to 1 do
    if Sections[I] <> nil then
      S5CollectClasses(Sections[I].Declarations, ClassNames);
  for I := 0 to 1 do
    if Sections[I] is TPasSection then
      S5UsedClasses(Src, TPasSection(Sections[I]).UsesClause, ClassNames);
  for I := 0 to 1 do
    if Sections[I] <> nil then
      S5CheckList(Src, Sections[I].Declarations, ClassNames, 'the global variable', Report);
  Stores := ' ';
  for I := 0 to 1 do
    if Sections[I] <> nil then
      S5CollectStores(Sections[I].Declarations, False, Stores);
  S5CheckEscapes(Src, Stores, ClassNames, Report);
end;

{ S9 }

const
  S9Names = ' unicodestring widestring shortstring ';

{ The column of the first legacy string type in Code (a line without comments and strings) and its name, or 0. }
function S9Type(const Code: String; out What: String): Integer;
var
  I, B, K: Integer;
  L, W: String;
begin
  Result := 0;
  What := '';
  L := LowerCase(Code);
  I := 1;
  while I <= Length(L) do
  begin
    if not IsWordChar(L[I]) or ((I > 1) and IsWordChar(L[I - 1])) then
    begin
      Inc(I);
      Continue;
    end;
    B := I;
    while (I <= Length(L)) and IsWordChar(L[I]) do
      Inc(I);
    W := Copy(L, B, I - B);
    if Pos(' ' + W + ' ', S9Names) > 0 then
    begin
      What := Copy(Code, B, I - B);
      Exit(B);
    end;
    if W = 'string' then
    begin
      K := I;
      while (K <= Length(L)) and (L[K] = ' ') do
        Inc(K);
      if (K <= Length(L)) and (L[K] = '[') then
      begin
        What := 'String[N]';
        Exit(B);
      end;
    end;
  end;
end;

procedure VetCheckS9(const Src: TVetSource; const Module: TPasModule; var Report: TVetReport);
var
  I, Col: Integer;
  InBrace, InParen, Covered: Boolean;
  Code, Tail, What: String;
begin
  if IsUnsafeUnit(Src) then
    Exit;
  InBrace := False;
  InParen := False;
  Covered := False;
  for I := 0 to High(Src.Lines) do
  begin
    Code := CodeOf(Src.Lines[I], InBrace, InParen, Tail);
    Col := S9Type(Code, What);
    if Col = 0 then
    begin
      if IsMarkComment(Src.Lines[I]) then
        Covered := True
      else if Trim(Code) <> '' then
        Covered := False;
      Continue;
    end;
    if not Covered and not IsMarkComment(Tail) then
      VetAdd(Report, Src.FileName, I + 1, Col, vsError, 'S9',
        'legacy string type ' + What + ': use String (UTF-8), or put a comment // UNSAFE: <why> on the '
        + 'line above (safe/SPEC.md, section 6)');
  end;
end;

{ S10 }

type
  TS10Parts = array of String;

{ S split at every D. }
function S10Split(const S: String; const D: Char): TS10Parts;
var
  I, Start, N: Integer;
begin
  Result := nil;
  N := 0;
  Start := 1;
  for I := 1 to Length(S) + 1 do
    if (I > Length(S)) or (S[I] = D) then
    begin
      SetLength(Result, N + 1);
      Result[N] := Copy(S, Start, I - Start);
      Inc(N);
      Start := I + 1;
    end;
end;

{ The TOwned types of the module, each as ' name ': towned and the names declared as NAME = specialize TOwned<...>. }
function S10OwnedTypes(const Src: TVetSource): String;
var
  I, Eq: Integer;
  L, Name, Rest: String;
begin
  Result := ' towned ';
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
    if (Pos('towned', Rest) = 1) and ((Length(Rest) = 6) or not IsWordChar(Rest[7])) and (Name <> '')
      and (Pos(' ', Name) = 0) then
      Result := Result + Name + ' ';
  end;
end;

{ The first word of S (lowercase, trimmed). }
function S10FirstWord(const S: String): String;
var
  T: String;
  K: Integer;
begin
  T := TrimLeft(S);
  K := 1;
  while (K <= Length(T)) and IsWordChar(T[K]) do
    Inc(K);
  Result := Copy(T, 1, K - 1);
end;

{ True when the type text T (lowercase) names a TOwned type. }
function S10IsOwned(const T, Owned: String): Boolean;
var
  W, Rest: String;
begin
  W := S10FirstWord(T);
  if W = 'specialize' then
  begin
    Rest := TrimLeft(T);
    Rest := Copy(Rest, 11, Length(Rest));
    Exit(S10FirstWord(Rest) = 'towned');
  end;
  Result := (W <> '') and (Pos(' ' + W + ' ', Owned) > 0);
end;

{ The declaration Seg (lowercase, 'names: type'): adds its names to Vars (' name ') when the type is a TOwned type,
  removes them otherwise. Returns True when Seg is a declaration of a TOwned type. }
function S10Declare(const Seg, Owned: String; var Vars: String): Boolean;
var
  C: Integer;
  Left, Name, W: String;
  Names: TS10Parts;
begin
  Result := False;
  C := Pos(':', Seg);
  if (C = 0) or ((C < Length(Seg)) and (Seg[C + 1] = '=')) then
    Exit;
  Left := Trim(Copy(Seg, 1, C - 1));
  W := S10FirstWord(Left);
  if (W = 'var') or (W = 'const') or (W = 'out') or (W = 'constref') then
    Left := Trim(Copy(Left, Length(W) + 1, Length(Left)));
  Result := S10IsOwned(Copy(Seg, C + 1, Length(Seg)), Owned);
  Names := S10Split(Left, ',');
  for Name in Names do
  begin
    W := Trim(Name);
    if (W = '') or (S10FirstWord(W) <> W) then
      Continue;
    Vars := StringReplace(Vars, ' ' + W + ' ', ' ', [rfReplaceAll]);
    if Result then
      Vars := Vars + W + ' ';
  end;
end;

{ The column of the right side of X := Y in L (lowercase code) when Y is a name path whose last name is in Vars, or 0. }
function S10Copy(const L, Vars: String): Integer;
var
  A, K, E, B: Integer;
  R: String;
begin
  Result := 0;
  A := Pos(':=', L);
  if A = 0 then
    Exit;
  K := A + 2;
  while (K <= Length(L)) and (L[K] = ' ') do
    Inc(K);
  E := K;
  while (E <= Length(L)) and (IsWordChar(L[E]) or (L[E] = '.')) do
    Inc(E);
  R := TrimRight(Copy(L, E, Length(L)));
  if (E = K) or not ((R = '') or (R = ';')) then
    Exit;
  B := E - 1;
  while (B >= K) and (L[B] <> '.') do
    Dec(B);
  R := Copy(L, B + 1, E - B - 1);
  if (R <> '') and (Pos(' ' + R + ' ', Vars) > 0) then
    Result := K;
end;

procedure VetCheckS10(const Src: TVetSource; const Module: TPasModule; var Report: TVetReport);
var
  I, Col, P, Q: Integer;
  InBrace, InParen, Covered, Header, Seen: Boolean;
  Code, Tail, L, T, W, Owned, Globals, Vars, Msg, Seg: String;
  Segs: TS10Parts;
begin
  if IsUnsafeUnit(Src) then
    Exit;
  Owned := S10OwnedTypes(Src);
  Globals := ' ';
  Vars := ' ';
  Seen := False;
  InBrace := False;
  InParen := False;
  Covered := False;
  for I := 0 to High(Src.Lines) do
  begin
    Code := CodeOf(Src.Lines[I], InBrace, InParen, Tail);
    L := LowerCase(Code);
    T := TrimLeft(L);
    W := S10FirstWord(T);
    if W = 'class' then
      W := S10FirstWord(Copy(T, 6, Length(T)));
    Header := (W = 'procedure') or (W = 'function') or (W = 'constructor') or (W = 'destructor');
    Col := 0;
    Msg := '';
    if Header then
    begin
      if not Seen then
        Globals := Vars;
      Seen := True;
      Vars := Globals;
      P := Pos('(', L);
      Q := Length(L);
      while (Q > P) and (L[Q] <> ')') do
        Dec(Q);
      if (P > 0) and (Q > P) then
      begin
        Segs := S10Split(Copy(L, P + 1, Q - P - 1), ';');
        for Seg in Segs do
        begin
          W := S10FirstWord(Seg);
          if S10Declare(Seg, Owned, Vars) and (W <> 'const') and (W <> 'var') and (W <> 'out') and (W <> 'constref')
            and (Col = 0) then
          begin
            Col := P + 1;
            Msg := 'a TOwned parameter passed by value copies the owner: make it const (borrow) or var (take it '
              + 'with .Move), or put a comment // UNSAFE: <why> on the line above (safe/SPEC.md, section 6)';
          end;
        end;
      end;
    end
    else
    begin
      Segs := S10Split(L, ';');
      for Seg in Segs do
        S10Declare(Seg, Owned, Vars);
      Col := S10Copy(L, Vars);
      if Col > 0 then
        Msg := 'a copy of a TOwned owner: move it with .Move (X := Y.Move), or put a comment // UNSAFE: <why> on '
          + 'the line above (safe/SPEC.md, section 6)';
    end;
    if Col = 0 then
    begin
      if IsMarkComment(Src.Lines[I]) then
        Covered := True
      else if Trim(Code) <> '' then
        Covered := False;
      Continue;
    end;
    if not Covered and not IsMarkComment(Tail) then
      VetAdd(Report, Src.FileName, I + 1, Col, vsError, 'S10', Msg);
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

{ S15 }

type
  TS15Edge = record
    Owner, Target, Field: String;  { lower-case class names; the field name as written }
    Row: Integer;
    Elem: TPasElement;
  end;

{ The TShared aliases of the module, each as ' name=class ': NAME = specialize TShared<CLASS>. }
function S15SharedAliases(const Src: TVetSource): String;
var
  I, Eq, Lt, Gt: Integer;
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
    if (Name = '') or (Pos(' ', Name) > 0) or (Pos('specialize ', Rest) <> 1) then
      Continue;
    Rest := TrimLeft(Copy(Rest, 12, Length(Rest)));
    Lt := Pos('<', Rest);
    Gt := Pos('>', Rest);
    if (Lt = 0) or (Gt < Lt) or (Trim(Copy(Rest, 1, Lt - 1)) <> 'tshared') then
      Continue;
    Result := Result + Name + '=' + Trim(Copy(Rest, Lt + 1, Gt - Lt - 1)) + ' ';
  end;
end;

{ The class that the field type text T (lower case, from after the colon) holds through TShared, or ''. }
function S15Target(const T, Aliases: String): String;
var
  Rest, W: String;
  Lt, Gt, P: Integer;
begin
  Result := '';
  Rest := TrimLeft(T);
  if Pos('specialize ', Rest) = 1 then
  begin
    Rest := TrimLeft(Copy(Rest, 12, Length(Rest)));
    Lt := Pos('<', Rest);
    Gt := Pos('>', Rest);
    if (Lt > 0) and (Gt > Lt) and (Trim(Copy(Rest, 1, Lt - 1)) = 'tshared') then
      Result := Trim(Copy(Rest, Lt + 1, Gt - Lt - 1));
    Exit;
  end;
  W := S10FirstWord(Rest);
  if W = '' then
    Exit;
  P := Pos(' ' + W + '=', Aliases);
  if P = 0 then
    Exit;
  Rest := Copy(Aliases, P + Length(W) + 2, Length(Aliases));
  Result := Copy(Rest, 1, Pos(' ', Rest) - 1);
end;

{ The TShared fields of the classes in L (and in classes nested in them), as edges owner class -> held class. }
procedure S15CollectEdges(const Src: TVetSource; const L: TFPList; const Aliases: String;
  var Edges: array of TS15Edge; var N: Integer);
var
  I, J, C: Integer;
  E, M: TPasElement;
  Line, Target: String;
begin
  if L = nil then
    Exit;
  for I := 0 to L.Count - 1 do
  begin
    E := TPasElement(L[I]);
    if not (E is TPasClassType) then
      Continue;
    if (TPasClassType(E).ObjKind = okClass) and (E.Name <> '') then
      for J := 0 to TPasClassType(E).Members.Count - 1 do
      begin
        M := TPasElement(TPasClassType(E).Members[J]);
        if M.ClassType <> TPasVariable then
          Continue;
        Line := LowerCase(VetLine(Src, M.SourceLinenumber));
        C := Pos(':', Line);
        if C = 0 then
          Continue;
        Target := S15Target(Copy(Line, C + 1, Length(Line)), Aliases);
        if (Target = '') or (N > High(Edges)) then
          Continue;
        Edges[N].Owner := LowerCase(E.Name);
        Edges[N].Target := Target;
        Edges[N].Field := E.Name + '.' + M.Name;
        Edges[N].Row := M.SourceLinenumber;
        Edges[N].Elem := M;
        Inc(N);
      end;
    S15CollectEdges(Src, TPasClassType(E).Members, Aliases, Edges, N);
  end;
end;

{ The path of fields from class From back to class Goal, as ' -> A.F -> B.G', or '' when there is none. }
function S15PathBack(const Edges: array of TS15Edge; const N: Integer; const From, Goal: String;
  var Seen: String): String;
var
  I: Integer;
  Rest: String;
begin
  Result := '';
  if From = Goal then
    Exit(' ');
  if Pos(' ' + From + ' ', Seen) > 0 then
    Exit;
  Seen := Seen + From + ' ';
  for I := 0 to N - 1 do
    if Edges[I].Owner = From then
    begin
      Rest := S15PathBack(Edges, N, Edges[I].Target, Goal, Seen);
      if Rest <> '' then
        Exit(' -> ' + Edges[I].Field + TrimRight(Rest));
    end;
end;

procedure VetCheckS15(const Src: TVetSource; const Module: TPasModule; var Report: TVetReport);
var
  Sections: array[0..1] of TPasDeclarations;
  Edges: array[0..255] of TS15Edge;
  I, N: Integer;
  Aliases, Seen, Path: String;
begin
  if IsUnsafeUnit(Src) then
    Exit;
  Sections[0] := nil;
  Sections[1] := nil;
  if Module is TPasProgram then
    Sections[0] := TPasProgram(Module).ProgramSection
  else if Module is TPasLibrary then
    Sections[0] := TPasLibrary(Module).LibrarySection
  else
  begin
    Sections[0] := Module.InterfaceSection;
    Sections[1] := Module.ImplementationSection;
  end;
  Aliases := S15SharedAliases(Src);
  N := 0;
  for I := 0 to 1 do
    if Sections[I] <> nil then
      S15CollectEdges(Src, Sections[I].Declarations, Aliases, Edges, N);
  for I := 0 to N - 1 do
  begin
    Seen := ' ';
    Path := S15PathBack(Edges, N, Edges[I].Target, Edges[I].Owner, Seen);
    if (Path <> '') and not S5UnsafeMarked(Src, Edges[I].Row) then
      AddAtElement(Src, Edges[I].Elem, vsWarning, 'S15',
        'the field ' + Edges[I].Field + ' holds through TShared an object that leads back to its own class ('
        + Edges[I].Field + TrimRight(Path) + '): the objects of such a cycle keep each other alive and leak; '
        + 'a back reference is TWeak (Shared.Weak), or put a comment // UNSAFE: <why> on the line above '
        + '(safe/SPEC.md, section 6)', Report);
  end;
end;

procedure VetRunRules(const Src: TVetSource; const Module: TPasModule; var Report: TVetReport);
begin
  VetCheckS3(Src, Module, Report);
  VetCheckS4(Src, Module, Report);
  VetCheckS5(Src, Module, Report);
  VetCheckS15(Src, Module, Report);
  VetCheckS6(Src, Module, Report);
  VetCheckS9(Src, Module, Report);
  VetCheckS10(Src, Module, Report);
  VetCheckS7(Src, Module, Report);
  VetCheckS8(Src, Module, Report);
  VetCheckS12(Src, Module, Report);
end;

end.
