{ SPDX-License-Identifier: MIT }
{ The rules of bpvet (safe/SPEC.md §6). A rule is a procedure over one parsed module that adds findings to the
  report; VetRunRules calls every rule. A new rule: a procedure VetCheckSxx here, a call in VetRunRules, and
  a pair of lint tests tests/lint/sxx_ok.pas and sxx_bad.pas (tests/lint.sh). }
unit BpvetRules;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, PasTree, BpvetCore, Safe;

procedure VetRunRules(const Src: TVetSource; const Module: TPasModule; var Report: TVetReport);

{ S7: Safe/BP is the last unit in scope of the module, so that its names shadow the poisoned routines (register H9).
    Error    a unit follows Safe/BP in the same uses clause;
    Warning  the implementation uses come after Safe/BP of the interface (they shadow it in the implementation);
    Warning  units follow BP that is first in the uses of a program (BP goes first there for the thread manager,
             SPEC §14, and the units after it shadow it in the program file). }
procedure VetCheckS7(const Src: TVetSource; const Module: TPasModule; var Report: TVetReport);

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

procedure VetRunRules(const Src: TVetSource; const Module: TPasModule; var Report: TVetReport);
begin
  VetCheckS7(Src, Module, Report);
end;

end.
