{ The Delve (dlv) debugger session: a client of the Debug Adapter Protocol (DAP) that "dlv dap" serves on a local TCP port.

  MIT. The unit knows nothing of the screen: the IDE (fpgodbg) starts a session, hands it the breakpoints
  and asks for a step, and gets back where the program stopped. The messages are JSON with a header "Content-Length: N" (the
  protocol of Delve is documented at https://github.com/go-delve/delve/tree/master/Documentation/api/dap).

  The way of a session: start "dlv dap --listen=127.0.0.1:0" (it writes the port it listens on), connect, "initialize", "launch"
  (mode "debug" builds the program with the flags a debugger needs, "exec" runs a built one), wait for the event "initialized",
  "setBreakpoints" for each file, "configurationDone". The program then runs until a "stopped" event (a breakpoint, a step, a
  pause) or until "terminated"; "stackTrace" tells where. The program writes to the output of dlv (a pipe), which
  the session collects. }
{$mode objfpc}{$H+}
unit FpDlv;

interface

uses
  SysUtils, Classes, Process, Sockets, BaseUnix, fpjson, jsonparser;

type
  { what a command that lets the program run came back with }
  TDlvResult = (drStopped, drExited, drFailed);

  { called while the program runs; True asks to interrupt it (the key Esc) }
  TDlvIdleFunc = function: Boolean;

  TDlvSession = class
  private
    FProc: TProcess;
    FSock: LongInt;
    FSeq: LongInt;
    FInBuf: AnsiString;
    FInitialized, FStopped, FTerminated, FPaused: Boolean;
    FThread: Int64;
    FStopFile: string;
    FStopLine: LongInt;
    FStopReason: string;
    FExitCode: LongInt;
    FOutput: AnsiString;
    FError: string;
    FLog: TStringList;
    procedure DrainProcess;
    function ReadMessage(TimeoutMs: LongInt): TJSONObject;
    procedure Handle(Msg: TJSONObject);
    procedure SendRaw(const Body: AnsiString);
    function Request(const Command: string; Args: TJSONObject; out Body: TJSONObject; TimeoutMs: LongInt): Boolean;
    function Wait(TimeoutMs: LongInt): TDlvResult;
    function Resume(const Command: string): TDlvResult;
    procedure ReadStop;
    procedure Fail(const Msg: string);
  public
    { called while the program runs }
    OnIdle: TDlvIdleFunc;
    constructor Create;
    destructor Destroy; override;
    { Tool is the path of dlv, Mode is "debug" or "exec", Prog is a Go file, a package directory or an executable; Cwd is where the program
      runs. The program is built and started but held back until Go is called. False: Error says why }
    function Start(const Tool, Mode, Prog, Cwd, Args: string): Boolean;
    { the breakpoints of one file (the lines are 1 based; none clears the file); the call may be made at any time }
    function SetBreakpoints(const FileName: string; const Lines: array of LongInt): Boolean;
    { lets the program run to the first stop }
    function Go: TDlvResult;
    function Proceed: TDlvResult;
    function StepOver: TDlvResult;
    function StepInto: TDlvResult;
    function StepOut: TDlvResult;
    { the value of an expression in the frame where the program stopped; False when it has none }
    function Evaluate(const Expr: string; out Value: string): Boolean;
    { ends the session and the program }
    procedure Stop;
    function Alive: Boolean;
    property StopFile: string read FStopFile;
    property StopLine: LongInt read FStopLine;
    property StopReason: string read FStopReason;
    property ExitCode: LongInt read FExitCode;
    { what the program wrote so far (taken out when read with TakeOutput) }
    function TakeOutput: AnsiString;
    property Error: string read FError;
    { the lines of the protocol that were seen (for the diagnosis of a failed start) }
    property Log: TStringList read FLog;
  end;

{ the full path of dlv found on the search path or in the directory of the Go tools ($GOBIN, $GOPATH/bin, ~/go/bin); '' when none }
function FindDlv: string;

implementation

const
  StartTimeout = 120000;      { building a program takes its time }
  ReplyTimeout = 30000;
  RunTimeout = 24 * 3600 * 1000;

function FileInPath(const Name: string): string;
var
  Paths: TStringList;
  I: Integer;
begin
  Result := '';
  Paths := TStringList.Create;
  try
    Paths.Delimiter := PathSeparator;
    Paths.StrictDelimiter := True;
    Paths.DelimitedText := GetEnvironmentVariable('PATH');
    for I := 0 to Paths.Count - 1 do
      if (Paths[I] <> '') and FileExists(IncludeTrailingPathDelimiter(Paths[I]) + Name) then
        Exit(IncludeTrailingPathDelimiter(Paths[I]) + Name);
  finally
    Paths.Free;
  end;
end;

function FindDlv: string;
var
  D: string;
begin
  Result := FileInPath('dlv');
  if Result <> '' then
    Exit;
  D := GetEnvironmentVariable('GOBIN');
  if (D <> '') and FileExists(IncludeTrailingPathDelimiter(D) + 'dlv') then
    Exit(IncludeTrailingPathDelimiter(D) + 'dlv');
  D := GetEnvironmentVariable('GOPATH');
  if D = '' then
    D := IncludeTrailingPathDelimiter(GetEnvironmentVariable('HOME')) + 'go';
  D := IncludeTrailingPathDelimiter(D) + 'bin' + PathDelim + 'dlv';
  if FileExists(D) then
    Exit(D);
end;

function Str(O: TJSONObject; const Name: string): string;
var
  D: TJSONData;
begin
  Result := '';
  if O = nil then
    Exit;
  D := O.Find(Name);
  if (D <> nil) and (D.JSONType = jtString) then
    Result := D.AsString;
end;

function Num(O: TJSONObject; const Name: string; Default: Int64): Int64;
var
  D: TJSONData;
begin
  Result := Default;
  if O = nil then
    Exit;
  D := O.Find(Name);
  if (D <> nil) and (D.JSONType = jtNumber) then
    Result := D.AsInt64;
end;

function Obj(O: TJSONObject; const Name: string): TJSONObject;
var
  D: TJSONData;
begin
  Result := nil;
  if O = nil then
    Exit;
  D := O.Find(Name);
  if (D <> nil) and (D.JSONType = jtObject) then
    Result := TJSONObject(D);
end;

{ --- the session ---------------------------------------------------------------------------------------------------------- }

constructor TDlvSession.Create;
begin
  inherited Create;
  FSock := -1;
  FLog := TStringList.Create;
end;

destructor TDlvSession.Destroy;
begin
  Stop;
  FLog.Free;
  inherited Destroy;
end;

procedure TDlvSession.Fail(const Msg: string);
begin
  if FError = '' then
    FError := Msg;
end;

procedure TDlvSession.DrainProcess;
var
  Buf: array[0..4095] of Byte;
  N: LongInt;
  Chunk: AnsiString;
begin
  { the program writes to the output of dlv (the pipe), which is also where dlv writes its own words; an unread pipe would stop it }
  if (FProc = nil) or (FProc.Output = nil) then
    Exit;
  while FProc.Output.NumBytesAvailable > 0 do
  begin
    N := FProc.Output.Read(Buf, SizeOf(Buf));
    if N <= 0 then
      Break;
    SetString(Chunk, PChar(@Buf), N);
    FOutput := FOutput + Chunk;
  end;
end;

procedure TDlvSession.SendRaw(const Body: AnsiString);
var
  Msg: AnsiString;
  Sent, N: LongInt;
begin
  if FSock < 0 then
    Exit;
  if FLog.Count < 400 then
    FLog.Add('> ' + Copy(Body, 1, 200));
  Msg := 'Content-Length: ' + IntToStr(Length(Body)) + #13#10#13#10 + Body;
  Sent := 0;
  while Sent < Length(Msg) do
  begin
    N := fpsend(FSock, @Msg[Sent + 1], Length(Msg) - Sent, MSG_NOSIGNAL);
    if N <= 0 then
    begin
      Fail('the connection to dlv is lost');
      Exit;
    end;
    Inc(Sent, N);
  end;
end;

function TDlvSession.ReadMessage(TimeoutMs: LongInt): TJSONObject;
var
  Deadline: QWord;
  P, Len: LongInt;
  Head: string;
  Buf: array[0..8191] of Byte;
  N: LongInt;
  FDs: TFDSet;
  Data: TJSONData;
  Slice: LongInt;

  function Frame: Boolean;
  var
    HP, LP: LongInt;
    Line: string;
  begin
    Result := False;
    HP := Pos(#13#10#13#10, FInBuf);
    if HP = 0 then
      Exit;
    Head := Copy(FInBuf, 1, HP - 1);
    LP := Pos('content-length:', LowerCase(Head));
    if LP = 0 then
    begin
      Fail('a message of dlv has no length');
      Exit;
    end;
    Line := Copy(Head, LP + 15, MaxInt);
    P := Pos(#13, Line);
    if P > 0 then
      Line := Copy(Line, 1, P - 1);
    Len := StrToIntDef(Trim(Line), -1);
    if (Len < 0) or (Length(FInBuf) < HP + 3 + Len) then
      Exit;
    Head := Copy(FInBuf, HP + 4, Len);
    Delete(FInBuf, 1, HP + 3 + Len);
    Result := True;
  end;

begin
  Result := nil;
  Deadline := GetTickCount64 + QWord(TimeoutMs);
  repeat
    if Frame then
    begin
      try
        Data := GetJSON(Head);
      except
        Data := nil;
      end;
      if (Data <> nil) and (Data.JSONType = jtObject) then
      begin
        if FLog.Count < 400 then
          FLog.Add(Copy(Head, 1, 300));
        Exit(TJSONObject(Data));
      end;
      Data.Free;
      Continue;
    end;
    if (FError <> '') or (FSock < 0) then
      Exit;
    Slice := 50;
    fpFD_ZERO(FDs);
    fpFD_SET(FSock, FDs);
    N := fpSelect(FSock + 1, @FDs, nil, nil, Slice);
    if N > 0 then
    begin
      N := fprecv(FSock, @Buf, SizeOf(Buf), 0);
      if N <= 0 then
      begin
        { the server closed the connection: the end of the session }
        FTerminated := True;
        fpshutdown(FSock, 2);
        CloseSocket(FSock);
        FSock := -1;
        Exit;
      end;
      SetString(Head, PChar(@Buf), N);
      FInBuf := FInBuf + Head;
    end
    else
    begin
      DrainProcess;
      if (FProc <> nil) and not FProc.Running and (FInBuf = '') then
      begin
        FTerminated := True;
        Fail('dlv has ended');
        Exit;
      end;
      if Assigned(OnIdle) and OnIdle() and not FPaused and (FSock >= 0) then
      begin
        FPaused := True;
        FSeq := FSeq + 1;
        SendRaw('{"seq":' + IntToStr(FSeq) + ',"type":"request","command":"pause","arguments":{"threadId":' +
          IntToStr(FThread) + '}}');
      end;
    end;
  until GetTickCount64 > Deadline;
end;

procedure TDlvSession.Handle(Msg: TJSONObject);
var
  Ev: string;
  B: TJSONObject;
begin
  if Str(Msg, 'type') <> 'event' then
    Exit;
  Ev := Str(Msg, 'event');
  B := Obj(Msg, 'body');
  if Ev = 'initialized' then
    FInitialized := True
  else if Ev = 'stopped' then
  begin
    FStopped := True;
    FStopReason := Str(B, 'reason');
    FThread := Num(B, 'threadId', FThread);
  end
  else if Ev = 'exited' then
    FExitCode := Num(B, 'exitCode', 0)
  else if Ev = 'terminated' then
    FTerminated := True
  ;                               { the "output" events are dlv's own words (Building ...): not the program's }
end;

function TDlvSession.Request(const Command: string; Args: TJSONObject; out Body: TJSONObject; TimeoutMs: LongInt): Boolean;
var
  R: TJSONObject;
  Msg: TJSONObject;
  Seq: LongInt;
  Deadline: QWord;
begin
  Result := False;
  Body := nil;
  Inc(FSeq);
  Seq := FSeq;
  Msg := TJSONObject.Create;
  try
    Msg.Add('seq', Seq);
    Msg.Add('type', 'request');
    Msg.Add('command', Command);
    if Args <> nil then
      Msg.Add('arguments', Args)      { Msg owns Args now }
    else
      Msg.Add('arguments', TJSONObject.Create);
    SendRaw(Msg.AsJSON);
  finally
    Msg.Free;
  end;
  Deadline := GetTickCount64 + QWord(TimeoutMs);
  repeat
    R := ReadMessage(200);
    if R = nil then
    begin
      if (FError <> '') or (FSock < 0) then
        Exit;
      Continue;
    end;
    try
      if (Str(R, 'type') = 'response') and (Num(R, 'request_seq', -1) = Seq) then
      begin
        if R.Find('success') <> nil then
          Result := R.Booleans['success'];
        if Result then
        begin
          if Obj(R, 'body') <> nil then
            Body := TJSONObject(Obj(R, 'body').Clone);
        end
        else
          Fail(Command + ': ' + Str(R, 'message'));
        Exit;
      end;
      Handle(R);
    finally
      R.Free;
    end;
  until GetTickCount64 > Deadline;
  Fail(Command + ': no answer from dlv');
end;

function TDlvSession.Start(const Tool, Mode, Prog, Cwd, Args: string): Boolean;
var
  Deadline: QWord;
  Line, Addr: string;
  Port: LongInt;
  P: LongInt;
  A: TSockAddr;
  A1, Body: TJSONObject;
  ArgList: TJSONArray;
  L: TStringList;
  I: Integer;
  Buf: array[0..1023] of Byte;
  N: LongInt;
  R: TJSONObject;
begin
  Result := False;
  FError := '';
  FProc := TProcess.Create(nil);
  FProc.Executable := Tool;
  FProc.Parameters.Add('dap');
  FProc.Parameters.Add('--listen=127.0.0.1:0');
  FProc.CurrentDirectory := Cwd;
  FProc.Options := [poUsePipes, poStderrToOutput, poNoConsole];
  try
    FProc.Execute;
  except
    on E: Exception do
    begin
      Fail('cannot run ' + Tool + ': ' + E.Message);
      Exit;
    end;
  end;
  FProc.CloseInput;               { the program reads nothing from the keyboard of the IDE }
  { the first line says where dlv listens: "DAP server listening at: 127.0.0.1:41207" }
  Deadline := GetTickCount64 + 20000;
  Line := '';
  Port := 0;
  while (Port = 0) and (GetTickCount64 < Deadline) do
  begin
    if FProc.Output.NumBytesAvailable > 0 then
    begin
      N := FProc.Output.Read(Buf, SizeOf(Buf));
      if N > 0 then
      begin
        SetString(Addr, PChar(@Buf), N);
        Line := Line + Addr;
        P := Pos('listening at:', Line);
        if P > 0 then
        begin
          Addr := Trim(Copy(Line, P + 13, MaxInt));
          P := Pos(#10, Addr);
          if P > 0 then
            Addr := Trim(Copy(Addr, 1, P - 1));
          P := LastDelimiter(':', Addr);
          if P > 0 then
            Port := StrToIntDef(Copy(Addr, P + 1, MaxInt), 0);
        end;
      end;
    end
    else if not FProc.Running then
      Break
    else
      Sleep(10);
  end;
  FLog.Add('dlv: ' + Trim(Line));
  if Port = 0 then
  begin
    Fail('dlv did not start: ' + Trim(Line));
    Exit;
  end;
  FSock := fpsocket(AF_INET, SOCK_STREAM, 0);
  if FSock < 0 then
  begin
    Fail('no socket');
    Exit;
  end;
  FillChar(A, SizeOf(A), 0);
  A.sin_family := AF_INET;
  A.sin_port := htons(Port);
  A.sin_addr.s_addr := htonl($7F000001);
  if fpconnect(FSock, @A, SizeOf(A)) <> 0 then
  begin
    Fail('cannot connect to dlv');
    Exit;
  end;
  A1 := TJSONObject.Create;
  A1.Add('clientID', 'fpide');
  A1.Add('adapterID', 'go');
  A1.Add('linesStartAt1', True);
  A1.Add('columnsStartAt1', True);
  A1.Add('pathFormat', 'path');
  if not Request('initialize', A1, Body, ReplyTimeout) then
    Exit;
  Body.Free;
  A1 := TJSONObject.Create;
  A1.Add('request', 'launch');
  A1.Add('mode', Mode);
  A1.Add('program', Prog);
  A1.Add('cwd', Cwd);
  A1.Add('stopOnEntry', False);
  A1.Add('stackTraceDepth', 8);
  ArgList := TJSONArray.Create;
  L := TStringList.Create;
  try
    L.Delimiter := ' ';
    L.StrictDelimiter := False;
    L.DelimitedText := Args;
    for I := 0 to L.Count - 1 do
      ArgList.Add(L[I]);
  finally
    L.Free;
  end;
  A1.Add('args', ArgList);
  { the answer to "launch" comes when the program is built; the server may send "initialized" before or after it }
  if not Request('launch', A1, Body, StartTimeout) then
    Exit;
  Body.Free;
  Deadline := GetTickCount64 + 20000;
  while not FInitialized and (FError = '') and not FTerminated and (GetTickCount64 < Deadline) do
  begin
    R := ReadMessage(200);
    if R <> nil then
    begin
      Handle(R);
      R.Free;
    end;
  end;
  if not FInitialized then
  begin
    Fail('dlv did not get ready');
    Exit;
  end;
  Result := FError = '';
end;

function TDlvSession.SetBreakpoints(const FileName: string; const Lines: array of LongInt): Boolean;
var
  A, Src: TJSONObject;
  Arr, Bps: TJSONArray;
  B, Resp: TJSONObject;
  I: Integer;
begin
  A := TJSONObject.Create;
  Src := TJSONObject.Create;
  Src.Add('path', FileName);
  A.Add('source', Src);
  Arr := TJSONArray.Create;
  Bps := TJSONArray.Create;
  for I := Low(Lines) to High(Lines) do
  begin
    B := TJSONObject.Create;
    B.Add('line', Lines[I]);
    Bps.Add(B);
    Arr.Add(Lines[I]);
  end;
  A.Add('breakpoints', Bps);
  A.Add('lines', Arr);
  Result := Request('setBreakpoints', A, Resp, ReplyTimeout);
  Resp.Free;
end;

procedure TDlvSession.ReadStop;
var
  A, Resp, F, S: TJSONObject;
  Frames: TJSONArray;
begin
  FStopFile := '';
  FStopLine := 0;
  A := TJSONObject.Create;
  A.Add('threadId', FThread);
  A.Add('startFrame', 0);
  A.Add('levels', 1);
  if not Request('stackTrace', A, Resp, ReplyTimeout) then
  begin
    FError := '';                 { a program that cannot tell where it is stays stopped }
    Exit;
  end;
  if (Resp <> nil) and (Resp.Find('stackFrames') <> nil) and (Resp.Find('stackFrames').JSONType = jtArray) then
  begin
    Frames := TJSONArray(Resp.Find('stackFrames'));
    if (Frames.Count > 0) and (Frames[0].JSONType = jtObject) then
    begin
      F := TJSONObject(Frames[0]);
      S := Obj(F, 'source');
      FStopFile := Str(S, 'path');
      FStopLine := Num(F, 'line', 0);
    end;
  end;
  Resp.Free;
end;

function TDlvSession.Wait(TimeoutMs: LongInt): TDlvResult;
var
  R: TJSONObject;
  Deadline: QWord;
begin
  Deadline := GetTickCount64 + QWord(TimeoutMs);
  FStopped := False;
  while True do
  begin
    R := ReadMessage(200);
    if R <> nil then
    begin
      Handle(R);
      R.Free;
    end;
    if FStopped then
    begin
      FPaused := False;
      ReadStop;
      Exit(drStopped);
    end;
    if FTerminated then
    begin
      Sleep(50);                  { what the program wrote last is still in the pipe }
      DrainProcess;
      Exit(drExited);
    end;
    if (FError <> '') or (GetTickCount64 > Deadline) then
    begin
      Fail('no more answer from dlv');
      Exit(drFailed);
    end;
  end;
end;

function TDlvSession.Go: TDlvResult;
var
  Body: TJSONObject;
begin
  if not Request('configurationDone', nil, Body, ReplyTimeout) then
    Exit(drFailed);
  Body.Free;
  Result := Wait(RunTimeout);
end;

function TDlvSession.Resume(const Command: string): TDlvResult;
var
  A, Body: TJSONObject;
begin
  if (FSock < 0) or FTerminated then
    Exit(drExited);
  A := TJSONObject.Create;
  A.Add('threadId', FThread);
  if not Request(Command, A, Body, ReplyTimeout) then
    Exit(drFailed);
  Body.Free;
  Result := Wait(RunTimeout);
end;

function TDlvSession.Proceed: TDlvResult;
begin
  Result := Resume('continue');
end;

function TDlvSession.StepOver: TDlvResult;
begin
  Result := Resume('next');
end;

function TDlvSession.StepInto: TDlvResult;
begin
  Result := Resume('stepIn');
end;

function TDlvSession.StepOut: TDlvResult;
begin
  Result := Resume('stepOut');
end;

function TDlvSession.Evaluate(const Expr: string; out Value: string): Boolean;
var
  A, Resp: TJSONObject;
  St, Body: TJSONObject;
  Frames: TJSONArray;
  FrameId: Int64;
begin
  Result := False;
  Value := '';
  if (FSock < 0) or FTerminated then
    Exit;
  FrameId := 0;
  A := TJSONObject.Create;
  A.Add('threadId', FThread);
  A.Add('startFrame', 0);
  A.Add('levels', 1);
  if not Request('stackTrace', A, St, ReplyTimeout) then
    Exit;
  if (St <> nil) and (St.Find('stackFrames') <> nil) and (St.Find('stackFrames').JSONType = jtArray) then
  begin
    Frames := TJSONArray(St.Find('stackFrames'));
    if (Frames.Count > 0) and (Frames[0].JSONType = jtObject) then
      FrameId := Num(TJSONObject(Frames[0]), 'id', 0);
  end;
  St.Free;
  A := TJSONObject.Create;
  A.Add('expression', Expr);
  A.Add('frameId', FrameId);
  A.Add('context', 'watch');
  Body := nil;
  Resp := nil;
  Result := Request('evaluate', A, Resp, ReplyTimeout);
  if Result then
    Value := Str(Resp, 'result')
  else
    FError := '';
  Resp.Free;
  Body.Free;
end;

procedure TDlvSession.Stop;
var
  A, Body: TJSONObject;
  I: Integer;
begin
  if (FSock >= 0) and not FTerminated and (FError = '') then
  begin
    A := TJSONObject.Create;
    A.Add('terminateDebuggee', True);
    Request('disconnect', A, Body, 5000);
    Body.Free;
  end;
  if FSock >= 0 then
  begin
    fpshutdown(FSock, 2);
    CloseSocket(FSock);
    FSock := -1;
  end;
  if FProc <> nil then
  begin
    for I := 1 to 50 do
      if FProc.Running then
        Sleep(20);
    if FProc.Running then
      FProc.Terminate(0);
    FreeAndNil(FProc);
  end;
  FTerminated := True;
end;

function TDlvSession.Alive: Boolean;
begin
  Result := (FSock >= 0) and not FTerminated;
end;

function TDlvSession.TakeOutput: AnsiString;
begin
  DrainProcess;
  Result := FOutput;
  FOutput := '';
end;

end.
