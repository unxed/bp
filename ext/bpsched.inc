{ SPDX-License-Identifier: MIT }
{ BPThreads, part 2: goroutines M:N, the events, and the hooks of the thread manager that serve both kinds of
  threads (safe/SPEC.md §21.3, "Step 5 design"). Included by bpthreads.pas in the raw mode.

  A goroutine is a region of the layout of a thread (the record at its start, aligned to RegionSize), so CurThread
  finds it from the stack pointer and the RTL sees a thread: threadvars, exception frames and the heap follow it. A
  switch saves the callee-saved registers and the FPU control words on the stack and swaps the stack pointer. A
  goroutine that waits keeps the lock of what it waits on through the switch; the carrier releases it after the
  goroutine's stack is saved (AfterPark), so a waker always finds a goroutine that has left its stack. }

const
  AfterNone = 0;
  AfterYield = 1;  // put it back into the run queue
  AfterPark = 2;   // put it on the timer list if it has a deadline, release AfterLock
  AfterDead = 3;   // it has ended: the joiners, the region

  WakeWaiting = 0;
  WakeSignalled = 1;
  WakeTimedOut = 2;

  {$ifdef cpu64}
  ChunkRegions = 4096;            // a reservation: 32 GiB of addresses, no memory
  {$else}
  ChunkRegions = 64;              // 64 MiB of the 32-bit address space
  {$endif}
  TopReserve = 256;               // the first frame of a goroutine
  PageSize = 4096;
  MaxCarriers = 256;
  MonitorTickMs = 10;
  MADV_DONTNEED = 4;

var
  SchedLock: LongInt = 0;         // the run queue, the timers, the free regions
  RegionLock: LongInt = 0;        // the reservations
  RunHead: PRawThread = nil;
  RunTail: PRawThread = nil;
  RunCount: LongInt = 0;
  Timers: PRawThread = nil;
  TimerCount: LongInt = 0;
  NextDeadline: Int64 = High(Int64);
  FreeRegions: PRawThread = nil;  // cold: the pages given back to the kernel
  WarmRegions: PRawThread = nil;  // freed during this tick of the monitor, the pages still mapped
  OldWarmRegions: PRawThread = nil; // freed during the tick before
  ChunkNext: PtrUInt = 0;         // the first region of the current reservation never carved
  ChunkHigh: PtrUInt = 0;
  GCtlSize: PtrUInt = 0;          // the record and the threadvar block of a goroutine, rounded up to pages
  GRecSize: PtrUInt = 0;
  Live: LongInt = 0;              // goroutines not ended
  Idle: LongInt = 0;              // carriers asleep
  IdleSeq: LongInt = 0;           // the futex word they sleep on
  Spinning: LongInt = 0;          // carriers that look for work a little before they sleep (SpinForWork)
  Procs: LongInt = 1;             // carriers at the start
  CarrierList: array[0..MaxCarriers - 1] of PRawThread;
  CarrierCount: LongInt = 0;
  SchedStarted: LongInt = 0;
  OsBlocked: LongInt = 0;         // OS threads in a wait of the runtime without a timeout (the deadlock check)
  MonitorWord: LongInt = 0;
  SeedState: QWord = 0;

{ ---------- a spin lock ---------- }

procedure SpinLock(var L: LongInt);
var
  N: Integer;
begin
  N := 0;
  while InterlockedExchange(L, 1) <> 0 do
  begin
    Inc(N);
    if N >= 64 then
    begin
      sched_yield;
      N := 0;
    end;
  end;
end;

procedure SpinUnlock(var L: LongInt);
begin
  InterlockedExchange(L, 0);
end;

{ ---------- the switch ----------
  SchedSwitch(Save, Next): pushes the callee-saved registers and the FPU control words on the current stack, stores the
  stack pointer to Save, loads Next as the stack pointer, restores what was saved there and returns into the code
  that saved it (or, for a new goroutine, into GoEntry: see InitialFrame). }

{$if defined(cpux86_64)}
procedure SchedSwitch(var Save: Pointer; Next: Pointer); assembler; nostackframe;
asm
  // rdi = Save, rsi = Next; callee-saved: rbx, rbp, r12-r15 (System V), MXCSR and the x87 control word
  pushq  %rbp
  pushq  %rbx
  pushq  %r12
  pushq  %r13
  pushq  %r14
  pushq  %r15
  subq   $8, %rsp
  stmxcsr (%rsp)
  fnstcw 4(%rsp)
  movq   %rsp, (%rdi)
  movq   %rsi, %rsp
  ldmxcsr (%rsp)
  fldcw  4(%rsp)
  addq   $8, %rsp
  popq   %r15
  popq   %r14
  popq   %r13
  popq   %r12
  popq   %rbx
  popq   %rbp
end;

function CurFpuWords: PtrUInt; assembler; nostackframe;
asm
  subq   $8, %rsp
  movq   $0, (%rsp)
  stmxcsr (%rsp)
  fnstcw 4(%rsp)
  movq   (%rsp), %rax
  addq   $8, %rsp
end;
{$elseif defined(cpui386)}
procedure SchedSwitch(var Save: Pointer; Next: Pointer); assembler; nostackframe;
asm
  // eax = Save, edx = Next (the register convention of FPC); callee-saved: ebx, esi, edi, ebp, the x87 control word
  pushl  %ebp
  pushl  %ebx
  pushl  %esi
  pushl  %edi
  subl   $4, %esp
  fnstcw (%esp)
  movl   %esp, (%eax)
  movl   %edx, %esp
  fldcw  (%esp)
  addl   $4, %esp
  popl   %edi
  popl   %esi
  popl   %ebx
  popl   %ebp
end;

function CurFpuWords: PtrUInt; assembler; nostackframe;
asm
  subl   $4, %esp
  movl   $0, (%esp)
  fnstcw (%esp)
  movl   (%esp), %eax
  addl   $4, %esp
end;
{$elseif defined(cpuaarch64)}
procedure SchedSwitch(var Save: Pointer; Next: Pointer); assembler; nostackframe;
asm
  // x0 = Save, x1 = Next; callee-saved: x19-x28, x29 (frame), x30 (link), d8-d15 (AAPCS64), FPCR
  sub    sp, sp, #176
  stp    x19, x20, [sp]
  stp    x21, x22, [sp, #16]
  stp    x23, x24, [sp, #32]
  stp    x25, x26, [sp, #48]
  stp    x27, x28, [sp, #64]
  stp    x29, x30, [sp, #80]
  stp    d8, d9, [sp, #96]
  stp    d10, d11, [sp, #112]
  stp    d12, d13, [sp, #128]
  stp    d14, d15, [sp, #144]
  mrs    x9, fpcr
  str    x9, [sp, #160]
  mov    x9, sp
  str    x9, [x0]
  mov    sp, x1
  ldr    x9, [sp, #160]
  msr    fpcr, x9
  ldp    x19, x20, [sp]
  ldp    x21, x22, [sp, #16]
  ldp    x23, x24, [sp, #32]
  ldp    x25, x26, [sp, #48]
  ldp    x27, x28, [sp, #64]
  ldp    x29, x30, [sp, #80]
  ldp    d8, d9, [sp, #96]
  ldp    d10, d11, [sp, #112]
  ldp    d12, d13, [sp, #128]
  ldp    d14, d15, [sp, #144]
  add    sp, sp, #176
end;

function CurFpuWords: PtrUInt; assembler; nostackframe;
asm
  mrs    x0, fpcr
end;
{$endif}

procedure GoEntry; forward;

{ The stack of a new goroutine as SchedSwitch leaves it: zero registers, the FPU words of the thread that starts it,
  and the return address GoEntry placed so that GoEntry starts with the alignment of a called routine. }
type
  TFrameWords = array[0..21] of PtrUInt;   // the largest frame: aarch64, 176 bytes
  PFrameWords = ^TFrameWords;

function InitialFrame(Top: PtrUInt; Fpu: PtrUInt): Pointer;
var
  W: PFrameWords;
begin
  {$if defined(cpux86_64)}
  // [Top-8] a zero return address, [Top-16] GoEntry, rbp ... r15, the FPU words: rsp = 8 mod 16 at the entry
  W := PFrameWords(Top - 72);
  System.FillChar(W^, 72, 0);
  W^[0] := Fpu;
  W^[7] := PtrUInt(@GoEntry);
  {$elseif defined(cpui386)}
  // [Top-4] a zero return address, [Top-8] GoEntry, ebp ... edi, the x87 word: esp = 12 mod 16 at the entry
  W := PFrameWords(Top - 28);
  System.FillChar(W^, 28, 0);
  W^[0] := Fpu;
  W^[5] := PtrUInt(@GoEntry);
  {$elseif defined(cpuaarch64)}
  // 176 bytes: x30 (at 88) is GoEntry, FPCR at 160; sp = Top (16-aligned) at the entry
  W := PFrameWords(Top - 176);
  System.FillChar(W^, 176, 0);
  W^[11] := PtrUInt(@GoEntry);
  W^[20] := Fpu;
  {$endif}
  Result := W;
end;

{ ---------- the seed ---------- }

function SeedNext(N: LongInt): LongInt;
begin
  // xorshift64
  SeedState := SeedState xor (SeedState shl 13);
  SeedState := SeedState xor (SeedState shr 7);
  SeedState := SeedState xor (SeedState shl 17);
  Result := LongInt(SeedState mod QWord(N));
end;

{ ---------- the run queue and the timers ---------- }

procedure UnlinkTimer(G: PRawThread);
begin
  if G^.TimerPrev <> nil then
    G^.TimerPrev^.TimerNext := G^.TimerNext
  else
    Timers := G^.TimerNext;
  if G^.TimerNext <> nil then
    G^.TimerNext^.TimerPrev := G^.TimerPrev;
  G^.TimerPrev := nil;
  G^.TimerNext := nil;
  G^.InTimers := False;
  Dec(TimerCount);
end;

procedure WakeIdle;
begin
  // the work was published before (a store under SchedLock or into a place "next"); a spinning carrier publishes
  // Spinning before it reads the work, so one of the two sees the other: a full barrier between the store and the read
  // (x86 has one in the exchange of the lock already)
  {$if not (defined(cpux86_64) or defined(cpui386))}
  ReadWriteBarrier;
  {$endif}
  // a spinning carrier takes the work and wakes the next one if more is left (CarrierMain)
  if (Idle > 0) and (Spinning = 0) then
  begin
    InterlockedIncrement(IdleSeq);
    FutexWake(IdleSeq, 1);
  end;
end;

{ G may run: off the timers, into the run queue. G has left its stack (it is new, or it switched away). }
procedure ReadyQueued(G: PRawThread);
begin
  SpinLock(SchedLock);
  if G^.InTimers then
    UnlinkTimer(G);
  G^.Next := nil;
  if RunTail = nil then
    RunHead := G
  else
    RunTail^.Next := G;
  RunTail := G;
  Inc(RunCount);
  SpinUnlock(SchedLock);
  WakeIdle;
end;

{ G may run on the carrier C: into the run queue of C, which the other carriers steal from when they have nothing to
  run. Only the carrier itself and the goroutines on it add to its queue, so its lock is rarely contended. }
procedure PushLocal(C, G: PRawThread);
begin
  G^.Next := nil;
  SpinLock(C^.QLock);
  if C^.QTail = nil then
    C^.QHead := G
  else
    C^.QTail^.Next := G;
  C^.QTail := G;
  Inc(C^.QCount);
  SpinUnlock(C^.QLock);
  WakeIdle;
end;

function PopLocal(C: PRawThread): PRawThread;
begin
  if C^.QCount = 0 then
    Exit(nil);
  SpinLock(C^.QLock);
  Result := C^.QHead;
  if Result <> nil then
  begin
    C^.QHead := Result^.Next;
    if C^.QHead = nil then
      C^.QTail := nil;
    Dec(C^.QCount);
  end;
  SpinUnlock(C^.QLock);
  if Result <> nil then
    Result^.Next := nil;
end;

{ The goroutines in the run queues of the carriers (the monitor, the sleep of a carrier). }
function LocalQueued: LongInt;
var
  K: LongInt;
  V: PRawThread;
begin
  Result := 0;
  for K := 0 to CarrierCount - 1 do
  begin
    V := CarrierList[K];
    if V <> nil then
      Inc(Result, V^.QCount);
  end;
end;

{ C has nothing to run: the first half of the run queue of another carrier, the victims taken in turn from a place that
  moves. The first goroutine taken is the result, the rest go into the queue of C. }
function Steal(C: PRawThread): PRawThread;
var
  I, K, N, Taken: LongInt;
  V, Last: PRawThread;
begin
  Result := nil;
  N := CarrierCount;
  if N > MaxCarriers then
    N := MaxCarriers;
  if N < 2 then
    Exit;
  K := LongInt(C^.Picks mod PtrUInt(N));
  for I := 1 to N do
  begin
    K := (K + 1) mod N;
    V := CarrierList[K];
    if (V = nil) or (V = C) or (V^.QCount = 0) then
      Continue;
    SpinLock(V^.QLock);
    Taken := (V^.QCount + 1) div 2;
    if Taken > 0 then
    begin
      Result := V^.QHead;
      Last := Result;
      while Taken > 1 do
      begin
        Last := Last^.Next;
        Dec(Taken);
      end;
      Taken := (V^.QCount + 1) div 2;
      V^.QHead := Last^.Next;
      if V^.QHead = nil then
        V^.QTail := nil;
      Dec(V^.QCount, Taken);
    end;
    SpinUnlock(V^.QLock);
    if Result = nil then
      Continue;
    if Result <> Last then
    begin
      SpinLock(C^.QLock);
      if C^.QTail = nil then
        C^.QHead := Result^.Next
      else
        C^.QTail^.Next := Result^.Next;
      C^.QTail := Last;
      Last^.Next := nil;
      Inc(C^.QCount, Taken - 1);
      SpinUnlock(C^.QLock);
    end;
    Result^.Next := nil;
    Exit;
  end;
end;

{ G may run. Woken by a goroutine, it runs next on the carrier of that goroutine, which will soon switch away (a waker
  usually blocks next: a channel round trip stays on one carrier, with no futex); the goroutine it pushes out of that
  place goes into the run queue of that carrier. Woken by anything else, it goes into the shared run queue. }
procedure Ready(G: PRawThread);
var
  T, Old: PRawThread;
begin
  T := CurThread;
  if SeedMode or (T^.Green = 0) or (T^.Carrier = nil) then
  begin
    ReadyQueued(G);
    Exit;
  end;
  if G^.InTimers then
  begin
    SpinLock(SchedLock);
    if G^.InTimers then
      UnlinkTimer(G);
    SpinUnlock(SchedLock);
  end;
  Old := PRawThread(InterlockedExchange(T^.Carrier^.RunNext, Pointer(G)));
  if Old <> nil then
    PushLocal(T^.Carrier, Old);
end;

procedure AddTimer(G: PRawThread);
begin
  SpinLock(SchedLock);
  G^.TimerPrev := nil;
  G^.TimerNext := Timers;
  if Timers <> nil then
    Timers^.TimerPrev := G;
  Timers := G;
  G^.InTimers := True;
  Inc(TimerCount);
  if G^.Deadline < NextDeadline then
    NextDeadline := G^.Deadline;
  SpinUnlock(SchedLock);
  WakeIdle; // an idle carrier sleeps until the old next deadline
end;

{ The next goroutine to run, or nil: the first of the queue, or one drawn from the seed. }
function TakeNext: PRawThread;
var
  P: ^PRawThread;
  Prev: PRawThread;
  K: LongInt;
begin
  if RunCount = 0 then
    Exit(nil);
  SpinLock(SchedLock);
  Result := nil;
  if RunHead <> nil then
  begin
    P := @RunHead;
    Prev := nil;
    if SeedMode then
      for K := 1 to SeedNext(RunCount) do
      begin
        Prev := P^;
        P := @P^^.Next;
      end;
    Result := P^;
    P^ := Result^.Next;
    if RunTail = Result then
      RunTail := Prev;
    Result^.Next := nil;
    Dec(RunCount);
  end;
  SpinUnlock(SchedLock);
end;

{ The goroutines whose deadline has passed wake up with a timeout (unless Set took them first). }
procedure FireTimers;
const
  Batch = 64;
var
  Fired: array[0..Batch - 1] of PRawThread;
  N, I: Integer;
  G, Nx: PRawThread;
  Now, Min: Int64;
begin
  if (TimerCount = 0) or (NextDeadline > NowMs) then
    Exit;
  repeat
    Now := NowMs;
    N := 0;
    Min := High(Int64);
    SpinLock(SchedLock);
    G := Timers;
    while G <> nil do
    begin
      Nx := G^.TimerNext;
      if (G^.Deadline <= Now) and (N < Batch) then
      begin
        UnlinkTimer(G);
        Fired[N] := G;
        Inc(N);
      end
      else if G^.Deadline < Min then
        Min := G^.Deadline;
      G := Nx;
    end;
    NextDeadline := Min;
    SpinUnlock(SchedLock);
    for I := 0 to N - 1 do
      if InterlockedCompareExchange(Fired[I]^.Wake, WakeTimedOut, WakeWaiting) = WakeWaiting then
        Ready(Fired[I]);
  until N < Batch;
end;

{ ---------- regions of goroutines ---------- }

procedure SchedFail(const Msg: ShortString);
begin
  WriteLn(StdErr, 'BPThreads: ', Msg);
  Flush(StdErr);
  do_syscall(syscall_nr_exit_group, 3);
end;

procedure NewChunk;
var
  Raw, Base, Len, N: PtrUInt;
  Tries: Integer;
begin
  N := ChunkRegions;
  for Tries := 1 to 16 do
  begin
    Len := (N + 1) * RegionSize;
    Raw := PtrUInt(Fpmmap(nil, Len, PROT_NONE, MAP_PRIVATE or MAP_ANONYMOUS or MAP_NORESERVE, -1, 0));
    if Pointer(Raw) = MAP_FAILED then
    begin
      N := N div 2;
      if N < 4 then
        Break;
      Continue;
    end;
    Base := (Raw + RegionSize - 1) and not (RegionSize - 1);
    if Base > Raw then
      Fpmunmap(Pointer(Raw), Base - Raw);
    if Raw + Len > Base + N * RegionSize then
      Fpmunmap(Pointer(Base + N * RegionSize), Raw + Len - (Base + N * RegionSize));
    if (Base < MainHigh) and (Base + N * RegionSize > MainLow) then
      // in the range taken as the stack of the main thread (qemu-user): kept reserved, never used
      Continue;
    ChunkNext := Base;
    ChunkHigh := Base + N * RegionSize;
    Exit;
  end;
  SchedFail('cannot reserve the stacks of goroutines');
end;

{ A region for a goroutine: a warm one (freed during the last two ticks of the monitor, its pages still mapped), a cold
  one (its pages given back, they read as zero), or a new one carved out of a reservation with the guard area PROT_NONE
  between the record and the stack. }
function NewGRegion: PRawThread;
var
  Base: PtrUInt;
begin
  SpinLock(SchedLock);
  Result := WarmRegions;
  if Result <> nil then
    WarmRegions := Result^.Next
  else
  begin
    Result := OldWarmRegions;
    if Result <> nil then
      OldWarmRegions := Result^.Next
    else
    begin
      Result := FreeRegions;
      if Result <> nil then
        FreeRegions := Result^.Next;
    end;
  end;
  SpinUnlock(SchedLock);
  if Result <> nil then
  begin
    // a warm region keeps the record of the goroutine before; qemu-user may keep the old pages after madvise
    System.FillChar(Result^, GCtlSize, 0);
    Exit;
  end;
  SpinLock(RegionLock);
  if ChunkNext >= ChunkHigh then
    NewChunk;
  Base := ChunkNext;
  Inc(ChunkNext, RegionSize);
  SpinUnlock(RegionLock);
  if (Fpmprotect(Pointer(Base), GCtlSize, PROT_READ or PROT_WRITE) <> 0) or
     (Fpmprotect(Pointer(Base + GCtlSize + GuardSize), RegionSize - GCtlSize - GuardSize,
       PROT_READ or PROT_WRITE) <> 0) then
    SchedFail('mprotect of a goroutine stack');
  Result := PRawThread(Base);
end;

{ The pages of a region go back to the kernel. A madvise costs a flush of the TLB of every carrier, so it is not done
  at the end of each goroutine: a region stays warm for the next one, and the monitor gives back the ones not taken. }
procedure ColdRegion(G: PRawThread);
var
  Lo: PtrUInt;
begin
  Lo := PtrUInt(G) + GCtlSize + GuardSize;
  do_syscall(syscall_nr_madvise, TSysParam(Lo), TSysParam(PtrUInt(G) + RegionSize - Lo), MADV_DONTNEED);
  do_syscall(syscall_nr_madvise, TSysParam(G), TSysParam(GCtlSize), MADV_DONTNEED);
end;

{ The goroutine has ended and is closed: its addresses go to the next goroutine. Without the monitor (the seed mode)
  the pages go back to the kernel at once. }
procedure FreeGRegion(G: PRawThread);
begin
  if SeedMode then
  begin
    ColdRegion(G);
    SpinLock(SchedLock);
    G^.Next := FreeRegions;
    FreeRegions := G;
    SpinUnlock(SchedLock);
    Exit;
  end;
  SpinLock(SchedLock);
  G^.Next := WarmRegions;
  WarmRegions := G;
  SpinUnlock(SchedLock);
end;

{ The monitor, at each tick: the regions warm since the tick before and not taken again go back to the kernel; the
  regions freed during this tick become the old ones. A region stays warm for one to two ticks. }
procedure CoolRegions;
var
  L, G, Last: PRawThread;
begin
  if (WarmRegions = nil) and (OldWarmRegions = nil) then
    Exit;
  SpinLock(SchedLock);
  L := OldWarmRegions;
  OldWarmRegions := WarmRegions;
  WarmRegions := nil;
  SpinUnlock(SchedLock);
  if L = nil then
    Exit;
  G := L;
  repeat
    ColdRegion(G);
    Last := G;
    G := G^.Next;
  until G = nil;
  SpinLock(SchedLock);
  Last^.Next := FreeRegions;
  FreeRegions := L;
  SpinUnlock(SchedLock);
end;

procedure Vote(G: PRawThread);
begin
  if InterlockedIncrement(G^.Votes) = 2 then
    FreeGRegion(G);
end;

{ ---------- events (both kinds of waiters) ---------- }

procedure EventSet(E: PSchedEvent); forward;

{ Under E^.Lock: consume the signal if there is one. }
function TryConsume(E: PSchedEvent): Boolean; inline;
begin
  if E^.Manual then
    Result := E^.Flag <> 0
  else
    Result := InterlockedExchange(E^.Flag, 0) <> 0; // an OS waiter consumes without the lock
end;

procedure RemoveWaiter(E: PSchedEvent; G: PRawThread);
var
  P: ^PRawThread;
begin
  P := @E^.Waiters;
  while P^ <> nil do
  begin
    if P^ = G then
    begin
      P^ := G^.WaitNext;
      Break;
    end;
    P := @P^^.WaitNext;
  end;
  G^.WaitNext := nil;
end;

{ ---------- running goroutines ---------- }

{ On the goroutine G: give the carrier back; the carrier does G^.After. }
procedure ToCarrier(G: PRawThread); inline;
begin
  SchedSwitch(G^.SP, G^.Carrier^.SP);
end;

procedure GreenYield(G: PRawThread);
begin
  G^.After := AfterYield;
  ToCarrier(G);
end;

{ On the carrier C: run G until it switches away, then do what it asked. }
procedure RunG(C, G: PRawThread);
var
  L: PLongInt;
begin
  G^.Carrier := C;
  Inc(C^.Switches);
  SchedSwitch(C^.SP, G^.SP);
  case G^.After of
    AfterYield:
      begin
        G^.After := AfterNone;
        if SeedMode then
          Ready(G)
        else
          PushLocal(C, G);
      end;
    AfterPark:
      begin
        G^.After := AfterNone;
        if G^.Deadline <> 0 then
          AddTimer(G);
        L := G^.AfterLock;
        G^.AfterLock := nil;
        SpinUnlock(L^);
      end;
    AfterDead:
      begin
        InterlockedExchange(G^.Tid, 0);
        FutexWake(G^.Tid, High(LongInt));
        EventSet(@G^.Done);
        InterlockedDecrement(Live);
        Vote(G);
      end;
  end;
end;

procedure Deadlock;
begin
  WriteLn(StdErr, 'BP: all goroutines are asleep - deadlock! (', Live, ' goroutine(s) parked; safe/SPEC.md section 21.3)');
  Flush(StdErr);
  do_syscall(syscall_nr_exit_group, 2);
end;

{ The seed mode, on the main thread: run one goroutine if one is ready. False: none was ready (the timers are fired,
  and with Block the thread sleeps until the next deadline or stops the program on a deadlock). }
function MainRunOne(Block: Boolean): Boolean;
var
  G: PRawThread;
  Dummy: LongInt;
  Left: Int64;
begin
  FireTimers;
  G := TakeNext;
  if G <> nil then
  begin
    RunG(@MainThread, G);
    Exit(True);
  end;
  Result := False;
  if not Block then
    Exit;
  if TimerCount = 0 then
    Deadlock;
  Left := NextDeadline - NowMs;
  if Left > 0 then
  begin
    Dummy := 0;
    FutexWait(Dummy, 0, Left);
  end;
end;

{ A carrier with nothing to run looks for work a little before it sleeps: a goroutine made ready meanwhile then costs no
  futex on either side. At most half of the carriers spin at once. It also takes the place "next" of another carrier
  when the same goroutine waits there at two looks in a row (its carrier is busy with a long run). True: there is
  work; G: a goroutine taken from another carrier, or nil when the work is in the run queue or in the place of C. }
function SpinForWork(C: PRawThread; out G: PRawThread): Boolean;
const
  SpinRounds = 2000;  // measured (2026-11-05): 200 and 20000 gave no more; the start of a goroutine 28 us -> 17 us
var
  I, K: LongInt;
  Seen, X: PRawThread;
  SeenAt: LongInt;
begin
  Result := False;
  G := nil;
  if SeedMode then
    Exit;
  if InterlockedIncrement(Spinning) > (CarrierCount + 1) div 2 then
  begin
    InterlockedDecrement(Spinning);
    Exit;
  end;
  Seen := nil;
  SeenAt := -1;
  for I := 1 to SpinRounds do
  begin
    ReadBarrier;
    if (RunCount > 0) or (C^.RunNext <> nil) then
    begin
      Result := True;
      Break;
    end;
    if I mod 64 = 0 then
    begin
      X := nil;
      if (SeenAt >= 0) and (CarrierList[SeenAt]^.RunNext = Seen) then
        X := PRawThread(InterlockedCompareExchange(CarrierList[SeenAt]^.RunNext, nil, Seen));
      if (X <> nil) and (X = Seen) then
      begin
        G := X;
        Result := True;
        Break;
      end;
      G := Steal(C);
      if G <> nil then
      begin
        Result := True;
        Break;
      end;
      Seen := nil;
      SeenAt := -1;
      for K := 0 to CarrierCount - 1 do
        if (CarrierList[K] <> nil) and (CarrierList[K] <> C) and (CarrierList[K]^.RunNext <> nil) then
        begin
          Seen := CarrierList[K]^.RunNext;
          SeenAt := K;
          Break;
        end;
    end;
  end;
  InterlockedDecrement(Spinning);
  ReadWriteBarrier; // Spinning is published before the carrier reads RunCount again on its way to sleep (WakeIdle)
end;

{ The loop of a carrier (an OS thread); it never ends. }
function CarrierMain(P: Pointer): PtrInt;
var
  C, G: PRawThread;
  Seq: LongInt;
  Left: Int64;
begin
  C := CurThread;
  repeat
    FireTimers;
    // the goroutine woken here runs next, but every 61st pick serves the run queue first, so that two goroutines that
    // wake each other do not keep the carrier from it
    Inc(C^.Picks);
    G := nil;
    if C^.Picks mod 61 = 0 then
      G := TakeNext;
    if G = nil then
      G := PRawThread(InterlockedExchange(C^.RunNext, nil));
    if G = nil then
      G := PopLocal(C);
    if G = nil then
      G := TakeNext;
    if G = nil then
      G := Steal(C);
    if G <> nil then
    begin
      RunG(C, G);
      Continue;
    end;
    if SpinForWork(C, G) then
    begin
      // the wakes skipped while this carrier spun: one more carrier for what is left
      if RunCount > 1 then
        WakeIdle;
      if G <> nil then
        RunG(C, G);
      Continue;
    end;
    Seq := IdleSeq;
    InterlockedIncrement(Idle);
    // Idle is published (a full barrier) before the queues are read; a carrier that adds to a queue reads Idle after
    // its unlock (an exchange): one of the two sees the other
    if (RunCount = 0) and (C^.RunNext = nil) and (LocalQueued = 0) then
    begin
      if TimerCount = 0 then
        Left := -1
      else
      begin
        Left := NextDeadline - NowMs;
        if Left < 1 then
          Left := 1;
      end;
      FutexWait(IdleSeq, Seq, Left);
    end;
    InterlockedDecrement(Idle);
  until False;
  Result := 0;
end;

procedure StartCarrier;
var
  Id: TThreadID;
  N: LongInt;
begin
  N := InterlockedIncrement(CarrierCount);
  if N > MaxCarriers then
  begin
    InterlockedDecrement(CarrierCount);
    Exit;
  end;
  Id := OsBeginThread(@CarrierMain, nil, False);
  if Id = TThreadID(0) then
    SchedFail('cannot start a carrier thread');
  CarrierList[N - 1] := PRawThread(Id);
end;

{ The monitor: the timers the carriers did not fire, a carrier more when the queue does not move (a blocking system
  call, a long loop), and the deadlock check. }
function MonitorMain(P: Pointer): PtrInt;
var
  I, N, Strikes, Queued: LongInt;
  Sum, Last: PtrUInt;
  C, G: PRawThread;
begin
  Last := High(PtrUInt);
  Strikes := 0;
  repeat
    FutexWait(MonitorWord, 0, MonitorTickMs);
    FireTimers;
    CoolRegions;
    N := CarrierCount;
    if N > MaxCarriers then
      N := MaxCarriers;
    Sum := 0;
    for I := 0 to N - 1 do
      if CarrierList[I] <> nil then
      begin
        C := CarrierList[I];
        Inc(Sum, C^.Switches);
        // a carrier that did not switch for a tick (a long loop, a blocking call) gives its next goroutine away
        if (C^.Switches = C^.Seen) and (C^.RunNext <> nil) then
        begin
          G := PRawThread(InterlockedExchange(C^.RunNext, nil));
          if G <> nil then
            ReadyQueued(G);
        end;
        C^.Seen := C^.Switches;
      end;
    Queued := RunCount + LocalQueued;
    if (Queued > 0) and (Idle = 0) and (Sum = Last) then
      StartCarrier;
    if (Live > 0) and (Queued = 0) and (TimerCount = 0) and (Idle >= N) and (OsBlocked >= 1) and (Sum = Last) then
    begin
      Inc(Strikes);
      if Strikes >= 2 then
        Deadlock;
    end
    else
      Strikes := 0;
    Last := Sum;
  until False;
  Result := 0;
end;

{ The carriers and the monitor, at the first goroutine. }
procedure StartScheduler;
var
  I: LongInt;
begin
  if InterlockedExchange(SchedStarted, 1) <> 0 then
    Exit;
  GRecSize := (SizeOf(TRawThread) + 63) and not PtrUInt(63);
  GCtlSize := (GRecSize + ThreadVarBlockSize + PageSize - 1) and not PtrUInt(PageSize - 1);
  if GCtlSize > CtlSize then
    SchedFail('the threadvars do not fit the record area of a region');
  // the first heap chunk of a thread for small blocks (32 KiB in the RTL) is cut into blocks at once, so every page of
  // it is touched: 16 page faults at the start of a goroutine that allocates, and 32 KiB of a parked one. A thread
  // started from now on (each goroutine copies it in InitThread) begins with one page; a heap that grows doubles it.
  // A value the program set is kept. The heap of FPC main has no such chunk (the variable is left only under
  // LEGACYHEAP).
  {$if declared(growheapsizesmall)}
  if growheapsizesmall = 32 * 1024 then
    growheapsizesmall := PageSize;
  {$endif}
  if SeedMode then
    Exit;
  for I := 1 to Procs do
    StartCarrier;
  if OsBeginThread(@MonitorMain, nil, False) = TThreadID(0) then
    SchedFail('cannot start the monitor thread');
end;

{ ---------- goroutines ---------- }

procedure GoExit(G: PRawThread);
begin
  DoneThread;                 // finalizes its heap, flushes its Output; no threadvar after this
  InterlockedDecrement(LiveThreads);
  G^.After := AfterDead;
  ToCarrier(G);
end;

{ The first frame of every goroutine (reached by the return of SchedSwitch); it never returns. }
procedure GoEntry;
var
  G: PRawThread;
begin
  G := CurThread;
  InitThread(G^.StackLen);    // the heap, the exceptions, stdio, StackBottom and ThreadID of this goroutine
  G^.ExitCode := G^.Fn(G^.Arg);
  GoExit(G);
end;

function GreenBeginThread(ThreadFunction: TThreadFunc; P: Pointer): TThreadID;
var
  G: PRawThread;
begin
  FirstThread;
  StartScheduler;
  G := NewGRegion;
  G^.Magic := ThreadMagic;
  G^.TVBlock := Pointer(PtrUInt(G) + GRecSize);   // in the record page: no mapping of its own
  G^.Fn := ThreadFunction;
  G^.Arg := P;
  G^.StackLen := RegionSize - GCtlSize - GuardSize - TopReserve;
  G^.Tid := 1;
  G^.Region := G;
  G^.Green := 1;
  G^.Done.Manual := True;
  G^.SP := InitialFrame(PtrUInt(G) + RegionSize, CurFpuWords);
  InterlockedIncrement(Live);
  InterlockedIncrement(LiveThreads);
  Ready(G);
  Result := TThreadID(G);
end;

{ ---------- event waits ---------- }

{ A goroutine waits: True signalled, False timed out. }
function GreenWait(E: PSchedEvent; G: PRawThread; TimeoutMs: Int64): Boolean;
var
  P: ^PRawThread;
begin
  SpinLock(E^.Lock);
  if TryConsume(E) then
  begin
    SpinUnlock(E^.Lock);
    Exit(True);
  end;
  if TimeoutMs = 0 then
  begin
    SpinUnlock(E^.Lock);
    Exit(False);
  end;
  G^.Wake := WakeWaiting;
  G^.WaitNext := nil;
  P := @E^.Waiters;
  while P^ <> nil do
    P := @P^^.WaitNext;
  P^ := G;
  if TimeoutMs > 0 then
    G^.Deadline := NowMs + TimeoutMs
  else
    G^.Deadline := 0;
  G^.After := AfterPark;
  G^.AfterLock := @E^.Lock;
  ToCarrier(G);               // the carrier releases E^.Lock
  if G^.Wake = WakeSignalled then
    Exit(True);
  SpinLock(E^.Lock);          // timed out: Set may not have taken it from the list
  RemoveWaiter(E, G);
  SpinUnlock(E^.Lock);
  Result := False;
end;

{ An OS thread waits on the futex. }
function OsWait(E: PSchedEvent; TimeoutMs: Int64): Boolean;
var
  Deadline, Left: Int64;
begin
  if TimeoutMs >= 0 then
    Deadline := NowMs + TimeoutMs
  else
    Deadline := 0;
  InterlockedIncrement(E^.OsWaiting);
  if TimeoutMs < 0 then
    InterlockedIncrement(OsBlocked);
  Result := False;
  repeat
    if E^.Manual then
    begin
      if E^.Flag <> 0 then
      begin
        Result := True;
        Break;
      end;
    end
    else if InterlockedExchange(E^.Flag, 0) <> 0 then
    begin
      Result := True;
      Break;
    end;
    if TimeoutMs < 0 then
      FutexWait(E^.Flag, 0, -1)
    else
    begin
      Left := Deadline - NowMs;
      if Left <= 0 then
        Break;
      FutexWait(E^.Flag, 0, Left);
    end;
  until False;
  if TimeoutMs < 0 then
    InterlockedDecrement(OsBlocked);
  InterlockedDecrement(E^.OsWaiting);
end;

{ The seed mode: the main thread runs the goroutines while it waits. }
function MainWait(E: PSchedEvent; TimeoutMs: Int64): Boolean;
var
  Deadline: Int64;
  Got: Boolean;
begin
  if TimeoutMs >= 0 then
    Deadline := NowMs + TimeoutMs
  else
    Deadline := High(Int64);
  repeat
    SpinLock(E^.Lock);
    Got := TryConsume(E);
    SpinUnlock(E^.Lock);
    if Got then
      Exit(True);
    if NowMs >= Deadline then
      Exit(False);
    if not MainRunOne(TimeoutMs < 0) and (TimeoutMs >= 0) then
      FutexWait(MonitorWord, 0, 1);
  until False;
end;

function EventWait(E: PSchedEvent; TimeoutMs: Int64): Boolean;
var
  T: PRawThread;
begin
  T := CurThread;
  if T^.Green <> 0 then
    Result := GreenWait(E, T, TimeoutMs)
  else if SeedMode and (T = @MainThread) and (SchedStarted <> 0) then
    Result := MainWait(E, TimeoutMs)
  else
    Result := OsWait(E, TimeoutMs);
end;

procedure EventSet(E: PSchedEvent);
var
  W, Nx, Take: PRawThread;
begin
  Take := nil;
  SpinLock(E^.Lock);
  if E^.Manual then
  begin
    InterlockedExchange(E^.Flag, 1);
    // all of them; a goroutine that timed out is only unlinked, it removes itself from nothing
    W := E^.Waiters;
    E^.Waiters := nil;
    while W <> nil do
    begin
      Nx := W^.WaitNext;
      W^.WaitNext := nil;
      if InterlockedCompareExchange(W^.Wake, WakeSignalled, WakeWaiting) = WakeWaiting then
      begin
        W^.WaitNext := Take;
        Take := W;
      end;
      W := Nx;
    end;
  end
  else
  begin
    // an auto-reset event hands its signal to the first goroutine still waiting
    repeat
      W := E^.Waiters;
      if W = nil then
      begin
        InterlockedExchange(E^.Flag, 1);
        Break;
      end;
      E^.Waiters := W^.WaitNext;
      W^.WaitNext := nil;
      if InterlockedCompareExchange(W^.Wake, WakeSignalled, WakeWaiting) = WakeWaiting then
      begin
        Take := W;
        Break;
      end;
    until False;
  end;
  SpinUnlock(E^.Lock);
  // the winners are parked and only this call readies them; a readied one may run at once, so Nx is read first
  W := Take;
  while W <> nil do
  begin
    Nx := W^.WaitNext;
    W^.WaitNext := nil;
    Ready(W);
    W := Nx;
  end;
  if (E^.OsWaiting > 0) and (E^.Flag <> 0) then
    FutexWake(E^.Flag, High(LongInt));
end;

procedure EventReset(E: PSchedEvent);
begin
  SpinLock(E^.Lock);
  E^.Flag := 0;
  SpinUnlock(E^.Lock);
end;

function NewEvent(Manual, Initial: Boolean): PSchedEvent;
begin
  System.New(Result);
  System.FillChar(Result^, SizeOf(TSchedEvent), 0);
  Result^.Manual := Manual;
  Result^.Flag := Ord(Initial);
end;

{ ---------- critical sections ---------- }

{ The goroutines parked on a critical section wait in a table of the runtime, by the address of the lock, not in the
  lock (as the semaphore table of Go): the leaver touches only the table after the lock is free, and the memory of the
  lock may be freed by then. }
const
  MutexBuckets = 256;

type
  TMutexBucket = record
    Lock: LongInt;
    Head: PRawThread;      // in order of arrival, linked by WaitNext; WaitAddr is the lock
  end;

var
  MutexWaits: array[0..MutexBuckets - 1] of TMutexBucket;

function MutexBucket(M: Pointer): PtrUInt; inline;
begin
  Result := ((PtrUInt(M) shr 3) xor (PtrUInt(M) shr 11)) and (MutexBuckets - 1);
end;

{ A goroutine takes a mutex that is taken: under the lock of the bucket it marks the mutex contended (State 2, as an OS
  waiter does) and parks there; the carrier releases the bucket after the switch. A leaver that saw State 2 takes the
  bucket after that, so it finds the goroutine; the woken one marks the mutex contended again when it retries. }
procedure GreenEnter(var M: TRawMutex; G: PRawThread);
var
  B: ^TMutexBucket;
  P: ^PRawThread;
begin
  if M.Owner = TThreadID(G) then
  begin
    Inc(M.Count);
    Exit;
  end;
  if InterlockedCompareExchange(M.State, 1, 0) <> 0 then
  begin
    B := @MutexWaits[MutexBucket(@M)];
    repeat
      SpinLock(B^.Lock);
      if InterlockedExchange(M.State, 2) = 0 then
      begin
        SpinUnlock(B^.Lock);
        Break;
      end;
      G^.WaitAddr := @M;
      G^.WaitNext := nil;
      P := @B^.Head;
      while P^ <> nil do
        P := @P^^.WaitNext;
      P^ := G;
      G^.Deadline := 0;
      G^.After := AfterPark;
      G^.AfterLock := @B^.Lock;
      ToCarrier(G);
    until False;
  end;
  M.Owner := TThreadID(G);
  M.Count := 1;
end;

procedure WakeMutexWaiter(M: Pointer);
var
  B: ^TMutexBucket;
  P: ^PRawThread;
  W: PRawThread;
begin
  B := @MutexWaits[MutexBucket(M)];
  W := nil;
  SpinLock(B^.Lock);
  P := @B^.Head;
  while P^ <> nil do
  begin
    if P^^.WaitAddr = M then
    begin
      W := P^;
      P^ := W^.WaitNext;
      W^.WaitNext := nil;
      Break;
    end;
    P := @P^^.WaitNext;
  end;
  SpinUnlock(B^.Lock);
  if W <> nil then
    Ready(W);
end;

{ ---------- the hooks ---------- }

procedure RawEnterCS(var CS);
var
  T: PRawThread;
begin
  T := CurThread;
  if T^.Green <> 0 then
  begin
    // a goroutine never sleeps in the futex (the owner may be waiting in the run queue of this carrier): it parks
    if SeedMode and (SeedNext(2) = 0) then
      GreenYield(T);
    GreenEnter(TRawMutex(CS), T);
  end
  else if SeedMode and (T = @MainThread) and (SchedStarted <> 0) then
  begin
    while not MutexTryEnter(TRawMutex(CS)) do
      MainRunOne(True);
  end
  else
    MutexEnter(TRawMutex(CS));
end;

function RawBeginThread(SA: Pointer; StackSize: PtrUInt; ThreadFunction: TThreadFunc; P: Pointer;
  CreationFlags: DWord; var ThreadId: TThreadID): TThreadID;
begin
  if MNOn then
    Result := GreenBeginThread(ThreadFunction, P)
  else
    Result := OsBeginThread(ThreadFunction, P, True);
  ThreadId := Result;
end;

procedure RawEndThread(ExitCode: DWord);
var
  T: PRawThread;
begin
  T := CurThread;
  if T^.Green <> 0 then
  begin
    T^.ExitCode := ExitCode;
    GoExit(T);
  end;
  DoneThread;
  HeapRelease(T);
  if T^.ExitCode <> 0 then  // counted: see OsBeginThread
    InterlockedDecrement(LiveThreads);
  do_syscall(syscall_nr_exit, TSysParam(ExitCode)); // this thread only; the collector frees the region
end;

function RawWaitForThreadTerminate(ThreadHandle: TThreadID; TimeoutMs: LongInt): DWord;
var
  T: PRawThread;
  Tid: LongInt;
begin
  T := PRawThread(ThreadHandle);
  if T^.Green <> 0 then
    EventWait(@T^.Done, -1)
  else
    repeat
      Tid := T^.Tid;
      if Tid = 0 then
        Break;
      FutexWaitShared(T^.Tid, Tid);
    until False;
  Result := 0;
end;

function RawCloseThread(ThreadHandle: TThreadID): DWord;
var
  T: PRawThread;
begin
  T := PRawThread(ThreadHandle);
  if (T <> nil) and (T <> @MainThread) then
  begin
    if T^.Green <> 0 then
    begin
      if InterlockedExchange(T^.Closed, 1) = 0 then
        Vote(T);
    end
    else
      InterlockedExchange(T^.Closed, 1);
  end;
  ReapZombies;
  Result := 0;
end;

function RawUnsupported(ThreadHandle: TThreadID): DWord;
begin
  Result := DWord(-1);
end;

procedure RawThreadSwitch;
var
  T: PRawThread;
begin
  T := CurThread;
  if T^.Green <> 0 then
    GreenYield(T)
  else if SeedMode and (T = @MainThread) and (SchedStarted <> 0) then
    MainRunOne(False)
  else
    sched_yield;
end;

function RawSetPriority(ThreadHandle: TThreadID; Prio: LongInt): Boolean;
begin
  Result := False;
end;

function RawGetPriority(ThreadHandle: TThreadID): LongInt;
begin
  Result := 0;
end;

procedure RawSetNameA(ThreadHandle: TThreadID; const ThreadName: AnsiString);
begin
end;

procedure RawSetNameU(ThreadHandle: TThreadID; const ThreadName: UnicodeString);
begin
end;

function RawRTLEventCreate: PRTLEvent;
begin
  Result := PRTLEvent(NewEvent(False, False));
end;

procedure RawRTLEventDestroy(State: PRTLEvent);
begin
  System.Dispose(PSchedEvent(State));
end;

procedure RawRTLEventSet(State: PRTLEvent);
begin
  EventSet(PSchedEvent(State));
end;

procedure RawRTLEventReset(State: PRTLEvent);
begin
  EventReset(PSchedEvent(State));
end;

procedure RawRTLEventWaitFor(State: PRTLEvent);
begin
  EventWait(PSchedEvent(State), -1);
end;

// FPC 3.3.1 (main) made the wait with a timeout a function and added FUseComWait to BasicEventWaitFor
{$if FPC_FULLVERSION >= 30301}
function RawRTLEventWaitForTimeout(State: PRTLEvent; Timeout: LongInt): Boolean;
begin
  Result := EventWait(PSchedEvent(State), Timeout);
end;
{$else}
procedure RawRTLEventWaitForTimeout(State: PRTLEvent; Timeout: LongInt);
begin
  EventWait(PSchedEvent(State), Timeout);
end;
{$endif}

function RawBasicEventCreate(EventAttributes: Pointer; AManualReset, InitialState: Boolean;
  const Name: AnsiString): PEventState;
begin
  Result := PEventState(NewEvent(AManualReset, InitialState));
end;

procedure RawBasicEventDestroy(State: PEventState);
begin
  System.Dispose(PSchedEvent(State));
end;

procedure RawBasicEventReset(State: PEventState);
begin
  EventReset(PSchedEvent(State));
end;

procedure RawBasicEventSet(State: PEventState);
begin
  EventSet(PSchedEvent(State));
end;

{$if FPC_FULLVERSION >= 30301}
function RawBasicEventWaitFor(Timeout: Cardinal; State: PEventState; FUseComWait: Boolean = False): LongInt;
{$else}
function RawBasicEventWaitFor(Timeout: Cardinal; State: PEventState): LongInt;
{$endif}
const
  wrSignaled = 0;
  wrTimeout = 1;
begin
  if Timeout = $FFFFFFFF then
    EventWait(PSchedEvent(State), -1)
  else if not EventWait(PSchedEvent(State), Timeout) then
    Exit(wrTimeout);
  Result := wrSignaled;
end;

{ For tests: the goroutines that are ready run first in the seed mode, as they would on carriers. }
function SafeRawThreadCount: LongInt;
begin
  if SeedMode and (CurThread = @MainThread) and (SchedStarted <> 0) then
    while MainRunOne(False) do
      ;
  Result := LiveThreads;
end;

{ The value of an environment variable, nil when it is not set (fpgetenv is deprecated, SysUtils comes later). }
function EnvValue(const Name: ShortString): PChar;
var
  P: PPChar;
  I: Integer;
begin
  Result := nil;
  P := envp;
  if P = nil then
    Exit;
  while P^ <> nil do
  begin
    I := 1;
    while (I <= Length(Name)) and (P^[I - 1] = Name[I]) do
      Inc(I);
    if (I > Length(Name)) and (P^[I - 1] = '=') then
      Exit(P^ + I);
    Inc(P);
  end;
end;

{ The switch to M:N, read once at the start: BP_MN=1|0, BP_SCHED_SEED=N, BP_PROCS=N. }
procedure ReadSchedEnv;
var
  V: PChar;
  N: QWord;
  Code: Integer;
  Mask: array[0..127] of Byte;
  Got, I, B: LongInt;
begin
  MNOn := {$ifdef BP_MN}True{$else}False{$endif};
  V := EnvValue('BP_MN');
  if V <> nil then
    MNOn := V[0] = '1';
  V := EnvValue('BP_SCHED_SEED');
  if (V <> nil) and (V[0] <> #0) then
  begin
    Val(AnsiString(V), N, Code);
    if Code = 0 then
    begin
      MNOn := True;
      SeedMode := True;
      SeedState := N xor QWord($9E3779B97F4A7C15);
      if SeedState = 0 then
        SeedState := 1;
    end;
  end;
  Procs := 0;
  Got := do_syscall(syscall_nr_sched_getaffinity, 0, SizeOf(Mask), TSysParam(@Mask));
  for I := 0 to Got - 1 do
    for B := 0 to 7 do
      if Mask[I] and (1 shl B) <> 0 then
        Inc(Procs);
  V := EnvValue('BP_PROCS');
  if V <> nil then
  begin
    Val(AnsiString(V), N, Code);
    if (Code = 0) and (N > 0) then
      Procs := N;
  end;
  if Procs < 1 then
    Procs := 1;
  if Procs > MaxCarriers div 2 then
    Procs := MaxCarriers div 2;
end;
