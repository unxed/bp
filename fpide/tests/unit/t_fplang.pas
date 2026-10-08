program t_fplang;
{ Tests of src/fplang.pas: the Go backend (the commands, the lines of the output, the module, the real tool when it is installed). }
{$mode objfpc}{$H+}
uses SysUtils, Classes, Process, FpLang;

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

function Join(L: TStrings): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to L.Count - 1 do
  begin
    if I > 0 then
      Result := Result + ' ';
    Result := Result + L[I];
  end;
end;

function Run(const Dir, Exe: string; Args: TStrings; out Output: string): Integer;
var
  P: TProcess;
  S: TStringStream;
  Buf: array[0..4095] of Byte;
  N: Integer;
begin
  P := TProcess.Create(nil);
  S := TStringStream.Create('');
  try
    P.Executable := Exe;
    P.Parameters.Assign(Args);
    P.CurrentDirectory := Dir;
    P.Options := [poUsePipes, poStderrToOutput];
    P.Execute;
    repeat
      N := P.Output.Read(Buf, SizeOf(Buf));
      if N > 0 then
        S.Write(Buf, N);
    until N <= 0;
    P.WaitOnExit;
    Result := P.ExitStatus;
    Output := S.DataString;
  finally
    S.Free;
    P.Free;
  end;
end;

function Write(const Name, Text: string): string;
var
  F: TextFile;
begin
  Result := Name;
  AssignFile(F, Name);
  Rewrite(F);
  System.Write(F, Text);
  CloseFile(F);
end;

var
  B: TLangBackend;
  M: TLangMessage;
  A: TStringList;
  Dir, Src, Out_, Exe: string;
  Lines: TStringList;
  I, Found: Integer;
begin
  B := BackendFor('/x/main.go');
  Check(B <> nil, 'a .go file has a backend');
  Check(BackendFor('/x/prog.pas') = nil, 'a Pascal file has none');
  Check(BackendFor('/x/go.mod') <> nil, 'go.mod belongs to Go');
  Check(B.Name = 'Go', 'the name');
  Check(B.ToolName = 'go', 'the tool');
  Check(B.DebuggerTool = 'dlv', 'the debugger of Go is Delve');

  { the lines of the output }
  Check(B.ParseLine('./main.go:12:5: undefined: x', M) and (M.FileName = 'main.go') and (M.Line = 12) and (M.Col = 5) and (M.Text = 'undefined: x') and (M.Severity = lsError), 'build error with a column');
  Check(B.ParseLine('pkg/util.go:7: declared and not used: y', M) and (M.FileName = 'pkg/util.go') and (M.Line = 7) and (M.Col = 0), 'a line without a column');
  Check(B.ParseLine('    main_test.go:20: got 1, want 2', M) and (M.FileName = 'main_test.go') and (M.Line = 20) and (M.Text = 'got 1, want 2'), 'a failed test is indented');
  Check(not B.ParseLine('# example.com/m', M), 'the package header is no message');
  Check(not B.ParseLine('', M), 'an empty line');
  Check(B.ParseLine('--- FAIL: TestX (0.00s)', M) and (M.FileName = '') and (M.Severity = lsError), 'a failed test has no place');
  Check(B.ParseLine('go: go.mod file not found in current directory or any parent directory', M), 'a message of the go command');
  Check(not B.ParseLine('ok  	example.com/m	0.002s', M), 'a passed package is no message');
  Check(not B.ParseLine('main.go:x:y: z', M), 'the line must be a number');

  { the arguments }
  Dir := GetTempDir + 't_fplang_' + IntToStr(GetProcessID) + '/';
  ForceDirectories(Dir + 'lone');
  ForceDirectories(Dir + 'mod/sub');
  Src := Write(Dir + 'lone/main.go', 'package main'#10'func main() {}'#10);
  A := TStringList.Create;
  B.Arguments(lmMake, Src, '/o/main', A);
  Check(Join(A) = 'build -o /o/main main.go', 'a file alone: ' + Join(A));
  A.Clear;
  Check(TGoBackend(B).ModuleDir(Src) = '', 'no module above a lone file');
  Write(Dir + 'mod/go.mod', 'module example.com/m'#10#10'go 1.20'#10);
  Src := Write(Dir + 'mod/sub/main.go', 'package main'#10'func main() {}'#10);
  Check(TGoBackend(B).ModuleDir(Src) = ExcludeTrailingPathDelimiter(Dir + 'mod'), 'the module is found above');
  B.Arguments(lmBuild, Src, '/o/main', A);
  Check(Join(A) = 'build -a -o /o/main .', 'a module: the package: ' + Join(A));
  A.Clear;
  B.Arguments(lmCompile, Src, '', A);
  Check(Join(A) = 'vet .', 'compile is vet: ' + Join(A));
  A.Clear;
  B.Arguments(lmTest, Src, '', A);
  Check(Join(A) = 'test ./...', 'test: ' + Join(A));
  Check(B.IsProgram(Src), 'package main is a program');
  Write(Dir + 'mod/sub/lib.go', 'package lib'#10);
  Check(not B.IsProgram(Dir + 'mod/sub/lib.go'), 'a package that is not main is not');

  { the real tool: a file with an error and a file that is right }
  if (SysUtils.ExeSearch('go', GetEnvironmentVariable('PATH')) <> '') then
  begin
    A.Clear;
    Src := Write(Dir + 'lone/bad.go', 'package main'#10#10'func main() {'#10#9'x := undefinedName'#10'}'#10);
    Out_ := '';
    B.Arguments(lmCompile, Src, '', A);
    Check(Run(B.WorkDir(Src), 'go', A, Out_) <> 0, 'go vet fails on a bad file');
    Lines := TStringList.Create;
    Lines.Text := Out_;
    Found := 0;
    for I := 0 to Lines.Count - 1 do
      if B.ParseLine(Lines[I], M) and (M.FileName = 'bad.go') and (M.Line = 4) then
        Inc(Found);
    Check(Found >= 1, 'the real error is read: ' + Out_);
    Lines.Free;
    DeleteFile(Dir + 'lone/bad.go');
    A.Clear;
    Exe := Dir + 'lone/main';
    Src := Dir + 'lone/main.go';
    B.Arguments(lmMake, Src, Exe, A);
    Check(Run(B.WorkDir(Src), 'go', A, Out_) = 0, 'go build of a good file: ' + Out_);
    Check(FileExists(Exe), 'the executable is made');
  end
  else
    WriteLn('(go is not installed: the checks of the real tool are skipped)');
  A.Free;

  { the template of a new file and the formatter }
  Check(Pos('func main()', B.NewFileText) > 0, 'a new Go file has a template with main');
  Check(B.FormatTool = 'gofmt', 'the formatter of Go is gofmt');
  if FileExists('/usr/local/go/bin/gofmt') or FileExists('/usr/bin/gofmt') then
  begin
    Src := Write(Dir + 'lone/ugly.go', 'package main' + LineEnding + 'func  f( ){ }' + LineEnding);
    Check(FormatFile(B, Src, Out_), 'gofmt formats a file: ' + Out_);
    Lines := TStringList.Create;
    Lines.LoadFromFile(Src);
    Check(Pos('func f() {', Lines.Text) > 0, 'the file is formatted');
    Lines.Free;
    Src := Write(Dir + 'lone/broken.go', 'package main' + LineEnding + 'func (' + LineEnding);
    Check(not FormatFile(B, Src, Out_), 'gofmt fails on a file that does not parse');
    Check(Out_ <> '', 'the message of gofmt is returned');
    DeleteFile(Dir + 'lone/ugly.go'); DeleteFile(Dir + 'lone/broken.go');
  end;

  DeleteFile(Dir + 'lone/main'); DeleteFile(Dir + 'lone/main.go');
  DeleteFile(Dir + 'mod/go.mod'); DeleteFile(Dir + 'mod/sub/main.go'); DeleteFile(Dir + 'mod/sub/lib.go');
  RemoveDir(Dir + 'lone'); RemoveDir(Dir + 'mod/sub'); RemoveDir(Dir + 'mod'); RemoveDir(Dir);
  if Bad = 0 then
    WriteLn('ALL OK (', Total, ' checks)')
  else
  begin
    WriteLn(Bad, ' of ', Total, ' checks FAILED');
    Halt(1);
  end;
end.
