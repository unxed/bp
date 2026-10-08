{ Languages of the IDE other than Pascal: what program builds a file, with what arguments, and how its output is read.

  MIT. The unit knows nothing of the screen: the IDE (fpintf) asks it for the command of a file and gives it the lines
  of the output, it answers with messages that the window of messages shows. Pascal is not here: its compiler keeps its own way (fpintf).
  A language is a class that is registered; the first that takes the file is the backend of the file.

  Go: "go build", "go vet", "go test"; the debugger of Go is Delve (fpdlv, fpgodbg). }
{$mode objfpc}{$H+}
unit FpLang;

interface

uses
  SysUtils, Classes, Process;

type
  { what the user asked: the same four of the Compile menu and the tests }
  TLangMode = (lmBuild, lmMake, lmCompile, lmRun, lmTest);
  TLangSeverity = (lsError, lsWarning, lsNote);

  TLangMessage = record
    Severity: TLangSeverity;
    FileName: string;              { as the tool wrote it; '' when the line has no place }
    Line, Col: LongInt;
    Text: string;
  end;

  TLangBackend = class
  public
    { the name of the language for the menus and the status line }
    function Name: string; virtual; abstract;
    { does the backend build this file }
    function Handles(const FileName: string): Boolean; virtual; abstract;
    { the program that is run (found on the search path) }
    function ToolName: string; virtual; abstract;
    { the arguments of the tool; OutFile is the executable that the IDE will run }
    procedure Arguments(Mode: TLangMode; const FileName, OutFile: string; Args: TStrings); virtual; abstract;
    { the directory in which the tool is run }
    function WorkDir(const FileName: string): string; virtual;
    { a line of the output: True when it is a message (Msg is filled) }
    function ParseLine(const Line: string; out Msg: TLangMessage): Boolean; virtual; abstract;
    { does the file make a program that can be run (not a library, not a unit) }
    function IsProgram(const FileName: string): Boolean; virtual;
    { the debugger that the language uses ('gdb' is the default) }
    function DebuggerTool: string; virtual;
    { the text of a new file of the language (what a file that does not exist yet starts with), '' for none }
    function NewFileText: string; virtual;
    { the formatter of the language: the program (''  when there is none) and its arguments for a file }
    function FormatTool: string; virtual;
    procedure FormatArguments(const FileName: string; Args: TStrings); virtual;
  end;

  TGoBackend = class(TLangBackend)
  public
    function Name: string; override;
    function Handles(const FileName: string): Boolean; override;
    function ToolName: string; override;
    procedure Arguments(Mode: TLangMode; const FileName, OutFile: string; Args: TStrings); override;
    function WorkDir(const FileName: string): string; override;
    function ParseLine(const Line: string; out Msg: TLangMessage): Boolean; override;
    function IsProgram(const FileName: string): Boolean; override;
    function DebuggerTool: string; override;
    function NewFileText: string; override;
    function FormatTool: string; override;
    procedure FormatArguments(const FileName: string; Args: TStrings); override;
    { the directory that holds go.mod above the file (the module), '' when there is none }
    function ModuleDir(const FileName: string): string;
  end;

procedure RegisterBackend(B: TLangBackend);
{ the backend of a file, nil for a file of Pascal (and of any language without a backend) }
function BackendFor(const FileName: string): TLangBackend;
{ runs the formatter of the backend on the file (the file is rewritten); Output has what the formatter wrote.
  False when the language has no formatter, the tool is not found or it failed }
function FormatFile(B: TLangBackend; const FileName: string; out Output: string): Boolean;

implementation

var
  Backends: TList;

function TLangBackend.WorkDir(const FileName: string): string;
begin
  Result := ExtractFilePath(ExpandFileName(FileName));
end;

function TLangBackend.IsProgram(const FileName: string): Boolean;
begin
  Result := True;
end;

function TLangBackend.DebuggerTool: string;
begin
  Result := 'gdb';
end;

function TLangBackend.NewFileText: string;
begin
  Result := '';
end;

function TLangBackend.FormatTool: string;
begin
  Result := '';
end;

procedure TLangBackend.FormatArguments(const FileName: string; Args: TStrings);
begin
end;

{ --- Go ------------------------------------------------------------------------------------------------------------------ }

function TGoBackend.Name: string;
begin
  Result := 'Go';
end;

function TGoBackend.Handles(const FileName: string): Boolean;
var
  E: string;
begin
  E := LowerCase(ExtractFileExt(FileName));
  Result := (E = '.go') or (LowerCase(ExtractFileName(FileName)) = 'go.mod');
end;

function TGoBackend.ToolName: string;
begin
  Result := 'go';
end;

function TGoBackend.DebuggerTool: string;
begin
  Result := 'dlv';
end;

function TGoBackend.NewFileText: string;
begin
  Result := 'package main' + LineEnding + LineEnding + 'import "fmt"' + LineEnding + LineEnding +
    'func main() {' + LineEnding + #9 + 'fmt.Println("hello")' + LineEnding + '}' + LineEnding;
end;

function TGoBackend.FormatTool: string;
begin
  Result := 'gofmt';
end;

procedure TGoBackend.FormatArguments(const FileName: string; Args: TStrings);
begin
  Args.Add('-w');
  Args.Add(FileName);
end;

function TGoBackend.ModuleDir(const FileName: string): string;
var
  D, Up: string;
begin
  Result := '';
  D := ExcludeTrailingPathDelimiter(ExtractFilePath(ExpandFileName(FileName)));
  while D <> '' do
  begin
    if FileExists(IncludeTrailingPathDelimiter(D) + 'go.mod') then
      Exit(D);
    Up := ExcludeTrailingPathDelimiter(ExtractFilePath(D));
    if Up = D then
      Break;
    D := Up;
  end;
end;

function TGoBackend.WorkDir(const FileName: string): string;
begin
  Result := ExtractFilePath(ExpandFileName(FileName));
end;

procedure TGoBackend.Arguments(Mode: TLangMode; const FileName, OutFile: string; Args: TStrings);
var
  Target: string;
begin
  { in a module the package of the file is built (the other files of the package are needed); a file alone is built as it is }
  if ModuleDir(FileName) <> '' then
    Target := '.'
  else
    Target := ExtractFileName(FileName);
  case Mode of
    lmBuild:
      begin
        Args.Add('build');
        Args.Add('-a');
        Args.Add('-o');
        Args.Add(OutFile);
        Args.Add(Target);
      end;
    lmMake, lmRun:
      begin
        Args.Add('build');
        Args.Add('-o');
        Args.Add(OutFile);
        Args.Add(Target);
      end;
    lmCompile:
      begin
        Args.Add('vet');
        Args.Add(Target);
      end;
    lmTest:
      begin
        Args.Add('test');
        if Target = '.' then
          Args.Add('./...')
        else
          Args.Add(Target);
      end;
  end;
end;

function IsDigits(const S: string): Boolean;
var
  I: Integer;
begin
  Result := S <> '';
  for I := 1 to Length(S) do
    if not (S[I] in ['0'..'9']) then
      Exit(False);
end;

function TGoBackend.ParseLine(const Line: string; out Msg: TLangMessage): Boolean;
var
  L, F, Rest: string;
  P, Q: Integer;
begin
  Result := False;
  Msg.FileName := '';
  Msg.Line := 0;
  Msg.Col := 0;
  Msg.Text := '';
  Msg.Severity := lsError;
  L := TrimRight(Line);
  if (L = '') or (L[1] = '#') then
    Exit;                          { "# package" says which package the next lines are about }
  L := TrimLeft(L);                { the lines of a failed test are indented }
  if (Copy(L, 1, 5) = 'vet: ') and (Pos('.go:', L) > 0) then
    Delete(L, 1, 5);              { go vet writes its findings with this prefix }
  { file.go:LINE:COL: text   or   file.go:LINE: text }
  P := Pos('.go:', L);
  if P < 2 then
  begin
    { not a position: the summary lines are shown as notes }
    if (Pos('FAIL', L) = 1) or (Pos('--- FAIL', L) = 1) or (Pos('panic:', L) = 1) then
    begin
      Msg.Text := L;
      Msg.Severity := lsError;
      Result := True;
    end
    else if (Pos('go: ', L) = 1) or (Pos('vet: ', L) = 1) then
    begin
      Msg.Text := L;
      Msg.Severity := lsError;
      Result := True;
    end;
    Exit;
  end;
  F := Copy(L, 1, P + 2);
  Rest := Copy(L, P + 4, MaxInt);
  Q := Pos(':', Rest);
  if (Q < 2) or not IsDigits(Copy(Rest, 1, Q - 1)) then
    Exit;
  Msg.Line := StrToInt(Copy(Rest, 1, Q - 1));
  Rest := Copy(Rest, Q + 1, MaxInt);
  Q := Pos(':', Rest);
  if (Q > 1) and IsDigits(Copy(Rest, 1, Q - 1)) then
  begin
    Msg.Col := StrToInt(Copy(Rest, 1, Q - 1));
    Rest := Copy(Rest, Q + 1, MaxInt);
  end;
  Msg.Text := Trim(Rest);
  if (Length(F) > 2) and (Copy(F, 1, 2) = './') then
    Delete(F, 1, 2);
  Msg.FileName := F;
  if (Pos('warning', LowerCase(Msg.Text)) = 1) then
    Msg.Severity := lsWarning
  else if Pos('note', LowerCase(Msg.Text)) = 1 then
    Msg.Severity := lsNote;
  Result := True;
end;

function TGoBackend.IsProgram(const FileName: string): Boolean;
var
  T: TextFile;
  S: string;
  N: Integer;
begin
  Result := True;
  if LowerCase(ExtractFileExt(FileName)) <> '.go' then
    Exit;
  AssignFile(T, FileName);
  {$I-}
  Reset(T);
  {$I+}
  if IOResult <> 0 then
    Exit;
  Result := False;
  N := 0;
  while not Eof(T) and (N < 200) do
  begin
    ReadLn(T, S);
    Inc(N);
    S := Trim(S);
    if Copy(S, 1, 8) = 'package ' then
    begin
      Result := Trim(Copy(S, 9, MaxInt)) = 'main';
      Break;
    end;
  end;
  CloseFile(T);
end;

{ --- the registry ---------------------------------------------------------------------------------------------------------- }

procedure RegisterBackend(B: TLangBackend);
begin
  Backends.Add(B);
end;

function BackendFor(const FileName: string): TLangBackend;
var
  I: Integer;
begin
  Result := nil;
  for I := 0 to Backends.Count - 1 do
    if TLangBackend(Backends[I]).Handles(FileName) then
      Exit(TLangBackend(Backends[I]));
end;

function FormatFile(B: TLangBackend; const FileName: string; out Output: string): Boolean;
var
  P: TProcess;
  Args: TStringList;
  S: TStringStream;
  Buf: array[0..4095] of Byte;
  N, I: Integer;
begin
  Output := '';
  Result := False;
  if (B = nil) or (B.FormatTool = '') then
    Exit;
  P := TProcess.Create(nil);
  Args := TStringList.Create;
  S := TStringStream.Create('');
  try
    P.Executable := B.FormatTool;
    B.FormatArguments(FileName, Args);
    for I := 0 to Args.Count - 1 do
      P.Parameters.Add(Args[I]);
    P.CurrentDirectory := B.WorkDir(FileName);
    P.Options := [poUsePipes, poStderrToOutput];
    try
      P.Execute;
    except
      on E: Exception do
      begin
        Output := E.Message;
        Exit;
      end;
    end;
    repeat
      N := P.Output.Read(Buf, SizeOf(Buf));
      if N > 0 then
        S.Write(Buf, N);
    until N <= 0;
    P.WaitOnExit;
    Output := Trim(S.DataString);
    Result := P.ExitStatus = 0;
  finally
    S.Free;
    Args.Free;
    P.Free;
  end;
end;

var
  I: Integer;
initialization
  Backends := TList.Create;
  RegisterBackend(TGoBackend.Create);
finalization
  for I := 0 to Backends.Count - 1 do
    TLangBackend(Backends[I]).Free;
  Backends.Free;
end.
