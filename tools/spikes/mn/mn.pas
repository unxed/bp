{ SPDX-License-Identifier: MIT }
// UNSAFE-UNIT: a prototype of a scheduler: the switch of stacks (assembler) and hooks of the thread manager.
{ Spike 4 of unxed/bp#108 (safe/SPEC.md §21.3, §21.7 step 2): goroutines M:N on the stacks of BPThreads, one carrier.

  A goroutine is a stack region laid out as BPThreads lays out the region of a thread: aligned to its size, with the head
  of the thread record (Magic, the threadvar block) at its start. BPThreads finds the current thread from the stack
  pointer, so a switch of the stack pointer is a switch of the thread for the RTL: the threadvars, the exception frames,
  the free lists of the heap and Output follow the goroutine with no code here.

  The scheduler sits behind the hooks of TThreadManager: RTLEventWaitFor parks the goroutine and runs the next one,
  RTLEventSetEvent puts the parked one back into the run queue, a contended EnterCriticalSection yields. So TChan of
  ext/go works between goroutines unchanged. An OS thread (not a goroutine) still gets the hooks of BPThreads.

  The regions are carved out of one reservation (PROT_NONE, MAP_NORESERVE). With MnGuard a guard area stays PROT_NONE
  between the record and the stack (two mappings per goroutine); without it the region is one read-write range that
  merges with its neighbours, and the stack check of the compiler (-Ct) is the net: the stack length given to the RTL
  ends above the same area, which then stays unused.

  The limits of the spike: one carrier (the run queue and the counters are not locked), no timers (a goroutine cannot
  wait with a timeout), MnGo instead of BeginThread. }
{$mode objfpc}{$H+}
unit Mn;

interface

{$if not defined(linux) or defined(SAFE_LIBC) or not (defined(cpux86_64) or defined(cpui386) or defined(cpuaarch64))}
  {$error Mn: the raw mode of BPThreads only (x86_64, i386, aarch64 Linux without -dSAFE_LIBC)}
{$endif}

uses
  BPThreads, BaseUnix, Linux, Syscall, SysUtils;

type
  TGoProc = procedure(Arg: Pointer);

var
  { A guard area (PROT_NONE) under each stack. Without it the stack check of the compiler (-Ct) is the only net. Set
    before the first MnGo; the default follows -Ct. }
  MnGuard: Boolean = {$ifopt S+}False{$else}True{$endif};
  { Exceptions that left the procedure of a goroutine; the message of the last one. }
  MnUncaught: Integer = 0;
  MnUncaughtMsg: ShortString = '';

{ Start a goroutine on the carrier (from the carrier or from a goroutine). StackLimit > 0: a shorter stack length for the
  RTL (StackBottom), for the test of -Ct. }
procedure MnGo(Fn: TGoProc; Arg: Pointer; StackLimit: PtrUInt = 0);
{ Give the carrier to the next ready goroutine; on an OS thread: sched_yield. }
procedure MnYield;
{ Run the goroutines on the current thread (the carrier) until none is ready. True: all have finished; False: a
  deadlock, every goroutine left is parked ("all goroutines are asleep"). }
function MnRun: Boolean;
{ The goroutine that runs now (its region), nil on an OS thread. }
function MnSelf: Pointer;
{ The id of the kernel thread (gettid): the same for every goroutine of one carrier. }
function MnKernelTid: LongInt;

{ For the measurements. }
function MnRegionSize: PtrUInt;
function MnThreadVarSize: PtrUInt;
function MnCtlSize: PtrUInt;          // the record and the threadvar block, rounded up to pages
function MnLive: Integer;             // goroutines not finished
function MnParked: Integer;           // goroutines parked now
function MnStackInUse(G: Pointer): PtrUInt; // the bytes of stack a parked goroutine holds (top - saved stack pointer)
function MnSwitches: Int64;           // switches of the stack pointer so far

implementation

{$S-} // hooks of the thread manager and the scheduler: no stack check here, as in BPThreads

const
  {$ifdef cpu64}
  RegionLog2 = 23;                    // = BPThreads (checked by SelfCheck at the first MnRun)
  MaxRegions = 4096;                  // 32 GiB of addresses, no memory
  {$else}
  RegionLog2 = 20;
  MaxRegions = 512;                   // 512 MiB of the 32-bit address space
  {$endif}
  RegionSize = PtrUInt(1) shl RegionLog2;
  RawMagic = PtrUInt($5AFE7EAD);      // = BPThreads.ThreadMagic
  GuardSize = 65536;                  // = BPThreads: larger than any frame of the RTL, so a frame cannot jump over it
  TopReserve = 256;                   // the first frame of a goroutine
  PageSize = 4096;

type
  TGState = (gsReady, gsRunning, gsParked, gsDead);

  PG = ^TG;
  TG = record
    Magic: PtrUInt;                   // the head of BPThreads.TRawThread: the threadvar block of the thread of Sptr
    TVBlock: Pointer;
    SP: Pointer;                      // the saved stack pointer while the goroutine does not run
    Fn: TGoProc;
    Arg: Pointer;
    StackLen: PtrUInt;
    State: TGState;
    Next: PG;                         // the run queue; the list of free regions
  end;

  { An event of the RTL (PRTLEvent) for both kinds of waiters. }
  PMnEvent = ^TMnEvent;
  TMnEvent = record
    Raw: PRTLEvent;                   // the event of BPThreads, for an OS thread
    Flag: LongInt;                    // set and not consumed yet
    OsWaiting: LongInt;               // OS threads in RTLEventWaitFor: only then the futex is woken
    Waiter: PG;                       // the goroutine parked on it (only its owner waits on it)
  end;

var
  Orig: TThreadManager;
  TVSize: PtrUInt = 0;
  CtlSize: PtrUInt = 0;
  RecSize: PtrUInt = 0;
  ResLow: PtrUInt = 0;                // the reservation: [ResLow, ResHigh)
  ResHigh: PtrUInt = 0;
  ResNext: PtrUInt = 0;               // the first region never carved
  FreeRegions: PG = nil;
  RunHead: PG = nil;
  RunTail: PG = nil;
  CarrierSP: Pointer = nil;           // the saved stack pointer of the carrier while a goroutine runs
  Live: Integer = 0;
  Parked: Integer = 0;
  Switches: Int64 = 0;
  Checked: Boolean = False;

threadvar
  MnProbe: Integer;                   // its address shows where the threadvar block of a thread is

{ ---------- the switch: about ten instructions per architecture ----------
  MnSwitch(Save, Next): pushes the callee-saved registers on the current stack, stores the stack pointer to Save^, loads
  Next as the stack pointer, pops the registers saved there and returns into the code that saved them (or, for a new
  goroutine, into GoEntry: see InitialFrame). }

{$if defined(cpux86_64)}
procedure MnSwitch(Save: PPointer; Next: Pointer); assembler; nostackframe;
asm
  // rdi = Save, rsi = Next; callee-saved: rbx, rbp, r12-r15 (System V)
  pushq  %rbp
  pushq  %rbx
  pushq  %r12
  pushq  %r13
  pushq  %r14
  pushq  %r15
  movq   %rsp, (%rdi)
  movq   %rsi, %rsp
  popq   %r15
  popq   %r14
  popq   %r13
  popq   %r12
  popq   %rbx
  popq   %rbp
end;
{$elseif defined(cpui386)}
procedure MnSwitch(Save: PPointer; Next: Pointer); assembler; nostackframe;
asm
  // eax = Save, edx = Next (the register convention of FPC); callee-saved: ebx, esi, edi, ebp
  pushl  %ebp
  pushl  %ebx
  pushl  %esi
  pushl  %edi
  movl   %esp, (%eax)
  movl   %edx, %esp
  popl   %edi
  popl   %esi
  popl   %ebx
  popl   %ebp
end;
{$elseif defined(cpuaarch64)}
procedure MnSwitch(Save: PPointer; Next: Pointer); assembler; nostackframe;
asm
  // x0 = Save, x1 = Next; callee-saved: x19-x28, x29 (frame), x30 (link), d8-d15 (AAPCS64)
  sub    sp, sp, #160
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
  mov    x9, sp
  str    x9, [x0]
  mov    sp, x1
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
  add    sp, sp, #160
end;
{$endif}

procedure GoEntry; forward;

{ The stack of a new goroutine as MnSwitch leaves it: zero registers, and the return address GoEntry placed so that
  GoEntry starts with the alignment of a called routine. }
function InitialFrame(Top: PtrUInt): Pointer;
var
  W: PPtrUInt;
begin
  {$if defined(cpux86_64)}
  // [Top-8] a zero return address of GoEntry, [Top-16] GoEntry, then rbp, rbx, r12-r15: rsp = 8 mod 16 at its entry
  W := PPtrUInt(Top - 64);
  System.FillChar(W^, 64, 0);
  W[6] := PtrUInt(@GoEntry);
  {$elseif defined(cpui386)}
  // [Top-4] a zero return address, [Top-8] GoEntry, then ebp, ebx, esi, edi: esp = 12 mod 16 at its entry
  W := PPtrUInt(Top - 24);
  System.FillChar(W^, 24, 0);
  W[4] := PtrUInt(@GoEntry);
  {$elseif defined(cpuaarch64)}
  // 160 bytes of registers; x30 (at 88) is GoEntry, sp = Top (16-aligned) at its entry
  W := PPtrUInt(Top - 160);
  System.FillChar(W^, 160, 0);
  W[11] := PtrUInt(@GoEntry);
  {$endif}
  Result := W;
end;

{ ---------- the current goroutine: from the stack pointer, as BPThreads does ---------- }

function Mine: PG; inline;
var
  SP: PtrUInt;
begin
  SP := PtrUInt(Sptr);
  if (SP >= ResLow) and (SP < ResHigh) then
    Result := PG(SP and not (RegionSize - 1))
  else
    Result := nil;
end;

function MnSelf: Pointer;
begin
  Result := Mine;
end;

function MnKernelTid: LongInt;
begin
  Result := do_syscall(syscall_nr_gettid);
end;

{ ---------- the run queue (one carrier: no lock) ---------- }

procedure Push(G: PG);
begin
  G^.State := gsReady;
  G^.Next := nil;
  if RunTail = nil then
    RunHead := G
  else
    RunTail^.Next := G;
  RunTail := G;
end;

procedure ToCarrier(G: PG);
begin
  Inc(Switches);
  MnSwitch(@G^.SP, CarrierSP);
end;

procedure Park(G: PG);
begin
  G^.State := gsParked;
  Inc(Parked);
  ToCarrier(G);
  Dec(Parked);
end;

procedure MakeReady(G: PG);
begin
  if G^.State = gsParked then
    Push(G);
end;

procedure MnYield;
var
  G: PG;
begin
  G := Mine;
  if G = nil then
  begin
    Orig.ThreadSwitch();
    Exit;
  end;
  Push(G);
  ToCarrier(G);
end;

{ ---------- regions ---------- }

procedure Fail(const Msg: ShortString);
begin
  WriteLn(StdErr, 'Mn: ', Msg);
  Halt(3);
end;

{ The stack of the main thread as BPThreads computes it, with a margin: a region there would be taken for the main
  thread (this happens under qemu-user). }
function HitsMainStack(Lo, Hi: PtrUInt): Boolean;
var
  RL: TRLimit;
  Reserve, MainHigh, MainLow: PtrUInt;
begin
  {$ifdef cpu64}
  Reserve := PtrUInt(1) shl 30;
  {$else}
  Reserve := PtrUInt(1) shl 28;
  {$endif}
  if (FpGetRLimit(RLIMIT_STACK, @RL) = 0) and (RL.rlim_cur < Reserve) then
    Reserve := RL.rlim_cur;
  if Reserve < 8 * 1024 * 1024 then
    Reserve := 8 * 1024 * 1024;
  MainHigh := PtrUInt(argv) + 65536;
  if MainHigh > Reserve + 16 * 1024 * 1024 then
    MainLow := MainHigh - Reserve - 16 * 1024 * 1024
  else
    MainLow := 0;
  Result := (Lo < MainHigh) and (Hi > MainLow);
end;

procedure Reserve;
const
  MaxTries = 8;
var
  N, Raw, Base, Len: PtrUInt;
  Rejected: array[0..MaxTries - 1] of PtrUInt;
  RejLen: array[0..MaxTries - 1] of PtrUInt;
  NRej, I: Integer;
begin
  N := MaxRegions;
  NRej := 0;
  repeat
    Len := (N + 1) * RegionSize;
    Raw := PtrUInt(Fpmmap(nil, Len, PROT_NONE, MAP_PRIVATE or MAP_ANONYMOUS or MAP_NORESERVE, -1, 0));
    if Pointer(Raw) = MAP_FAILED then
    begin
      N := N div 2;
      if N < 16 then
        Fail('cannot reserve the stacks');
      Continue;
    end;
    if HitsMainStack(Raw, Raw + Len) then
    begin
      Rejected[NRej] := Raw;
      RejLen[NRej] := Len;
      Inc(NRej);
      if NRej = MaxTries then
        Fail('every reservation falls into the stack of the main thread');
      Continue;
    end;
    Break;
  until False;
  for I := 0 to NRej - 1 do
    Fpmunmap(Pointer(Rejected[I]), RejLen[I]);
  Base := (Raw + RegionSize - 1) and not (RegionSize - 1);
  if Base > Raw then
    Fpmunmap(Pointer(Raw), Base - Raw);
  if Raw + Len > Base + N * RegionSize then
    Fpmunmap(Pointer(Base + N * RegionSize), Raw + Len - (Base + N * RegionSize));
  ResLow := Base;
  ResHigh := Base + N * RegionSize;
  ResNext := ResLow;
end;

function NewRegion: PG;
var
  Base: PtrUInt;
begin
  if FreeRegions <> nil then
  begin
    Result := FreeRegions;
    FreeRegions := Result^.Next;
    System.FillChar(Result^, CtlSize, 0);   // madvise may keep the old pages (qemu-user): the threadvars start at zero
    Exit;
  end;
  if ResLow = 0 then
    Reserve;
  if ResNext >= ResHigh then
    Fail('the reservation of the spike is full');
  Base := ResNext;
  Inc(ResNext, RegionSize);
  if MnGuard then
  begin
    // [record + threadvars] [guard: stays PROT_NONE] [stack]
    if (Fpmprotect(Pointer(Base), CtlSize, PROT_READ or PROT_WRITE) <> 0) or
       (Fpmprotect(Pointer(Base + CtlSize + GuardSize), RegionSize - CtlSize - GuardSize,
         PROT_READ or PROT_WRITE) <> 0) then
      Fail('mprotect');
  end
  else if Fpmprotect(Pointer(Base), RegionSize, PROT_READ or PROT_WRITE) <> 0 then
    Fail('mprotect');
  Result := PG(Base);
end;

{ On the carrier, after the goroutine has switched away for the last time: the pages go back to the kernel, the
  addresses stay for the next goroutine. }
procedure FreeRegion(G: PG);
const
  MADV_DONTNEED = 4;
var
  Lo: PtrUInt;
begin
  Lo := PtrUInt(G) + CtlSize + GuardSize;
  do_syscall(syscall_nr_madvise, TSysParam(Lo), TSysParam(PtrUInt(G) + RegionSize - Lo), MADV_DONTNEED);
  do_syscall(syscall_nr_madvise, TSysParam(G), TSysParam(CtlSize), MADV_DONTNEED);
  G^.Next := FreeRegions;  // the record reads as zeroes now (touches its first page again)
  FreeRegions := G;
end;

{ ---------- goroutines ---------- }

procedure RunBody(G: PG);
begin
  try
    G^.Fn(G^.Arg);
  except
    on E: Exception do
    begin
      Inc(MnUncaught);
      MnUncaughtMsg := E.ClassName + ': ' + E.Message;
    end;
  end;
end;

{ The first frame of every goroutine (reached by the return of MnSwitch); it never returns. }
procedure GoEntry;
var
  G: PG;
begin
  G := Mine;
  InitThread(G^.StackLen);    // the heap, the exceptions, stdio, StackBottom and ThreadID of this goroutine
  RunBody(G);
  DoneThread;                 // finalizes its heap, flushes its Output; no threadvar after this
  G^.State := gsDead;
  Dec(Live);
  ToCarrier(G);
end;

procedure MnGo(Fn: TGoProc; Arg: Pointer; StackLimit: PtrUInt);
var
  G: PG;
begin
  if TVSize = 0 then
    Fail('MnGo before the threadvars are set up: call it on a carrier started by BeginThread');
  G := NewRegion;
  G^.Magic := RawMagic;
  G^.TVBlock := Pointer(PtrUInt(G) + RecSize);   // in the record page: no mapping of its own
  G^.Fn := Fn;
  G^.Arg := Arg;
  G^.StackLen := RegionSize - CtlSize - GuardSize - TopReserve;
  if (StackLimit > 0) and (StackLimit < G^.StackLen) then
    G^.StackLen := StackLimit;
  G^.SP := InitialFrame(PtrUInt(G) + RegionSize);
  Inc(Live);
  Push(G);
end;

{ The layout of BPThreads that a goroutine relies on, checked on a thread of BPThreads (the carrier). }
procedure SelfCheck;
var
  Base, TV: PtrUInt;
begin
  Base := PtrUInt(Sptr) and not (RegionSize - 1);
  if PPtrUInt(Base)^ <> RawMagic then
    Fail('the carrier is not a thread of BPThreads with regions of the expected size');
  TV := PPtrUInt(Base + SizeOf(PtrUInt))^;
  if (PtrUInt(@MnProbe) < TV) or (PtrUInt(@MnProbe) >= TV + TVSize) then
    Fail('the threadvar block is not where BPThreads keeps it');
  Checked := True;
end;

function MnRun: Boolean;
var
  G: PG;
begin
  if not Checked then
    SelfCheck;
  while RunHead <> nil do
  begin
    G := RunHead;
    RunHead := G^.Next;
    if RunHead = nil then
      RunTail := nil;
    G^.State := gsRunning;
    Inc(Switches);
    MnSwitch(@CarrierSP, G^.SP);
    if G^.State = gsDead then
      FreeRegion(G);
  end;
  Result := Live = 0;
end;

{ ---------- the hooks of the thread manager ---------- }

procedure MnInitThreadVar(var Offset: DWord; Size: DWord);
begin
  Orig.InitThreadVar(Offset, Size);
  if Offset + Size > TVSize then
    TVSize := Offset + Size;
  RecSize := (SizeOf(TG) + 63) and not PtrUInt(63);
  CtlSize := (RecSize + TVSize + PageSize - 1) and not PtrUInt(PageSize - 1);
end;

procedure MnReleaseThreadVars;
begin
  if Mine = nil then           // a goroutine: the block lies in its region, which the carrier reuses
    Orig.ReleaseThreadVars();
end;

procedure MnEnterCS(var CS);
begin
  if Mine <> nil then
    while Orig.TryEnterCriticalSection(CS) = 0 do
      MnYield                  // never park a carrier in the futex while the owner waits in the run queue
  else
    Orig.EnterCriticalSection(CS);
end;

function MnEventCreate: PRTLEvent;
var
  E: PMnEvent;
begin
  System.New(E);
  E^.Raw := Orig.RTLEventCreate();
  E^.Flag := 0;
  E^.OsWaiting := 0;
  E^.Waiter := nil;
  Result := PRTLEvent(E);
end;

procedure MnEventDestroy(State: PRTLEvent);
begin
  Orig.RTLEventDestroy(PMnEvent(State)^.Raw);
  System.Dispose(PMnEvent(State));
end;

procedure MnEventSet(State: PRTLEvent);
var
  E: PMnEvent;
  W: PG;
begin
  E := PMnEvent(State);
  InterlockedExchange(E^.Flag, 1);
  W := E^.Waiter;
  if W <> nil then
  begin
    E^.Waiter := nil;
    MakeReady(W);
  end;
  if E^.OsWaiting > 0 then
    Orig.RTLEventSetEvent(E^.Raw);
end;

procedure MnEventReset(State: PRTLEvent);
begin
  InterlockedExchange(PMnEvent(State)^.Flag, 0);
  Orig.RTLEventResetEvent(PMnEvent(State)^.Raw);
end;

procedure MnEventWait(State: PRTLEvent);
var
  E: PMnEvent;
  G: PG;
begin
  E := PMnEvent(State);
  G := Mine;
  if G <> nil then
    while InterlockedExchange(E^.Flag, 0) = 0 do
    begin
      E^.Waiter := G;
      Park(G);
    end
  else
  begin
    InterlockedIncrement(E^.OsWaiting);
    while InterlockedExchange(E^.Flag, 0) = 0 do
      Orig.RTLEventWaitFor(E^.Raw);
    InterlockedDecrement(E^.OsWaiting);
  end;
end;

procedure MnEventWaitTimeout(State: PRTLEvent; Timeout: LongInt);
var
  E: PMnEvent;
begin
  E := PMnEvent(State);
  if Mine <> nil then
    Fail('a goroutine waits with a timeout: no timers in the spike');
  InterlockedIncrement(E^.OsWaiting);
  if InterlockedExchange(E^.Flag, 0) = 0 then
  begin
    Orig.RTLEventWaitForTimeout(E^.Raw, Timeout);
    InterlockedExchange(E^.Flag, 0);
  end;
  InterlockedDecrement(E^.OsWaiting);
end;

procedure Install;
var
  TM: TThreadManager;
begin
  GetThreadManager(Orig);
  TM := Orig;
  TM.InitThreadVar := @MnInitThreadVar;
  TM.ReleaseThreadVars := @MnReleaseThreadVars;
  TM.EnterCriticalSection := @MnEnterCS;
  TM.RTLEventCreate := @MnEventCreate;
  TM.RTLEventDestroy := @MnEventDestroy;
  TM.RTLEventSetEvent := @MnEventSet;
  TM.RTLEventResetEvent := @MnEventReset;
  TM.RTLEventWaitFor := @MnEventWait;
  TM.RTLEventWaitForTimeout := @MnEventWaitTimeout;
  SetThreadManager(TM);
end;

{ ---------- for the measurements ---------- }

function MnRegionSize: PtrUInt;
begin
  Result := RegionSize;
end;

function MnThreadVarSize: PtrUInt;
begin
  Result := TVSize;
end;

function MnCtlSize: PtrUInt;
begin
  Result := CtlSize;
end;

function MnLive: Integer;
begin
  Result := Live;
end;

function MnParked: Integer;
begin
  Result := Parked;
end;

function MnStackInUse(G: Pointer): PtrUInt;
begin
  Result := PtrUInt(G) + RegionSize - PtrUInt(PG(G)^.SP);
end;

function MnSwitches: Int64;
begin
  Result := Switches;
end;

initialization
  Install;
end.
