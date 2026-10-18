{ Languages of the IDE other than Pascal: what program builds a file, with what arguments, and how its output is read.

  MIT. The unit knows nothing of the screen: the IDE (fpintf) asks it for the command of a file and gives it the lines
  of the output, it answers with messages that the window of messages shows. Pascal is not here: its compiler keeps its own way (fpintf).
  A language is a class that is registered; the first that takes the file is the backend of the file.

  Go: "go build", "go vet", "go test"; the debugger of Go is Delve (fpdlv, fpgodbg).

  Ownership (Safe Pascal, step 3c of safe/FPIDE-ADOPTION.md): the registered backends belong to an arena that the unit owns;
  RegisterBackend takes the ownership of its argument. BackendFor gives out a borrow that lives until ReleaseBackends
  or the end of the program. }
{$mode objfpc}{$H+}
{$WARN SYMBOL_DEPRECATED ERROR}
unit FpLang;

interface

uses
  SysUtils, Classes, TvPath, FpProcGuard, Safe;

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

{ takes the ownership of B: the backend lives until ReleaseBackends or the end of the program }
procedure RegisterBackend(B: TLangBackend);
{ frees every registered backend (the borrows given out by BackendFor become invalid); the program ends with it in the tests that check for leaks }
procedure ReleaseBackends;
{ the backend of a file, nil for a file of Pascal (and of any language without a backend) }
function BackendFor(const FileName: string): TLangBackend;
{ runs the formatter of the backend on the file (the file is rewritten); Output has what the formatter wrote.
  False when the language has no formatter, the tool is not found or it failed }
function FormatFile(B: TLangBackend; const FileName: string; out Output: string): Boolean;

implementation

type
  TGuardBox = specialize TOwned<TProcGuard>;
  TStringListBox = specialize TOwned<TStringList>;
  TStringStreamBox = specialize TOwned<TStringStream>;

var
  Arena: TArena;                         { owns the backends }
  Backends: array of TLangBackend;       { borrow: Arena }

function TLangBackend.WorkDir(const FileName: string): string;
begin
  Result := PathDir(PathExpand(FileName));
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
  E := LowerCase(PathExt(FileName));
  Result := (E = '.go') or (LowerCase(PathName(FileName)) = 'go.mod');
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
  D := PathDelSep(PathDir(PathExpand(FileName)));
  while D <> '' do
  begin
    if FileExists(PathAddSep(D) + 'go.mod') then
      Exit(D);
    Up := PathDelSep(PathDir(D));
    if Up = D then
      Break;
    D := Up;
  end;
end;

function TGoBackend.WorkDir(const FileName: string): string;
begin
  Result := PathDir(PathExpand(FileName));
end;

procedure TGoBackend.Arguments(Mode: TLangMode; const FileName, OutFile: string; Args: TStrings);
var
  Target: string;
begin
  { in a module the package of the file is built (the other files of the package are needed); a file alone is built as it is }
  if ModuleDir(FileName) <> '' then
    Target := '.'
  else
    Target := PathName(FileName);
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
  if LowerCase(PathExt(FileName)) <> '.go' then
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
  SetLength(Backends, Length(Backends) + 1);
  Backends[High(Backends)] := Arena.Adopt(B) as TLangBackend;
end;

procedure ReleaseBackends;
begin
  SetLength(Backends, 0);
  Arena.FreeAll;
end;

function BackendFor(const FileName: string): TLangBackend;
var
  I: Integer;
begin
  Result := nil;
  for I := 0 to High(Backends) do
    if Backends[I].Handles(FileName) then
      Exit(Backends[I]);
end;

function FormatFile(B: TLangBackend; const FileName: string; out Output: string): Boolean;
var
  GBox: TGuardBox;
  ArgsBox: TStringListBox;
  SBox: TStringStreamBox;
  G: TProcGuard;                         { borrow: GBox }
  Args: TStringList;                     { borrow: ArgsBox }
  S: TStringStream;                      { borrow: SBox }
  ArgArr: array of string;
  Chunk: AnsiString;
  WasRunning: Boolean;
  I: Integer;
begin
  Output := '';
  Result := False;
  if (B = nil) or (B.FormatTool = '') then
    Exit;
  { the guard owns the child: every way out of this function (also an exception while reading) ends it, see fpprocguard.pas }
  GBox := TGuardBox.Own(TProcGuard.Create);
  ArgsBox := TStringListBox.Own(TStringList.Create);
  SBox := TStringStreamBox.Own(TStringStream.Create(''));
  G := GBox.Get;
  Args := ArgsBox.Get;
  S := SBox.Get;
  try
    B.FormatArguments(FileName, Args);
    SetLength(ArgArr, Args.Count);
    for I := 0 to Args.Count - 1 do
      ArgArr[I] := Args[I];
    try
      G.Start(B.FormatTool, ArgArr, B.WorkDir(FileName));
    except
      on E: Exception do
      begin
        Output := E.Message;
        Exit;
      end;
    end;
    repeat
      { the state is read before the output: when the child had ended before the read, an empty read means all is drained }
      WasRunning := G.Running;
      Chunk := G.ReadAvailable;
      if Chunk <> '' then
        S.WriteString(Chunk)
      else if WasRunning then
        Sleep(10);
    until (not WasRunning) and (Chunk = '');
    Output := Trim(S.DataString);
    Result := G.ExitCode = 0;
  finally
    SBox.Reset;
    ArgsBox.Reset;
    GBox.Reset;
  end;
end;

initialization
  Arena := TArena.Create;
  RegisterBackend(TGoBackend.Create);
finalization
  ReleaseBackends;
end.
