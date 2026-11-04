{ SPDX-License-Identifier: MIT }
// UNSAFE-UNIT: a test of a runtime prototype: goroutine arguments and regions are raw pointers.
{ Spike 4 of unxed/bp#108: the checks and the measurements of the M:N prototype (tools/spikes/mn/mn.pas).
  Every test starts a carrier (one thread of BPThreads), starts goroutines on it with MnGo and runs them with MnRun;
  the goroutines talk over TChan of ext/go. Prints ok/FAIL and info lines, exits with 1 on a failure.
  `mntest overflow`: a goroutine recurses without end; run.sh expects the process to stop (the guard area).
  Run by tools/spikes/mn/run.sh. }
{$mode objfpc}{$H+}
program mntest;

uses
  BPThreads, Mn, SysUtils, UnixType, Linux, BP;

type
  TIntChan = specialize TChan<Integer>;
  TStrChan = specialize TChan<String>;

  EMnTest = class(Exception);

  TBox = class
    N: Integer;
    S: String;
  end;
  TBoxChan = specialize TChan<TBox>;

  TSetup = procedure;

var
  Failures: Integer = 0;
  RunOk: Boolean;
  TidCarrier: LongInt;

procedure Check(const Cond: Boolean; const What: String);
begin
  if Cond then
    WriteLn('ok   ', What)
  else
  begin
    WriteLn('FAIL ', What);
    Inc(Failures);
  end;
end;

function NowNs: Int64;
var
  TS: TTimeSpec;
begin
  clock_gettime(CLOCK_MONOTONIC, @TS);
  Result := Int64(TS.tv_sec) * 1000000000 + TS.tv_nsec;
end;

{ ---------- a carrier per test ---------- }

function CarrierMain(P: System.Pointer): PtrInt;
begin
  TidCarrier := MnKernelTid;
  TSetup(P)();
  RunOk := MnRun;
  Result := 0;
end;

{ Starts a carrier, runs Setup on it (it starts goroutines), then the goroutines; True when all have finished. }
function OnCarrier(Setup: TSetup): Boolean;
var
  Id: TThreadID;
begin
  Id := BeginThread(@CarrierMain, System.Pointer(Setup));
  WaitForThreadTerminate(Id, -1);
  CloseThread(Id);
  Result := RunOk;
end;

{ ---------- /proc ---------- }

function ReadNumbers(const Name: String; const Index: Integer): Int64;
var
  F: TextFile;
  L: String;
  I, P: Integer;
begin
  Result := -1;
  AssignFile(F, Name);
  {$I-}Reset(F);{$I+}
  if IOResult <> 0 then
    Exit;
  ReadLn(F, L);
  CloseFile(F);
  L := L + ' ';
  for I := 0 to Index - 1 do
  begin
    P := Pos(' ', L);
    Delete(L, 1, P);
  end;
  Result := StrToInt64Def(Copy(L, 1, Pos(' ', L) - 1), -1);
end;

function RssBytes: Int64;
begin
  Result := ReadNumbers('/proc/self/statm', 1) * 4096;
end;

function MapCount: Integer;
var
  F: TextFile;
  L: String;
begin
  Result := 0;
  AssignFile(F, '/proc/self/maps');
  {$I-}Reset(F);{$I+}
  if IOResult <> 0 then
    Exit(-1);
  while not Eof(F) do
  begin
    ReadLn(F, L);
    Inc(Result);
  end;
  CloseFile(F);
end;

{ ---------- two goroutines exchange values; threadvars follow each one ---------- }

threadvar
  TvInt: Integer;
  TvStr: String;

var
  CA, CB: TIntChan;
  Rounds: Integer;
  SumA, SumB: Int64;
  TvOk: Boolean;
  TidA, TidB, LiveThreads: LongInt;
  IdA, IdB: TThreadID;
  GA, GB: System.Pointer;

procedure PingA(Arg: System.Pointer);
var
  I, V: Integer;
begin
  TvInt := 1;
  TvStr := 'goroutine A';
  TidA := MnKernelTid;
  IdA := ThreadID;
  GA := MnSelf;
  LiveThreads := SafeRawThreadCount;
  for I := 1 to Rounds do
  begin
    CA.Send(I);
    CB.Recv(V);
    Inc(SumA, V);
    if (TvInt <> 1) or (TvStr <> 'goroutine A') then
      TvOk := False;
  end;
  CA.Close;
end;

procedure PingB(Arg: System.Pointer);
var
  V: Integer;
begin
  TvInt := 2;
  TvStr := 'goroutine B';
  TidB := MnKernelTid;
  IdB := ThreadID;
  GB := MnSelf;
  while CA.Recv(V) do
  begin
    Inc(SumB, V);
    CB.Send(2 * V);
    if (TvInt <> 2) or (TvStr <> 'goroutine B') then
      TvOk := False;
  end;
end;

procedure SetupPing;
begin
  CA := TIntChan.Create(0);
  CB := TIntChan.Create(0);
  SumA := 0;
  SumB := 0;
  TvOk := True;
  MnGo(@PingA, nil);
  MnGo(@PingB, nil);
end;

procedure PingPong;
var
  N: Int64;
begin
  Rounds := 1000;
  Check(OnCarrier(@SetupPing), 'two goroutines on one carrier: both finish');
  N := Rounds;
  Check((SumA = N * (N + 1)) and (SumB = N * (N + 1) div 2),
    'they exchange 1000 values each way over unbuffered TChan of ext/go');
  Check((TidA = TidCarrier) and (TidB = TidCarrier) and (LiveThreads = 1),
    'one kernel thread: gettid is the carrier''s in both, BPThreads counts one thread');
  Check(TvOk, 'threadvars (an Integer and a String) keep their values in each goroutine across 4000 switches');
  Check((IdA = TThreadID(GA)) and (IdB = TThreadID(GB)) and (IdA <> IdB) and (GA <> nil),
    'ThreadID of the RTL is the region of the goroutine: two different ids');
end;

{ ---------- exceptions across switches ---------- }

var
  C1, C2, C3: TIntChan;
  LogA, LogB, LogC: String;

procedure ExcA(Arg: System.Pointer);
var
  V: Integer;
begin
  try
    try
      C1.Send(1);
      C2.Recv(V);                        // B sends this from its except block, with its exception live
      raise EMnTest.Create('A');
    finally
      LogA := LogA + 'finally;';
    end;
  except
    on E: EMnTest do
      LogA := LogA + 'caught ' + E.Message + ';';
  end;
  C3.Send(0);
end;

procedure ExcB(Arg: System.Pointer);
var
  V: Integer;
begin
  try
    try
      C1.Recv(V);
      raise EMnTest.Create('B');
    except
      on E: EMnTest do
      begin
        C2.Send(2);                      // A raises and handles its own exception now
        C3.Recv(V);
        LogB := LogB + 'handler ' + E.Message + ';';
        raise;                           // the exception of B, not the one A raised meanwhile
      end;
    end;
  except
    on E: EMnTest do
      LogB := LogB + 'outer ' + E.Message + ';';
  end;
end;

procedure ExcC(Arg: System.Pointer);
var
  C: TIntChan;
begin
  C := TIntChan.Create(1);
  C.Close;
  try
    C.Send(1);
  except
    on E: ESafety do
      LogC := 'ESafety';
  end;
  MnYield;
  raise EMnTest.Create('loose');         // not caught: MnUncaught counts it, the others go on
end;

procedure SetupExc;
begin
  C1 := TIntChan.Create(0);
  C2 := TIntChan.Create(0);
  C3 := TIntChan.Create(0);
  LogA := '';
  LogB := '';
  LogC := '';
  MnGo(@ExcA, nil);
  MnGo(@ExcB, nil);
  MnGo(@ExcC, nil);
end;

procedure Exceptions;
begin
  Check(OnCarrier(@SetupExc), 'three goroutines with exceptions: all finish');
  Check(LogA = 'finally;caught A;', 'A: finally and except run on its own stack (' + LogA + ')');
  Check(LogB = 'handler B;outer B;',
    'B: its exception lives across switches while A raises another; a re-raise gives B''s (' + LogB + ')');
  Check(LogC = 'ESafety', 'ESafety of TChan (R6) is caught inside a goroutine');
  Check((MnUncaught = 1) and (MnUncaughtMsg = 'EMnTest: loose'), 'an exception that leaves a goroutine is counted: ' +
    MnUncaughtMsg);
end;

{ ---------- the heap: allocated in one goroutine, freed in another ---------- }

const
  HeapItems = 10000;

var
  CS: TStrChan;
  CO: TBoxChan;
  HeapOk: Boolean;
  HeapUsed1, HeapUsed2: PtrUInt;

procedure Producer(Arg: System.Pointer);
var
  I, Round: Integer;
  B: TBox;
begin
  for Round := 1 to 2 do
  begin
    for I := 1 to HeapItems do
    begin
      CS.Send(IntToStr(I) + StringOfChar('x', I mod 100));
      B := TBox.Create;
      B.N := I;
      B.S := 'box ' + IntToStr(I);
      CO.Send(B);
    end;
    if Round = 1 then
      HeapUsed1 := GetFPCHeapStatus.CurrHeapUsed
    else
      HeapUsed2 := GetFPCHeapStatus.CurrHeapUsed;
  end;
  CS.Close;
  CO.Close;
end;

procedure Consumer(Arg: System.Pointer);
var
  S: String;
  B: TBox;
  I: Integer;
  A: array of Integer;
begin
  I := 0;
  A := nil;
  while CS.Recv(S) do
  begin
    I := I mod HeapItems + 1;
    if S <> IntToStr(I) + StringOfChar('x', I mod 100) then
      HeapOk := False;
    if not CO.Recv(B) then
      HeapOk := False
    else
    begin
      if (B.N <> I) or (B.S <> 'box ' + IntToStr(I)) then
        HeapOk := False;
      B.Destroy; // UNSAFE: a test of the heap: the object of the producer is freed here
    end;
    if I mod 1000 = 0 then
    begin
      SetLength(A, Length(A) + 1);       // the consumer's own heap grows while it frees the producer's blocks
      A[High(A)] := I;
    end;
  end;
  if Length(A) <> 2 * HeapItems div 1000 then
    HeapOk := False;
end;

procedure SetupHeap;
begin
  CS := TStrChan.Create(16);
  CO := TBoxChan.Create(16);
  HeapOk := True;
  MnGo(@Producer, nil);
  MnGo(@Consumer, nil);
end;

procedure Heap;
begin
  Check(OnCarrier(@SetupHeap), 'producer and consumer finish');
  Check(HeapOk, '2 x 10^4 strings and objects made in one goroutine are read and freed in another');
  Check(HeapUsed2 <= HeapUsed1 + 64 * 1024, 'the producer''s heap does not grow over the second round: the frees of the '
    + 'consumer come back to it (' + IntToStr(HeapUsed1) + ', then ' + IntToStr(HeapUsed2) + ' bytes)');
end;

{ ---------- the cost of a switch ---------- }

const
  Yields = 100000;

var
  TYield, TPing: Int64;
  SwYield, SwPing: Int64;

procedure Yielder(Arg: System.Pointer);
var
  I: Integer;
begin
  for I := 1 to Yields do
    MnYield;
end;

procedure SetupYield;
begin
  MnGo(@Yielder, nil);
  MnGo(@Yielder, nil);
end;

procedure TimedYield;
var
  T0, S0: Int64;
begin
  S0 := MnSwitches;
  T0 := NowNs;
  Check(OnCarrier(@SetupYield), 'two goroutines yield to each other 10^5 times each');
  TYield := NowNs - T0;
  SwYield := MnSwitches - S0;
end;

function OsPingA(P: System.Pointer): PtrInt;
begin
  PingA(nil);
  Result := 0;
end;

function OsPingB(P: System.Pointer): PtrInt;
begin
  PingB(nil);
  Result := 0;
end;

procedure Speed;
var
  T0, S0, TOs: Int64;
  A, B: TThreadID;
  PerSwitch, PerTrip, PerOsTrip: Double;
begin
  TimedYield;
  PerSwitch := TYield / SwYield;
  Rounds := 20000;
  S0 := MnSwitches;
  T0 := NowNs;
  Check(OnCarrier(@SetupPing), '2 x 10^4 round trips over unbuffered channels, M:N');
  TPing := NowNs - T0;
  SwPing := MnSwitches - S0;
  PerTrip := TPing / Rounds;
  // the same exchange between two threads of BPThreads (1:1, futex)
  Rounds := 2000;
  CA := TIntChan.Create(0);
  CB := TIntChan.Create(0);
  SumA := 0;
  SumB := 0;
  T0 := NowNs;
  A := BeginThread(@OsPingA, nil);
  B := BeginThread(@OsPingB, nil);
  WaitForThreadTerminate(A, -1);
  WaitForThreadTerminate(B, -1);
  TOs := NowNs - T0;
  CloseThread(A);
  CloseThread(B);
  Check(SumA = Int64(Rounds) * (Rounds + 1), 'the same exchange between two OS threads (1:1) still works under the hooks');
  PerOsTrip := TOs / Rounds;
  WriteLn('info a switch (an MnYield is two: to the carrier and on): ', PerSwitch:0:1, ' ns (', SwYield,
    ' switches in ', TYield div 1000000, ' ms, with the starts of the goroutines)');
  WriteLn('info a round trip over two unbuffered TChan: M:N ', PerTrip / 1000:0:2, ' us (', SwPing div 20000,
    ' switches), 1:1 ', PerOsTrip / 1000:0:2, ' us: ', PerOsTrip / PerTrip:0:1, ' times faster on one carrier');
end;

{ ---------- the memory of a goroutine ---------- }

var
  Gate: TIntChan;
  Parked: Integer;
  GFirst: System.Pointer;
  Rss0, Rss1: Int64;
  Maps0, Maps1: Integer;
  T0Mem, TGo, TParked, TDone: Int64;
  StackUse: PtrUInt;

procedure Sleeper(Arg: System.Pointer);
var
  V: Integer;
begin
  if GFirst = nil then
    GFirst := MnSelf;
  Gate.Recv(V);                          // parks until the gate closes
end;

procedure Meter(Arg: System.Pointer);
begin
  TParked := NowNs;
  Parked := MnParked;
  Rss1 := RssBytes;
  Maps1 := MapCount;
  StackUse := MnStackInUse(GFirst);
  Gate.Close;
end;

var
  MemCount: Integer;

procedure SetupMem;
var
  I: Integer;
begin
  Gate := TIntChan.Create(0);
  GFirst := nil;
  Rss0 := RssBytes;
  Maps0 := MapCount;
  T0Mem := NowNs;
  for I := 1 to MemCount do
    MnGo(@Sleeper, nil);
  TGo := NowNs;
  MnGo(@Meter, nil);
end;

{ HeapChunk: the first chunk of the heap of a thread for small blocks (growheapsizesmall of the RTL, 32 KiB by default;
  the RTL cuts it into blocks at once, so all of it is touched). }
procedure Memory(const HeapChunk: PtrUInt);
var
  PerG, PerGiB, MaxMaps, MapsPerG: Double;
  Cap: Int64;
  Saved: PtrUInt;
begin
  {$ifdef cpu64}
  MemCount := 500;
  {$else}
  MemCount := 200;
  {$endif}
  Saved := growheapsizesmall;
  growheapsizesmall := HeapChunk;        // a goroutine copies it in InitThread
  Check(OnCarrier(@SetupMem), IntToStr(MemCount) + ' goroutines park on one channel and finish when it closes (first ' +
    'heap chunk ' + IntToStr(HeapChunk div 1024) + ' KiB)');
  TDone := NowNs;
  growheapsizesmall := Saved;
  Check(Parked = MemCount, 'all of them were parked at once (' + IntToStr(Parked) + ')');
  PerG := (Rss1 - Rss0) / MemCount;
  PerGiB := 1073741824.0 / PerG;
  MapsPerG := (Maps1 - Maps0) / MemCount;
  WriteLn('info a parked goroutine, first heap chunk ', HeapChunk div 1024, ' KiB: ', PerG / 1024:0:1,
    ' KiB of memory (the record and the threadvars ', MnCtlSize div 1024, ' KiB, of them threadvars ',
    MnThreadVarSize, ' bytes; stack in use ', StackUse, ' bytes); ', PerGiB:0:0, ' goroutines per GiB');
  if HeapChunk <> Saved then
    Exit;
  WriteLn('info a region (the stack of one goroutine): ', MnRegionSize div 1024, ' KiB of addresses; guard area: ',
    BoolToStr(MnGuard, 'yes', 'no (-Ct)'), '; mappings per goroutine: ', MapsPerG:0:2);
  MaxMaps := ReadNumbers('/proc/sys/vm/max_map_count', 0);
  if MapsPerG > 0.5 then
    Cap := Round((MaxMaps - Maps0) / MapsPerG)
  else
    Cap := -1;
  if Cap > 0 then
    WriteLn('info vm.max_map_count ', MaxMaps:0:0, ': at most about ', Cap, ' goroutines (65530 by default: ',
      Round((65530 - Maps0) / MapsPerG), ')')
  else
    WriteLn('info vm.max_map_count ', MaxMaps:0:0, ': no limit from mappings');
  {$ifndef cpu64}
  WriteLn('info the 32-bit address space: at most about ', (3 * 1024) div (MnRegionSize div (1024 * 1024)),
    ' regions of ', MnRegionSize div 1024, ' KiB');
  {$endif}
  WriteLn('info the start of a goroutine on a new region: MnGo ', (TGo - T0Mem) / MemCount / 1000:0:2,
    ' us, to parked ', (TParked - T0Mem) / MemCount / 1000:0:2, ' us; to the end of all: ', (TDone - T0Mem) div 1000000,
    ' ms');
end;

{ The start and the end of short goroutines on regions that are reused. }

var
  Churned: Integer;

procedure Short(Arg: System.Pointer);
begin
  Inc(Churned);
end;

procedure SetupChurn;
var
  I: Integer;
begin
  for I := 1 to MemCount do
    MnGo(@Short, nil);
end;

procedure Churn;
var
  T0: Int64;
begin
  Churned := 0;
  T0 := NowNs;
  Check(OnCarrier(@SetupChurn) and (Churned = MemCount), IntToStr(MemCount) + ' short goroutines on reused regions');
  WriteLn('info the start and the end of a goroutine on a reused region: ', (NowNs - T0) / MemCount / 1000:0:2,
    ' us (with the start of the carrier)');
end;

{ ---------- the stack check (-Ct) without a guard ---------- }

var
  Depth: Integer;
  OverflowLog: String;

function Deep(const N: Integer): Integer;
var
  Pad: array[0..255] of Integer;
begin
  Depth := N;
  Pad[N and 255] := N;
  Result := Deep(N + 1) + Pad[(N + 1) and 255];
end;

{$ifopt S+}
procedure Overflower(Arg: System.Pointer);
begin
  try
    Deep(0);
  except
    on E: EStackOverflow do
      OverflowLog := 'EStackOverflow at depth ' + IntToStr(Depth);
  end;
end;

procedure Survivor(Arg: System.Pointer);
var
  V: Integer;
begin
  CA.Recv(V);
  OverflowLog := OverflowLog + '; next ' + IntToStr(V);
end;

procedure Sender(Arg: System.Pointer);
begin
  CA.Send(7);
end;

procedure SetupOverflow;
begin
  CA := TIntChan.Create(0);
  OverflowLog := '';
  MnGo(@Overflower, nil, 256 * 1024);
  MnGo(@Survivor, nil);
  MnGo(@Sender, nil);
end;

procedure StackCheck;
begin
  Check(OnCarrier(@SetupOverflow), 'a goroutine overflows its stack of 256 KiB, the others go on');
  Check(Pos('EStackOverflow at depth', OverflowLog) = 1, '-Ct, no guard: the overflow is EStackOverflow (' +
    OverflowLog + ')');
  Check(Pos('; next 7', OverflowLog) > 0, 'the goroutines after it still exchange values');
  Check(StackError, 'StackError of the RTL is one global: after one overflow the check is off in every thread');
  StackError := False;
end;
{$endif}

{ ---------- an overflow into the guard area: the process stops (run by run.sh) ---------- }

procedure Endless(Arg: System.Pointer);
begin
  Deep(0);
end;

procedure SetupEndless;
begin
  MnGo(@Endless, nil);
end;

{ ---------- deadlock: every goroutine parked ---------- }

var
  Never: TIntChan;

procedure Waiter(Arg: System.Pointer);
var
  V: Integer;
begin
  Never.Recv(V);
end;

procedure SetupDeadlock;
begin
  Never := TIntChan.Create(0);
  MnGo(@Waiter, nil);
  MnGo(@Waiter, nil);
end;

procedure Deadlock;
begin
  Check(not OnCarrier(@SetupDeadlock) and (MnLive = 2) and (MnParked = 2),
    'all goroutines asleep: MnRun returns False with the two parked ones (deadlock detection)');
end;

begin
  if ParamStr(1) = 'overflow' then
  begin
    OnCarrier(@SetupEndless);
    WriteLn('FAIL the overflow did not stop the process (depth ', Depth, ')');
    Halt(1);
  end;
  PingPong;
  Exceptions;
  Heap;
  {$ifopt S+}StackCheck;{$endif}
  Speed;
  Memory(growheapsizesmall);
  Memory(4096);
  Churn;
  Deadlock;                              // last: its two goroutines stay parked
  if Failures > 0 then
    Halt(1);
end.
