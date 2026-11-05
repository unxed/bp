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
    GLives.PrevLive := L; // UNSAFE: under SafeLockLives
  GLives := L; // UNSAFE: under SafeLockLives
  L.Listed := True;
  SafeUnlockLives;
end;

procedure SafeUnlistLife(L: TSafeLife);
begin
  SafeLockLives;
  if L.PrevLive <> nil then
    L.PrevLive.NextLive := L.NextLive
  else
    GLives := L.NextLive; // UNSAFE: under SafeLockLives
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

{ ---------- R20: the quarantine of freed class objects (SAFE_DEBUG) ----------
  The paths that destroy an object for the dialect (TSafeLife, TSafeArenaImpl.FreeAll, a held object of a region) call
  SafeDestroyObject. With debug checks on it arms the address of the object, runs the destructor, and the
  FreeMem(Pointer(Self)) that ends every destructor reaches a wrapper of the memory manager, which finds the address
  armed and keeps the block: its VMT pointer becomes the poison VMT, the fields $DE, and the block waits in a ring.
  The wrapper goes over the manager in use (the heap of BP, the heap of the RTL, heaptrc): it is installed on the
  first owned object made with the checks on and only then, so a build with the checks off never has it. }
type
  PSafeQEntry = ^TSafeQEntry;
  TSafeQEntry = record
    P: PtrUInt;      // the block; 0 is an empty slot of the table of armed addresses
    Orig: PtrUInt;   // the VMT of the class it had (the ring)
    Size: SizeInt;   // the size of the instance
  end;
  TSafeQArr = array[0..(MaxInt div 64)] of TSafeQEntry;
  PSafeQArr = ^TSafeQArr;
  PSafeVmtWords = ^TSafeVmtWords;
  TSafeVmtWords = array[0..(MaxInt div 64)] of PtrUInt;

const
  SafeQPoisonSlots = 1024;   // virtual methods of the poison VMT; a class with more has the rest unchecked
  SafeQFillByte = $DE;
  SafeQPoisonName: ShortString = 'TSafeFreedObject';

var
  GQLock: LongInt = 0;
  GQInstalled: Boolean = False;
  GQClosed: Boolean = False;       // the quarantine was flushed at exit: nothing is armed any more
  GQOld: TMemoryManager;
  GQMaxObjects: SizeInt = 4096;
  GQMaxBytes: SizeInt = 16 * 1024 * 1024;
  GQRing: PSafeQArr = nil;
  GQCap: SizeInt = 0;
  GQHead: SizeInt = 0;             // the oldest
  GQCount: SizeInt = 0;
  GQBytes: SizeInt = 0;
  GQArmed: PSafeQArr = nil;        // open addressing, a power of two slots
  GQArmedCap: SizeInt = 0;
  GQArmedCount: SizeInt = 0;       // read without the lock by the wrapper: zero means nothing to look for
  GQPoison: PSafeVmtWords = nil;

{$push}{$R-}{$Q-}
procedure SafeQLock;
begin
  while InterlockedCompareExchange(GQLock, 1, 0) <> 0 do
    ThreadSwitch;
end;

procedure SafeQUnlock;
begin
  InterlockedExchange(GQLock, 0);
end;

function SafeQHash(P: PtrUInt): SizeInt;
var
  H: PtrUInt;
begin
  H := P shr 4;
  Result := SizeInt((H xor (H shr 9) xor (H shr 17)) and PtrUInt(GQArmedCap - 1));
end;

{ Under the lock. }
procedure SafeQArmedPut(P: PtrUInt; Size: SizeInt);
var
  I: SizeInt;
begin
  I := SafeQHash(P);
  while GQArmed^[I].P <> 0 do
  begin
    if GQArmed^[I].P = P then
      Break;
    I := (I + 1) and (GQArmedCap - 1);
  end;
  if GQArmed^[I].P = 0 then
    Inc(GQArmedCount);
  GQArmed^[I].P := P;
  GQArmed^[I].Size := Size;
end;

procedure SafeQArmedGrow;
var
  Old: PSafeQArr;
  OldCap, I: SizeInt;
begin
  Old := GQArmed;
  OldCap := GQArmedCap;
  GQArmedCap := OldCap * 2;
  GQArmed := GQOld.AllocMem(GQArmedCap * SizeOf(TSafeQEntry));
  GQArmedCount := 0;
  for I := 0 to OldCap - 1 do
    if Old^[I].P <> 0 then
      SafeQArmedPut(Old^[I].P, Old^[I].Size);
  GQOld.FreeMem(Old);
end;

{ Under the lock: the slot of P, or -1. }
function SafeQArmedFind(P: PtrUInt): SizeInt;
var
  I: SizeInt;
begin
  I := SafeQHash(P);
  while GQArmed^[I].P <> 0 do
  begin
    if GQArmed^[I].P = P then
      Exit(I);
    I := (I + 1) and (GQArmedCap - 1);
  end;
  Result := -1;
end;

{ Under the lock: removes slot I and moves back the entries of its run that the hole would hide. }
procedure SafeQArmedDelete(I: SizeInt);
var
  J, K: SizeInt;
begin
  J := I;
  while True do
  begin
    J := (J + 1) and (GQArmedCap - 1);
    if GQArmed^[J].P = 0 then
      Break;
    K := SafeQHash(GQArmed^[J].P);
    if ((J > I) and ((K <= I) or (K > J))) or ((J < I) and ((K <= I) and (K > J))) then
    begin
      GQArmed^[I] := GQArmed^[J];
      I := J;
    end;
  end;
  GQArmed^[I].P := 0;
  Dec(GQArmedCount);
end;

{ Every virtual method of the poison VMT. The object is the first argument, as for any method. }
procedure SafeQTrap(Obj: System.Pointer);
var
  I: SizeInt;
  Cls: String;
begin
  Cls := '';
  SafeQLock;
  for I := 0 to GQCount - 1 do
    if GQRing^[(GQHead + I) mod GQCap].P = PtrUInt(Obj) then
    begin
      Cls := TClass(System.Pointer(GQRing^[(GQHead + I) mod GQCap].Orig)).ClassName;
      Break;
    end;
  SafeQUnlock;
  if Cls = '' then
    SafeFail('SAFE-R20: a virtual method of an object that was freed (it has left the quarantine) is called')
  else
    SafeFail('SAFE-R20: a virtual method of a freed ' + Cls + ' is called (use after free or a second free)');
end;

{ Under the lock: the oldest block goes back to the heap. }
procedure SafeQEvictOldest;
var
  E: PSafeQEntry;
begin
  E := @GQRing^[GQHead];
  Dec(GQBytes, E^.Size);
  GQOld.FreeMem(System.Pointer(E^.P));
  GQHead := (GQHead + 1) mod GQCap;
  Dec(GQCount);
end;

function SafeQFreeMem(P: System.Pointer): PtrUInt;
var
  I: SizeInt;
  Size: SizeInt;
  W: PSafeVmtWords;
  Tail: System.PByte;
  E: PSafeQEntry;
begin
  if (GQArmedCount <> 0) and (P <> nil) then
  begin
    SafeQLock;
    I := SafeQArmedFind(PtrUInt(P));
    if I >= 0 then
    begin
      Size := GQArmed^[I].Size;
      SafeQArmedDelete(I);
      W := PSafeVmtWords(P);
      while (GQCount >= GQCap) or ((GQCount > 0) and (GQBytes + Size > GQMaxBytes)) do
        SafeQEvictOldest;
      E := @GQRing^[(GQHead + GQCount) mod GQCap];
      E^.P := PtrUInt(P);
      E^.Orig := W^[0];
      E^.Size := Size;
      Inc(GQCount);
      Inc(GQBytes, Size);
      W^[0] := PtrUInt(GQPoison);
      Tail := System.PByte(P) + SizeOf(PtrUInt);
      System.FillChar(Tail^, Size - SizeOf(PtrUInt), SafeQFillByte);
      SafeQUnlock;
      Exit(Size);
    end;
    SafeQUnlock;
  end;
  Result := GQOld.FreeMem(P);
end;

function SafeQFreeMemSize(P: System.Pointer; Size: PtrUInt): PtrUInt;
begin
  Result := SafeQFreeMem(P);   // the size is the manager's to know; the RTL heap and the heap of BP both ignore it
end;

procedure SafeQuarantineFlush;
begin
  SafeQLock;
  while GQCount > 0 do
    SafeQEvictOldest;
  SafeQUnlock;
end;

procedure SafeQuarantineExit;
begin
  SafeQuarantineFlush;
  SafeQLock;
  GQClosed := True;   // the manager stays installed for the rest of the exit; nothing is armed from now on
  SafeQUnlock;
end;

{ Allocates the ring (under the lock). }
procedure SafeQAllocRing;
begin
  GQCap := GQMaxObjects;
  if GQCap < 1 then
    GQCap := 1;
  GQRing := GQOld.AllocMem(GQCap * SizeOf(TSafeQEntry));
  GQHead := 0;
  GQCount := 0;
  GQBytes := 0;
end;

procedure SafeQuarantineSetLimits(MaxObjects, MaxBytes: SizeInt);
begin
  SafeQuarantineFlush;
  SafeQLock;
  GQMaxObjects := MaxObjects;
  GQMaxBytes := MaxBytes;
  if GQRing <> nil then
  begin
    GQOld.FreeMem(GQRing);
    SafeQAllocRing;
  end;
  SafeQUnlock;
end;

function SafeQuarantineCount: SizeInt;
begin
  Result := GQCount;
end;

{ Installs the wrapper once. Debug checks only; the first owned object calls it, so it is in place before the
  program starts its threads. }
procedure SafeQuarantineEnsure;
var
  M: TMemoryManager;
  Base: PSafeVmtWords;
  I: SizeInt;
begin
  if GQInstalled then
    Exit;
  SafeQLock;
  if not GQInstalled then
  begin
    GetMemoryManager(GQOld);
    SafeQAllocRing;
    GQArmedCap := 256;
    GQArmed := GQOld.AllocMem(GQArmedCap * SizeOf(TSafeQEntry));
    // the poison VMT: the header of TObject without a parent, a name of its own, and a trap in every slot
    Base := PSafeVmtWords(System.Pointer(TObject));
    GQPoison := GQOld.AllocMem(vmtMethodStart + SafeQPoisonSlots * SizeOf(CodePointer));
    System.Move(Base^, GQPoison^, vmtMethodStart);
    GQPoison^[vmtInstanceSize div SizeOf(PtrUInt)] := SizeOf(PtrUInt);
    GQPoison^[vmtInstanceSize div SizeOf(PtrUInt) + 1] := PtrUInt(-SizeInt(SizeOf(PtrUInt)));
    for I := vmtParent div SizeOf(PtrUInt) to vmtMsgStrPtr div SizeOf(PtrUInt) do
      GQPoison^[I] := 0;
    GQPoison^[vmtClassName div SizeOf(PtrUInt)] := PtrUInt(@SafeQPoisonName);
    for I := vmtMethodStart div SizeOf(PtrUInt) to vmtMethodStart div SizeOf(PtrUInt) + SafeQPoisonSlots - 1 do
      GQPoison^[I] := PtrUInt(@SafeQTrap);
    M := GQOld;
    M.FreeMem := @SafeQFreeMem;
    M.FreememSize := @SafeQFreeMemSize;
    SetMemoryManager(M);
    AddExitProc(@SafeQuarantineExit);
    GQInstalled := True;
  end;
  SafeQUnlock;
end;

{ Arms the address of O for its destruction; False when the object is not to be kept (already freed, or the
  quarantine is closed). }
function SafeQArm(O: TObject): Boolean;
begin
  SafeQuarantineEnsure;
  Result := False;
  if PtrUInt(O.ClassType) = PtrUInt(GQPoison) then
    Exit;
  SafeQLock;
  if not GQClosed then
  begin
    if (GQArmedCount + 1) * 2 > GQArmedCap then
      SafeQArmedGrow;
    SafeQArmedPut(PtrUInt(O), O.InstanceSize);
    Result := True;
  end;
  SafeQUnlock;
end;

procedure SafeQDisarm(O: TObject);
var
  I: SizeInt;
begin
  SafeQLock;
  I := SafeQArmedFind(PtrUInt(O));
  if I >= 0 then
    SafeQArmedDelete(I);
  SafeQUnlock;
end;
{$pop}

procedure SafeDestroyQuarantined(O: TObject);
begin
  if not SafeQArm(O) then
  begin
    O.Destroy;
    Exit;
  end;
  try
    O.Destroy;
  finally
    SafeQDisarm(O);
  end;
end;

{ The destruction of an owned object: the destructor, and with debug checks on, the quarantine (R20). }
procedure SafeDestroyObject(O: TObject);
begin
  if SafeDebugChecks then
    SafeDestroyQuarantined(O)
  else
    O.Destroy; // Free is shadowed by a helper here
end;

function SafeDynArrayRefs(const P: Pointer): SizeInt;
begin
  if P = nil then
    Exit(0);
  // UNSAFE: the header of a dynamic array in the FPC RTL, the reference count and the high bound before the data
  Result := PSizeInt(System.PByte(P) - 2 * SizeOf(SizeInt))^;
end;

function SafeNewLife(AObj: TObject; const Who: string): TSafeLife;
begin
  if AObj = nil then
    Exit(nil);
  if AObj is TInterfacedObject then
    SafeFail('SAFE-R3: ' + Who + '(' + AObj.ClassName +
      '): TInterfacedObject is owned by its interface refcount; hold it through an interface');
  if AObj is TRegionObject then
    SafeFail('SAFE-R16: ' + Who + '(' + AObj.ClassName + '): an object of a region belongs to its region');
  Result := TSafeLife.Create;
  Result.Obj := AObj;
  if SafeDebugChecks then
  begin
    SafeQuarantineEnsure;
    SafeListLife(Result);
  end;
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
    SafeDestroyObject(O);
    InterlockedDecrement(GLive);
  end;
  CellRef := nil;
  inherited Destroy;
end;

function TSafeLife.QueryInterface(constref IID: TGUID; out Obj): LongInt;
  {$ifndef WINDOWS}cdecl{$else}stdcall{$endif};
begin
  if GetInterface(IID, Obj) then
    Result := S_OK
  else
    Result := LongInt(E_NOINTERFACE);
end;

function TSafeLife._AddRef: LongInt; {$ifndef WINDOWS}cdecl{$else}stdcall{$endif};
begin
  Result := InterlockedIncrement(FRefCount);
end;

function TSafeLife._Release: LongInt; {$ifndef WINDOWS}cdecl{$else}stdcall{$endif};
begin
  Result := InterlockedDecrement(FRefCount);
  if Result = 0 then
    Destroy; // TryAddRef sees 0 from now on and does not revive it
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
    if (Life <> nil) and (Life as TSafeLife).TryAddRef then
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
    SafeDestroyObject(O);
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
    L := C.AcquireLife as TSafeLife; // thread-safe against the last Reset in another thread (H6)
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
  if AObj is TRegionObject then
    SafeFail('SAFE-R16: TArena.Adopt(' + AObj.ClassName + '): an object of a region belongs to its region');
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
