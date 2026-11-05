{ SPDX-License-Identifier: MIT }
{ Safe Pascal, region style (implementation): SPEC §20. }

const
  SafeRegionFirstBlock = 4096;

type
  PSafeRegionBlock = ^TSafeRegionBlock;
  TSafeRegionBlock = record
    Next: PSafeRegionBlock;   // the block taken before this one (smaller)
    Size: SizeUInt;
  end;

  TSafeRegionFinKind = (
    sfkClean,                 // an object of the region with managed fields: CleanupInstance
    sfkArray,                 // Count elements of the type Info at P: FinalizeArray
    sfkHeld,                  // an object on the heap (Hold): Destroy
    sfkDefer);                // an action (Defer): Proc

  TSafeRegionFinalizer = record
    Kind: TSafeRegionFinKind;
    P: System.Pointer;
    Info: System.Pointer;     // the type info of an element of an array
    Count: SizeInt;           // the elements of an array
    Proc: TSafeDeferProc;
  end;

  PSafeRegionCell = ^TSafeRegionCell; // the layout of TRegion
  TSafeRegionCell = record
    D: System.Pointer;
  end;
  PSafeRegionData = ^TSafeRegionData;
  TSafeRegionData = record
    Cur, Limit: System.PByte;
    Blocks: PSafeRegionBlock; // the newest (largest) block first
    Fin: array of TSafeRegionFinalizer;
    FinCount: SizeInt;
    Outer: PSafeRegionData;   // the region that was current before this one
    Fresh: Boolean;           // made by Create and empty yet: the result of Create may still move (TRegion.Copy)
  end;

threadvar
  GRegionCurrent: PSafeRegionData; // the innermost region of this goroutine

function CurrentRegionDepth: Integer;
var
  D: PSafeRegionData;
begin
  Result := 0;
  D := GRegionCurrent;
  while D <> nil do
  begin
    Inc(Result);
    D := D^.Outer;
  end;
end;

procedure SafeRegionNewBlock(D: PSafeRegionData; Need: SizeUInt);
var
  Size: SizeUInt;
  B: PSafeRegionBlock;
begin
  if D^.Blocks = nil then
    Size := SafeRegionFirstBlock
  else
    Size := 2 * D^.Blocks^.Size;
  while Size < Need + SizeOf(TSafeRegionBlock) + 16 do
    Size := 2 * Size;
  {$if defined(SAFE_DEBUG) and defined(unix)}
  // R12: each block is pages of its own, so a reset or a release can take all access away from it
  B := Fpmmap(nil, Size, PROT_READ or PROT_WRITE, MAP_PRIVATE or MAP_ANONYMOUS, -1, 0);
  if System.Pointer(B) = MAP_FAILED then
    SafeFail('SAFE-R12: mmap of a region block failed');
  {$else}
  // UNSAFE: the blocks of a region are raw memory; the region hands it out to its objects and arrays
  System.GetMem(B, Size);
  {$endif}
  D^.Fresh := False;
  B^.Next := D^.Blocks;
  B^.Size := Size;
  D^.Blocks := B;
  D^.Cur := System.PByte(Align(System.PByte(B) + SizeOf(TSafeRegionBlock), 16));
  D^.Limit := System.PByte(B) + Size;
end;

function SafeRegionCurrent: System.Pointer;
begin
  Result := GRegionCurrent;
  if Result = nil then
    SafeFail('SAFE-R15: an allocation in the current region, and the goroutine has none (make one with '
      + 'TRegion.Create or for R in Scope)');
end;

function SafeRegionAlloc(Region: System.Pointer; Size: SizeUInt): System.Pointer;
var
  D: PSafeRegionData;
begin
  if Region = nil then
    Region := SafeRegionCurrent;
  D := PSafeRegionData(Region);
  Size := (Size + 15) and not SizeUInt(15);
  if (D^.Cur = nil) or (PtrUInt(D^.Limit) - PtrUInt(D^.Cur) < Size) then
    SafeRegionNewBlock(D, Size);
  Result := D^.Cur;
  Inc(D^.Cur, Size);
end;

{ A new entry of the finalizer list of D; the caller fills it. }
function SafeRegionNewEntry(D: PSafeRegionData; const Kind: TSafeRegionFinKind): SizeInt;
begin
  if D^.FinCount = Length(D^.Fin) then
    SetLength(D^.Fin, 2 * D^.FinCount + 8);
  Result := D^.FinCount;
  D^.Fin[Result] := Default(TSafeRegionFinalizer);
  D^.Fin[Result].Kind := Kind;
  Inc(D^.FinCount);
end;

procedure SafeRegionAddFinalizer(Region, P, Info: System.Pointer; Count: SizeInt);
var
  I: SizeInt;
begin
  if Info = nil then
    I := SafeRegionNewEntry(PSafeRegionData(Region), sfkClean)
  else
    I := SafeRegionNewEntry(PSafeRegionData(Region), sfkArray);
  PSafeRegionData(Region)^.Fin[I].P := P;
  PSafeRegionData(Region)^.Fin[I].Info := Info;
  PSafeRegionData(Region)^.Fin[I].Count := Count;
end;

{ Hold: Obj is destroyed when the region D is reset or released; V := Obj. Who: the name in a message. }
procedure SafeRegionHold(D: PSafeRegionData; out V: TObject; Obj: TObject; const Who: String);
var
  I: SizeInt;
begin
  V := nil;
  if Obj = nil then
    Exit;
  if Obj is TRegionObject then
    SafeFail('SAFE-R16: ' + Who + '.Hold(' + Obj.ClassName + '): an object of a region belongs to its region');
  if (D = nil) or (Obj is TInterfacedObject) then
  begin
    // UNSAFE: nobody else owns the new object yet: it does not outlive the failed call
    Obj.Destroy;
    if D = nil then
      SafeFail('SAFE-R15: ' + Who + '.Hold in a region that is released (or a handle that has none)');
    SafeFail('SAFE-R3: ' + Who + '.Hold of a TInterfacedObject: it is owned by its interface refcount; hold it '
      + 'through an interface');
  end;
  I := SafeRegionNewEntry(D, sfkHeld);
  D^.Fin[I].P := Obj;
  V := Obj;
end;

procedure SafeRegionDefer(D: PSafeRegionData; const AProc: TSafeDeferProc; const Who: String);
var
  I: SizeInt;
begin
  if D = nil then
    SafeFail('SAFE-R15: ' + Who + '.Defer in a region that is released (or a handle that has none)');
  I := SafeRegionNewEntry(D, sfkDefer);
  D^.Fin[I].Proc := AProc;
end;

{ Runs the finalizer list of D, the newest entry first: a later object may refer to an earlier one. An exception in a
  destructor or a deferred action is counted (as in TDefer) and the rest still runs; an entry added while the list runs
  (by a destructor or an action) runs too. }
procedure SafeRegionFinalize(D: PSafeRegionData);
var
  E: TSafeRegionFinalizer;
begin
  while D^.FinCount > 0 do
  begin
    Dec(D^.FinCount);
    E := D^.Fin[D^.FinCount];
    case E.Kind of
      sfkClean:
        TObject(E.P).CleanupInstance;
      sfkArray:
        FinalizeArray(E.P, E.Info, E.Count);
      sfkHeld:
        try
          // UNSAFE: the region is the only owner of a held object (Hold); nothing uses it after the scope (S17)
          TObject(E.P).Destroy;
        except
          InterlockedIncrement(GDeferFailures);
          // FPC skips the end of a destructor that raised, FreeInstance included: the memory is freed here
          TObject(E.P).FreeInstance;
        end;
      sfkDefer:
        try
          E.Proc();
        except
          InterlockedIncrement(GDeferFailures);
        end;
    end;
  end;
end;

{ Frees the blocks of D; Keep: the newest (largest) one stays, empty, for the next round. }
procedure SafeRegionFreeBlocks(D: PSafeRegionData; Keep: Boolean);
var
  B, N, Kept: PSafeRegionBlock;
begin
  Kept := nil;
  B := D^.Blocks;
  {$if not (defined(SAFE_DEBUG) and defined(unix))}
  if Keep and (B <> nil) then
  begin
    Kept := B;
    B := B^.Next;
    Kept^.Next := nil;
  end;
  {$endif}
  while B <> nil do
  begin
    N := B^.Next;
    {$if defined(SAFE_DEBUG) and defined(unix)}
    // R12: what the block held must stop at the first access; its pages are never reused
    Fpmprotect(B, B^.Size, PROT_NONE);
    {$else}
    // UNSAFE: a block of the region, taken by SafeRegionNewBlock; nothing in it is used after a reset or a release
    System.FreeMem(B);
    {$endif}
    B := N;
  end;
  D^.Blocks := Kept;
  D^.Cur := nil;
  D^.Limit := nil;
  if Kept <> nil then
  begin
    D^.Cur := System.PByte(Align(System.PByte(Kept) + SizeOf(TSafeRegionBlock), 16));
    D^.Limit := System.PByte(Kept) + Kept^.Size;
  end;
end;

{ Finalizes what N holds, frees its blocks and N itself; N is off the stack of regions already. }
procedure SafeRegionDrop(N: PSafeRegionData);
begin
  try
    SafeRegionFinalize(N);
  finally
    SafeRegionFreeBlocks(N, False);
    // UNSAFE: made by TRegion.Create; nothing refers to it any more
    System.Dispose(N);
  end;
end;

{ ---------- TRegion ---------- }

class function TRegion.Create: TRegion;
var
  N: PSafeRegionData;
begin
  // FPC builds the result in the variable itself and does not finalize it first: R := TRegion.Create of a variable
  // that holds a region releases that one before the new one is pushed
  Result.Release;
  // UNSAFE: the data of a region lives until its Release, which disposes it
  System.New(N);
  N^.Cur := nil;
  N^.Limit := nil;
  N^.Blocks := nil;
  N^.FinCount := 0;
  N^.Outer := GRegionCurrent;
  N^.Fresh := True;
  GRegionCurrent := N;
  Result.D := N;
end;

procedure TRegion.Reset;
begin
  if D = nil then
    Exit;
  SafeRegionFinalize(PSafeRegionData(D));
  SafeRegionFreeBlocks(PSafeRegionData(D), True);
end;

procedure TRegion.Release;
var
  N: PSafeRegionData;
begin
  if D = nil then
    Exit;
  if GRegionCurrent <> D then
    SafeFail('SAFE-R14: Release of a region that is not the innermost one of the goroutine (regions are nested)');
  N := PSafeRegionData(D);
  D := nil;
  GRegionCurrent := N^.Outer;
  SafeRegionDrop(N);
end;

procedure TRegion.Hold(out V; Obj: TObject);
begin
  // UNSAFE: V is a variable of a class type (the typed bpvet checks it): its memory is a class reference
  SafeRegionHold(PSafeRegionData(D), TObject(V), Obj, 'TRegion');
end;

procedure TRegion.Defer(AProc: TSafeDeferProc);
begin
  SafeRegionDefer(PSafeRegionData(D), AProc, 'TRegion');
end;

function TRegion.Used: SizeUInt;
var
  B: PSafeRegionBlock;
begin
  Result := 0;
  if D = nil then
    Exit;
  B := PSafeRegionData(D)^.Blocks;
  while B <> nil do
  begin
    Inc(Result, B^.Size);
    B := B^.Next;
  end;
end;

class operator TRegion.Initialize(var R: TRegion);
begin
  R.D := nil;
end;

class operator TRegion.Finalize(var R: TRegion);
begin
  R.Release;
end;

{ A region has one owner. FPC builds the result of R := TRegion.Create in R itself, except when R is passed by
  reference somewhere in the routine: then it builds it in a temporary and copies. So the region of a Create that has
  allocated nothing yet moves into Dst (the temporary is left empty); any other copy raises. A region Dst held before
  is released: when the new one was pushed right over it, the new one takes its place in the stack of regions. }
class operator TRegion.Copy(constref Src: TRegion; var Dst: TRegion);
var
  N, Old: PSafeRegionData;
begin
  N := PSafeRegionData(Src.D);
  if (N = nil) or not N^.Fresh then
    SafeFail('SAFE: a TRegion is copied; a region has one owner, its variable (R := TRegion.Create)');
  N^.Fresh := False;
  Old := PSafeRegionData(Dst.D);
  if (Old <> nil) and (GRegionCurrent = N) and (N^.Outer = Old) then
  begin
    N^.Outer := Old^.Outer;
    Dst.D := nil;
    SafeRegionDrop(Old);
  end
  else
    Dst.Release;
  Dst.D := N;
  // UNSAFE: the move out of the temporary that holds the result of Create (D is its only field); it is finalized next
  // and must not release
  PSafeRegionCell(@Src)^.D := nil;
end;

procedure SafeRegionReleaseData(var D: System.Pointer);
var
  R: TRegion;
begin
  R.D := D;
  D := nil;
  R.Release;
end;

procedure SafeRegionRound(var D: System.Pointer);
var
  R: TRegion;
begin
  if D = nil then
  begin
    R := TRegion.Create;
    D := R.D;
  end
  else
  begin
    R.D := D;
    R.Reset;  // the region of the iteration before
  end;
  R.D := nil;
end;

{ ---------- TSafeRegionHold ---------- }

class operator TSafeRegionHold.Initialize(var H: TSafeRegionHold);
begin
  H.D := nil;
end;

class operator TSafeRegionHold.Finalize(var H: TSafeRegionHold);
begin
  if H.D <> nil then
    SafeRegionReleaseData(H.D);
end;

class operator TSafeRegionHold.Copy(constref Src: TSafeRegionHold; var Dst: TSafeRegionHold);
begin
  if Src.D <> nil then
    SafeFail('SAFE: an enumerator of a region is copied after its region was made');
  Dst.D := nil;
end;

{ ---------- Scope ---------- }

function TScope.MoveNext: Boolean;
var
  R: TRegion;
begin
  Inc(N);
  if N = 1 then
  begin
    R := TRegion.Create;
    D := R.D;
    R.D := nil;
    Exit(True);
  end;
  if D <> nil then
    SafeRegionReleaseData(D);
  Result := False;
end;

function TScope.GetCurrent: TScopeRef;
begin
  Result.D := D;
end;

{ ---------- TScopeRef ---------- }

procedure TScopeRef.Hold(out V; Obj: TObject);
begin
  // UNSAFE: V is a variable of a class type (the typed bpvet checks it): its memory is a class reference
  SafeRegionHold(PSafeRegionData(D), TObject(V), Obj, 'Scope');
end;

procedure TScopeRef.Defer(AProc: TSafeDeferProc);
begin
  SafeRegionDefer(PSafeRegionData(D), AProc, 'Scope');
end;

function TScopeRef.Depth: Integer;
var
  N: PSafeRegionData;
begin
  Result := 0;
  N := PSafeRegionData(D);
  while N <> nil do
  begin
    Inc(Result);
    N := N^.Outer;
  end;
end;

class operator TScope.Initialize(var S: TScope);
begin
  S.D := nil;
  S.N := 0;
end;

class operator TScope.Finalize(var S: TScope);
begin
  if S.D <> nil then
    SafeRegionReleaseData(S.D);
end;

class operator TScope.Copy(constref Src: TScope; var Dst: TScope);
begin
  if Src.D <> nil then
    SafeFail('SAFE: a TScope is copied after its region was made');
  Dst.N := Src.N;
end;

function TScopes.GetEnumerator: TScope;
begin
  Result.N := 0;
end;

function Scope: TScopes;
begin
  Result := Default(TScopes);
end;

{ ---------- Each ---------- }

function Each(const Lines: array of String): TEachString;
var
  K: SizeInt;
begin
  Result := Default(TEachString);
  SetLength(Result.Items, Length(Lines));
  for K := 0 to High(Lines) do
    Result.Items[K] := Lines[K];
  Result.I := -1;
end;

function TEachString.GetEnumerator: TEachString;
begin
  Result := Self;
end;

function TEachString.GetCurrent: String;
begin
  Result := Items[I];
end;

function TEachString.MoveNext: Boolean;
begin
  Inc(I);
  SafeRegionRound(D);
  Result := I <= High(Items);
  if not Result then
    SafeRegionReleaseData(D);
end;

class operator TEachString.Initialize(var S: TEachString);
begin
  S.D := nil;
  S.I := -1;
end;

class operator TEachString.Finalize(var S: TEachString);
begin
  if S.D <> nil then
    SafeRegionReleaseData(S.D);
end;

class operator TEachString.Copy(constref Src: TEachString; var Dst: TEachString);
begin
  if Src.D <> nil then
    SafeFail('SAFE: a TEachString is copied after its region was made');
  Dst.Items := Src.Items;
  Dst.I := Src.I;
end;

{ ---------- TRegionObject ---------- }

function SafeHasManagedFields(C: TClass): Boolean;
begin
  while C <> nil do
  begin
    if PVmt(C)^.vInitTable <> nil then
      Exit(True);
    C := C.ClassParent;
  end;
  Result := False;
end;

class function TRegionObject.NewInstance: TObject;
var
  D, P: System.Pointer;
begin
  D := SafeRegionCurrent;
  P := SafeRegionAlloc(D, InstanceSize);
  Result := InitInstance(P);
  if SafeHasManagedFields(Self) then
    SafeRegionAddFinalizer(D, P, nil, 1);
end;

procedure TRegionObject.FreeInstance;
begin
  // nothing: the region releases its objects at once
end;

{ ---------- TGrowArray ---------- }

procedure SafeGrowIndexFail(I, Len: SizeInt);
begin
  SafeFail(Format('SAFE-R2: TGrowArray index %d out of bounds, length %d', [I, Len]));
end;

class function TGrowArray.Make(Region: System.Pointer): TGrowArray;
begin
  Result.P := SafeRegionAlloc(Region, SizeOf(TData));
  System.FillChar(Result.P^, SizeOf(TData), 0);
  Result.P^.Region := Region;
end;

class function TGrowArray.Create: TGrowArray;
begin
  Result := Make(SafeRegionCurrent);
end;

class function TGrowArray.Create(var R: TRegion): TGrowArray;
begin
  if R.D = nil then
    SafeFail('SAFE-R15: TGrowArray.Create in a region that is released');
  Result := Make(R.D);
end;

function TGrowArray.Len: SizeInt;
begin
  Result := P^.Len;
end;

function TGrowArray.At(I: SizeInt): PT;
var
  J: SizeUInt;
  K: Integer;
begin
  if SizeUInt(I) >= SizeUInt(P^.Len) then
    SafeGrowIndexFail(I, P^.Len);
  J := SizeUInt(I) + (SizeUInt(1) shl ChunkLog2);
  K := {$ifdef CPU64}BsrQWord(J){$else}BsrDWord(J){$endif};
  Result := P^.Chunks[K - ChunkLog2] + (J - (SizeUInt(1) shl K));
end;

function TGrowArray.Push(const V: T): SizeInt;
var
  J: SizeUInt;
  K: Integer;
  N: SizeInt;
  C: PT;
begin
  Result := P^.Len;
  J := SizeUInt(Result) + (SizeUInt(1) shl ChunkLog2);
  K := {$ifdef CPU64}BsrQWord(J){$else}BsrDWord(J){$endif};
  if J = SizeUInt(1) shl K then
  begin
    // the first element of a new chunk of 2^K elements, in the region of the header
    N := SizeInt(1) shl K;
    C := SafeRegionAlloc(P^.Region, N * SizeOf(T));
    System.FillChar(PCell(C)^, N * SizeOf(T), 0);
    if Boolean(IsManagedType(T)) then
      SafeRegionAddFinalizer(P^.Region, C, TypeInfo(T), N);
    P^.Chunks[K - ChunkLog2] := C;
  end;
  Inc(P^.Len);
  PCell(At(Result))^.V := V;
end;

function TGrowArray.GetItem(I: SizeInt): T;
begin
  Result := PCell(At(I))^.V;
end;

procedure TGrowArray.SetItem(I: SizeInt; const V: T);
begin
  PCell(At(I))^.V := V;
end;

function TGrowArray.GetEnumerator: TEnum;
begin
  Result.Cur := nil;
  Result.Stop := nil;
  Result.Data := P;
  Result.Chunk := 0;
  Result.Left := P^.Len;
end;

function TGrowArray.TEnum.MoveNext: Boolean;
begin
  Inc(Cur);
  Result := (PtrUInt(Cur) < PtrUInt(Stop)) or NextChunk;
end;

function TGrowArray.TEnum.NextChunk: Boolean;
var
  N: SizeInt;
begin
  if Left <= 0 then
    Exit(False);
  N := SizeInt(1) shl (Chunk + ChunkLog2);
  if N > Left then
    N := Left;
  Cur := Data^.Chunks[Chunk];
  Stop := Cur + N;
  Dec(Left, N);
  Inc(Chunk);
  Result := True;
end;

function TGrowArray.Chunks: TChunkEnum;
begin
  Result.Cur.Data := nil;
  Result.Cur.Count := 0;
  Result.Data := P;
  Result.Chunk := 0;
  Result.Left := P^.Len;
end;

function TGrowArray.TChunkEnum.GetEnumerator: TChunkEnum;
begin
  Result := Self;
end;

function TGrowArray.TChunkEnum.MoveNext: Boolean;
begin
  if Left <= 0 then
    Exit(False);
  Cur.Count := SizeInt(1) shl (Chunk + ChunkLog2);
  if Cur.Count > Left then
    Cur.Count := Left;
  Cur.Data := Data^.Chunks[Chunk];
  Dec(Left, Cur.Count);
  Inc(Chunk);
  Result := True;
end;

function TGrowArray.Each: TEachEnum;
begin
  Result.E := GetEnumerator;
end;

function TGrowArray.TEachEnum.GetEnumerator: TEachEnum;
begin
  Result := Self;
end;

function TGrowArray.TEachEnum.GetCurrent: PT;
begin
  Result := E.Current;
end;

function TGrowArray.TEachEnum.MoveNext: Boolean;
begin
  SafeRegionRound(H.D);
  Result := E.MoveNext;
  if not Result then
    SafeRegionReleaseData(H.D);
end;
