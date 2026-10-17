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

var
  MainFile: string;
begin
  MainFile := ExpandFileName('tests/unit/fixtures/browser_main.pas');
  Check(FileExists(MainFile), 'the source-browser fixture exists');
  Check(BuildSourceBrowser(MainFile), 'the source browser builds after parser teardown');
  Check(Modules <> nil, 'the module collection exists');
  Check(Modules.Count = 2, 'the program and its adjacent unit are present');
  Check(HasModule('browser_main'), 'the root program survives parser teardown');
  Check(HasModule('browser_fixture'), 'the used unit survives parser teardown');
  DisposeBrowserCol;
  WriteLn('PASS source-browser module lifetime');
end.
