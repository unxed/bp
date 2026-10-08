{ The debugger of Go programs in the IDE: Delve (fpdlv) behind the same Run menu commands as the debugger of Pascal.

  MIT. A session starts with Run when a breakpoint is set in the Go file (or with F7/F8, which stop in
  main.main); the breakpoints of the list in the files of Go are handed to dlv before each run of the program; the line where it stops is
  painted as the debugger row. The commands of gdb (call stack, watches, registers) are not served for Go. }
{$mode objfpc}{$H+}{$modeswitch nestedprocvars}{$modeswitch autoderef}

unit FpGoDbg;

interface

{ the Run menu commands that the debugger of Go serves (cmRun, cmContinue, cmStepOver, cmTraceInto, cmUntilReturn, cmGotoCursor,
  cmResetDebugger); True when the command was handled (a session is open, or the file is a Go file that is debugged) }
function GoDebugCommand(Cmd: Word): Boolean;
{ is a session open }
function GoDebugActive: Boolean;
{ ends the session (the program is killed) }
procedure GoDebugEnd;

implementation

uses
  SysUtils, Classes, Objects, Drivers, Views, App, MsgBox, WViews, WEditor,
  FpLang, FpDlv, FPConst, FPViews, FPVars, FPUtils, FPCompil, FPIde, FPHelp,
{$ifndef NODEBUG}
  FPDebug,
{$endif}
  FPIntf;

{$ifdef NODEBUG}
function GoDebugCommand(Cmd: Word): Boolean;
begin
  Result := False;
end;

function GoDebugActive: Boolean;
begin
  Result := False;
end;

procedure GoDebugEnd;
begin
end;
{$else}

var
  Session: TDlvSession = nil;
  LastGoFile: string = '';
  { the files whose breakpoints dlv has (a file that lost its last breakpoint must be cleared) }
  SyncedFiles: TStringList = nil;

function GoDebugActive: Boolean;
begin
  Result := (Session <> nil) and Session.Alive;
end;

function EscPressed: Boolean;
var
  Event: TEvent;
begin
  GetKeyEvent(Event);
  Result := (Event.What = evKeyDown) and (Event.KeyCode = kbEsc);
end;

procedure ClearDebuggerRows;
  procedure ResetRow(P: PView);
  begin
    if (P <> nil) and (P is TSourceWindow) then
      PSourceWindow(P).Editor.SetLineFlagExclusive(lfDebuggerRow, -1);
  end;
begin
  if Desktop <> nil then
    Desktop.ForEach(@ResetRow);
end;

procedure UpdateMenus(Running: Boolean);
begin
  SetCmdState([cmResetDebugger, cmUntilReturn], Running);
  IDEApp.UpdateRunMenu(Running);
end;

procedure GoDebugEnd;
begin
  if Session <> nil then
  begin
    Session.Free;
    Session := nil;
  end;
  FreeAndNil(SyncedFiles);
  ClearDebuggerRows;
  if IDEApp <> nil then
    UpdateMenus(False);
end;

{ the Go file that is run: the primary file, else the file of the active window }
function CurrentGoFile: string;
var
  P: PSourceWindow;
  B: TLangBackend;
begin
  Result := '';
  if PrimaryFileMain <> '' then
    Result := PrimaryFileMain
  else
  begin
    P := TSourceWindow(Message(Desktop, evBroadcast, cmSearchWindow, nil));
    if P <> nil then
      Result := P.Editor.FileName;
  end;
  if Result = '' then
    Exit;
  Result := ExpandFileName(Result);
  B := BackendFor(Result);
  if (B = nil) or (B.DebuggerTool <> 'dlv') then
    Result := '';
end;

{ what dlv is given as the program: the package directory in a module, the file alone otherwise }
function ProgramOf(const GoFile: string): string;
var
  G: TGoBackend;
begin
  G := TGoBackend.Create;
  try
    if G.ModuleDir(GoFile) <> '' then
      Result := ExcludeTrailingPathDelimiter(ExtractFilePath(GoFile))
    else
      Result := GoFile;
  finally
    G.Free;
  end;
end;

{ the breakpoints of the list (and one more line, the target of "go to cursor") are given to dlv, file by file }
procedure SyncBreakpoints(const ExtraFile: string; ExtraLine: LongInt);
var
  Files: TStringList;
  Lines: array of LongInt;
  I, J, N: Integer;
  PB: PBreakpoint;
  F: string;
  Tmp: TStringList;
begin
  Files := TStringList.Create;
  try
    Files.Sorted := True;
    Files.Duplicates := dupIgnore;
    if BreakpointsCollection <> nil then
      for I := 0 to BreakpointsCollection.Count - 1 do
      begin
        PB := BreakpointsCollection.At(I);
        if (PB.typ = bt_file_line) and (PB.state = bs_enabled) and (PB.FileName <> nil) and
           (LowerCase(ExtractFileExt(PB.FileName^)) = '.go') then
          Files.Add(ExpandFileName(PB.FileName^));
      end;
    if ExtraFile <> '' then
      Files.Add(ExtraFile);
    if SyncedFiles = nil then
      SyncedFiles := TStringList.Create;
    for I := 0 to SyncedFiles.Count - 1 do
      Files.Add(SyncedFiles[I]);          { a file that has none now is cleared }
    SyncedFiles.Clear;
    for I := 0 to Files.Count - 1 do
    begin
      F := Files[I];
      Tmp := TStringList.Create;
      try
        Tmp.Sorted := True;
        Tmp.Duplicates := dupIgnore;
        if BreakpointsCollection <> nil then
          for J := 0 to BreakpointsCollection.Count - 1 do
          begin
            PB := BreakpointsCollection.At(J);
            if (PB.typ = bt_file_line) and (PB.state = bs_enabled) and (PB.FileName <> nil) and
               (ExpandFileName(PB.FileName^) = F) then
              Tmp.Add(Format('%.8d', [PB.Line]));
          end;
        if (F = ExtraFile) and (ExtraLine > 0) then
          Tmp.Add(Format('%.8d', [ExtraLine]));
        SetLength(Lines, Tmp.Count);
        for N := 0 to Tmp.Count - 1 do
          Lines[N] := StrToInt(Tmp[N]);
        Session.SetBreakpoints(F, Lines);
        if Tmp.Count > 0 then
          SyncedFiles.Add(F);
      finally
        Tmp.Free;
      end;
    end;
  finally
    Files.Free;
  end;
end;

procedure ShowOutput(const Header: string);
var
  Out_: string;
  L: TStringList;
  I, First: Integer;
  S: string;
begin
  Out_ := Session.TakeOutput;
  L := TStringList.Create;
  try
    L.Text := Out_;
    First := 0;
    if L.Count > 4 then
      First := L.Count - 4;
    S := '';
    for I := First to L.Count - 1 do
      S := S + #3 + Copy(L[I], 1, 44) + #13;
    if Out_ = '' then
      S := #3'(the program wrote nothing)'#13;
    MessageBox(Copy(#3 + Header + #13 + S, 1, 250), mfInformation or mfOKButton);
  finally
    L.Free;
  end;
end;

procedure ShowStop;
var
  W: PSourceWindow;
  Line: LongInt;
begin
  Line := Session.StopLine - 1;
  if Line < 0 then
    Line := 0;
  ClearDebuggerRows;
  if (Session.StopFile = '') or not FileExists(Session.StopFile) then
  begin
    InformationBox(#3'Stopped (' + Session.StopReason + ')'#13#3'in code without source here', nil);
    Exit;
  end;
  Desktop.Lock;
  W := TryToOpenFile(nil, Session.StopFile, 0, Line, False);
  if W <> nil then
  begin
    W.Editor.SetCurPtr(0, Line);
    W.Editor.SetLineFlagExclusive(lfDebuggerRow, Line);
    W.Editor.TrackCursor(IniCenterDebuggerRow);
    W.SelectInDebugSession;
  end;
  Desktop.UnLock;
end;

procedure Finished(R: TDlvResult);
var
  Code: LongInt;
  Err: string;
begin
  case R of
    drStopped:
      ShowStop;
    drExited:
      begin
        Code := Session.ExitCode;
        LastExitCode := Code;
        ClearDebuggerRows;
        ShowOutput('Program exited with'#13#3'exitcode = ' + IntToStr(Code));
        GoDebugEnd;
      end;
    drFailed:
      begin
        Err := Session.Error;
        GoDebugEnd;
        { the output of a failed build has positions: the window of messages lists them }
        if (LastGoFile <> '') and (Pos('.go:', Err) > 0) then
        begin
          ShowBackendMessages(LastGoFile, Err);
          ErrorBox(#3'The program does not build'#13#3'(see the messages)', nil);
        end
        else
          ErrorBox(#3'The debugger of Go failed:'#13#3 + Copy(Err, 1, 70), nil);
      end;
  end;
end;

{ opens a session on the Go file and runs to the first stop (a breakpoint, or main.main when StopAtMain) }
procedure StartSession(const GoFile: string; StopAtMain: Boolean; const ExtraFile: string; ExtraLine: LongInt);
var
  Tool: string;
  R: TDlvResult;
begin
  Tool := FindDlv;
  if Tool = '' then
  begin
    ErrorBox(#3'Delve (dlv) is not installed.'#13#3'go install github.com/go-delve/delve/cmd/dlv@latest', nil);
    Exit;
  end;
  SaveModifiedSources;
  GoDebugEnd;
  LastGoFile := GoFile;
  Session := TDlvSession.Create;
  Session.OnIdle := @EscPressed;
  PushStatus('Starting Delve...');
  try
    if not Session.Start(Tool, 'debug', ProgramOf(GoFile), ExtractFilePath(GoFile), GetRunParameters) then
    begin
      PopStatus;
      Finished(drFailed);
      Exit;
    end;
  finally
  end;
  PopStatus;
  UpdateMenus(True);
  SyncBreakpoints(ExtraFile, ExtraLine);
  if StopAtMain then
    Session.SetFunctionBreakpoint('main.main');
  R := Session.Go;
  Finished(R);
end;

function Resume(Kind: Word; const ExtraFile: string; ExtraLine: LongInt): Boolean;
var
  R: TDlvResult;
begin
  SyncBreakpoints(ExtraFile, ExtraLine);
  case Kind of
    cmStepOver: R := Session.StepOver;
    cmTraceInto: R := Session.StepInto;
    cmUntilReturn: R := Session.StepOut;
  else
    R := Session.Proceed;
  end;
  Finished(R);
  Result := True;
end;

function GoDebugCommand(Cmd: Word): Boolean;
var
  GoFile, F: string;
  W: PFPWindow;
  Line: LongInt;
begin
  Result := False;
  if GoDebugActive then
  begin
    case Cmd of
      cmResetDebugger:
        begin
          GoDebugEnd;
          Result := True;
        end;
      cmRun, cmContinue, cmStepOver, cmTraceInto, cmUntilReturn:
        Result := Resume(Cmd, '', 0);
      cmGotoCursor:
        begin
          W := PFPWindow(Desktop.Current);
          if (W <> nil) and (W.ClassType = TSourceWindow) then
          begin
            F := ExpandFileName(PSourceWindow(W).Editor.FileName);
            Line := PSourceWindow(W).Editor.CurPos.Y + 1;
            Result := Resume(cmContinue, F, Line);
          end;
        end;
    end;
    Exit;
  end;
  if (Session <> nil) then
    GoDebugEnd;                       { a session that ended by itself }
  GoFile := CurrentGoFile;
  if GoFile = '' then
    Exit;
  case Cmd of
    cmRun:
      if ActiveBreakpoints then
      begin
        StartSession(GoFile, False, '', 0);
        Result := True;
      end;
    cmStepOver, cmTraceInto, cmUntilReturn:
      begin
        StartSession(GoFile, True, '', 0);
        Result := True;
      end;
    cmGotoCursor:
      begin
        W := PFPWindow(Desktop.Current);
        if (W <> nil) and (W.ClassType = TSourceWindow) then
        begin
          F := ExpandFileName(PSourceWindow(W).Editor.FileName);
          Line := PSourceWindow(W).Editor.CurPos.Y + 1;
          StartSession(GoFile, False, F, Line);
          Result := True;
        end;
      end;
  end;
end;

{$endif NODEBUG}

finalization
{$ifndef NODEBUG}
  FreeAndNil(Session);
  FreeAndNil(SyncedFiles);
{$endif}
end.
