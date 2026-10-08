{ SPDX-License-Identifier: MIT }
// UNSAFE-UNIT: the FPC thread manager. On Linux it works on system calls without libc (like Go); with -dSAFE_LIBC and on other Unix it is cthreads.
{ BPThreads: one line for threads on all targets (SPEC §14).

    program P;
    uses BP, SysUtils, ...;   // BP (which pulls in BPThreads) goes FIRST in the program uses; in the other units BP goes last

  - Linux (x86_64, i386, aarch64) by default: a thread manager on clone + futex
    + mmap, no libc needed; a static binary runs on any distribution
    (glibc, musl). C code that uses libc must not be called from these threads (the libc TLS
    is not set up for them): a program with FFI to libc is built with -dSAFE_LIBC
    (SPEC §13 F5); if libc is loaded anyway, the first BeginThread stops the
    program with an explanation instead of a silent race;
  - -dSAFE_LIBC and other Unix: cthreads (libc/pthread threads);
  - on the other targets the unit is empty.

  How it works (RAW mode):
  - the stack of a thread is a separate mmap region of size R (a power of two), aligned to R;
    the control record of the thread lies at its start, followed by a guard page;
  - the current thread is found from the stack pointer: Sptr and not (R - 1), with no
    assembler and no TLS register; the main thread is recognised by the range of its stack;
  - the threadvar block of a thread is mmap'ed, its pointer is kept in the control record;
  - the lock is Drepper's futex mutex (recursive, as the RTL requires), events are futexes;
  - exit: CLONE_CHILD_CLEARTID, the kernel clears Tid and wakes the waiters;
    the stack region is freed by the next BeginThread/CloseThread (the "zombie collector");
  - the main thread is recognised by the range [MainLow, MainHigh): argv above, the stack
    limit below; a region that falls into the range is dropped (this happens under qemu-user). }
unit BPThreads;

{$mode objfpc}{$H+}

{$if defined(linux) and not defined(SAFE_LIBC)}
  {$define SAFE_RAW}
  {$if defined(FPC_USE_LIBC)}
    {$error BPThreads raw mode needs an RTL built without libc; build with -dSAFE_LIBC}
  {$endif}
  {$if not (defined(cpux86_64) or defined(cpui386) or defined(cpuaarch64))}
    {$error BPThreads raw mode: only x86_64, i386, aarch64 Linux; build with -dSAFE_LIBC}
  {$endif}
{$endif}

interface

{$ifdef SAFE_RAW}
uses
  BaseUnix, UnixType, Linux, Syscall;

{ How many threads are alive now (for tests). }
function SafeRawThreadCount: LongInt;
{$else}
  {$ifdef unix}
uses
  cthreads;
  {$endif}
{$endif}

implementation

{$ifdef SAFE_RAW}

const
  {$ifdef cpu64}
  RegionLog2 = 23; // 8 MiB of virtual address space per thread, as with pthread
  {$else}
  RegionLog2 = 20; // 1 MiB: the 32-bit address space is tight
  {$endif}
  RegionSize = PtrUInt(1) shl RegionLog2;
  CtlSize = 65536;   // the thread record; 64 KiB is a multiple of any page size
  GuardSize = 65536; // the guard area between the record and the stack
  ThreadMagic = PtrUInt($5AFE7EAD);

  FUTEX_PRIVATE = 128;
  CloneFlags = CLONE_VM or CLONE_FS or CLONE_FILES or CLONE_SIGHAND or CLONE_THREAD or
    CLONE_SYSVSEM or CLONE_CHILD_CLEARTID;

type
  PRawThread = ^TRawThread;
  TRawThread = record
    Magic: PtrUInt;
    TVBlock: Pointer;      // the threadvar block
    Fn: TThreadFunc;
    Arg: Pointer;
    StackLen: PtrUInt;
    Tid: LongInt;          // 1 while the thread is alive; the kernel clears it on exit (CLONE_CHILD_CLEARTID)
    Closed: LongInt;       // CloseThread was called: the region may be freed after the exit
    ExitCode: PtrInt;
    Region: Pointer;
    Next: PRawThread;      // the list of regions not freed yet
  end;

  { A recursive futex mutex laid over TRTLCriticalSection. }
  PRawMutex = ^TRawMutex;
  TRawMutex = record
    State: LongInt;        // 0 free, 1 taken, 2 taken with waiters
    Count: LongInt;
    Owner: TThreadID;
  end;

  PRawEvent = ^TRawEvent;
  TRawEvent = record
    Flag: LongInt;
    Manual: Boolean;
  end;

  TRawEntry = function(Arg: Pointer): PtrInt; cdecl;

var
  MainThread: TRawThread;
  MainLow, MainHigh: PtrUInt; // [MainLow, MainHigh) is the stack of the main thread
  ThreadVarBlockSize: DWord = 0;
  TVInitialized: LongInt = 0;
  Zombies: PRawThread = nil;
  ZombieLock: TRawMutex;
  LiveThreads: LongInt = 0;

function SafeRawThreadCount: LongInt;
begin
  Result := LiveThreads;
end;

{ ---------- the current thread: from the stack pointer ---------- }

function CurThread: PRawThread; inline;
var
  SP: PtrUInt;
begin
  SP := PtrUInt(Sptr);
  if (SP >= MainLow) and (SP < MainHigh) then
    Result := @MainThread
  else
    Result := PRawThread(SP and not (RegionSize - 1));
end;

function RawGetCurrentThreadId: TThreadID;
begin
  Result := TThreadID(CurThread);
end;

{ ---------- futex ---------- }

procedure FutexWait(var Addr: LongInt; Expected: LongInt; TimeoutMs: Int64);
var
  TS: TTimeSpec;
begin
  if TimeoutMs < 0 then
    Linux.futex(Addr, FUTEX_WAIT or FUTEX_PRIVATE, Expected, nil)
  else
  begin
    TS.tv_sec := TimeoutMs div 1000;
    TS.tv_nsec := (TimeoutMs mod 1000) * 1000000;
    Linux.futex(Addr, FUTEX_WAIT or FUTEX_PRIVATE, Expected, @TS);
  end;
end;

procedure FutexWake(var Addr: LongInt; N: LongInt);
begin
  Linux.futex(Addr, FUTEX_WAKE or FUTEX_PRIVATE, N, nil);
end;

{ Without FUTEX_PRIVATE: the kernel clears Tid in the thread record and wakes without that flag. }
procedure FutexWaitShared(var Addr: LongInt; Expected: LongInt);
begin
  Linux.futex(Addr, FUTEX_WAIT, Expected, nil);
end;

function NowMs: Int64;
var
  TS: TTimeSpec;
begin
  clock_gettime(CLOCK_MONOTONIC, @TS);
  Result := Int64(TS.tv_sec) * 1000 + TS.tv_nsec div 1000000;
end;

{ ---------- mutex (Drepper, "Futexes are tricky", variant 2) + recursion ---------- }

procedure MutexEnter(var M: TRawMutex);
var
  Me: TThreadID;
  C: LongInt;
begin
  Me := RawGetCurrentThreadId;
  if M.Owner = Me then
  begin
    Inc(M.Count);
    Exit;
  end;
  C := InterlockedCompareExchange(M.State, 1, 0);
  if C <> 0 then
  begin
    if C <> 2 then
      C := InterlockedExchange(M.State, 2);
    while C <> 0 do
    begin
      FutexWait(M.State, 2, -1);
      C := InterlockedExchange(M.State, 2);
    end;
  end;
  M.Owner := Me;
  M.Count := 1;
end;

function MutexTryEnter(var M: TRawMutex): Boolean;
var
  Me: TThreadID;
begin
  Me := RawGetCurrentThreadId;
  if M.Owner = Me then
  begin
    Inc(M.Count);
    Exit(True);
  end;
  Result := InterlockedCompareExchange(M.State, 1, 0) = 0;
  if Result then
  begin
    M.Owner := Me;
    M.Count := 1;
  end;
end;

procedure MutexLeave(var M: TRawMutex);
begin
  Dec(M.Count);
  if M.Count > 0 then
    Exit;
  M.Owner := TThreadID(0);
  if InterlockedDecrement(M.State) <> 0 then
  begin
    InterlockedExchange(M.State, 0);
    FutexWake(M.State, 1);
  end;
end;

procedure RawInitCS(var CS);
begin
  System.FillChar(CS, SizeOf(TRawMutex), 0);
end;

procedure RawDoneCS(var CS);
begin
end;

procedure RawEnterCS(var CS);
begin
  MutexEnter(TRawMutex(CS));
end;

function RawTryEnterCS(var CS): LongInt;
begin
  Result := Ord(MutexTryEnter(TRawMutex(CS)));
end;

procedure RawLeaveCS(var CS);
begin
  MutexLeave(TRawMutex(CS));
end;

{ ---------- threadvar ---------- }

procedure RawInitThreadVar(var Offset: DWord; Size: DWord);
begin
  ThreadVarBlockSize := Align(ThreadVarBlockSize, 16);
  Offset := ThreadVarBlockSize;
  Inc(ThreadVarBlockSize, Size);
end;

function NewTVBlock: Pointer;
begin
  // memory not from the heap: the heap itself lives in threadvars (as in cthreads)
  Result := Fpmmap(nil, ThreadVarBlockSize, PROT_READ or PROT_WRITE, MAP_PRIVATE or MAP_ANONYMOUS, -1, 0);
  if Result = MAP_FAILED then
    RunError(203);
end;

function RawRelocateThreadVar(Offset: DWord): Pointer;
begin
  Result := CurThread^.TVBlock + Offset;
end;

procedure RawAllocateThreadVars;
begin
  CurThread^.TVBlock := NewTVBlock; // called for the main thread from InitThreadVars
end;

procedure RawReleaseThreadVars;
var
  T: PRawThread;
begin
  T := CurThread;
  if T <> @MainThread then
  begin
    Fpmunmap(T^.TVBlock, ThreadVarBlockSize);
    T^.TVBlock := nil;
  end;
end;

{ ---------- clone: the only place with assembler ----------
  RawClone(Fn, StackTop, Flags, Arg, ChildTid): in the child, on the new stack,
  calls Fn(Arg) (cdecl) and exits (this thread only). }

{$ifdef cpux86_64}
function RawClone(Fn: TRawEntry; Stack: Pointer; Flags: PtrInt; Arg: Pointer; ChildTid: Pointer): PtrInt;
  cdecl; assembler; nostackframe;
asm
  // rdi=Fn rsi=Stack rdx=Flags rcx=Arg r8=ChildTid
  andq   $-16, %rsi
  subq   $16, %rsi
  movq   %rcx, 8(%rsi)
  movq   %rdi, (%rsi)
  movq   %rdx, %rdi        // flags
  xorq   %rdx, %rdx        // parent_tid
  movq   %r8, %r10         // child_tid
  xorq   %r8, %r8          // tls
  movl   $56, %eax         // clone
  syscall
  testq  %rax, %rax
  jnz    .Lparent
  xorl   %ebp, %ebp
  popq   %rax              // Fn
  popq   %rdi              // Arg
  call   *%rax
  movq   %rax, %rdi
  movl   $60, %eax         // exit (this thread only)
  syscall
  hlt
.Lparent:
end;
{$endif}

{$ifdef cpui386}
function RawClone(Fn: TRawEntry; Stack: Pointer; Flags: PtrInt; Arg: Pointer; ChildTid: Pointer): PtrInt;
  cdecl; assembler; nostackframe;
asm
  pushl  %ebx
  pushl  %esi
  pushl  %edi
  movl   20(%esp), %ecx    // Stack
  andl   $-16, %ecx
  subl   $16, %ecx
  movl   28(%esp), %eax    // Arg
  movl   %eax, 4(%ecx)
  movl   16(%esp), %eax    // Fn
  movl   %eax, (%ecx)
  movl   24(%esp), %ebx    // flags
  xorl   %edx, %edx        // parent_tid
  xorl   %esi, %esi        // tls
  movl   32(%esp), %edi    // child_tid
  movl   $120, %eax        // clone
  int    $0x80
  testl  %eax, %eax
  jnz    .Lparent
  xorl   %ebp, %ebp
  popl   %eax              // Fn; Arg stays on top of the stack as the cdecl argument
  call   *%eax
  movl   %eax, %ebx
  movl   $1, %eax          // exit (this thread only)
  int    $0x80
  hlt
.Lparent:
  popl   %edi
  popl   %esi
  popl   %ebx
end;
{$endif}

{$ifdef cpuaarch64}
function RawClone(Fn: TRawEntry; Stack: Pointer; Flags: PtrInt; Arg: Pointer; ChildTid: Pointer): PtrInt;
  cdecl; assembler; nostackframe;
asm
  // x0=Fn x1=Stack x2=Flags x3=Arg x4=ChildTid
  mov    x9, #-16
  and    x1, x1, x9
  sub    x1, x1, #16
  str    x0, [x1]
  str    x3, [x1, #8]
  mov    x0, x2            // flags
  mov    x2, xzr           // parent_tid
  mov    x3, xzr           // tls
  mov    x8, #220          // clone (x4 = child_tid)
  svc    #0
  cbnz   x0, .Lparent
  ldr    x9, [sp]          // Fn
  ldr    x0, [sp, #8]      // Arg
  add    sp, sp, #16
  mov    x29, xzr
  mov    x30, xzr
  blr    x9
  mov    x8, #93           // exit (this thread only)
  svc    #0
.Lparent:
end;
{$endif}

{ ---------- threads ---------- }

function RawThreadMain(Arg: Pointer): PtrInt; cdecl;
var
  T: PRawThread;
begin
  T := PRawThread(Arg);
  InitThread(T^.StackLen);
  T^.ExitCode := T^.Fn(T^.Arg);
  DoneThread;
  InterlockedDecrement(LiveThreads);
  Result := 0;
end;

{ Free the regions of the threads that have exited and are closed. }
procedure ReapZombies;
var
  P: ^PRawThread;
  T: PRawThread;
begin
  MutexEnter(ZombieLock);
  P := @Zombies;
  while P^ <> nil do
  begin
    T := P^;
    if (T^.Closed <> 0) and (T^.Tid = 0) then
    begin
      P^ := T^.Next;
      Fpmunmap(T^.Region, RegionSize);
    end
    else
      P := @T^.Next;
  end;
  MutexLeave(ZombieLock);
end;

function AllocRegion: Pointer;
const
  MaxTries = 8;
var
  Raw, Base: PtrUInt;
  Rejected: array[0..MaxTries - 1] of PtrUInt;
  NRej, I: Integer;
begin
  Result := nil;
  NRej := 0;
  repeat
    Raw := PtrUInt(Fpmmap(nil, 2 * RegionSize, PROT_READ or PROT_WRITE,
      MAP_PRIVATE or MAP_ANONYMOUS or MAP_NORESERVE, -1, 0));
    if Pointer(Raw) = MAP_FAILED then
      Break;
    Base := (Raw + RegionSize - 1) and not (RegionSize - 1);
    if Base > Raw then
      Fpmunmap(Pointer(Raw), Base - Raw);
    if Raw + 2 * RegionSize > Base + RegionSize then
      Fpmunmap(Pointer(Base + RegionSize), Raw + 2 * RegionSize - (Base + RegionSize));
    if (Base < MainHigh) and (Base + RegionSize > MainLow) then
    begin
      // The region overlaps the range taken as the stack of the main thread
      // (this happens under qemu-user, for one): keep it mapped and ask for another one.
      Rejected[NRej] := Base;
      Inc(NRej);
      Continue;
    end;
    Fpmprotect(Pointer(Base + CtlSize), GuardSize, PROT_NONE);
    Result := Pointer(Base);
    Break;
  until NRej >= MaxTries;
  for I := 0 to NRej - 1 do
    Fpmunmap(Pointer(Rejected[I]), RegionSize);
end;

{ Is libc in the process (FFI without -dSAFE_LIBC)? Read /proc/self/maps; without /proc we cannot tell and skip the check. }
function LibcLoaded: Boolean;
var
  Fd: cint;
  Buf: array[0..4095] of Char;
  Tail: string[32];
  S: AnsiString;
  N: TSsize;
begin
  Result := False;
  Fd := FpOpen('/proc/self/maps', O_RDONLY);
  if Fd < 0 then
    Exit;
  Tail := '';
  repeat
    N := FpRead(Fd, Buf, SizeOf(Buf));
    if N <= 0 then
      Break;
    SetString(S, PChar(@Buf[0]), N);
    S := Tail + S;
    if (Pos('/libc.so', S) > 0) or (Pos('/libc.musl', S) > 0) or (Pos('/ld-musl', S) > 0) then
    begin
      Result := True;
      Break;
    end;
    Tail := Copy(S, Length(S) - 31, 32);
  until False;
  FpClose(Fd);
end;

function RawBeginThread(SA: Pointer; StackSize: PtrUInt; ThreadFunction: TThreadFunc; P: Pointer;
  CreationFlags: DWord; var ThreadId: TThreadID): TThreadID;
var
  T: PRawThread;
  Region: Pointer;
begin
  if InterlockedExchange(TVInitialized, 1) = 0 then
  begin
    if LibcLoaded then
    begin
      WriteLn(StdErr, 'BPThreads: libc is loaded (FFI?), but threads run without libc TLS.');
      WriteLn(StdErr, 'Build this program with -dSAFE_LIBC (SPEC section 13, F5).');
      Halt(232);
    end;
    InitThreadVars(@RawRelocateThreadVar); // still single-threaded: copies the threadvars of the main thread
  end;
  IsMultiThread := True;
  ReapZombies;
  ThreadId := TThreadID(0);
  Result := TThreadID(0);
  Region := AllocRegion;
  if Region = nil then
    Exit;
  T := PRawThread(Region);
  T^.Magic := ThreadMagic;
  T^.TVBlock := NewTVBlock;
  T^.Fn := ThreadFunction;
  T^.Arg := P;
  T^.StackLen := RegionSize - CtlSize - GuardSize;
  T^.Tid := 1;
  T^.Closed := 0;
  T^.ExitCode := 0;
  T^.Region := Region;
  MutexEnter(ZombieLock);
  T^.Next := Zombies;
  Zombies := T;
  MutexLeave(ZombieLock);
  InterlockedIncrement(LiveThreads);
  if RawClone(@RawThreadMain, Region + RegionSize, CloneFlags, T, @T^.Tid) < 0 then
  begin
    InterlockedDecrement(LiveThreads);
    T^.Tid := 0;
    T^.Closed := 1;
    Fpmunmap(T^.TVBlock, ThreadVarBlockSize);
    ReapZombies;
    Exit;
  end;
  ThreadId := TThreadID(T);
  Result := ThreadId;
end;

procedure RawEndThread(ExitCode: DWord);
begin
  DoneThread;
  InterlockedDecrement(LiveThreads);
  do_syscall(syscall_nr_exit, TSysParam(ExitCode)); // this thread only; the collector frees the region
end;

function RawWaitForThreadTerminate(ThreadHandle: TThreadID; TimeoutMs: LongInt): DWord;
var
  T: PRawThread;
  Tid: LongInt;
begin
  T := PRawThread(ThreadHandle);
  repeat
    Tid := T^.Tid;
    if Tid = 0 then
      Break;
    FutexWaitShared(T^.Tid, Tid);
  until False;
  Result := 0;
end;

function RawCloseThread(ThreadHandle: TThreadID): DWord;
begin
  if (ThreadHandle <> TThreadID(0)) and (PRawThread(ThreadHandle) <> @MainThread) then
    InterlockedExchange(PRawThread(ThreadHandle)^.Closed, 1);
  ReapZombies;
  Result := 0;
end;

function RawUnsupported(ThreadHandle: TThreadID): DWord;
begin
  Result := DWord(-1);
end;

procedure RawThreadSwitch;
begin
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

{ ---------- events ---------- }

function NewEvent(Manual, Initial: Boolean): PRawEvent;
begin
  System.New(Result);
  Result^.Manual := Manual;
  Result^.Flag := Ord(Initial);
end;

{ True: signalled, False: timeout. TimeoutMs < 0: no timeout. }
function EventWait(E: PRawEvent; TimeoutMs: Int64): Boolean;
var
  Deadline, Left: Int64;
begin
  if TimeoutMs >= 0 then
    Deadline := NowMs + TimeoutMs
  else
    Deadline := 0;
  repeat
    if E^.Manual then
    begin
      if E^.Flag <> 0 then
        Exit(True);
    end
    else if InterlockedExchange(E^.Flag, 0) <> 0 then
      Exit(True);
    if TimeoutMs < 0 then
      FutexWait(E^.Flag, 0, -1)
    else
    begin
      Left := Deadline - NowMs;
      if Left <= 0 then
        Exit(False);
      FutexWait(E^.Flag, 0, Left);
    end;
  until False;
end;

procedure EventSet(E: PRawEvent);
begin
  InterlockedExchange(E^.Flag, 1);
  FutexWake(E^.Flag, High(LongInt));
end;

function RawRTLEventCreate: PRTLEvent;
begin
  Result := PRTLEvent(NewEvent(False, False));
end;

procedure RawRTLEventDestroy(State: PRTLEvent);
begin
  System.Dispose(PRawEvent(State));
end;

procedure RawRTLEventSet(State: PRTLEvent);
begin
  EventSet(PRawEvent(State));
end;

procedure RawRTLEventReset(State: PRTLEvent);
begin
  InterlockedExchange(PRawEvent(State)^.Flag, 0);
end;

procedure RawRTLEventWaitFor(State: PRTLEvent);
begin
  EventWait(PRawEvent(State), -1);
end;

procedure RawRTLEventWaitForTimeout(State: PRTLEvent; Timeout: LongInt);
begin
  EventWait(PRawEvent(State), Timeout);
end;

function RawBasicEventCreate(EventAttributes: Pointer; AManualReset, InitialState: Boolean;
  const Name: AnsiString): PEventState;
begin
  Result := PEventState(NewEvent(AManualReset, InitialState));
end;

procedure RawBasicEventDestroy(State: PEventState);
begin
  System.Dispose(PRawEvent(State));
end;

procedure RawBasicEventReset(State: PEventState);
begin
  InterlockedExchange(PRawEvent(State)^.Flag, 0);
end;

procedure RawBasicEventSet(State: PEventState);
begin
  EventSet(PRawEvent(State));
end;

function RawBasicEventWaitFor(Timeout: Cardinal; State: PEventState): LongInt;
const
  wrSignaled = 0;
  wrTimeout = 1;
begin
  if Timeout = $FFFFFFFF then
    EventWait(PRawEvent(State), -1)
  else if not EventWait(PRawEvent(State), Timeout) then
    Exit(wrTimeout);
  Result := wrSignaled;
end;

{ ---------- installation ---------- }

function RawInitManager: Boolean;
begin
  Result := True;
end;

function RawDoneManager: Boolean;
begin
  Result := True;
end;

procedure SetRawThreadManager;
var
  TM: TThreadManager;
  RL: TRLimit;
  Reserve: PtrUInt;
begin
  if ThreadingAlreadyUsed then
  begin
    WriteLn('BPThreads: threading was used before BPThreads was initialized.');
    WriteLn('In the program put BP (or BPThreads) FIRST in the uses clause: uses BP, SysUtils, ...');
    RunError(211);
  end;
  {$if SizeOf(TRTLCriticalSection) < SizeOf(TRawMutex)}
    {$error BPThreads: TRTLCriticalSection is smaller than the futex mutex}
  {$endif}
  // The stack of the main thread: [MainLow, MainHigh). Above: argv, which lies on the stack
  // above any frame of the main thread. Below: the stack limit (RLIMIT_STACK, with a margin).
  // Thread regions never fall into this range: AllocRegion makes sure of it.
  {$ifdef cpu64}
  Reserve := PtrUInt(1) shl 30;
  {$else}
  Reserve := PtrUInt(1) shl 28;
  {$endif}
  if (FpGetRLimit(RLIMIT_STACK, @RL) = 0) and (RL.rlim_cur < Reserve) then
    Reserve := RL.rlim_cur;
  if Reserve < 8 * 1024 * 1024 then
    Reserve := 8 * 1024 * 1024;
  MainHigh := PtrUInt(argv);
  if MainHigh < PtrUInt(Sptr) then // just in case: argv must be higher
    MainHigh := PtrUInt(Sptr) + 65536;
  if PtrUInt(Sptr) > Reserve then
    MainLow := PtrUInt(Sptr) - Reserve
  else
    MainLow := 0;
  MainThread.Magic := ThreadMagic;
  MainThread.Tid := 1;

  System.FillChar(TM, SizeOf(TM), 0);
  TM.InitManager := @RawInitManager;
  TM.DoneManager := @RawDoneManager;
  TM.BeginThread := @RawBeginThread;
  TM.EndThread := @RawEndThread;
  TM.SuspendThread := @RawUnsupported;
  TM.ResumeThread := @RawUnsupported;
  TM.KillThread := @RawUnsupported;
  TM.CloseThread := @RawCloseThread;
  TM.ThreadSwitch := @RawThreadSwitch;
  TM.WaitForThreadTerminate := @RawWaitForThreadTerminate;
  TM.ThreadSetPriority := @RawSetPriority;
  TM.ThreadGetPriority := @RawGetPriority;
  TM.GetCurrentThreadId := @RawGetCurrentThreadId;
  TM.SetThreadDebugNameA := @RawSetNameA;
  TM.SetThreadDebugNameU := @RawSetNameU;
  TM.InitCriticalSection := @RawInitCS;
  TM.DoneCriticalSection := @RawDoneCS;
  TM.EnterCriticalSection := @RawEnterCS;
  TM.TryEnterCriticalSection := @RawTryEnterCS;
  TM.LeaveCriticalSection := @RawLeaveCS;
  TM.InitThreadVar := @RawInitThreadVar;
  TM.RelocateThreadVar := @RawRelocateThreadVar;
  TM.AllocateThreadVars := @RawAllocateThreadVars;
  TM.ReleaseThreadVars := @RawReleaseThreadVars;
  TM.BasicEventCreate := @RawBasicEventCreate;
  TM.BasicEventDestroy := @RawBasicEventDestroy;
  TM.BasicEventResetEvent := @RawBasicEventReset;
  TM.BasicEventSetEvent := @RawBasicEventSet;
  TM.BasiceventWaitFor := @RawBasicEventWaitFor;
  TM.RTLEventCreate := @RawRTLEventCreate;
  TM.RTLEventDestroy := @RawRTLEventDestroy;
  TM.RTLEventSetEvent := @RawRTLEventSet;
  TM.RTLEventResetEvent := @RawRTLEventReset;
  TM.RTLEventWaitFor := @RawRTLEventWaitFor;
  TM.RTLEventWaitForTimeout := @RawRTLEventWaitForTimeout;
  SetThreadManager(TM);
end;

initialization
  SetRawThreadManager;
{$endif SAFE_RAW}
end.
