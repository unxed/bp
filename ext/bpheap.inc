{ SPDX-License-Identifier: MIT }
{ The memory manager of BP (SPEC §25.4), included by BPThreads after bpsched.inc. On with BP_HEAP=bp at run time (or
  -dBP_HEAP as the default of a build); never under another manager (heaptrc, cmem: IsMemoryManagerSet).

  - Address space: reservations of PROT_NONE cut into segments of 4 MiB aligned to their size; a block finds its
    segment by a mask, and the header of the segment (its page 0) describes the 63 other pages of 64 KiB.
  - A page holds blocks of one size class (72 classes up to 32 KiB, at most 12.5% lost to rounding). A larger block is
    a run of pages; a block over 63 pages is a run of whole segments.
  - A cache per carrier (a goroutine uses the cache of its carrier: it is never preempted, so nothing switches it away
    in the middle of an allocation) and per OS thread; an ended thread gives its cache back to a pool, with its pages,
    and the next thread takes it. Per class: the current page, the pages with free blocks, the full pages.
  - A free into a page of this cache pushes onto its free list; into a page of another cache, onto the list of the
    page for other threads (an atomic push), which the owner takes when it runs out. A remote free into a full page
    counts on its owner (FullRemote), so the owner looks at its full pages again.
  - The blocks of the RTL heap made before the install (outside the reservations) go back to the RTL. }

const
  HeapSegLog2 = 22;
  HeapSegSize = PtrUInt(1) shl HeapSegLog2;
  HeapPageLog2 = 16;
  HeapPageSize = PtrUInt(1) shl HeapPageLog2;
  HeapPagesPerSeg = HeapSegSize div HeapPageSize;   // 64; page 0 is the header
  HeapMaxSmall = 32768;
  HeapClasses = 72;
  HeapSegMagic = PtrUInt($B9EA95E6);
  {$ifdef cpu64}
  HeapResSegs = 16384;   // 64 GiB of addresses per reservation, no memory
  HeapMaxRes = 8;
  {$else}
  HeapResSegs = 16;      // 64 MiB: the 32-bit address space is tight
  HeapMaxRes = 48;
  {$endif}

  PkFree = 0;   // the kinds of a page
  PkSmall = 1;
  PkLarge = 2;  // the first page of a run of pages
  PkHuge = 3;   // page 1 of the first segment of a run of segments
  PkMeta = 4;   // the caches themselves

  PsNone = 0;   // the state of a small page in its cache
  PsCurrent = 1;
  PsPartial = 2;
  PsFull = 3;

type
  PHeapCache = ^THeapCache;
  PHeapPage = ^THeapPage;
  THeapPage = record
    Free: Pointer;          // the free blocks the owner hands out first
    RemoteFree: Pointer;    // blocks freed by other threads (pushed atomically, taken all at once by the owner)
    Bump, Limit: PtrUInt;   // the blocks never handed out: [Bump, Limit)
    Used: SizeInt;          // blocks handed out and not freed, as the owner knows it
    BlockSize: PtrUInt;     // a small page: the size of the class; a run: its bytes
    Owner: PHeapCache;
    Next, Prev: PHeapPage;  // the partial or the full list of the class in the owner
    Count: LongInt;         // a run: its pages (PkLarge) or segments (PkHuge)
    Cls: Byte;
    Kind: Byte;
    State: Byte;            // read by other threads without the owner (FullRemote)
  end;

  PHeapSeg = ^THeapSeg;
  THeapSeg = record
    Magic: PtrUInt;
    FreeMask: QWord;        // bit I: page I is free (page 0, the header, never)
    NextFree, PrevFree: PHeapSeg;
    InFreeList: Boolean;
    Pages: array[0..HeapPagesPerSeg - 1] of THeapPage;
  end;

  THeapCache = record
    Cur: array[0..HeapClasses - 1] of PHeapPage;
    Partial: array[0..HeapClasses - 1] of PHeapPage;
    Full: array[0..HeapClasses - 1] of PHeapPage;
    FullRemote: array[0..HeapClasses - 1] of LongInt;
    InUse: SizeInt;         // bytes allocated minus bytes freed through this cache
    NextAll: PHeapCache;
    NextPool: PHeapCache;
  end;

  THeapRes = record
    Lo, Hi: PtrUInt;
    Used: array[0..(HeapResSegs + 63) div 64 - 1] of QWord; // bit I: segment I is taken
  end;

var
  HeapOn: Boolean = False;
  HeapOld: TMemoryManager;
  HeapClassSize: array[0..HeapClasses - 1] of PtrUInt;
  HeapClassOf: array[0..HeapMaxSmall div 16] of Byte;    // by (Size + 15) shr 4
  HeapRes: array[0..HeapMaxRes - 1] of THeapRes;
  HeapResCount: LongInt = 0;
  HeapPageLock: LongInt = 0;   // the free pages, the segments, the reservations
  HeapFreeSegs: PHeapSeg = nil;
  HeapCacheLock: LongInt = 0;
  HeapAllCaches: PHeapCache = nil;
  HeapCachePool: PHeapCache = nil;
  HeapMeta: PtrUInt = 0;       // carving of cache records
  HeapMetaEnd: PtrUInt = 0;
  HeapUsedSegs: SizeInt = 0;

{ ---------- the classes ---------- }

procedure HeapInitClasses;
var
  N, K, Step, S, I: PtrUInt;
begin
  N := 0;
  for S := 1 to 8 do
  begin
    HeapClassSize[N] := S * 16;
    Inc(N);
  end;
  K := 128;
  while K < HeapMaxSmall do
  begin
    Step := K div 8;
    for S := 1 to 8 do
    begin
      HeapClassSize[N] := K + S * Step;
      Inc(N);
    end;
    K := K * 2;
  end;
  if N <> HeapClasses then
    SchedFail('the size classes of the heap');
  K := 0;
  for I := 0 to High(HeapClassOf) do
  begin
    while HeapClassSize[K] < I * 16 do
      Inc(K);
    HeapClassOf[I] := K;
  end;
end;

{ ---------- reservations and segments ---------- }

function HeapOurs(P: PtrUInt): Boolean; inline;
var
  I: LongInt;
begin
  for I := 0 to HeapResCount - 1 do
    if (P >= HeapRes[I].Lo) and (P < HeapRes[I].Hi) then
      Exit(True);
  Result := False;
end;

{ A new reservation, under HeapPageLock. False: no address space left. }
function HeapReserve: Boolean;
var
  Raw, Base, Len, N: PtrUInt;
  Tries: Integer;
  R: ^THeapRes;
begin
  Result := False;
  if HeapResCount >= HeapMaxRes then
    Exit;
  N := HeapResSegs;
  for Tries := 1 to 24 do
  begin
    Len := (N + 1) * HeapSegSize;
    Raw := PtrUInt(Fpmmap(nil, Len, PROT_NONE, MAP_PRIVATE or MAP_ANONYMOUS or MAP_NORESERVE, -1, 0));
    if Pointer(Raw) = MAP_FAILED then
    begin
      N := N div 2;
      if N < 1 then
        Break;
      Continue;
    end;
    Base := (Raw + HeapSegSize - 1) and not (HeapSegSize - 1);
    if Base > Raw then
      Fpmunmap(Pointer(Raw), Base - Raw);
    if Raw + Len > Base + N * HeapSegSize then
      Fpmunmap(Pointer(Base + N * HeapSegSize), Raw + Len - (Base + N * HeapSegSize));
    if (Base < MainHigh) and (Base + N * HeapSegSize > MainLow) then
      // in the range taken as the stack of the main thread: kept reserved, never used (as the regions of threads)
      Continue;
    R := @HeapRes[HeapResCount];
    System.FillChar(R^, SizeOf(R^), 0);
    R^.Lo := Base;
    R^.Hi := Base + N * HeapSegSize;
    // the bits past the end of a smaller reservation are taken
    while N < HeapResSegs do
    begin
      R^.Used[N shr 6] := R^.Used[N shr 6] or (QWord(1) shl (N and 63));
      Inc(N);
    end;
    ReadWriteBarrier;   // the range is written before a reader of HeapResCount may see it
    Inc(HeapResCount);
    Exit(True);
  end;
end;

{ K consecutive segments, mapped read-write, under HeapPageLock; nil: no memory. }
function HeapTakeSegs(K: LongInt): PtrUInt;
var
  I, J, M, Run, Start: LongInt;
  R: ^THeapRes;
begin
  repeat
    for I := 0 to HeapResCount - 1 do
    begin
      R := @HeapRes[I];
      Run := 0;
      Start := 0;
      J := 0;
      while J < HeapResSegs do
      begin
        if R^.Used[J shr 6] = High(QWord) then
        begin
          Run := 0;
          J := (J or 63) + 1;   // the whole word is taken
          Continue;
        end;
        if R^.Used[J shr 6] and (QWord(1) shl (J and 63)) <> 0 then
          Run := 0
        else
        begin
          if Run = 0 then
            Start := J;
          Inc(Run);
          if Run = K then
          begin
            for M := Start to Start + K - 1 do
              R^.Used[M shr 6] := R^.Used[M shr 6] or (QWord(1) shl (M and 63));
            Result := R^.Lo + PtrUInt(Start) * HeapSegSize;
            if Fpmprotect(Pointer(Result), PtrUInt(K) * HeapSegSize, PROT_READ or PROT_WRITE) <> 0 then
              SchedFail('mprotect of a heap segment');
            Inc(HeapUsedSegs, K);
            Exit;
          end;
        end;
        Inc(J);
      end;
    end;
  until not HeapReserve;
  Result := 0;
end;

{ Under HeapPageLock; the pages were given back to the kernel before it was taken. }
procedure HeapGiveSegs(P: PtrUInt; K: LongInt);
var
  I, J, First: LongInt;
begin
  for I := 0 to HeapResCount - 1 do
    if (P >= HeapRes[I].Lo) and (P < HeapRes[I].Hi) then
    begin
      First := (P - HeapRes[I].Lo) shr HeapSegLog2;
      for J := First to First + K - 1 do
        HeapRes[I].Used[J shr 6] := HeapRes[I].Used[J shr 6] and not (QWord(1) shl (J and 63));
      Dec(HeapUsedSegs, K);
      Exit;
    end;
end;

procedure HeapLinkFreeSeg(S: PHeapSeg);
begin
  S^.PrevFree := nil;
  S^.NextFree := HeapFreeSegs;
  if HeapFreeSegs <> nil then
    HeapFreeSegs^.PrevFree := S;
  HeapFreeSegs := S;
  S^.InFreeList := True;
end;

procedure HeapUnlinkFreeSeg(S: PHeapSeg);
begin
  if S^.PrevFree <> nil then
    S^.PrevFree^.NextFree := S^.NextFree
  else
    HeapFreeSegs := S^.NextFree;
  if S^.NextFree <> nil then
    S^.NextFree^.PrevFree := S^.PrevFree;
  S^.InFreeList := False;
end;

{ The first of N free consecutive pages in Mask (bits 1..63), or 0. }
function HeapFindRun(Mask: QWord; N: LongInt): LongInt;
var
  I: LongInt;
  Want: QWord;
begin
  if Mask = 0 then
    Exit(0);
  if N = 1 then
    Exit(BsfQWord(Mask));
  Want := (QWord(1) shl N) - 1;
  for I := 1 to HeapPagesPerSeg - N do
    if (Mask shr I) and Want = Want then
      Exit(I);
  Result := 0;
end;

{ N consecutive free pages (N <= 63); nil: no memory. }
function HeapTakePages(N: LongInt): PHeapPage;
var
  S: PHeapSeg;
  I: LongInt;
  P: PtrUInt;
begin
  Result := nil;
  SpinLock(HeapPageLock);
  S := HeapFreeSegs;
  I := 0;
  while S <> nil do
  begin
    I := HeapFindRun(S^.FreeMask, N);
    if I > 0 then
      Break;
    S := S^.NextFree;
  end;
  if S = nil then
  begin
    P := HeapTakeSegs(1);
    if P = 0 then
    begin
      SpinUnlock(HeapPageLock);
      Exit;
    end;
    S := PHeapSeg(P);   // a new segment reads as zero
    S^.Magic := HeapSegMagic;
    S^.FreeMask := High(QWord) and not QWord(1);
    HeapLinkFreeSeg(S);
    I := HeapFindRun(S^.FreeMask, N);
  end;
  if N = HeapPagesPerSeg - 1 then
    S^.FreeMask := 0
  else
    S^.FreeMask := S^.FreeMask and not (((QWord(1) shl N) - 1) shl I);
  if S^.FreeMask = 0 then
    HeapUnlinkFreeSeg(S);
  SpinUnlock(HeapPageLock);
  Result := @S^.Pages[I];
end;

procedure HeapGivePages(S: PHeapSeg; I, N: LongInt);
begin
  SpinLock(HeapPageLock);
  if N = HeapPagesPerSeg - 1 then
    S^.FreeMask := High(QWord) and not QWord(1)
  else
    S^.FreeMask := S^.FreeMask or (((QWord(1) shl N) - 1) shl I);
  if not S^.InFreeList then
    HeapLinkFreeSeg(S);
  SpinUnlock(HeapPageLock);
end;

function HeapPageAddr(Pg: PHeapPage): PtrUInt; inline;
var
  S: PtrUInt;
begin
  S := PtrUInt(Pg) and not (HeapSegSize - 1);
  Result := S + ((PtrUInt(Pg) - PtrUInt(@PHeapSeg(S)^.Pages[0])) div SizeOf(THeapPage)) shl HeapPageLog2;
end;

function HeapPageOf(P: PtrUInt): PHeapPage; inline;
var
  S: PtrUInt;
begin
  S := P and not (HeapSegSize - 1);
  Result := @PHeapSeg(S)^.Pages[(P - S) shr HeapPageLog2];
end;

{ ---------- caches ---------- }

{ The cache of the current thread: of its carrier for a goroutine. }
function HeapAcquire(T: PRawThread): PHeapCache;
var
  Pg: PHeapPage;
begin
  SpinLock(HeapCacheLock);
  Result := HeapCachePool;
  if Result <> nil then
    HeapCachePool := Result^.NextPool
  else
  begin
    if HeapMeta + SizeOf(THeapCache) > HeapMetaEnd then
    begin
      Pg := HeapTakePages(1);
      if Pg = nil then
        SchedFail('no memory for a heap cache');
      Pg^.Kind := PkMeta;
      HeapMeta := HeapPageAddr(Pg);
      HeapMetaEnd := HeapMeta + HeapPageSize;
    end;
    Result := PHeapCache(HeapMeta);
    Inc(HeapMeta, (SizeOf(THeapCache) + 63) and not PtrUInt(63));
    System.FillChar(Result^, SizeOf(THeapCache), 0); // the page may have held blocks before
    Result^.NextAll := HeapAllCaches;
    HeapAllCaches := Result;
  end;
  SpinUnlock(HeapCacheLock);
  T^.Heap := Result;
end;

{ An OS thread ends: its cache, with its pages, goes to the next thread. }
procedure HeapRelease(T: PRawThread);
var
  C: PHeapCache;
begin
  C := PHeapCache(T^.Heap);
  if C = nil then
    Exit;
  T^.Heap := nil;
  SpinLock(HeapCacheLock);
  C^.NextPool := HeapCachePool;
  HeapCachePool := C;
  SpinUnlock(HeapCacheLock);
end;

function HeapCache: PHeapCache; inline;
var
  T: PRawThread;
begin
  T := CurThread;
  if T^.Green <> 0 then
    T := T^.Carrier;
  Result := PHeapCache(T^.Heap);
  if Result = nil then
    Result := HeapAcquire(T);
end;

procedure HeapLink(var Head: PHeapPage; Pg: PHeapPage); inline;
begin
  Pg^.Prev := nil;
  Pg^.Next := Head;
  if Head <> nil then
    Head^.Prev := Pg;
  Head := Pg;
end;

procedure HeapUnlink(var Head: PHeapPage; Pg: PHeapPage); inline;
begin
  if Pg^.Prev <> nil then
    Pg^.Prev^.Next := Pg^.Next
  else
    Head := Pg^.Next;
  if Pg^.Next <> nil then
    Pg^.Next^.Prev := Pg^.Prev;
  Pg^.Next := nil;
  Pg^.Prev := nil;
end;

{ The blocks other threads freed into Pg join its free list; the number of them. }
function HeapCollect(Pg: PHeapPage): SizeInt;
var
  L, Last: Pointer;
begin
  Result := 0;
  if Pg^.RemoteFree = nil then
    Exit;
  L := InterlockedExchange(Pg^.RemoteFree, nil);
  if L = nil then
    Exit;
  Last := L;
  Result := 1;
  while PPointer(Last)^ <> nil do
  begin
    Last := PPointer(Last)^;
    Inc(Result);
  end;
  PPointer(Last)^ := Pg^.Free;
  Pg^.Free := L;
  Dec(Pg^.Used, Result);
end;

{ A small page of this cache with no block in use goes back to its segment. }
procedure HeapDropPage(Pg: PHeapPage);
var
  S: PtrUInt;
begin
  Pg^.Kind := PkFree;
  Pg^.State := PsNone;
  Pg^.Owner := nil;
  Pg^.Free := nil;
  Pg^.Bump := 0;
  Pg^.Limit := 0;
  S := PtrUInt(Pg) and not (HeapSegSize - 1);
  HeapGivePages(PHeapSeg(S), (PtrUInt(Pg) - PtrUInt(@PHeapSeg(S)^.Pages[0])) div SizeOf(THeapPage), 1);
end;

function HeapNewPage(C: PHeapCache; Cls: LongInt): PHeapPage;
var
  A: PtrUInt;
begin
  Result := HeapTakePages(1);
  if Result = nil then
    Exit;
  A := HeapPageAddr(Result);
  Result^.Free := nil;
  Result^.RemoteFree := nil;
  Result^.BlockSize := HeapClassSize[Cls];
  Result^.Bump := A;
  Result^.Limit := A + (HeapPageSize div Result^.BlockSize) * Result^.BlockSize;
  Result^.Used := 0;
  Result^.Owner := C;
  Result^.Next := nil;
  Result^.Prev := nil;
  Result^.Cls := Cls;
  Result^.Kind := PkSmall;
  Result^.State := PsCurrent;
end;

function HeapPop(Pg: PHeapPage): Pointer; inline;
begin
  Result := Pg^.Free;
  if Result <> nil then
    Pg^.Free := PPointer(Result)^
  else if Pg^.Bump < Pg^.Limit then
  begin
    Result := Pointer(Pg^.Bump);
    Inc(Pg^.Bump, Pg^.BlockSize);
  end
  else
    Exit;
  Inc(Pg^.Used);
end;

{ The current page of the class has no block: the blocks freed into it by others, a page of the partial list, the
  full pages others freed into, a new page. }
function HeapSlowGet(C: PHeapCache; Cls: LongInt): Pointer;
var
  Pg, N: PHeapPage;
begin
  Pg := C^.Cur[Cls];
  if Pg <> nil then
  begin
    if HeapCollect(Pg) > 0 then
      Exit(HeapPop(Pg));
    C^.Cur[Cls] := nil;
    Pg^.State := PsFull;
    HeapLink(C^.Full[Cls], Pg);
    ReadWriteBarrier;   // the state is published before RemoteFree is read: a remote free sees one or the other
    if Pg^.RemoteFree <> nil then
    begin
      HeapUnlink(C^.Full[Cls], Pg);
      HeapCollect(Pg);
      Pg^.State := PsCurrent;
      C^.Cur[Cls] := Pg;
      Exit(HeapPop(Pg));
    end;
  end;
  if (C^.FullRemote[Cls] <> 0) and (InterlockedExchange(C^.FullRemote[Cls], 0) <> 0) then
  begin
    Pg := C^.Full[Cls];
    while Pg <> nil do
    begin
      N := Pg^.Next;
      if Pg^.RemoteFree <> nil then
      begin
        HeapUnlink(C^.Full[Cls], Pg);
        HeapCollect(Pg);
        Pg^.State := PsPartial;
        HeapLink(C^.Partial[Cls], Pg);
      end;
      Pg := N;
    end;
  end;
  Pg := C^.Partial[Cls];
  if Pg <> nil then
  begin
    HeapUnlink(C^.Partial[Cls], Pg);
    HeapCollect(Pg);
    Pg^.State := PsCurrent;
    C^.Cur[Cls] := Pg;
    Exit(HeapPop(Pg));
  end;
  Pg := HeapNewPage(C, Cls);
  if Pg = nil then
    Exit(nil);
  C^.Cur[Cls] := Pg;
  Result := HeapPop(Pg);
end;

{ ---------- large and huge blocks ---------- }

function HeapGetLarge(C: PHeapCache; Size: PtrUInt): Pointer;
var
  N, K: PtrUInt;
  Pg: PHeapPage;
  S: PtrUInt;
begin
  if Size > PtrUInt(HeapResSegs - 1) * HeapSegSize then
    // more than a reservation holds (64 MiB on i386): the heap of the RTL maps it on its own
    Exit(HeapOld.GetMem(Size));
  N := (Size + HeapPageSize - 1) shr HeapPageLog2;
  if N < HeapPagesPerSeg then
  begin
    Pg := HeapTakePages(N);
    if Pg = nil then
      Exit(nil);
    Pg^.Kind := PkLarge;
    Pg^.Count := N;
    Pg^.BlockSize := N shl HeapPageLog2;
    Inc(C^.InUse, Pg^.BlockSize);
    Exit(Pointer(HeapPageAddr(Pg)));
  end;
  // a run of segments; page 1 of the first holds the block, page 0 its header
  K := (Size + HeapPageSize + HeapSegSize - 1) shr HeapSegLog2;
  SpinLock(HeapPageLock);
  S := HeapTakeSegs(K);
  SpinUnlock(HeapPageLock);
  if S = 0 then
    Exit(nil);
  PHeapSeg(S)^.Magic := HeapSegMagic;
  Pg := @PHeapSeg(S)^.Pages[1];
  Pg^.Kind := PkHuge;
  Pg^.Count := K;
  Pg^.BlockSize := K * HeapSegSize - HeapPageSize;
  Inc(C^.InUse, Pg^.BlockSize);
  Result := Pointer(S + HeapPageSize);
end;

procedure HeapFreeRun(C: PHeapCache; Pg: PHeapPage; P: PtrUInt);
var
  S: PtrUInt;
  N: LongInt;
begin
  Dec(C^.InUse, Pg^.BlockSize);
  S := P and not (HeapSegSize - 1);
  N := Pg^.Count;
  if Pg^.Kind = PkHuge then
  begin
    // the header of the run is in it: read before the pages read as zero
    do_syscall(syscall_nr_madvise, TSysParam(S), TSysParam(PtrUInt(N) * HeapSegSize), MADV_DONTNEED);
    SpinLock(HeapPageLock);
    HeapGiveSegs(S, N);
    SpinUnlock(HeapPageLock);
    Exit;
  end;
  Pg^.Kind := PkFree;
  HeapGivePages(PHeapSeg(S), (P - S) shr HeapPageLog2, N);
end;

{ ---------- the manager ---------- }

function HeapGetMem(Size: PtrUInt): Pointer;
var
  C: PHeapCache;
  Cls: LongInt;
  Pg: PHeapPage;
begin
  C := HeapCache;
  if Size <= HeapMaxSmall then
  begin
    Cls := HeapClassOf[(Size + 15) shr 4];
    Pg := C^.Cur[Cls];
    Result := nil;
    if Pg <> nil then
      Result := HeapPop(Pg);
    if Result = nil then
      Result := HeapSlowGet(C, Cls);
    if Result <> nil then
      Inc(C^.InUse, HeapClassSize[Cls]);
  end
  else
    Result := HeapGetLarge(C, Size);
  if Result = nil then
    RunError(203);
end;

function HeapFreeMem(P: Pointer): PtrUInt;
var
  C, O: PHeapCache;
  Pg: PHeapPage;
  Cls: LongInt;
  Old: Pointer;
begin
  if P = nil then
    Exit(0);
  if not HeapOurs(PtrUInt(P)) then
    Exit(HeapOld.FreeMem(P));
  Pg := HeapPageOf(PtrUInt(P));
  C := HeapCache;
  Result := Pg^.BlockSize;
  if Pg^.Kind <> PkSmall then
  begin
    HeapFreeRun(C, Pg, PtrUInt(P));
    Exit;
  end;
  Dec(C^.InUse, Result);
  O := Pg^.Owner;
  if O = C then
  begin
    PPointer(P)^ := Pg^.Free;
    Pg^.Free := P;
    Dec(Pg^.Used);
    case Pg^.State of
      PsFull:
        begin
          Cls := Pg^.Cls;
          HeapUnlink(C^.Full[Cls], Pg);
          Pg^.State := PsPartial;
          HeapLink(C^.Partial[Cls], Pg);
        end;
      PsPartial:
        if Pg^.Used = 0 then
        begin
          HeapUnlink(C^.Partial[Pg^.Cls], Pg);
          HeapDropPage(Pg);
        end;
    end;
    Exit;
  end;
  Cls := Pg^.Cls;
  repeat
    Old := Pg^.RemoteFree;
    PPointer(P)^ := Old;
  until InterlockedCompareExchange(Pg^.RemoteFree, P, Old) = Old;
  // the push is a full barrier; the owner publishes PsFull before it reads RemoteFree (HeapSlowGet)
  if Pg^.State = PsFull then
    InterlockedIncrement(O^.FullRemote[Cls]);
end;

function HeapFreeMemSize(P: Pointer; Size: PtrUInt): PtrUInt;
begin
  Result := HeapFreeMem(P);
end;

function HeapMemSize(P: Pointer): PtrUInt;
begin
  if not HeapOurs(PtrUInt(P)) then
    Exit(HeapOld.MemSize(P));
  Result := HeapPageOf(PtrUInt(P))^.BlockSize;
end;

function HeapAllocMem(Size: PtrUInt): Pointer;
begin
  Result := HeapGetMem(Size);
  System.FillChar(Result^, Size, 0);
end;

function HeapReAllocMem(var P: Pointer; Size: PtrUInt): Pointer;
var
  Old, N: PtrUInt;
  Q: Pointer;
begin
  if Size = 0 then
  begin
    if P <> nil then
      HeapFreeMem(P);
    P := nil;
    Exit(nil);
  end;
  if P = nil then
  begin
    P := HeapGetMem(Size);
    Exit(P);
  end;
  Old := HeapMemSize(P);
  if HeapOurs(PtrUInt(P)) and (Size <= Old) and (Size > Old div 2) then
    Exit(P);   // fits, and does not waste more than half
  Q := HeapGetMem(Size);
  N := Old;
  if N > Size then
    N := Size;
  System.Move(P^, Q^, N);
  HeapFreeMem(P);
  P := Q;
  Result := Q;
end;

function HeapUsedNow: PtrUInt;
var
  C: PHeapCache;
  Sum: SizeInt;
begin
  Sum := 0;
  C := HeapAllCaches;
  while C <> nil do
  begin
    Inc(Sum, C^.InUse);
    C := C^.NextAll;
  end;
  if Sum < 0 then
    Sum := 0;
  Result := PtrUInt(Sum);
end;

function HeapFPCStatus: TFPCHeapStatus;
begin
  Result := HeapOld.GetFPCHeapStatus();
  Inc(Result.CurrHeapUsed, HeapUsedNow);
  Inc(Result.CurrHeapSize, PtrUInt(HeapUsedSegs) * HeapSegSize);
  if Result.CurrHeapSize > Result.CurrHeapUsed then
    Result.CurrHeapFree := Result.CurrHeapSize - Result.CurrHeapUsed
  else
    Result.CurrHeapFree := 0;
  if Result.MaxHeapUsed < Result.CurrHeapUsed then
    Result.MaxHeapUsed := Result.CurrHeapUsed;
  if Result.MaxHeapSize < Result.CurrHeapSize then
    Result.MaxHeapSize := Result.CurrHeapSize;
end;

function HeapStatus: THeapStatus;
var
  F: TFPCHeapStatus;
begin
  F := HeapFPCStatus;
  System.FillChar(Result, SizeOf(Result), 0);
  Result.TotalAddrSpace := F.CurrHeapSize;
  Result.TotalCommitted := F.CurrHeapSize;
  Result.TotalAllocated := F.CurrHeapUsed;
  Result.TotalFree := F.CurrHeapFree;
end;

{ Installed at the start of the program, after the bounds of the main stack (CurThread) are known. }
procedure HeapInstall;
var
  M: TMemoryManager;
  V: PChar;
  Enabled: Boolean;
begin
  Enabled := {$ifdef BP_HEAP}True{$else}False{$endif};
  V := EnvValue('BP_HEAP');
  if V <> nil then
    Enabled := (V[0] = 'b') and (V[1] = 'p');
  {$ifdef BP_RTLHEAP}
  Enabled := False;
  {$endif}
  if not Enabled or IsMemoryManagerSet then
    Exit;
  HeapInitClasses;
  GetMemoryManager(HeapOld);
  M := HeapOld;
  M.GetMem := @HeapGetMem;
  M.FreeMem := @HeapFreeMem;
  M.FreeMemSize := @HeapFreeMemSize;
  M.AllocMem := @HeapAllocMem;
  M.ReAllocMem := @HeapReAllocMem;
  M.MemSize := @HeapMemSize;
  M.GetHeapStatus := @HeapStatus;
  M.GetFPCHeapStatus := @HeapFPCStatus;
  HeapOn := True;
  SetMemoryManager(M);
end;
