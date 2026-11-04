{ SPDX-License-Identifier: MIT }
{ Spike 3 of unxed/bp#108: can a collector find its roots on the stack of its own goroutine? (safe/SPEC.md §20)
  A heap per thread; roots: a conservative scan of [Sptr, SafeStackHigh) after the callee-saved registers are
  written to the stack; edges: the published fields of the classes (the field table of the VMT); mark and sweep.
  Prints ok/FAIL lines, exits with 1 on a failure. Run by tools/spikes/gcroots/run.sh, not by tests/run.sh. }
{$mode objfpc}{$H+}
program gcroots;

uses
  BPThreads, SysUtils;

type
  {$M+}
  TGcObject = class
  public
    class function NewInstance: TObject; override;
    procedure FreeInstance; override;
  end;
  {$M-}

  TNode = class(TGcObject)
    Next, Child: TNode;          // the default section of an $M+ class is published: these are the edges
  public
    X: Integer;
    Name: String;
  end;

  PFieldInfo = ^TFieldInfo;
  TFieldInfo = {$ifndef FPC_REQUIRES_PROPER_ALIGNMENT}packed{$endif} record
    FieldOffset: SizeUInt;
    ClassTypeIndex: Word;
    Name: ShortString;
  end;
  PFieldTable = ^TFieldTable;
  TFieldTable = {$ifndef FPC_REQUIRES_PROPER_ALIGNMENT}packed{$endif} record
    FieldCount: Word;
    ClassTable: Pointer;
    Fields: TFieldInfo;
  end;

  TPtrArray = array of Pointer;

threadvar
  Heap: TPtrArray;        // the objects of this thread's heap
  HeapCount: SizeInt;

var
  Failures: Integer = 0;

procedure Check(Cond: Boolean; const What: String);
begin
  if Cond then
    WriteLn('ok   ', What)
  else
  begin
    WriteLn('FAIL ', What);
    Inc(Failures);
  end;
end;

class function TGcObject.NewInstance: TObject;
var
  P: Pointer;
begin
  GetMem(P, InstanceSize);
  Result := InitInstance(P);
  if HeapCount = Length(Heap) then
    SetLength(Heap, 2 * HeapCount + 16);
  Heap[HeapCount] := P;
  Inc(HeapCount);
end;

procedure TGcObject.FreeInstance;
begin
  // the collector frees the objects; Free of a GC object does nothing
end;

{ ---------- the callee-saved registers onto the stack ---------- }

{$if defined(cpux86_64)}
procedure SpillRegs(Buf: Pointer); assembler; nostackframe;
asm
  movq %rbx, 0(%rdi)
  movq %rbp, 8(%rdi)
  movq %r12, 16(%rdi)
  movq %r13, 24(%rdi)
  movq %r14, 32(%rdi)
  movq %r15, 40(%rdi)
end;
{$elseif defined(cpui386)}
procedure SpillRegs(Buf: Pointer); assembler; nostackframe;
asm
  movl %ebx, 0(%eax)
  movl %esi, 4(%eax)
  movl %edi, 8(%eax)
  movl %ebp, 12(%eax)
end;
{$elseif defined(cpuaarch64)}
procedure SpillRegs(Buf: Pointer); assembler; nostackframe;
asm
  stp x19, x20, [x0]
  stp x21, x22, [x0, #16]
  stp x23, x24, [x0, #32]
  stp x25, x26, [x0, #48]
  stp x27, x28, [x0, #64]
  stp x29, x30, [x0, #80]
end;
{$else}
  {$error gcroots: x86_64, i386, aarch64 only}
{$endif}

{ ---------- mark and sweep ---------- }

threadvar
  Sorted: TPtrArray;       // the heap sorted by address, for the lookup of a word
  Marked: array of Boolean;
  Work: TPtrArray;
  WorkCount: SizeInt;

procedure SortHeap;
  procedure QSort(L, R: SizeInt);
  var
    I, J: SizeInt;
    P, T: Pointer;
  begin
    repeat
      I := L; J := R; P := Sorted[(L + R) div 2];
      repeat
        while PtrUInt(Sorted[I]) < PtrUInt(P) do Inc(I);
        while PtrUInt(Sorted[J]) > PtrUInt(P) do Dec(J);
        if I <= J then
        begin
          T := Sorted[I]; Sorted[I] := Sorted[J]; Sorted[J] := T;
          Inc(I); Dec(J);
        end;
      until I > J;
      if L < J then QSort(L, J);
      L := I;
    until I >= R;
  end;
begin
  Sorted := Copy(Heap, 0, HeapCount);
  if HeapCount > 1 then
    QSort(0, HeapCount - 1);
  SetLength(Marked, HeapCount);
  if HeapCount > 0 then
    FillChar(Marked[0], HeapCount, 0);
end;

{ The object a word points into (to its start or inside it), or -1. }
function Find(W: PtrUInt): SizeInt;
var
  L, R, M: SizeInt;
begin
  L := 0; R := HeapCount - 1; Result := -1;
  while L <= R do
  begin
    M := (L + R) div 2;
    if PtrUInt(Sorted[M]) <= W then
    begin
      Result := M; L := M + 1;
    end
    else
      R := M - 1;
  end;
  if (Result >= 0) and (W >= PtrUInt(Sorted[Result]) + PtrUInt(TObject(Sorted[Result]).InstanceSize)) then
    Result := -1;
end;

procedure MarkWord(W: PtrUInt);
var
  I: SizeInt;
begin
  I := Find(W);
  if (I < 0) or Marked[I] then
    Exit;
  Marked[I] := True;
  if WorkCount = Length(Work) then
    SetLength(Work, 2 * WorkCount + 16);
  Work[WorkCount] := Sorted[I];
  Inc(WorkCount);
end;

procedure MarkEdges(Obj: Pointer);
var
  C: TClass;
  T: PFieldTable;
  F: PFieldInfo;
  I: Integer;
begin
  C := TObject(Obj).ClassType;
  while C <> nil do
  begin
    T := PFieldTable(PVmt(C)^.vFieldTable);
    if T <> nil then
    begin
      F := @T^.Fields;
      for I := 1 to T^.FieldCount do
      begin
        MarkWord(PPtrUInt(PByte(Obj) + F^.FieldOffset)^);
        F := PFieldInfo(PByte(@F^.Name) + 1 + Length(F^.Name));
        {$ifdef FPC_REQUIRES_PROPER_ALIGNMENT}
        F := PFieldInfo(Align(F, SizeOf(SizeUInt)));
        {$endif}
      end;
    end;
    C := C.ClassParent;
  end;
end;

{ Collects the heap of the current thread; returns the number of freed objects. }
function GcCollect: SizeInt;
var
  Regs: array[0..15] of PtrUInt;
  P, High: PtrUInt;
  I, N: SizeInt;
begin
  {$ifndef NOSPILL}SpillRegs(@Regs[0]);{$endif} // -dNOSPILL: the check that the test needs the spill
  SortHeap;
  WorkCount := 0;
  P := PtrUInt(Sptr) and not PtrUInt(SizeOf(Pointer) - 1);
  High := SafeStackHigh;
  while P < High do
  begin
    MarkWord(PPtrUInt(P)^);
    Inc(P, SizeOf(Pointer));
  end;
  while WorkCount > 0 do
  begin
    Dec(WorkCount);
    MarkEdges(Work[WorkCount]);
  end;
  N := 0;
  Result := 0;
  for I := 0 to HeapCount - 1 do
    if Marked[I] then
    begin
      Heap[N] := Sorted[I];
      Inc(N);
    end
    else
    begin
      TObject(Sorted[I]).CleanupInstance;     // the managed fields (strings)
      FillChar(Sorted[I]^, TObject(Sorted[I]).InstanceSize, $DE);
      FreeMem(Sorted[I]);
      Inc(Result);
    end;
  HeapCount := N;
  if Regs[0] = 0 then ; // keeps Regs alive
end;

{ ---------- a reference that lives only in one callee-saved register ----------
  HoldIn*(Masked) puts "not Masked" (the object) into one register, calls GcCollect and returns the register, masked
  again. Outside the register the object is only in its masked form, which the scan does not see. }

{$if defined(cpux86_64)}
function HoldInA(Masked: PtrUInt): PtrUInt; assembler; nostackframe;
asm
  pushq %r15
  movq %rdi, %r15
  notq %r15
  call GcCollect
  movq %r15, %rax
  notq %rax
  popq %r15
end;

function HoldInB(Masked: PtrUInt): PtrUInt; assembler; nostackframe;
asm
  pushq %rbx
  movq %rdi, %rbx
  notq %rbx
  call GcCollect
  movq %rbx, %rax
  notq %rax
  popq %rbx
end;
{$elseif defined(cpui386)}
function HoldInA(Masked: PtrUInt): PtrUInt; assembler; nostackframe;
asm
  pushl %edi
  movl %eax, %edi
  notl %edi
  call GcCollect
  movl %edi, %eax
  notl %eax
  popl %edi
end;

function HoldInB(Masked: PtrUInt): PtrUInt; assembler; nostackframe;
asm
  pushl %ebx
  movl %eax, %ebx
  notl %ebx
  call GcCollect
  movl %ebx, %eax
  notl %eax
  popl %ebx
end;
{$elseif defined(cpuaarch64)}
function HoldInA(Masked: PtrUInt): PtrUInt; assembler; nostackframe;
asm
  stp x28, x30, [sp, #-16]!
  mvn x28, x0
  bl GcCollect
  mvn x0, x28
  ldp x28, x30, [sp], #16
end;

function HoldInB(Masked: PtrUInt): PtrUInt; assembler; nostackframe;
asm
  stp x19, x30, [sp, #-16]!
  mvn x19, x0
  bl GcCollect
  mvn x0, x19
  ldp x19, x30, [sp], #16
end;
{$endif}

function MakeMasked: PtrUInt;
var
  N: TNode;
begin
  N := TNode.Create;
  N.X := 77;
  Result := not PtrUInt(N);
end;

function Live(P: Pointer): Boolean;
var
  I: SizeInt;
begin
  for I := 0 to HeapCount - 1 do
    if Heap[I] = P then
      Exit(True);
  Result := False;
end;

{ ---------- the scenarios ---------- }

{ Overwrites the stack below the caller, so the old frames keep no stale references. }
procedure ClearStack;
var
  Junk: array[0..8191] of PtrUInt;
begin
  FillChar(Junk, SizeOf(Junk), 0);
  if Junk[100] <> 0 then WriteLn('?');
end;

procedure MakeGarbage(N: Integer);
var
  I: Integer;
  A, B: TNode;
begin
  for I := 1 to N do
  begin
    A := TNode.Create;
    B := TNode.Create;
    A.Next := B; B.Next := A;            // a cycle of 2
    A.Name := 'garbage ' + IntToStr(I);  // a managed field: CleanupInstance frees it
  end;
end;

function MakeRing(N: Integer): TNode;
var
  I: Integer;
  First, Cur: TNode;
begin
  First := TNode.Create;
  Cur := First;
  for I := 2 to N do
  begin
    Cur.Next := TNode.Create;
    Cur := Cur.Next;
    Cur.X := I;
  end;
  Cur.Next := First;
  Result := First;
end;

function RingLength(R: TNode): Integer;
var
  C: TNode;
begin
  Result := 1;
  C := R.Next;
  while C <> R do
  begin
    Inc(Result);
    C := C.Next;
  end;
end;

{ A reference held only in a local (under -O2 in a register) across the collection. }
function LocalSurvives: Boolean;
var
  N: TNode;
  I: Integer;
begin
  N := TNode.Create;
  N.X := 42;
  N.Child := TNode.Create;
  N.Child.X := 43;
  for I := 1 to 3 do
  begin
    ClearStack;
    GcCollect;
  end;
  Result := (N.X = 42) and (N.Child.X = 43) and Live(Pointer(N)) and Live(Pointer(N.Child));
end;

{ The ring is made, checked and dropped here: stale copies of its address stay in this frame, below the caller. }
function KeepRing: Boolean;
var
  R: TNode;
begin
  R := MakeRing(1000);
  ClearStack;
  GcCollect;
  Result := RingLength(R) = 1000;
end;

procedure Scenarios(const Where: String);
var
  Freed, Before: SizeInt;
  M: PtrUInt;
begin
  M := MakeMasked;
  ClearStack;
  GcCollect;
  Check(not Live(Pointer(not M)), Where + ': control: an object held only in masked form is collected');

  M := MakeMasked;
  ClearStack;
  M := HoldInA(M);
  Check(Live(Pointer(not M)) and (TNode(not M).X = 77), Where + ': an object only in register A survives');
  M := MakeMasked;
  ClearStack;
  M := HoldInB(M);
  Check(Live(Pointer(not M)) and (TNode(not M).X = 77), Where + ': an object only in register B survives');

  Check(LocalSurvives, Where + ': an object referenced only by a local survives (and its child)');

  ClearStack;
  GcCollect;                 // what LocalSurvives left is garbage now
  Before := HeapCount;
  MakeGarbage(500);
  ClearStack;
  Freed := GcCollect;
  Check((Freed >= 1000) and (HeapCount <= Before),
    Where + ': 500 cycles of 2 without references are collected (freed ' + IntToStr(Freed) + ' of 1000)');

  Check(KeepRing, Where + ': a ring of 1000 reachable from a local is kept');
  ClearStack;
  Freed := GcCollect;
  Check(Freed = 1000, Where + ': the ring of 1000 is collected once unreferenced (freed ' + IntToStr(Freed) + ')');
end;

function ThreadMain(P: Pointer): PtrInt;
begin
  Scenarios('goroutine');
  Flush(Output);
  Result := 0;
end;

var
  T: TThreadID;
begin
  Scenarios('main');
  Flush(Output);
  T := BeginThread(@ThreadMain, nil);
  WaitForThreadTerminate(T, 0);
  CloseThread(T);
  if Failures > 0 then
    Halt(1);
end.
