{ SPDX-License-Identifier: MIT }
{ Better Pascal, ext/go (implementation). }

{ ---------- goroutines: synchronization ---------- }

threadvar
  TMyEvent: PRTLEvent; // the event of the current thread for waits; created lazily

function MyEvent: PRTLEvent;
begin
  if TMyEvent = nil then
    TMyEvent := RTLEventCreate;
  Result := TMyEvent;
end;

constructor TSafeSync.Create;
begin
  inherited Create;
  InitCriticalSection(FLock);
end;

destructor TSafeSync.Destroy;
begin
  DoneCriticalSection(FLock);
  inherited Destroy;
end;

procedure TSafeSync.Lock;
begin
  EnterCriticalSection(FLock);
end;

procedure TSafeSync.Unlock;
begin
  LeaveCriticalSection(FLock);
end;

procedure TSafeSync.Register;
begin
  if FWaitCount = Length(FWaiters) then
    SetLength(FWaiters, 2 * FWaitCount + 4);
  FWaiters[FWaitCount] := MyEvent;
  Inc(FWaitCount);
end;

procedure TSafeSync.Unregister;
var
  I: SizeInt;
  E: PRTLEvent;
begin
  E := MyEvent;
  for I := 0 to FWaitCount - 1 do
    if FWaiters[I] = E then
    begin
      FWaiters[I] := FWaiters[FWaitCount - 1];
      Dec(FWaitCount);
      Exit;
    end;
end;

procedure TSafeSync.Broadcast;
var
  I: SizeInt;
begin
  for I := 0 to FWaitCount - 1 do
    RTLEventSetEvent(FWaiters[I]);
  FWaitCount := 0;
end;

function TSafeSync.WaitLocked(TimeoutMs: Integer): Boolean;
begin
  // The event is sticky (an RTLEvent is a binary semaphore): a SetEvent between Unlock and
  // WaitFor is not lost. Spurious wakeups are harmless: the caller checks the condition in a loop.
  Register;
  Unlock;
  if TimeoutMs < 0 then
    RTLEventWaitFor(MyEvent)
  else
    RTLEventWaitFor(MyEvent, TimeoutMs);
  Lock;
  Unregister; // after a timeout; if Broadcast already removed us, finds nothing
  Result := True;
end;

{ ---------- channels ---------- }

procedure TSafeChan.Close;
begin
  Lock;
  try
    if FClosed then
      SafeFail('SAFE-R6: close of closed channel');
    FClosed := True;
    Broadcast;
  finally
    Unlock;
  end;
end;

function TSafeChan.Ready: Boolean;
begin
  Result := (FCount > 0) or FClosed;
end;

constructor TSafeChanOf.Create(ACap: SizeInt);
begin
  inherited Create;
  if ACap < 0 then
    ACap := 0;
  FCap := ACap;
  if ACap = 0 then
    SetLength(FBuf, 1)
  else
    SetLength(FBuf, ACap);
end;

procedure TSafeChanOf.Send(const V: T);
var
  Ticket: Int64;
begin
  Lock;
  try
    while (not FClosed) and (FCount >= Length(FBuf)) do
      WaitLocked(-1);
    if FClosed then
      SafeFail('SAFE-R6: send on closed channel');
    FBuf[(FHead + FCount) mod Length(FBuf)] := V;
    Inc(FCount);
    Inc(FSentSeq);
    Ticket := FSentSeq;
    Broadcast;
    if FCap = 0 then // rendezvous: wait until the value is taken
      while FRecvSeq < Ticket do
        WaitLocked(-1);
  finally
    Unlock;
  end;
end;

function TSafeChanOf.TakeLocked(out V: T): Boolean;
begin
  Result := FCount > 0;
  if not Result then
  begin
    V := Default(T);
    Exit;
  end;
  V := FBuf[FHead];
  FBuf[FHead] := Default(T); // do not keep a reference to the value handed out
  FHead := (FHead + 1) mod Length(FBuf);
  Dec(FCount);
  Inc(FRecvSeq);
  Broadcast;
end;

function TSafeChanOf.Recv(out V: T): Boolean;
begin
  Lock;
  try
    while (FCount = 0) and not FClosed do
      WaitLocked(-1);
    Result := TakeLocked(V);
  finally
    Unlock;
  end;
end;

function TSafeChanOf.TryRecv(out V: T): Boolean;
begin
  Lock;
  try
    Result := TakeLocked(V);
  finally
    Unlock;
  end;
end;

function TChanEnumerator.MoveNext: Boolean;
begin
  Result := FImpl.Recv(FCur);
end;

class function TChan.Create(ACap: SizeInt): TChan;
begin
  Result.FImpl := TImpl.Create(ACap);
  Result.FRef := Result.FImpl;
end;

procedure TChan.Check;
begin
  if FRef = nil then
    SafeFail('SAFE-R4: TChan used before TChan.Create');
end;

procedure TChan.Send(const V: T);
begin
  Check;
  FImpl.Send(V);
end;

function TChan.Recv(out V: T): Boolean;
begin
  Check;
  Result := FImpl.Recv(V);
end;

function TChan.TryRecv(out V: T): Boolean;
begin
  Check;
  Result := FImpl.TryRecv(V);
end;

procedure TChan.Close;
begin
  Check;
  FImpl.Close;
end;

function TChan.Sel: TSafeChan;
begin
  Check;
  Result := FImpl;
end;

function TChan.GetEnumerator: specialize TChanEnumerator<T>;
begin
  Check;
  Result.FImpl := FImpl;
  Result.FRef := FRef;
end;

function Select(const Chans: array of TSafeChan; TimeoutMs: Integer): Integer;
var
  I, J: Integer;
  Deadline, Now: QWord;
  Left: Integer;
begin
  Deadline := GetTickCount64 + QWord(TimeoutMs);
  repeat
    // The check and the registration are under the lock of each channel: no wakeup is lost.
    for I := 0 to High(Chans) do
    begin
      Chans[I].Lock;
      if Chans[I].Ready then
      begin
        Chans[I].Unlock;
        for J := 0 to I - 1 do
        begin
          Chans[J].Lock;
          Chans[J].Unregister;
          Chans[J].Unlock;
        end;
        Exit(I);
      end;
      Chans[I].Register;
      Chans[I].Unlock;
    end;
    if TimeoutMs < 0 then
      RTLEventWaitFor(MyEvent)
    else
    begin
      Now := GetTickCount64;
      if Now >= Deadline then
        Left := 0
      else
        Left := Deadline - Now;
      if Left > 0 then
        RTLEventWaitFor(MyEvent, Left);
    end;
    for J := 0 to High(Chans) do
    begin
      Chans[J].Lock;
      Chans[J].Unregister;
      Chans[J].Unlock;
    end;
  until (TimeoutMs >= 0) and (GetTickCount64 >= Deadline);
  // a last chance after the timeout
  for I := 0 to High(Chans) do
  begin
    Chans[I].Lock;
    try
      if Chans[I].Ready then
        Exit(I);
    finally
      Chans[I].Unlock;
    end;
  end;
  Result := -1;
end;

{ ---------- groups and tasks ---------- }

function SafeGoThread(P: System.Pointer): PtrInt;
var
  T: TTask;
  G: TSafeGroupImpl;
  Err: string;
begin
  T := TTask(P);
  G := T.FGroup;
  Err := '';
  try
    T.Run;
  except
    on E: Exception do
      Err := E.ClassName + ': ' + E.Message;
    else
      Err := 'non-Exception object raised';
  end;
  try
    T.Destroy;
  except
    on E: Exception do
      if Err = '' then
        Err := 'in task destructor: ' + E.ClassName + ': ' + E.Message;
  end;
  if TMyEvent <> nil then
  begin
    RTLEventDestroy(TMyEvent);
    TMyEvent := nil;
  end;
  G.TaskDone(Err); // the group may be destroyed after this: G is not touched any more
  Result := 0;
end;

function TTask.Cancelled: Boolean;
begin
  Result := FGroup.Cancelled;
end;

function TTask.Done: TSafeChan;
begin
  Result := FGroup.FDone;
end;

procedure TTask.Go(ATask: TTask);
begin
  FGroup.Go(ATask);
end;

type
  TSafeDoneChan = specialize TSafeChanOf<Boolean>;

  TSafeProcTask = class(TTask)
  public
    Proc: TProcedure;
    procedure Run; override;
  end;

procedure TSafeProcTask.Run;
begin
  Proc();
end;

constructor TSafeGroupImpl.Create;
begin
  inherited Create;
  FDone := TSafeDoneChan.Create(0);
  FDoneRef := FDone;
end;

destructor TSafeGroupImpl.Destroy;
begin
  // Structured concurrency: a group does not die before its tasks.
  if WaitAll <> '' then
    InterlockedIncrement(GGoFailures); // a destructor must not raise: count it instead (R5)
  inherited Destroy;
end;

procedure TSafeGroupImpl.Go(ATask: TTask);
var
  Id: TThreadID;
  Probe: PRTLEvent;
begin
  if ATask = nil then
    Exit;
  if ATask.FGroup <> nil then
    SafeFail('SAFE-R3: TGroup.Go: task already started');
  ATask.FGroup := Self;
{$if defined(go32v2) or defined(msdos)}
  // DOS is single-tasking: there are no threads, BeginThread does not return in a useful way (on go32v2 under DOSBox-X the test hung).
  ATask.Destroy;
  SafeFail('SAFE-R8: this target (DOS) has no threads; goroutines are not available. Use plain procedures');
{$endif}
  // Without a thread manager RTLEventCreate returns nil.
  Probe := RTLEventCreate;
  if Probe = nil then
  begin
    ATask.Destroy;
    SafeFail('SAFE-R8: no thread manager. Put BP FIRST in the program uses: uses BP, SysUtils, ...');
  end;
  RTLEventDestroy(Probe);
  Lock;
  Inc(FRunning);
  Unlock;
  Id := BeginThread(@SafeGoThread, ATask);
  if Id = TThreadID(0) then
  begin
    ATask.Destroy;
    TaskDone('');
    SafeFail('SAFE-R7: cannot start thread');
  end;
  CloseThread(Id);
end;

procedure TSafeGroupImpl.Cancel;
var
  WasClosed: Boolean;
begin
  FDone.Lock;
  WasClosed := FDone.FClosed;
  FDone.Unlock;
  if not WasClosed then
    try
      FDone.Close;
    except
      on ESafety do ; // closed concurrently: the same result
    end;
end;

function TSafeGroupImpl.Cancelled: Boolean;
begin
  FDone.Lock;
  Result := FDone.FClosed;
  FDone.Unlock;
end;

function TSafeGroupImpl.WaitAll: string;
begin
  Lock;
  try
    while FRunning > 0 do
      WaitLocked(-1);
    Result := FError;
    FError := '';
  finally
    Unlock;
  end;
end;

procedure TSafeGroupImpl.TaskDone(const Err: string);
var
  Failed: Boolean;
begin
  Lock;
  Failed := (Err <> '') and (FError = '');
  if Failed then
    FError := Err;
  Unlock;
  if Failed then
    Cancel; // the first error cancels the others (errgroup)
  Lock;
  Dec(FRunning);
  Broadcast;
  Unlock;
end;

class function TGroup.Create: TGroup;
begin
  Result.FImpl := TSafeGroupImpl.Create;
  Result.FRef := Result.FImpl;
end;

procedure TGroup.Check;
begin
  if FRef = nil then
    SafeFail('SAFE-R4: TGroup used before TGroup.Create');
end;

procedure TGroup.Go(ATask: TTask);
begin
  Check;
  FImpl.Go(ATask);
end;

procedure TGroup.Go(AProc: TProcedure);
var
  T: TSafeProcTask;
begin
  Check;
  T := TSafeProcTask.Create;
  T.Proc := AProc;
  FImpl.Go(T);
end;

procedure TGroup.Wait;
var
  Err: string;
begin
  Check;
  Err := FImpl.WaitAll;
  if Err <> '' then
    SafeFail('SAFE-R7: task failed: ' + Err);
end;

procedure TGroup.Cancel;
begin
  Check;
  FImpl.Cancel;
end;

function TGroup.Cancelled: Boolean;
begin
  Check;
  Result := FImpl.Cancelled;
end;

function TGroup.Done: TSafeChan;
begin
  Check;
  Result := FImpl.FDone;
end;

