{ The Delve (dlv) debugger session: a client of the Debug Adapter Protocol (DAP) that "dlv dap" serves on a local TCP port.

  MIT. The unit knows nothing of the screen: the IDE (fpgodbg) starts a session, hands it the breakpoints
  and asks for a step, and gets back where the program stopped. The messages are JSON with a header "Content-Length: N" (the
  protocol of Delve is documented at https://github.com/go-delve/delve/tree/master/Documentation/api/dap).

  The way of a session: start "dlv dap --listen=127.0.0.1:0" (it writes the port it listens on), connect, "initialize", "launch"
  (mode "debug" builds the program with the flags a debugger needs, "exec" runs a built one), wait for the event "initialized",
  "setBreakpoints" for each file, "configurationDone". The program then runs until a "stopped" event (a breakpoint, a step, a
  pause) or until "terminated"; "stackTrace" tells where. The program writes to the output of dlv (a pipe), which
  the session collects.

  Ownership (Safe Pascal, step 4.2a of safe/FPIDE-ADOPTION.md): the process of dlv, the log and every JSON document that
  a function holds or returns belong to a TOwned; nothing here is freed by hand. A JSON node that is added to a container
  belongs to the container (the root of a document is the only thing that is owned). The only raw pointer type in the unit
  is PChar in the three SetString calls that turn the bytes of a read into a string; each has an // UNSAFE: line. }
{$mode objfpc}{$H+}
{$WARN SYMBOL_DEPRECATED ERROR}
unit FpDlv;

interface

uses
  SysUtils, Classes, Process, Sockets, BaseUnix, fpjson, jsonparser, TvPath, Safe;

type
  { what a command that lets the program run came back with }
  TDlvResult = (drStopped, drExited, drFailed);

  { called while the program runs; True asks to interrupt it (the key Esc) }
  TDlvIdleFunc = function: Boolean;

  { a breakpoint of a file: the line (1 based), an expression that must be true for the stop, a hit condition of dlv ("> 2" stops from the third hit on) }
  TDlvBreakpoint = record
    Line: LongInt;
    Condition: string;
    HitCondition: string;
  end;

  { one frame of the call stack }
  TDlvFrame = record
    Id: Int64;
    Name: string;
    FileName: string;
    Line: LongInt;
  end;

  TProcessBox = specialize TOwned<TProcess>;
  TStringListBox = specialize TOwned<TStringList>;
  TJSONBox = specialize TOwned<TJSONObject>;
  TJSONDataBox = specialize TOwned<TJSONData>;

  TDlvSession = class
  private
    FProcBox: TProcessBox;
    FProc: TProcess;            { a borrow of FProcBox.Get; nil when there is no process }
    FLogBox: TStringListBox;
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
    FLog: TStringList;          { a borrow of FLogBox.Get }
    FFrames: array of TDlvFrame;
    FSelected: LongInt;
    procedure DrainProcess;
    function ReadMessage(TimeoutMs: LongInt): TJSONBox;
    procedure Handle(Msg: TJSONObject);
    procedure SendRaw(const Body: AnsiString);
    { Args stays with the caller (it is copied into the message; an empty box is "no arguments"); Body is the body of the answer, empty when it has none }
    function Request(const Command: string; const Args: TJSONBox; out Body: TJSONBox; TimeoutMs: LongInt): Boolean;
    function Wait(TimeoutMs: LongInt): TDlvResult;
    function Resume(const Command: string): TDlvResult;
    procedure ReadStop;
    procedure Fail(const Msg: string);
    function SelectedFrameId: Int64;
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
    { the same with a condition and a hit condition for each }
    function SetBreakpointsEx(const FileName: string; const Bps: array of TDlvBreakpoint): Boolean;
    { a breakpoint on a function, for example main.main (the program held back stops in it) }
    function SetFunctionBreakpoint(const Name: string): Boolean;
    { lets the program run to the first stop }
    function Go: TDlvResult;
    function Proceed: TDlvResult;
    function StepOver: TDlvResult;
    function StepInto: TDlvResult;
    function StepOut: TDlvResult;
    { the value of an expression in the selected frame (the top one after a stop); False when it has none (Value is the reason then) }
    function Evaluate(const Expr: string; out Value: string): Boolean;
    { the arguments and local variables of the selected frame as "name = value" lines }
    function Locals(out Text: string): Boolean;
    { the call stack of the stop (the frames are read at each stop) and the frame that expressions are evaluated in }
    function FrameCount: LongInt;
    function FrameAt(Index: LongInt): TDlvFrame;
    property SelectedFrame: LongInt read FSelected write FSelected;
    { text for the keyboard of the program (its standard input); a line needs its end of line }
    procedure SendInput(const S: AnsiString);
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
  MaxFrames = 20;

function FileInPath(const Name: string): string;
var
  PathsBox: TStringListBox;
  Paths: TStringList;
  I: Integer;
begin
  Result := '';
  PathsBox := TStringListBox.Own(TStringList.Create);
  Paths := PathsBox.Get;
  Paths.Delimiter := PathSeparator;
  Paths.StrictDelimiter := True;
  Paths.DelimitedText := GetEnvironmentVariable('PATH');
  for I := 0 to Paths.Count - 1 do
    if (Paths[I] <> '') and FileExists(PathJoin(Paths[I], Name)) then
      Exit(PathJoin(Paths[I], Name));
end;

function FindDlv: string;
var
  D: string;
begin
  Result := FileInPath('dlv');
  if Result <> '' then
    Exit;
  D := GetEnvironmentVariable('GOBIN');
  if (D <> '') and FileExists(PathJoin(D, 'dlv')) then
    Exit(PathJoin(D, 'dlv'));
  D := GetEnvironmentVariable('GOPATH');
  if D = '' then
    D := PathJoin(GetEnvironmentVariable('HOME'), 'go');
  D := PathJoin(PathJoin(D, 'bin'), 'dlv');
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
  FLogBox := TStringListBox.Own(TStringList.Create);
  FLog := FLogBox.Get;
end;

destructor TDlvSession.Destroy;
begin
  WriteLn('DIAG destroy begin ', SafeLiveCount);
  Stop;
  WriteLn('DIAG after Stop ', SafeLiveCount);
  FLogBox.Reset;
  FLog := nil;
  WriteLn('DIAG after log ', SafeLiveCount);
  inherited Destroy;
  WriteLn('DIAG after inherited ', SafeLiveCount);
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
    // UNSAFE: Buf holds the N bytes that Read has just put there; SetString copies exactly N of them
    SetString(Chunk, System.PChar(@Buf), N);
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

function TDlvSession.ReadMessage(TimeoutMs: LongInt): TJSONBox;
var
  Deadline: QWord;
  P, Len: LongInt;
  Head: string;
  Buf: array[0..8191] of Byte;
  N: LongInt;
  FDs: TFDSet;
  Data: TJSONData;
  Junk: TJSONDataBox;
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
        Exit(TJSONBox.Own(TJSONObject(Data)));
      end;
      { a message that is not an object is dropped }
      Junk := TJSONDataBox.Own(Data);
      Junk.Reset;
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
      // UNSAFE: Buf holds the N bytes that fprecv has just put there; SetString copies exactly N of them
      SetString(Head, System.PChar(@Buf), N);
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

function TDlvSession.Request(const Command: string; const Args: TJSONBox; out Body: TJSONBox; TimeoutMs: LongInt): Boolean;
var
  R: TJSONBox;
  Msg: TJSONBox;
  Seq: LongInt;
  Deadline: QWord;
begin
  Result := False;
  Body.Reset;
  Inc(FSeq);
  Seq := FSeq;
  Msg := TJSONBox.Own(TJSONObject.Create);
  Msg.Get.Add('seq', Seq);
  Msg.Get.Add('type', 'request');
  Msg.Get.Add('command', Command);
  if not Args.IsEmpty then
    Msg.Get.Add('arguments', Args.Get.Clone)      { the copy belongs to Msg }
  else
    Msg.Get.Add('arguments', TJSONObject.Create);
  SendRaw(Msg.Get.AsJSON);
  Msg.Reset;
  Deadline := GetTickCount64 + QWord(TimeoutMs);
  repeat
    R := ReadMessage(200);
    if R.IsEmpty then
    begin
      if (FError <> '') or (FSock < 0) then
        Exit;
      Continue;
    end;
    if (Str(R.Get, 'type') = 'response') and (Num(R.Get, 'request_seq', -1) = Seq) then
    begin
      if R.Get.Find('success') <> nil then
        Result := R.Get.Booleans['success'];
      if Result then
      begin
        if Obj(R.Get, 'body') <> nil then
          Body := TJSONBox.Own(TJSONObject(Obj(R.Get, 'body').Clone));
      end
      else if Str(Obj(Obj(R.Get, 'body'), 'error'), 'format') <> '' then
        Fail(Command + ': ' + Str(Obj(Obj(R.Get, 'body'), 'error'), 'format'))     { the build output is in it }
      else
        Fail(Command + ': ' + Str(R.Get, 'message'));
      Exit;
    end;
    Handle(R.Get);
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
  A1, Body: TJSONBox;
  ArgList: TJSONArray;
  LBox: TStringListBox;
  L: TStringList;
  I: Integer;
  Buf: array[0..1023] of Byte;
  N: LongInt;
  R: TJSONBox;
begin
  Result := False;
  FError := '';
  FProcBox := TProcessBox.Own(TProcess.Create(nil));
  FProc := FProcBox.Get;
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
  { the input of dlv stays open: it is the standard input of the program (SendInput) }
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
        // UNSAFE: Buf holds the N bytes that Read has just put there; SetString copies exactly N of them
        SetString(Addr, System.PChar(@Buf), N);
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
  A := Default(TSockAddr);
  A.sin_family := AF_INET;
  A.sin_port := htons(Port);
  A.sin_addr.s_addr := htonl($7F000001);
  if fpconnect(FSock, @A, SizeOf(A)) <> 0 then
  begin
    Fail('cannot connect to dlv');
    Exit;
  end;
  A1 := TJSONBox.Own(TJSONObject.Create);
  A1.Get.Add('clientID', 'fpide');
  A1.Get.Add('adapterID', 'go');
  A1.Get.Add('linesStartAt1', True);
  A1.Get.Add('columnsStartAt1', True);
  A1.Get.Add('pathFormat', 'path');
  if not Request('initialize', A1, Body, ReplyTimeout) then
    Exit;
  A1 := TJSONBox.Own(TJSONObject.Create);
  A1.Get.Add('request', 'launch');
  A1.Get.Add('mode', Mode);
  A1.Get.Add('program', Prog);
  A1.Get.Add('cwd', Cwd);
  A1.Get.Add('stopOnEntry', False);
  A1.Get.Add('stackTraceDepth', MaxFrames);
  ArgList := TJSONArray.Create;
  A1.Get.Add('args', ArgList);              { A1 owns the list now }
  LBox := TStringListBox.Own(TStringList.Create);
  L := LBox.Get;
  L.Delimiter := ' ';
  L.StrictDelimiter := False;
  L.DelimitedText := Args;
  for I := 0 to L.Count - 1 do
    ArgList.Add(L[I]);
  { the answer to "launch" comes when the program is built; the server may send "initialized" before or after it }
  if not Request('launch', A1, Body, StartTimeout) then
    Exit;
  Deadline := GetTickCount64 + 20000;
  while not FInitialized and (FError = '') and not FTerminated and (GetTickCount64 < Deadline) do
  begin
    R := ReadMessage(200);
    if not R.IsEmpty then
      Handle(R.Get);
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
  B: array of TDlvBreakpoint;
  I: Integer;
begin
  SetLength(B, Length(Lines));
  for I := 0 to High(Lines) do
  begin
    B[I].Line := Lines[I];
    B[I].Condition := '';
    B[I].HitCondition := '';
  end;
  Result := SetBreakpointsEx(FileName, B);
end;

function TDlvSession.SetBreakpointsEx(const FileName: string; const Bps: array of TDlvBreakpoint): Boolean;
var
  A, Resp: TJSONBox;
  Src, B: TJSONObject;
  Arr, List: TJSONArray;
  I: Integer;
begin
  A := TJSONBox.Own(TJSONObject.Create);
  Src := TJSONObject.Create;
  A.Get.Add('source', Src);                 { A owns what is added to it }
  Src.Add('path', FileName);
  List := TJSONArray.Create;
  A.Get.Add('breakpoints', List);
  Arr := TJSONArray.Create;
  A.Get.Add('lines', Arr);
  for I := Low(Bps) to High(Bps) do
  begin
    B := TJSONObject.Create;
    List.Add(B);
    B.Add('line', Bps[I].Line);
    if Bps[I].Condition <> '' then
      B.Add('condition', Bps[I].Condition);
    if Bps[I].HitCondition <> '' then
      B.Add('hitCondition', Bps[I].HitCondition);
    Arr.Add(Bps[I].Line);
  end;
  Result := Request('setBreakpoints', A, Resp, ReplyTimeout);
end;

function TDlvSession.SetFunctionBreakpoint(const Name: string): Boolean;
var
  A, Resp: TJSONBox;
  B: TJSONObject;
  Bps: TJSONArray;
begin
  A := TJSONBox.Own(TJSONObject.Create);
  Bps := TJSONArray.Create;
  A.Get.Add('breakpoints', Bps);            { A owns what is added to it }
  B := TJSONObject.Create;
  Bps.Add(B);
  B.Add('name', Name);
  Result := Request('setFunctionBreakpoints', A, Resp, ReplyTimeout);
end;

procedure TDlvSession.ReadStop;
var
  A, Resp: TJSONBox;
  F, S: TJSONObject;
  Frames: TJSONArray;
  I: Integer;
begin
  FStopFile := '';
  FStopLine := 0;
  SetLength(FFrames, 0);
  FSelected := 0;
  A := TJSONBox.Own(TJSONObject.Create);
  A.Get.Add('threadId', FThread);
  A.Get.Add('startFrame', 0);
  A.Get.Add('levels', MaxFrames);
  if not Request('stackTrace', A, Resp, ReplyTimeout) then
  begin
    FError := '';                 { a program that cannot tell where it is stays stopped }
    Exit;
  end;
  if (not Resp.IsEmpty) and (Resp.Get.Find('stackFrames') <> nil) and (Resp.Get.Find('stackFrames').JSONType = jtArray) then
  begin
    Frames := TJSONArray(Resp.Get.Find('stackFrames'));
    for I := 0 to Frames.Count - 1 do
      if Frames[I].JSONType = jtObject then
      begin
        F := TJSONObject(Frames[I]);
        S := Obj(F, 'source');
        SetLength(FFrames, Length(FFrames) + 1);
        with FFrames[High(FFrames)] do
        begin
          Id := Num(F, 'id', 0);
          Name := Str(F, 'name');
          FileName := Str(S, 'path');
          Line := Num(F, 'line', 0);
        end;
      end;
    if Length(FFrames) > 0 then
    begin
      FStopFile := FFrames[0].FileName;
      FStopLine := FFrames[0].Line;
    end;
  end;
end;

function TDlvSession.FrameCount: LongInt;
begin
  Result := Length(FFrames);
end;

function TDlvSession.FrameAt(Index: LongInt): TDlvFrame;
begin
  Result := Default(TDlvFrame);
  if (Index >= 0) and (Index < Length(FFrames)) then
    Result := FFrames[Index];
end;

function TDlvSession.Wait(TimeoutMs: LongInt): TDlvResult;
var
  R: TJSONBox;
  Deadline: QWord;
begin
  Deadline := GetTickCount64 + QWord(TimeoutMs);
  FStopped := False;
  while True do
  begin
    R := ReadMessage(200);
    if not R.IsEmpty then
      Handle(R.Get);
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
  NoArgs, Body: TJSONBox;
begin
  if not Request('configurationDone', NoArgs, Body, ReplyTimeout) then
    Exit(drFailed);
  Result := Wait(RunTimeout);
end;

function TDlvSession.Resume(const Command: string): TDlvResult;
var
  A, Body: TJSONBox;
begin
  if (FSock < 0) or FTerminated then
    Exit(drExited);
  A := TJSONBox.Own(TJSONObject.Create);
  A.Get.Add('threadId', FThread);
  if not Request(Command, A, Body, ReplyTimeout) then
    Exit(drFailed);
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

function TDlvSession.SelectedFrameId: Int64;
begin
  Result := 0;
  if (FSelected >= 0) and (FSelected < Length(FFrames)) then
    Result := FFrames[FSelected].Id
  else if Length(FFrames) > 0 then
    Result := FFrames[0].Id;
end;

function TDlvSession.Evaluate(const Expr: string; out Value: string): Boolean;
var
  A, Resp: TJSONBox;
begin
  Result := False;
  Value := '';
  if (FSock < 0) or FTerminated then
    Exit;
  A := TJSONBox.Own(TJSONObject.Create);
  A.Get.Add('expression', Expr);
  A.Get.Add('frameId', SelectedFrameId);
  A.Get.Add('context', 'watch');
  Result := Request('evaluate', A, Resp, ReplyTimeout);
  if Result then
  begin
    if not Resp.IsEmpty then
      Value := Str(Resp.Get, 'result');
  end
  else
  begin
    Value := FError;              { "evaluate: could not find symbol value for x": the reason is the value of a watch that has none }
    if Pos('evaluate: ', Value) = 1 then
      Delete(Value, 1, 10);
    FError := '';
  end;
end;

function TDlvSession.Locals(out Text: string): Boolean;
var
  A, Resp, R2: TJSONBox;
  Sc, V: TJSONObject;
  Scopes, Vars: TJSONArray;
  I, J: Integer;
  Ref: Int64;
begin
  Result := False;
  Text := '';
  if (FSock < 0) or FTerminated then
    Exit;
  A := TJSONBox.Own(TJSONObject.Create);
  A.Get.Add('frameId', SelectedFrameId);
  if not Request('scopes', A, Resp, ReplyTimeout) then
  begin
    FError := '';
    Exit;
  end;
  Result := True;
  if (not Resp.IsEmpty) and (Resp.Get.Find('scopes') <> nil) and (Resp.Get.Find('scopes').JSONType = jtArray) then
  begin
    Scopes := TJSONArray(Resp.Get.Find('scopes'));
    for I := 0 to Scopes.Count - 1 do
    begin
      if Scopes[I].JSONType <> jtObject then
        Continue;
      Sc := TJSONObject(Scopes[I]);
      if Pos('Local', Str(Sc, 'name')) = 0 then      { "Locals" holds the arguments too; the globals are not listed }
        Continue;
      Ref := Num(Sc, 'variablesReference', 0);
      if Ref = 0 then
        Continue;
      A := TJSONBox.Own(TJSONObject.Create);
      A.Get.Add('variablesReference', Ref);
      if not Request('variables', A, R2, ReplyTimeout) then
      begin
        FError := '';
        Continue;
      end;
      if (not R2.IsEmpty) and (R2.Get.Find('variables') <> nil) and (R2.Get.Find('variables').JSONType = jtArray) then
      begin
        Vars := TJSONArray(R2.Get.Find('variables'));
        for J := 0 to Vars.Count - 1 do
          if Vars[J].JSONType = jtObject then
          begin
            V := TJSONObject(Vars[J]);
            if Text <> '' then
              Text := Text + #10;
            Text := Text + Str(V, 'name') + ' = ' + Str(V, 'value');
          end;
      end;
    end;
  end;
end;

procedure TDlvSession.SendInput(const S: AnsiString);
begin
  if (FProc <> nil) and (FProc.Input <> nil) and (S <> '') then
    try
      FProc.Input.Write(S[1], Length(S));
    except
    end;
end;

procedure TDlvSession.Stop;
var
  A, Body: TJSONBox;
  I: Integer;
begin
  if (FSock >= 0) and not FTerminated and (FError = '') then
  begin
    A := TJSONBox.Own(TJSONObject.Create);
    A.Get.Add('terminateDebuggee', True);
    Request('disconnect', A, Body, 5000);
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
    FProcBox.Reset;
    FProc := nil;
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
