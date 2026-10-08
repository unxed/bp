program t_fpdlv;
{ Tests of src/fpdlv.pas: a session with the real dlv when it is installed (a breakpoint, steps, a value, the end of the program with its
  output, the end of a session that is stopped) and the failure of a start (no such tool, a program that does not build). }
{$mode objfpc}{$H+}
uses SysUtils, Classes, FpDlv;

var
  Bad: Integer = 0;
  Total: Integer = 0;

procedure Check(OK: Boolean; const What: string);
begin
  Inc(Total);
  if not OK then
  begin
    Inc(Bad);
    WriteLn('FAIL ', What);
  end;
end;

function Write(const Name, Text: string): string;
var
  L: TStringList;
begin
  ForceDirectories(ExtractFilePath(Name));
  L := TStringList.Create;
  L.Text := Text;
  L.SaveToFile(Name);
  L.Free;
  Result := Name;
end;

const
  Prog = 'package main' + LineEnding +                       { 1 }
    LineEnding +                                              { 2 }
    'import "fmt"' + LineEnding +                             { 3 }
    LineEnding +                                              { 4 }
    'func add(a, b int) int {' + LineEnding +                 { 5 }
    #9 + 'return a + b' + LineEnding +                        { 6 }
    '}' + LineEnding +                                        { 7 }
    LineEnding +                                              { 8 }
    'func main() {' + LineEnding +                            { 9 }
    #9 + 'x := 20' + LineEnding +                             { 10 }
    #9 + 'y := add(x, 22)' + LineEnding +                     { 11 }
    #9 + 'fmt.Println("sum", y)' + LineEnding +               { 12 }
    '}' + LineEnding;

var
  Dir, Src, Dlv, V: string;
  S: TDlvSession;
  R: Boolean;
begin
  Dir := GetTempDir + 't_fpdlv_' + IntToStr(GetProcessID) + '/';
  Src := Write(Dir + 'p.go', Prog);

  { a tool that is not there }
  S := TDlvSession.Create;
  R := S.Start('/no/such/dlv', 'debug', Src, Dir, ''); Check(not R, 'a missing dlv does not start');
  Check(S.Error <> '', 'the failure has a text');
  S.Free;

  Dlv := FindDlv;
  if (Dlv = '') or (FileSearch('go', GetEnvironmentVariable('PATH')) = '') then
    WriteLn('(dlv or go is not installed: the checks of a real session are skipped)')
  else
  begin
    S := TDlvSession.Create;
    R := S.Start(Dlv, 'debug', Src, Dir, ''); Check(R, 'dlv builds and starts the program: ' + S.Error);
    R := S.SetBreakpoints(Src, [11]); Check(R, 'a breakpoint is set: ' + S.Error);
    R := S.Go = drStopped; Check(R, 'the program runs to the breakpoint: ' + S.Error);
    Check(S.StopFile = Src, 'it stopped in the file: ' + S.StopFile);
    Check(S.StopLine = 11, 'it stopped on line 11: ' + IntToStr(S.StopLine));
    R := S.Evaluate('x', V); Check(R and (V = '20'), 'x is 20: ' + V);
    R := S.StepInto = drStopped; Check(R, 'step into: ' + S.Error);
    Check((S.StopFile = Src) and (S.StopLine = 5), 'step into goes into add (line 5): ' + IntToStr(S.StopLine));
    R := S.StepOut = drStopped; Check(R, 'step out: ' + S.Error);
    R := S.StepOver = drStopped; Check(R, 'step over: ' + S.Error);
    Check(S.StopLine = 12, 'step over reaches line 12: ' + IntToStr(S.StopLine));
    R := S.Evaluate('y', V); Check(R and (V = '42'), 'y is 42: ' + V);
    { a breakpoint set while the program is stopped, and the end }
    Check(S.SetBreakpoints(Src, []), 'the breakpoints are cleared');
    R := S.Proceed = drExited; Check(R, 'continue runs to the end: ' + S.Error);
    Check(S.ExitCode = 0, 'exit code 0');
    Check(Pos('sum 42', S.TakeOutput) > 0, 'the output of the program is returned');
    S.Free;

    { a session that starts at main.main }
    S := TDlvSession.Create;
    R := S.Start(Dlv, 'debug', Src, Dir, ''); Check(R, 'third start: ' + S.Error);
    Check(S.SetFunctionBreakpoint('main.main'), 'a function breakpoint is set');
    R := S.Go = drStopped; Check(R, 'the program stops in main.main: ' + S.Error);
    Check((S.StopFile = Src) and (S.StopLine = 9), 'main.main stops on its line (9): ' + IntToStr(S.StopLine));
    S.Free;

    { a session ended while the program is stopped }
    S := TDlvSession.Create;
    R := S.Start(Dlv, 'debug', Src, Dir, ''); Check(R, 'second start: ' + S.Error);
    S.SetBreakpoints(Src, [10]);
    Check((S.Go = drStopped) and (S.StopLine = 10), 'stopped on line 10');
    S.Stop;
    Check(not S.Alive, 'Stop ends the session');
    S.Free;

    { a program that does not build }
    Src := Write(Dir + 'bad.go', 'package main' + LineEnding + 'func main() { x := nope }' + LineEnding);
    S := TDlvSession.Create;
    R := S.Start(Dlv, 'debug', Src, Dir, ''); Check(not R, 'a program that does not build does not start');
    Check(S.Error <> '', 'the build error is reported: ' + S.Error);
    S.Free;
  end;

  DeleteFile(Dir + 'p.go'); DeleteFile(Dir + 'bad.go'); RemoveDir(Dir);
  if Bad = 0 then
    WriteLn('ALL OK (', Total, ' checks)')
  else
  begin
    WriteLn(Bad, ' of ', Total, ' checks FAILED');
    Halt(1);
  end;
end.
