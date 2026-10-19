{ The guard of one child process of the IDE (external compiler, language tools).

  MIT. The guard owns the process and ends it on every way out of its scope: Stop asks the child to end (SIGTERM on unix), waits a
  grace time, then kills it (SIGKILL) and waits for the exit; Destroy always does it, also while an exception unwinds. After Stop or
  Destroy no child of the guard remains. The unit has no threads: it is polled by the caller, as the IDE does, so the DOS-like
  synchronous path of the IDE is not changed (step 5a of safe/FPIDE-ADOPTION.md, decision D5).

  Ownership: the TProcess belongs to the guard through a TOwned box; the guard itself is meant to be held by a TOwned box too. }
{$mode objfpc}{$H+}
{$WARN SYMBOL_DEPRECATED ERROR}
unit FpProcGuard;

interface

uses
  SysUtils, Classes, Process, Safe;

type
  TProcBox = specialize TOwned<TProcess>;

  TProcGuard = class
  private
    FBox: TProcBox;
    FProc: TProcess;                 { borrow: FBox }
    FStarted: Boolean;
    FStopped: Boolean;
    function GetRunning: Boolean;
    function GetExitCode: Integer;
    function GetPid: LongInt;
  public
    constructor Create;
    destructor Destroy; override;
    { run Exe with Args (stderr goes to the same pipe as stdout); an exception from the system if the program cannot start }
    procedure Start(const Exe: string; const Args: array of string; const WorkDir: string = '');
    { the output that is ready now, '' when there is none; it never blocks }
    function ReadAvailable: AnsiString;
    { text for the standard input of the child (it stays open until the guard ends the child); False when there is nothing to write to or the write fails }
    function WriteInput(const S: AnsiString): Boolean;
    { wait up to TimeoutMs for the exit; True when the child has ended }
    function WaitFor(TimeoutMs: Integer): Boolean;
    { end the child: ask, wait GraceMs, kill, wait for the exit; nothing is left to wait for afterwards. Safe to call again. }
    procedure Stop(GraceMs: Integer = 1000);
    property Running: Boolean read GetRunning;
    { the exit code of the program (not the raw wait status, which TProcess.ExitStatus gives) }
    property ExitCode: Integer read GetExitCode;
    property Pid: LongInt read GetPid;
    { True when Stop had to end a child that was still running }
    property Stopped: Boolean read FStopped;
  end;

implementation

{$ifdef unix}
uses
  BaseUnix;
{$endif}

const
  KillWaitMs = 2000;

constructor TProcGuard.Create;
begin
  inherited Create;
  FBox := TProcBox.Own(TProcess.Create(nil));
  FProc := FBox.Get;
end;

destructor TProcGuard.Destroy;
begin
  Stop;
  FBox.Reset;
  inherited Destroy;
end;

function TProcGuard.GetRunning: Boolean;
begin
  Result := FStarted and FProc.Running;
end;

function TProcGuard.GetExitCode: Integer;
begin
  Result := FProc.ExitCode;
end;

function TProcGuard.GetPid: LongInt;
begin
  Result := FProc.ProcessID;
end;

procedure TProcGuard.Start(const Exe: string; const Args: array of string; const WorkDir: string);
var
  I: Integer;
begin
  if FStarted then
    raise Exception.Create('TProcGuard.Start: the process is already started');
  FProc.Executable := Exe;
  for I := Low(Args) to High(Args) do
    FProc.Parameters.Add(Args[I]);
  if WorkDir <> '' then
    FProc.CurrentDirectory := WorkDir;
  FProc.Options := [poUsePipes, poStderrToOutput, poNoConsole];
  FProc.Execute;
  FStarted := True;
end;

function TProcGuard.ReadAvailable: AnsiString;
var
  Buf: array[0..4095] of Char;
  N, I: LongInt;
begin
  Result := '';
  if not FStarted then
    Exit;
  if FProc.Output.NumBytesAvailable > 0 then
  begin
    N := FProc.Output.Read(Buf, SizeOf(Buf));
    if N > 0 then
    begin
      SetLength(Result, N);
      for I := 1 to N do
        Result[I] := Buf[I - 1];
    end;
  end;
end;

function TProcGuard.WriteInput(const S: AnsiString): Boolean;
begin
  Result := False;
  if (S = '') or not FStarted or (FProc.Input = nil) then
    Exit;
  try
    FProc.Input.Write(S[1], Length(S));
    Result := True;
  except
    { the child has ended and the pipe is broken: the text is lost, the caller learns it from False }
  end;
end;

function TProcGuard.WaitFor(TimeoutMs: Integer): Boolean;
var
  T: Integer;
begin
  T := 0;
  while GetRunning and (T < TimeoutMs) do
  begin
    Sleep(10);
    Inc(T, 10);
  end;
  Result := not GetRunning;
end;

procedure TProcGuard.Stop(GraceMs: Integer);
begin
  if not GetRunning then
    Exit;
  FStopped := True;
  FProc.Terminate(1);
  if WaitFor(GraceMs) then
    Exit;
{$ifdef unix}
  { the child ignores the request: kill it }
  fpKill(FProc.ProcessID, SIGKILL);
{$else}
  FProc.Terminate(1);
{$endif}
  WaitFor(KillWaitMs);
end;

end.
