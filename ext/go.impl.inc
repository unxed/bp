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

procedure QueueAdd(var Q: TSafeWaitQueue; W: PSafeWaiter);
begin
  W^.Next := nil;
  W^.Prev := Q.Last;
  if Q.Last = nil then
    Q.First := W
  else
    Q.Last^.Next := W;
  Q.Last := W;
  W^.Queued := True;
end;

procedure QueueRemove(var Q: TSafeWaitQueue; W: PSafeWaiter);
begin
  if not W^.Queued then
    Exit;
  if W^.Prev = nil then
    Q.First := W^.Next
  else
    W^.Prev^.Next := W^.Next;
  if W^.Next = nil then
    Q.Last := W^.Prev
  else
    W^.Next^.Prev := W^.Prev;
  W^.Prev := nil;
  W^.Next := nil;
  W^.Queued := False;
end;

{ Under the lock of the channel of Q: the first waiter that this channel may fire, out of the queue; a waiter whose call
  has already fired elsewhere or given up is only taken out. }
function QueueTake(var Q: TSafeWaitQueue): PSafeWaiter;
begin
  repeat
    Result := Q.First;
    if Result = nil then
      Exit;
    QueueRemove(Q, Result);
  until InterlockedCompareExchange(Result^.Sel^.Fired, Result^.Index, -1) = -1;
end;

{ Under the lock of the channel: the waiting call goes on (it takes the lock before it reads anything). }
procedure WakeWaiter(W: PSafeWaiter);
begin
  RTLEventSetEvent(W^.Sel^.Event);
end;

procedure TSafeChan.CheckSend(Src: Pointer);
begin
end;

function TSafeChan.TrySendLocked(Src: Pointer): Boolean;
var
  W: PSafeWaiter;
begin
  W := QueueTake(FRecvQ);
  if W <> nil then
  begin
    CopyElem(W^.Elem, Src);
    W^.Ok := True;
    WakeWaiter(W);
    Exit(True);
  end;
  Result := FCount < FCap;
  if Result then
  begin
    PutElem(Src);
    Inc(FCount);
    Broadcast; // Select over channels
  end;
end;

function TSafeChan.TryRecvLocked(Dst: Pointer; out Ok: Boolean): Boolean;
var
  W: PSafeWaiter;
begin
  Ok := True;
  Result := True;
  if FCount > 0 then
  begin
    TakeElem(Dst);
    Dec(FCount);
    W := QueueTake(FSendQ); // a waiting sender moves into the place just freed
    if W <> nil then
    begin
      PutElem(W^.Elem);
      Inc(FCount);
      W^.Ok := True;
      WakeWaiter(W);
    end;
    Exit;
  end;
  W := QueueTake(FSendQ);   // unbuffered: straight from the sender
  if W <> nil then
  begin
    CopyElem(Dst, W^.Elem);
    W^.Ok := True;
    WakeWaiter(W);
    Exit;
  end;
  Ok := False;
  Result := FClosed;
  if Result then
    ClearElem(Dst);
end;

procedure TSafeChan.SendElem(Src: Pointer);
var
  Sel: TSafeSel;
  W: TSafeWaiter;
begin
  Lock;
  try
    if FClosed then
      SafeFail('SAFE-R6: send on closed channel');
    CheckSend(Src);
    if TrySendLocked(Src) then
      Exit;
    Sel.Fired := -1;
    Sel.Event := MyEvent;
    W := Default(TSafeWaiter);
    W.Sel := @Sel;
    W.Elem := Src;
    QueueAdd(FSendQ, @W);
    Broadcast; // Select over channels: a waiting sender is a value
    repeat
      // the event is sticky (an RTLEvent is a binary semaphore): a set between Unlock and WaitFor is not lost; a stale
      // one only makes another round
      Unlock;
      RTLEventWaitFor(Sel.Event);
      Lock;
    until Sel.Fired <> -1;
    if not W.Ok then
      SafeFail('SAFE-R6: send on closed channel');
  finally
    Unlock;
  end;
end;

function TSafeChan.RecvElem(Dst: Pointer): Boolean;
var
  Sel: TSafeSel;
  W: TSafeWaiter;
begin
  Lock;
  try
    if TryRecvLocked(Dst, Result) then
      Exit;
    Sel.Fired := -1;
    Sel.Event := MyEvent;
    W := Default(TSafeWaiter);
    W.Sel := @Sel;
    W.Elem := Dst;
    QueueAdd(FRecvQ, @W);
    repeat
      Unlock;
      RTLEventWaitFor(Sel.Event);
      Lock;
    until Sel.Fired <> -1;
    Result := W.Ok;
  finally
    Unlock;
  end;
end;

procedure TSafeChan.Close;
var
  W: PSafeWaiter;
begin
  Lock;
  try
    if FClosed then
      SafeFail('SAFE-R6: close of closed channel');
    FClosed := True;
    // the receivers get "closed"; the senders wake up and raise R6
    repeat
      W := QueueTake(FRecvQ);
      if W <> nil then
      begin
        ClearElem(W^.Elem);
        W^.Ok := False;
        WakeWaiter(W);
      end;
    until W = nil;
    repeat
      W := QueueTake(FSendQ);
      if W <> nil then
      begin
        W^.Ok := False;
        WakeWaiter(W);
      end;
    until W = nil;
    Broadcast;
  finally
    Unlock;
  end;
end;

function TSafeChan.Ready: Boolean;
begin
  Result := (FCount > 0) or (FSendQ.First <> nil) or FClosed;
end;

function TSafeChan.RecvCase: TSelCase;
begin
  Result.Chan := Self;
  Result.Kind := skRecv;
  Result.Elem := nil;
  Result.Ok := nil;
end;

constructor TSafeChanOf.Create(ACap: SizeInt);
begin
  inherited Create;
  if ACap < 0 then
    ACap := 0;
  FCap := ACap;
  SetLength(FBuf, ACap);
end;

procedure TSafeChanOf.PutElem(Src: Pointer);
begin
  FBuf[(FHead + FCount) mod FCap] := PCell(Src)^.V;
end;

procedure TSafeChanOf.TakeElem(Dst: Pointer);
begin
  if Dst <> nil then
    PCell(Dst)^.V := FBuf[FHead];
  FBuf[FHead] := Default(T); // do not keep a reference to the value handed out
  FHead := (FHead + 1) mod FCap;
end;

procedure TSafeChanOf.CopyElem(Dst, Src: Pointer);
begin
  if Dst <> nil then
    PCell(Dst)^.V := PCell(Src)^.V;
end;

procedure TSafeChanOf.ClearElem(Dst: Pointer);
begin
  if Dst <> nil then
    PCell(Dst)^.V := Default(T);
end;

procedure TSafeChanOf.CheckSend(Src: Pointer);
begin
  // R17: a dynamic array is a reference; a second holder of it would share it with the receiver (H14, S11m)
  if SafeDebugChecks and (GetTypeKind(T) = tkDynArray) and (SafeDynArrayRefs(PPointer(Src)^) > 1) then
    SafeFail(Format('SAFE-R17: Send of a dynamic array that %d variables hold: the receiver would share it with '
      + 'them; send Copy(A), or a local that nothing else holds', [SafeDynArrayRefs(PPointer(Src)^)]));
end;

procedure TSafeChanOf.Send(const V: T);
begin
  SendElem(@V);
end;

function TSafeChanOf.Recv(out V: T): Boolean;
begin
  Result := RecvElem(@V);
end;

function TSafeChanOf.TryRecv(out V: T): Boolean;
var
  Ok: Boolean;
begin
  Lock;
  try
    if not TryRecvLocked(@V, Ok) then
      V := Default(T);
    Result := Ok;
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

function TChan.RecvCase(var V: T): TSelCase;
begin
  Check;
  Result.Chan := FImpl;
  Result.Kind := skRecv;
  Result.Elem := @V;
  Result.Ok := nil;
end;

function TChan.RecvCase(var V: T; var Ok: Boolean): TSelCase;
begin
  Check;
  Result.Chan := FImpl;
  Result.Kind := skRecv;
  Result.Elem := @V;
  Result.Ok := @Ok;
end;

function TChan.SendCase(constref V: T): TSelCase;
begin
  Check;
  Result.Chan := FImpl;
  Result.Kind := skSend;
  Result.Elem := @V;
  Result.Ok := nil;
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
  // no deadline without a timeout: GetTickCount64 + QWord(-1) would overflow under -Co (#146)
  Deadline := 0;
  if TimeoutMs >= 0 then
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

threadvar
  TSelSeed: Cardinal; // the random start of Select (xorshift32), per thread

function SelRandom(N: Integer): Integer;
var
  X: Cardinal;
begin
  X := TSelSeed;
  if X = 0 then
    X := Cardinal(PtrUInt(@TSelSeed) shr 4) or 1;
  X := X xor (X shl 13);
  X := X xor (X shr 17);
  X := X xor (X shl 5);
  TSelSeed := X;
  Result := Integer(X mod Cardinal(N));
end;

function Select(const Cases: array of TSelCase; TimeoutMs: Integer): Integer;
var
  N, I, J, K, Start: Integer;
  Order: array of Integer;          // the cases by the address of their channel: the order of locking (sellock of Go)
  Ws: array of TSafeWaiter;         // not resized while they are queued
  Sel: TSafeSel;
  Ok, Closed, Waited: Boolean;
  Deadline, Now: QWord;

  procedure LockAll;
  var
    L: Integer;
  begin
    for L := 0 to N - 1 do
      if (L = 0) or (Cases[Order[L]].Chan <> Cases[Order[L - 1]].Chan) then
        Cases[Order[L]].Chan.Lock;
  end;

  procedure UnlockAll;
  var
    L: Integer;
  begin
    for L := N - 1 downto 0 do
      if (L = 0) or (Cases[Order[L]].Chan <> Cases[Order[L - 1]].Chan) then
        Cases[Order[L]].Chan.Unlock;
  end;

begin
  N := Length(Cases);
  if N = 0 then
  begin
    if TimeoutMs < 0 then
      repeat
        RTLEventWaitFor(MyEvent); // select {} of Go: waits for ever
      until False;
    Sleep(TimeoutMs);
    Exit(-1);
  end;
  for I := 0 to N - 1 do
    if Cases[I].Chan = nil then
      SafeFail('SAFE-R4: Select case of a channel used before TChan.Create');
  SetLength(Order, N);
  for I := 0 to N - 1 do
  begin
    J := I;
    while (J > 0) and (PtrUInt(Cases[Order[J - 1]].Chan) > PtrUInt(Cases[I].Chan)) do
    begin
      Order[J] := Order[J - 1];
      Dec(J);
    end;
    Order[J] := I;
  end;
  Deadline := 0;
  if TimeoutMs >= 0 then
    Deadline := GetTickCount64 + QWord(TimeoutMs);

  LockAll;
  Closed := False;
  Result := -1;
  try
    // a case that can happen now, from a random start: no case is starved
    Start := SelRandom(N);
    for K := 0 to N - 1 do
    begin
      I := (Start + K) mod N;
      if Cases[I].Kind = skRecv then
      begin
        if Cases[I].Chan.TryRecvLocked(Cases[I].Elem, Ok) then
        begin
          if Cases[I].Ok <> nil then
            Cases[I].Ok^ := Ok;
          Result := I;
          Break;
        end;
      end
      else if Cases[I].Chan.FClosed then
      begin
        Closed := True;
        Result := I;
        Break;
      end
      else
      begin
        Cases[I].Chan.CheckSend(Cases[I].Elem);
        if Cases[I].Chan.TrySendLocked(Cases[I].Elem) then
        begin
          Result := I;
          Break;
        end;
      end;
    end;
  except
    UnlockAll;
    raise;
  end;
  if (Result >= 0) or (TimeoutMs = 0) then
  begin
    UnlockAll;
    if Closed then
      SafeFail('SAFE-R6: send on closed channel');
    Exit;
  end;
  // none: a waiter on every channel, one Sel for all of them
  SetLength(Ws, N);
  Sel.Fired := -1;
  Sel.Event := MyEvent;
  for I := 0 to N - 1 do
  begin
    Ws[I] := Default(TSafeWaiter);
    Ws[I].Sel := @Sel;
    Ws[I].Index := I;
    Ws[I].Elem := Cases[I].Elem;
    if Cases[I].Kind = skRecv then
      QueueAdd(Cases[I].Chan.FRecvQ, @Ws[I])
    else
    begin
      QueueAdd(Cases[I].Chan.FSendQ, @Ws[I]);
      Cases[I].Chan.Broadcast; // Select over channels: a waiting sender is a value
    end;
  end;
  UnlockAll;
  // a channel fires one case under its lock and sets the event; a stale set only makes another round
  Waited := False;
  repeat
    if TimeoutMs < 0 then
      RTLEventWaitFor(Sel.Event)
    else
    begin
      Now := GetTickCount64;
      if Now >= Deadline then
        Break;
      RTLEventWaitFor(Sel.Event, Deadline - Now);
    end;
    Waited := InterlockedCompareExchange(Sel.Fired, -1, -1) <> -1;
  until Waited;
  LockAll;
  // after LockAll the channel that fired has finished with its waiter; no channel fires one after this
  InterlockedCompareExchange(Sel.Fired, -2, -1);
  for I := 0 to N - 1 do
    if Cases[I].Kind = skRecv then
      QueueRemove(Cases[I].Chan.FRecvQ, @Ws[I])
    else
      QueueRemove(Cases[I].Chan.FSendQ, @Ws[I]);
  Result := Sel.Fired;
  if Result >= 0 then
  begin
    if not Waited then
      RTLEventWaitFor(Sel.Event, 0); // fired as the time ran out: take the set it made
    if Cases[Result].Kind = skRecv then
    begin
      if Cases[Result].Ok <> nil then
        Cases[Result].Ok^ := Ws[Result].Ok;
    end
    else
      Closed := not Ws[Result].Ok;
  end
  else
    Result := -1;
  UnlockAll;
  if Closed then
    SafeFail('SAFE-R6: send on closed channel');
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

