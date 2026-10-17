program t_fpsrcbrw;
{$mode objfpc}{$H+}
uses SysUtils, BrowCol, FPSrcBrw;

procedure Check(OK: Boolean; const What: string);
begin
  if not OK then
  begin
    WriteLn('FAIL ', What);
    Halt(1);
  end;
end;

function HasModule(const Name: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  if Modules = nil then
    Exit;
  for I := 0 to Modules.Count - 1 do
    if SameText(Modules.At(I).GetName, Name) then
      Exit(True);
end;

function HasProcedure(Module: PModuleSymbol; const Name, SourceFile: string; SourceLine: Integer): Boolean;
var
  I, J: Integer;
  S, Member: PSymbol;
  function HasSourceReference(Symbol: PSymbol): Boolean;
  var
    R: Integer;
  begin
    Result := False;
    for R := 0 to Symbol.GetReferenceCount - 1 do
      if SameText(ExtractFileName(Symbol.GetReference(R).GetFileName),
         ExtractFileName(SourceFile)) and
         (Symbol.GetReference(R).Position.Y = SourceLine) then
        Exit(True);
  end;
begin
  Result := False;
  if (Module = nil) or (Module.Items = nil) then
    Exit;
  for I := 0 to Module.Items.Count - 1 do
  begin
    S := Module.Items.At(I);
    if SameText(S.GetName, Name) and HasSourceReference(S) then
      Exit(True);
    if S.Items = nil then
      Continue;
    for J := 0 to S.Items.Count - 1 do
    begin
      Member := S.Items.At(J);
      if SameText(Member.GetName, Name) and HasSourceReference(Member) then
        Exit(True);
    end;
  end;
end;

function FindModule(const Name: string): PModuleSymbol;
var
  I: Integer;
begin
  Result := nil;
  if Modules = nil then
    Exit;
  for I := 0 to Modules.Count - 1 do
    if SameText(Modules.At(I).GetName, Name) then
      Exit(PModuleSymbol(Modules.At(I)));
end;

var
  MainFile: string;
  FixtureFile: string;
begin
  MainFile := ExpandFileName('tests/unit/fixtures/browser_main.pas');
  FixtureFile := ExpandFileName('tests/unit/fixtures/browser_fixture.pas');
  Check(FileExists(MainFile), 'the source-browser fixture exists');
  Check(FileExists(FixtureFile), 'the adjacent-unit fixture exists');
  Check(BuildSourceBrowser(MainFile), 'the source browser builds after parser teardown');
  Check(Modules <> nil, 'the module collection exists');
  Check(Modules.Count = 2, 'the program and its adjacent unit are present');
  Check(HasModule('browser_main'), 'the root program survives parser teardown');
  Check(HasModule('browser_fixture'), 'the used unit survives parser teardown');
  Check(HasProcedure(FindModule('browser_fixture'), 'KeepAlive', FixtureFile, 6),
    'the copied procedure and source reference survive parser teardown');
  DisposeBrowserCol;
  WriteLn('PASS source-browser module lifetime');
end.
