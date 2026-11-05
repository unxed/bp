{ SPDX-License-Identifier: MIT }
{ The atomic routines that the locks and the lock-free lists of BP rely on (included at the start of the implementation
  of units Safe, BP and BPThreads). On aarch64 the Interlocked routines of FPC 3.2.2 are ldxr/stxr loops with no
  barrier: a spin lock built on them orders nothing, and the fields written under it may be seen before the lock, or
  after the unlock. These versions put a full barrier (dmb ish) on both sides, as the lock prefix does on x86, so the
  code that uses them reads the same on every CPU. Elsewhere they are not compiled (-dBP_ATOMIC_BARRIERS compiles them
  on any CPU, to check that every call still resolves). }
{$if defined(cpuaarch64) or defined(BP_ATOMIC_BARRIERS)}
function InterlockedExchange(var Target: LongInt; Source: LongInt): LongInt; overload;
begin
  ReadWriteBarrier;
  Result := System.InterlockedExchange(Target, Source);
  ReadWriteBarrier;
end;

function InterlockedExchange(var Target: System.Pointer; Source: System.Pointer): System.Pointer; overload;
begin
  ReadWriteBarrier;
  Result := System.InterlockedExchange(Target, Source);
  ReadWriteBarrier;
end;

function InterlockedCompareExchange(var Target: LongInt; NewValue, Comperand: LongInt): LongInt; overload;
begin
  ReadWriteBarrier;
  Result := System.InterlockedCompareExchange(Target, NewValue, Comperand);
  ReadWriteBarrier;
end;

function InterlockedCompareExchange(var Target: System.Pointer; NewValue, Comperand: System.Pointer): System.Pointer;
  overload;
begin
  ReadWriteBarrier;
  Result := System.InterlockedCompareExchange(Target, NewValue, Comperand);
  ReadWriteBarrier;
end;

function InterlockedIncrement(var Target: LongInt): LongInt; overload;
begin
  ReadWriteBarrier;
  Result := System.InterlockedIncrement(Target);
  ReadWriteBarrier;
end;

function InterlockedDecrement(var Target: LongInt): LongInt; overload;
begin
  ReadWriteBarrier;
  Result := System.InterlockedDecrement(Target);
  ReadWriteBarrier;
end;
{$endif}
