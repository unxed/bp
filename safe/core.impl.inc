{ SPDX-License-Identifier: MIT }
{ Safe Pascal, core (implementation). }

{ ---------- internals ---------- }

var
  GLive: LongInt = 0;         // owned objects (TOwned/TShared/TArena) alive right now
  GDeferFailures: LongInt = 0; // exceptions suppressed in deferred calls
  GGoFailures: LongInt = 0;    // task errors that nobody collected via TGroup.Wait
  GLives: TSafeLife = nil;     // lives made with debug checks on (H2), a doubly linked list
  GLivesLock: LongInt = 0;     // a spin lock over GLives

procedure SafeLockLives;
begin
  while InterlockedCompareExchange(GLivesLock, 1, 0) <> 0 do
    ThreadSwitch;
end;

procedure SafeUnlockLives;
begin
  InterlockedExchange(GLivesLock, 0);
end;

procedure SafeListLife(L: TSafeLife);
begin
  SafeLockLives;
  L.NextLive := GLives;
  if GLives <> nil then
    GLives.PrevLive := L;
  GLives := L;
  L.Listed := True;
  SafeUnlockLives;
end;

procedure SafeUnlistLife(L: TSafeLife);
begin
  SafeLockLives;
  if L.PrevLive <> nil then
    L.PrevLive.NextLive := L.NextLive
  else
    GLives := L.NextLive;
  if L.NextLive <> nil then
    L.NextLive.PrevLive := L.PrevLive;
  L.PrevLive := nil;
  L.NextLive := nil;
  L.Listed := False;
  SafeUnlockLives;
end;

{ How many words of the instance of A.Obj (the fields, after the VMT pointer) hold the value P. }
function SafeRefsTo(A: TSafeLife; P: System.Pointer): LongInt;
var
  I, N: PtrUInt;
begin
  Result := 0;
  N := A.Obj.InstanceSize div SizeOf(PtrUInt);
  for I := 1 to N - 1 do
    if System.PPtrUInt(PtrUInt(A.Obj) + I * SizeOf(PtrUInt))^ = PtrUInt(P) then
      Inc(Result);
end;

{ '' or the text about the live listed objects reachable only from each other (a TShared cycle, H2): an object
  is held from outside when its count is greater than the number of references to it from the fields of the
  listed objects; everything those reach is held too; the rest is garbage that keeps itself alive. }
function SafeCycleReport: string;
var
  Lives: array of TSafeLife;
  Inner: array of LongInt;
  Held, Seen: array of Boolean;
  L: TSafeLife;
  N, I, J, Cur, Count: SizeInt;
  Changed: Boolean;
  Types, Path: string;
begin
  Result := '';
  SafeLockLives;
  try
    N := 0;
    L := GLives;
    while L <> nil do
    begin
      if (L.Obj <> nil) and (L.IntfPtr <> nil) then
      begin
        SetLength(Lives, N + 1);
        Lives[N] := L;
        Inc(N);
      end;
      L := L.NextLive;
    end;
    if N = 0 then
      Exit;
    SetLength(Inner, N);
    SetLength(Held, N);
    SetLength(Seen, N);
    for J := 0 to N - 1 do
    begin
      Inner[J] := 0;
      for I := 0 to N - 1 do
        Inc(Inner[J], SafeRefsTo(Lives[I], Lives[J].IntfPtr));
      Held[J] := Lives[J].RefCount > Inner[J];
      Seen[J] := False;
    end;
    repeat
      Changed := False;
      for I := 0 to N - 1 do
        if Held[I] then
          for J := 0 to N - 1 do
            if not Held[J] and (SafeRefsTo(Lives[I], Lives[J].IntfPtr) > 0) then
            begin
              Held[J] := True;
              Changed := True;
            end;
    until not Changed;
    Count := 0;
    Types := '';
    Cur := -1;
    for J := 0 to N - 1 do
      if not Held[J] then
      begin
        Inc(Count);
        if Cur < 0 then
          Cur := J;
        if Pos(' ' + Lives[J].Obj.ClassName + ' ', ' ' + StringReplace(Types, ',', ' ', [rfReplaceAll]) + ' ') = 0 then
        begin
          if Types <> '' then
            Types := Types + ', ';
          Types := Types + Lives[J].Obj.ClassName;
        end;
      end;
    if Count = 0 then
      Exit;
    Path := Lives[Cur].Obj.ClassName;
    while not Seen[Cur] do
    begin
      Seen[Cur] := True;
      I := -1;
      for J := 0 to N - 1 do
        if not Held[J] and (SafeRefsTo(Lives[Cur], Lives[J].IntfPtr) > 0) then
        begin
          I := J;
          Break;
        end;
      if I < 0 then
        Break;
      Cur := I;
      Path := Path + ' -> ' + Lives[Cur].Obj.ClassName;
    end;
    Result := Format('; %d of them are reachable only from each other, a TShared cycle (H2): types %s, path %s; '
      + 'make the back reference a TWeak (Shared.Weak)', [Count, Types, Path]);
  finally
    SafeUnlockLives;
  end;
end;

function SafeLiveCount: LongInt;
begin
  Result := GLive;
end;

function SafeDeferFailures: LongInt;
begin
  Result := GDeferFailures;
end;

procedure SafeCheckNoLeaks;
begin
  if GLive <> 0 then
    SafeFail(Format('SAFE-R5: %d owned object(s) still alive', [GLive]) + SafeCycleReport);
  if GDeferFailures <> 0 then
    SafeFail(Format('SAFE-R5: %d exception(s) were suppressed in deferred calls', [GDeferFailures]));
  if GGoFailures <> 0 then
    SafeFail(Format('SAFE-R5: %d task failure(s) were never observed by TGroup.Wait', [GGoFailures]));
end;

procedure SafeFail(const Msg: string);
begin
  raise ESafety.Create(Msg);
end;

function SafeNewLife(AObj: TObject; const Who: string): TSafeLife;
begin
  if AObj = nil then
    Exit(nil);
  if AObj is TInterfacedObject then
    SafeFail('SAFE-R3: ' + Who + '(' + AObj.ClassName +
      '): TInterfacedObject is owned by its interface refcount; hold it through an interface');
  Result := TSafeLife.Create;
  Result.Obj := AObj;
  if SafeDebugChecks then
    SafeListLife(Result);
  InterlockedIncrement(GLive);
end;

destructor TSafeLife.Destroy;
var
  O: TObject;
begin
  if Listed then
    SafeUnlistLife(Self);
  if CellObj <> nil then
    CellObj.ClearLife; // weak references will no longer lock the object (under the cell lock: TryLock, H6)
  O := Obj;
  Obj := nil;
  if O <> nil then
  begin
    O.Destroy; // Free is shadowed by a helper here
    InterlockedDecrement(GLive);
  end;
  CellRef := nil;
  inherited Destroy;
end;

function TSafeLife.Cell: TSafeCell;
begin
  if CellObj = nil then
  begin
    CellObj := TSafeCell.Create;
    CellObj.Life := Self;
    CellRef := CellObj;
  end;
  Result := CellObj;
end;

function TSafeLife.TryAddRef: Boolean;
var
  N: LongInt;
begin
  repeat
    N := FRefCount;
    if N <= 0 then
      Exit(False); // the last reference is gone: the destructor runs or is about to run in another thread
  until InterlockedCompareExchange(FRefCount, N + 1, N) = N;
  Result := True;
end;

{ ---------- TSafeCell ---------- }

procedure SafeCellEnter(C: TSafeCell);
begin
  while InterlockedCompareExchange(C.Lock, 1, 0) <> 0 do
    ThreadSwitch;
end;

procedure SafeCellLeave(C: TSafeCell);
begin
  InterlockedExchange(C.Lock, 0);
end;

function TSafeCell.AcquireLife: TObject;
begin
  Result := nil;
  SafeCellEnter(Self);
  try
    // Life is valid here: its destructor clears it under the same lock before the memory is freed
    if (Life <> nil) and TSafeLife(Life).TryAddRef then
      Result := Life;
  finally
    SafeCellLeave(Self);
  end;
end;

procedure TSafeCell.ClearLife;
begin
  SafeCellEnter(Self);
  Life := nil;
  SafeCellLeave(Self);
end;

procedure TSafeArenaImpl.FreeAll;
var
  I: SizeInt;
  O: TObject;
begin
  for I := Count - 1 downto 0 do // reverse order: later-created ones may reference earlier ones
  begin
    O := Items[I];
    Items[I] := nil;
    O.Destroy;
    InterlockedDecrement(GLive);
  end;
  Count := 0;
  SetLength(Items, 0);
  if GenObj <> nil then
    Inc(GenObj.Generation); // every TArenaRef taken before this point is stale now (R10)
end;

destructor TSafeArenaImpl.Destroy;
begin
  FreeAll;
  inherited Destroy;
end;

{ ---------- TOwned ---------- }

class function TOwned.Own(AObj: T): TOwned;
var
  L: TSafeLife;
begin
  L := SafeNewLife(AObj, 'TOwned.Own');
  Result.FLife := L;
  if L <> nil then
    L.IntfPtr := System.Pointer(Result.FLife); // the cycle report of SafeCheckNoLeaks looks for this value (H2)
  Result.FObj := AObj;
end;

function TOwned.Get: T;
begin
  if FLife = nil then
    SafeFail('SAFE-R1: TOwned.Get on empty owner (after Move or Reset)');
  Result := FObj;
end;

function TOwned.TryGet(out AObj: T): Boolean;
begin
  Result := FLife <> nil;
  if Result then AObj := FObj else AObj := nil;
end;

function TOwned.IsEmpty: Boolean;
begin
  Result := FLife = nil;
end;

function TOwned.Move: TOwned;
var
  L: IInterface;
  O: T;
begin
  // Via locals: correct even if Result and Self are the same memory (A := A.Move).
  L := FLife;
  O := FObj;
  FLife := nil;
  FObj := nil;
  Result.FObj := O;
  Result.FLife := L;
end;

procedure TOwned.Reset;
var
  N: LongInt;
begin
  if SafeDebugChecks and (FLife <> nil) then
  begin
    // _AddRef returns the count with this probe: 2 when this owner is the only one (S10, R9)
    N := FLife._AddRef;
    FLife._Release;
    if N > 2 then
      SafeFail('SAFE-R9: TOwned<' + T.ClassName + '>.Reset: a copy of the owner is alive; copy a TOwned only '
        + 'with .Move (S10)');
  end;
  FObj := nil;
  FLife := nil;
end;

{ ---------- TWeak ---------- }

procedure TWeak.SetCell(ACell: TSafeCell);
begin
  FCellObj := ACell;
  FCell := ACell;
end;

function TWeak.CellObj: TSafeCell;
begin
  Result := FCellObj;
end;

function TWeak.IsAlive: Boolean;
begin
  Result := (FCellObj <> nil) and (FCellObj.Life <> nil);
end;

procedure TWeak.Reset;
begin
  FCellObj := nil;
  FCell := nil;
end;

{ ---------- TShared ---------- }

class function TShared.Share(AObj: T): TShared;
begin
  Result.FLifeObj := SafeNewLife(AObj, 'TShared.Share');
  Result.FLife := Result.FLifeObj;
  if Result.FLifeObj <> nil then
    Result.FLifeObj.IntfPtr := System.Pointer(Result.FLife); // the cycle report of SafeCheckNoLeaks looks for it (H2)
  Result.FObj := AObj;
end;

function TShared.Get: T;
begin
  if FLife = nil then
    SafeFail('SAFE-R1: TShared.Get on empty reference (after Reset or failed TryLock)');
  Result := FObj;
end;

function TShared.TryGet(out AObj: T): Boolean;
begin
  Result := FLife <> nil;
  if Result then AObj := FObj else AObj := nil;
end;

function TShared.IsEmpty: Boolean;
begin
  Result := FLife = nil;
end;

procedure TShared.Reset;
begin
  FObj := nil;
  FLifeObj := nil;
  FLife := nil;
end;

function TShared.Weak: specialize TWeak<T>;
begin
  if FLife = nil then
    Result.SetCell(nil)
  else
    Result.SetCell(FLifeObj.Cell);
end;

function TShared.TryLock(const W: specialize TWeak<T>): Boolean;
var
  C: TSafeCell;
  L: TSafeLife;
begin
  C := W.CellObj;
  L := nil;
  if C <> nil then
    L := TSafeLife(C.AcquireLife); // thread-safe against the last Reset in another thread (H6)
  Result := L <> nil;
  if Result then
  begin
    FLife := L; // strong reference: the object will not die while it exists
    FLife._Release; // the reference that AcquireLife took for us; FLife holds its own
    FLifeObj := L;
    FObj := T(L.Obj);
  end
  else
    Reset;
end;

{ ---------- TSlice ---------- }

class function TSlice.From(const A: specialize TArray<T>): TSlice;
begin
  Result.FData := A;
  Result.FStart := 0;
  Result.FLen := Length(A);
end;

function TSlice.Sub(AStart, ALen: SizeInt): TSlice;
begin
  if (AStart < 0) or (ALen < 0) or (AStart > FLen - ALen) then
    SafeFail(Format('SAFE-R2: TSlice.Sub(%d, %d) out of bounds, length %d', [AStart, ALen, FLen]));
  Result.FData := FData;
  Result.FStart := FStart + AStart;
  Result.FLen := ALen;
end;

function TSlice.Len: SizeInt;
begin
  Result := FLen;
end;

function TSlice.ToArray: specialize TArray<T>;
begin
  Result := Copy(FData, FStart, FLen);
end;

function TSlice.GetItem(I: SizeInt): T;
begin
  if (I < 0) or (I >= FLen) then
    SafeFail(Format('SAFE-R2: TSlice index %d out of bounds, length %d', [I, FLen]));
  Result := FData[FStart + I];
end;

procedure TSlice.SetItem(I: SizeInt; const V: T);
begin
  if (I < 0) or (I >= FLen) then
    SafeFail(Format('SAFE-R2: TSlice index %d out of bounds, length %d', [I, FLen]));
  FData[FStart + I] := V;
end;

{ ---------- TArena ---------- }

class function TArena.Create: TArena;
begin
  Result.FImpl := TSafeArenaImpl.Create;
  Result.FRef := Result.FImpl;
  Result.FImpl.GenObj := TSafeArenaGen.Create;
  Result.FImpl.GenRef := Result.FImpl.GenObj;
end;

procedure TArena.Check;
begin
  if FRef = nil then
    SafeFail('SAFE-R4: TArena used before TArena.Create');
end;

function TArena.Adopt(AObj: TObject): TObject;
begin
  Check;
  Result := AObj;
  if AObj = nil then
    Exit;
  if AObj is TInterfacedObject then
    SafeFail('SAFE-R3: TArena.Adopt(' + AObj.ClassName +
      '): TInterfacedObject is owned by its interface refcount; hold it through an interface');
  if FImpl.Count = Length(FImpl.Items) then
    SetLength(FImpl.Items, 2 * FImpl.Count + 8);
  FImpl.Items[FImpl.Count] := AObj;
  Inc(FImpl.Count);
  InterlockedIncrement(GLive);
end;

procedure TArena.FreeAll;
begin
  Check;
  FImpl.FreeAll;
end;

function TArena.Count: SizeInt;
begin
  Check;
  Result := FImpl.Count;
end;

function TArena.Generation: LongWord;
begin
  Check;
  Result := FImpl.GenObj.Generation;
end;

function TArena.GenCell: TSafeArenaGen;
begin
  Check;
  Result := FImpl.GenObj;
end;

{ ---------- TArenaRef ---------- }

class function TArenaRef.Adopt(AObj: T; var A: TArena): TArenaRef;
begin
  Result.FObj := T(A.Adopt(AObj));
  if SafeDebugChecks and (AObj <> nil) then
  begin
    Result.FGenObj := A.GenCell;
    Result.FGenRef := Result.FGenObj;
    Result.FGen := Result.FGenObj.Generation;
    Result.FCls := AObj.ClassType;
  end
  else
  begin // Result may reuse the storage of the target variable: clear every field
    Result.FGenObj := nil;
    Result.FGenRef := nil;
    Result.FGen := 0;
    Result.FCls := nil;
  end;
end;

function TArenaRef.IsStale: Boolean;
begin
  Result := (FGenObj <> nil) and (FGenObj.Generation <> FGen);
end;

function TArenaRef.Get: T;
begin
  if (FGenObj <> nil) and (FGenObj.Generation <> FGen) then
    SafeFail('SAFE-R10: TArenaRef.Get of ' + FCls.ClassName +
      ' after TArena.FreeAll: the object is destroyed; take the reference again after the arena is refilled');
  Result := FObj;
end;

{ ---------- defer ---------- }

destructor TSafeDeferImpl.Destroy;
begin
  if (not Cancelled) and Assigned(Proc) then
    try
      Proc();
    except
      InterlockedIncrement(GDeferFailures); // cannot throw from a destructor: count it, SafeCheckNoLeaks will notice
    end;
  inherited Destroy;
end;

class function TDefer.Call(AProc: TSafeDeferProc): TDefer;
begin
  Result.FImpl := TSafeDeferImpl.Create;
  Result.FImpl.Proc := AProc;
  Result.FRef := Result.FImpl;
end;

procedure TDefer.Cancel;
begin
  if FImpl <> nil then
    FImpl.Cancelled := True;
end;

{ ---------- FFI ---------- }

constructor TCResource.Create(APtr: System.Pointer; AFree: TCFreeProc);
begin
  inherited Create;
  FPtr := APtr;
  FFree := AFree;
end;

destructor TCResource.Destroy;
begin
  if (FPtr <> nil) and Assigned(FFree) then
    FFree(FPtr);
  FPtr := nil;
  inherited Destroy;
end;

function TCResource.Ptr: System.Pointer;
begin
  Result := FPtr;
end;


function SafeGoFailures: LongInt;
begin
  Result := GGoFailures;
end;
