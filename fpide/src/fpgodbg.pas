{ The debugger of Go programs in the IDE: Delve (fpdlv) behind the same Run menu commands as the debugger of Pascal.

  MIT. A session starts with Run when a breakpoint is set in the Go file (or with F7/F8, which stop in
  main.main); the breakpoints of the list in the files of Go are handed to dlv before each run of the program; the line where it stops is
  painted as the debugger row. The windows of watches, of Evaluate and of the call stack are served by Delve while a session is open
  (fpdebug.ForeignEval and the like); the registers and the disassembly are not. Breakpoint conditions and ignore counts go to dlv.
  While the program runs its output is listed live in the Messages window and what is typed goes to its standard input
  (the status line shows the line; Enter sends it, Esc interrupts the program). }
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
  SysUtils, TvPath, Classes, Objects, Drivers, Views, App, MsgBox, WViews, WEditor,
  FpLang, FpDlv, FPConst, FPViews, FPVars, FPUtils, FPCompil, FPIde, FPHelp, FPTools,
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

var
  StdinLine: string = '';
  OutputPending: string = '';

{ the lines the program wrote so far are added to the Messages window }
procedure PumpOutput;
var
  L: TStringList;
  I: Integer;
  Text: string;
begin
  if Session = nil then
    Exit;
  Text := OutputPending + Session.TakeOutput;
  OutputPending := '';
  if Text = '' then
    Exit;
  { an unfinished line waits for its end }
  I := Length(Text);
  while (I > 0) and (Text[I] <> #10) do
    Dec(I);
  OutputPending := Copy(Text, I + 1, MaxInt);
  Text := Copy(Text, 1, I);
  if Text = '' then
    Exit;
  if MessagesWindow = nil then
    Message(TProgram.Application, evCommand, cmToolsMessages, nil);
  L := TStringList.Create;
  try
    L.Text := Text;
    for I := 0 to L.Count - 1 do
      AddToolMessage('', L[I], 0, 0);
  finally
    L.Free;
  end;
  UpdateToolMessages;
end;

{ while the program runs: the output is shown, keys go to its standard input, Esc interrupts it }
function GoIdle: Boolean;
var
  Event: TEvent;
  S: string;
  I: Integer;
begin
  Result := False;
  PumpOutput;
  repeat
    GetKeyEvent(Event);
    if Event.What <> evKeyDown then
      Break;
    if Event.KeyDown.KeyCode = kbEsc then
    begin
      Result := True;
      Break;
    end
    else if Event.KeyDown.KeyCode = kbEnter then
    begin
      Session.SendInput(StdinLine + #10);
      AddToolMessage('', '> ' + StdinLine, 0, 0);
      UpdateToolMessages;
      StdinLine := '';
    end
    else if Event.KeyDown.KeyCode = kbBack then
    begin
      if StdinLine <> '' then
      begin
        I := Length(StdinLine);
        while (I > 1) and ((Ord(StdinLine[I]) and $C0) = $80) do
          Dec(I);
        SetLength(StdinLine, I - 1);
      end;
    end
    else if (Event.KeyDown.TextLength > 0) and (Ord(Event.KeyDown.Text[0]) >= 32) then
    begin
      SetString(S, PChar(@Event.KeyDown.Text[0]), Event.KeyDown.TextLength);
      StdinLine := StdinLine + S;
    end
    else
      Continue;
    SetStatus('Program input (Enter sends, Esc interrupts): ' + StdinLine);
  until False;
end;

{ the windows of watches, of Evaluate and of the call stack read Delve while a session is open }
function HookEval(const Expr: ShortString; out Value: ShortString): Boolean;
var
  V: string;
begin
  Value := '';
  if (Session = nil) or not Session.Alive then
  begin
    Value := 'no program is running';
    Exit(False);
  end;
  if Trim(Expr) = '$locals' then
  begin
    Result := Session.Locals(V);
    V := StringReplace(V, #10, ', ', [rfReplaceAll]);
    if Result and (V = '') then
      V := '(no variables)';
  end
  else
    Result := Session.Evaluate(Expr, V);
  Value := Copy(V, 1, 255);
end;

function HookFrameCount: LongInt;
begin
  if Session = nil then
    Result := 0
  else
    Result := Session.FrameCount;
end;

procedure HookFrame(Index: LongInt; out Name, FileName: ShortString; out Line: LongInt);
var
  F: TDlvFrame;
begin
  F := Session.FrameAt(Index);
  Name := F.Name;
  FileName := F.FileName;
  Line := F.Line;
end;

procedure HookSelect(Index: LongInt);
begin
  if Session <> nil then
    Session.SelectedFrame := Index;
end;

procedure InstallHooks;
begin
  ForeignEval := @HookEval;
  ForeignFrameCount := @HookFrameCount;
  ForeignFrame := @HookFrame;
  ForeignSelectFrame := @HookSelect;
end;

procedure RemoveHooks;
begin
  ForeignEval := nil;
  ForeignFrameCount := nil;
  ForeignFrame := nil;
  ForeignSelectFrame := nil;
  if StackWindow <> nil then
    StackWindow.Update;
  if WatchesCollection <> nil then
    ForeignRereadWatches;        { back to gdb }
end;

procedure ClearDebuggerRows;
  procedure ResetRow(P: PView);
  begin
    if (P <> nil) and (P is TSourceWindow) then
      PSourceWindow(P).Editor.SetLineFlagExclusive(lfDebuggerRow, -1);
  end;
begin
  if TProgram.DeskTop <> nil then
    TProgram.DeskTop.ForEach(@ResetRow);
end;

procedure UpdateMenus(Running: Boolean);
begin
  TView.SetCmdState(CommandSetOf([cmResetDebugger, cmUntilReturn]), Running);
  IDEApp.UpdateRunMenu(Running);
end;

procedure GoDebugEnd;
begin
  RemoveHooks;
  StdinLine := '';
  OutputPending := '';
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
    P := TSourceWindow(Message(TProgram.DeskTop, evBroadcast, cmSearchWindow, nil));
    if P <> nil then
      Result := P.Editor.FileName;
  end;
  if Result = '' then
    Exit;
  Result := PathExpand(Result);
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
      Result := PathDelSep(PathDir(GoFile))
    else
      Result := GoFile;
  finally
    G.Free;
  end;
end;

{ the breakpoints of the list (and one more line, the target of "go to cursor") are given to dlv, file by file; the condition of a
  breakpoint and its ignore count (the first N hits do not stop: dlv's hit condition "> N") go with it }
procedure SyncBreakpoints(const ExtraFile: string; ExtraLine: LongInt);
var
  Files: TStringList;
  Bps: array of TDlvBreakpoint;
  I, J, K: Integer;
  PB: PBreakpoint;
  F: string;
  Dup: Boolean;

  function Wanted(P: PBreakpoint): Boolean;
  begin
    Result := (P.typ = bt_file_line) and (P.state = bs_enabled) and (P.FileName <> nil);
  end;

begin
  Files := TStringList.Create;
  try
    Files.Sorted := True;
    Files.Duplicates := dupIgnore;
    if BreakpointsCollection <> nil then
      for I := 0 to BreakpointsCollection.Count - 1 do
      begin
        PB := BreakpointsCollection.At(I);
        if Wanted(PB) and (LowerCase(PathExt(PB.FileName^)) = '.go') then
          Files.Add(PathExpand(PB.FileName^));
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
      SetLength(Bps, 0);
      if BreakpointsCollection <> nil then
        for J := 0 to BreakpointsCollection.Count - 1 do
        begin
          PB := BreakpointsCollection.At(J);
          if not (Wanted(PB) and (PathExpand(PB.FileName^) = F)) then
            Continue;
          Dup := False;
          for K := 0 to High(Bps) do
            if Bps[K].Line = PB.Line then
              Dup := True;
          if Dup then
            Continue;                     { one breakpoint per line: the first one counts }
          SetLength(Bps, Length(Bps) + 1);
          with Bps[High(Bps)] do
          begin
            Line := PB.Line;
            Condition := Trim(GetStr(PB.Conditions));
            if PB.IgnoreCount > 0 then
              HitCondition := '> ' + IntToStr(PB.IgnoreCount)
            else
              HitCondition := '';
          end;
        end;
      if (F = ExtraFile) and (ExtraLine > 0) then
      begin
        Dup := False;
        for K := 0 to High(Bps) do
          if Bps[K].Line = ExtraLine then
          begin
            { the target of the run to the cursor stops at once: no condition }
            Bps[K].Condition := '';
            Bps[K].HitCondition := '';
            Dup := True;
          end;
        if not Dup then
        begin
          SetLength(Bps, Length(Bps) + 1);
          Bps[High(Bps)].Line := ExtraLine;
          Bps[High(Bps)].Condition := '';
          Bps[High(Bps)].HitCondition := '';
        end;
      end;
      Session.SetBreakpointsEx(F, Bps);
      if Length(Bps) > 0 then
        SyncedFiles.Add(F);
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
  TProgram.DeskTop.Lock;
  W := TryToOpenFile(nil, Session.StopFile, 0, Line, False);
  if W <> nil then
  begin
    W.Editor.SetCurPtr(0, Line);
    W.Editor.SetLineFlagExclusive(lfDebuggerRow, Line);
    W.Editor.TrackCursor(IniCenterDebuggerRow);
    W.SelectInDebugSession;
  end;
  TProgram.DeskTop.UnLock;
end;

procedure Finished(R: TDlvResult);
var
  Code: LongInt;
  Err: string;
begin
  StdinLine := '';
  SetStatus('');
  PumpOutput;
  case R of
    drStopped:
      begin
        ShowStop;
        ForeignRereadWatches;
        if StackWindow <> nil then
          StackWindow.Update;
      end;
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
  Session.OnIdle := @GoIdle;
  ClearToolMessages;
  PushStatus('Starting Delve...');
  try
    if not Session.Start(Tool, 'debug', ProgramOf(GoFile), PathDir(GoFile), GetRunParameters) then
    begin
      PopStatus;
      Finished(drFailed);
      Exit;
    end;
  finally
  end;
  PopStatus;
  UpdateMenus(True);
  InstallHooks;
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
          W := PFPWindow(TProgram.DeskTop.Current);
          if (W <> nil) and (W.ClassType = TSourceWindow) then
          begin
            F := PathExpand(PSourceWindow(W).Editor.FileName);
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
        W := PFPWindow(TProgram.DeskTop.Current);
        if (W <> nil) and (W.ClassType = TSourceWindow) then
        begin
          F := PathExpand(PSourceWindow(W).Editor.FileName);
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
