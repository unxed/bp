program t_fpprocguard;
{ Tests of the process guard (src/fpprocguard.pas): normal exit, partial output, abort, a child that ignores the request, a timeout,
  an exception while the child runs, and "no child remains" (checked by pid). Step 5a of safe/FPIDE-ADOPTION.md.
  The children are /bin/sh and sleep, so the tests are skipped where they are missing (Windows). The test ends with SafeCheckNoLeaks. }
{$mode objfpc}{$H+}
uses SysUtils, {$ifdef unix}BaseUnix, {$endif}FpProcGuard, Safe;

type
  TGuardBox = specialize TOwned<TProcGuard>;

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

function Gone(Pid: LongInt): Boolean;
begin
{$ifdef unix}
  { the child is reaped by Stop/WaitFor, so no zombie is left either: the pid does not exist }
  Result := (fpKill(Pid, 0) <> 0) and (fpGetErrno = ESysESRCH);
{$else}
  Result := True;
{$endif}
end;

function Drain(G: TProcGuard; WaitMs: Integer): AnsiString;
var
  T: Integer;
  S: AnsiString;
begin
  Result := '';
  T := 0;
  while T < WaitMs do
  begin
    S := G.ReadAvailable;
    Result := Result + S;
    if (S = '') and (not G.Running) then
      Break;
    if S = '' then
    begin
      Sleep(10);
      Inc(T, 10);
    end;
  end;
end;

procedure TestNormalExit;
var
  Box: TGuardBox;
  G: TProcGuard;                       { borrow: Box }
  Out_: AnsiString;
  Pid: LongInt;
begin
  Box := TGuardBox.Own(TProcGuard.Create);
  G := Box.Get;
  G.Start('/bin/sh', ['-c', 'echo hello; echo oops 1>&2; exit 3']);
  Pid := G.Pid;
  Out_ := Drain(G, 5000);
  Check(G.WaitFor(5000), 'normal: the child ends by itself');
  Check(Pos('hello', Out_) > 0, 'normal: stdout is read');
  Check(Pos('oops', Out_) > 0, 'normal: stderr goes to the same pipe');
  Check(G.ExitCode = 3, 'normal: exit code is 3, got ' + IntToStr(G.ExitCode));
  G.Stop;
  Check(not G.Stopped, 'normal: Stop after a normal exit does not count as an abort');
  Check(Gone(Pid), 'normal: no child remains');
end;

procedure TestPartialAndAbort;
var
  Box: TGuardBox;
  G: TProcGuard;                       { borrow: Box }
  Out_: AnsiString;
  Pid: LongInt;
  Start: QWord;
begin
  Box := TGuardBox.Own(TProcGuard.Create);
  G := Box.Get;
  G.Start('/bin/sh', ['-c', 'echo first; exec sleep 30']);
  Pid := G.Pid;
  Out_ := '';
  Start := GetTickCount64;
  while (Pos('first', Out_) = 0) and (GetTickCount64 - Start < 5000) do
  begin
    Out_ := Out_ + G.ReadAvailable;
    Sleep(10);
  end;
  Check(Pos('first', Out_) > 0, 'partial: the output that is ready is read while the child still runs');
  Check(G.Running, 'partial: the child still runs');
  Start := GetTickCount64;
  G.Stop;
  Check(GetTickCount64 - Start < 5000, 'abort: Stop returns quickly');
  Check(G.Stopped, 'abort: Stop ended a running child');
  Check(not G.Running, 'abort: the child is not running');
  Check(Gone(Pid), 'abort: no child remains');
  G.Stop;
  Check(not G.Running, 'abort: a second Stop is harmless');
end;

procedure TestIgnoresRequest;
var
  Box: TGuardBox;
  G: TProcGuard;                       { borrow: Box }
  Pid: LongInt;
  Start: QWord;
begin
  Box := TGuardBox.Own(TProcGuard.Create);
  G := Box.Get;
  { the disposition "ignore" is kept over exec, so sleep itself does not react to SIGTERM }
  G.Start('/bin/sh', ['-c', 'trap "" TERM; exec sleep 30']);
  Pid := G.Pid;
  Sleep(200);
  Check(G.Running, 'ignores: the child runs');
  Start := GetTickCount64;
  G.Stop(300);
  Check(GetTickCount64 - Start < 6000, 'ignores: Stop gives up the grace time and kills');
  Check(not G.Running, 'ignores: the child is not running');
  Check(Gone(Pid), 'ignores: no child remains');
end;

procedure TestTimeout;
var
  Box: TGuardBox;
  G: TProcGuard;                       { borrow: Box }
  Pid: LongInt;
begin
  Box := TGuardBox.Own(TProcGuard.Create);
  G := Box.Get;
  G.Start('/bin/sh', ['-c', 'exec sleep 30']);
  Pid := G.Pid;
  Check(not G.WaitFor(200), 'timeout: WaitFor reports that the child is still running');
  G.Stop;
  Check(G.WaitFor(0), 'timeout: after Stop the child has ended');
  Check(Gone(Pid), 'timeout: no child remains');
end;

procedure RaiseWhileRunning(out Pid: LongInt);
var
  Box: TGuardBox;
begin
  Box := TGuardBox.Own(TProcGuard.Create);
  Box.Get.Start('/bin/sh', ['-c', 'exec sleep 30']);
  Pid := Box.Get.Pid;
  raise Exception.Create('reading failed');
end;

procedure TestException;
var
  Pid: LongInt;
  Raised: Boolean;
begin
  Pid := 0;
  Raised := False;
  try
    RaiseWhileRunning(Pid);
  except
    on E: Exception do
      Raised := E.Message = 'reading failed';
  end;
  Check(Raised, 'exception: the exception reaches the caller');
  Check(Pid > 0, 'exception: the child was started');
  Check(Gone(Pid), 'exception: the guard left the scope and no child remains');
end;

procedure TestNotFound;
var
  Box: TGuardBox;
  Failed: Boolean;
begin
  Box := TGuardBox.Own(TProcGuard.Create);
  Failed := False;
  try
    Box.Get.Start('/nonexistent/bp-no-such-program', []);
  except
    Failed := True;
  end;
  Check(Failed, 'missing program: Start raises');
  Check(not Box.Get.Running, 'missing program: nothing runs');
end;

begin
{$ifdef unix}
  if not FileExists('/bin/sh') then
  begin
    WriteLn('SKIP t_fpprocguard: /bin/sh is missing');
    Halt(0);
  end;
  TestNormalExit;
  TestPartialAndAbort;
  TestIgnoresRequest;
  TestTimeout;
  TestException;
  TestNotFound;
  SafeCheckNoLeaks;
  WriteLn('t_fpprocguard: ', Total - Bad, '/', Total, ' checks');
  if Bad > 0 then
    Halt(1);
{$else}
  WriteLn('SKIP t_fpprocguard: unix only');
{$endif}
end.
