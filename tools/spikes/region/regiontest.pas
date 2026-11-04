{ SPDX-License-Identifier: MIT }
{ Spike 2 of unxed/bp#108: the checks of the region prototype (tools/spikes/region/region.pas).
  Prints ok/FAIL lines, exits with 1 on a failure. Run by tools/spikes/region/run.sh. }
{$mode objfpc}{$H+}{$modeswitch autoderef}
program regiontest;

uses
  BPThreads, SysUtils, Region;

type
  TNode = class(TRegionObject)
    X: Integer;
    Next: TNode;
  end;

  TNamed = class(TRegionObject)
    Name: String;
  end;

  TPt = record
    X, Y: Integer;
  end;

  TRow = record
    Key: String;
    N: Integer;
  end;

  TPts = specialize TGrowArray<TPt>;
  TRows = specialize TGrowArray<TRow>;
  TNodes = specialize TGrowArray<TNode>;

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

function HeapUsed: PtrUInt;
begin
  Result := GetFPCHeapStatus.CurrHeapUsed;
end;

{ ---------- the region variable: one release, at the end of the scope ---------- }

procedure ScopeRelease;
var
  R: TRegion;
  N: TNode;
begin
  R := TRegion.Create;
  N := TNode.Create;
  N.X := 1;
end;

{ ---------- objects ---------- }

procedure Objects;
var
  R: TRegion;
  A, B: TNode;
begin
  R := TRegion.Create;
  A := TNode.Create;
  B := TNode.Create;
  A.Next := B;
  A.Next.X := 5;
  Check(PtrUInt(B) - PtrUInt(A) = (PtrUInt(TNode.InstanceSize) + 15) and not PtrUInt(15),
    'objects of a region lie one after another (' + IntToStr(PtrUInt(B) - PtrUInt(A)) + ' bytes apart)');
  Check(B.X = 5, 'N.Next.X := 5 through ordinary class references');
  A.Free;                         // Free of a region object releases nothing
  Check(A.Next = B, 'Free of a region object leaves it in place until the region goes');
end;

{ ---------- strings ---------- }

procedure Strings;
var
  R: TRegion;
  S: String;
  N: TNamed;
  Rows: TRows;
  Row: TRow;
  I: Integer;
begin
  S := 'key ' + IntToStr(Random(1000));
  R := TRegion.Create;
  N := TNamed.Create;
  N.Name := S;
  Rows := TRows.Create;
  for I := 1 to 100 do
  begin
    Row.Key := S;
    Row.N := I;
    Rows.Push(Row);
  end;
  Row.Key := '';
  Check(StringRefCount(S) = 102, 'the string is held by the object and by 100 elements (refcount ' +
    IntToStr(StringRefCount(S)) + ')');
  R.Release;
  Check(StringRefCount(S) = 1, 'Release finalizes the strings of objects and elements (refcount ' +
    IntToStr(StringRefCount(S)) + ')');
end;

{ ---------- TGrowArray ---------- }

procedure Grow;
var
  R: TRegion;
  A: TPts;
  P: TPt;
  First: Pointer;
  I: Integer;
  Ok: Boolean;
begin
  R := TRegion.Create;
  A := TPts.Create;
  P.X := 0; P.Y := 0;
  A.Push(P);
  First := A.At(0);
  for I := 1 to 1000000 - 1 do
  begin
    P.X := I; P.Y := -I;
    A.Push(P);
  end;
  Check(Pointer(A.At(0)) = First, 'the address of an element does not change over 10^6 Push');
  A.At(500000).X := 42;                       // in place, through autoderef
  Check(A[500000].X = 42, 'A.At(I).X := 42 in place, read back by value as A[I].X');
  Ok := True;
  for I := 0 to A.Len - 1 do
    if (I <> 500000) and (A.At(I).X <> I) then
      Ok := False;
  Check(Ok and (A.Len = 1000000), 'all 10^6 elements are where they were put');
  Check(R.Used < 3 * 1000000 * SizeOf(TPt), 'memory of the region for 10^6 elements: ' + IntToStr(R.Used div 1024) +
    ' KiB');
end;

procedure NodesInArray;
var
  R: TRegion;
  A: TNodes;
begin
  R := TRegion.Create;
  A := TNodes.Create;
  A.Push(TNode.Create);
  A[0].X := 7;                                 // a class reference: no autoderef needed
  Check(A[0].X = 7, 'an array of region objects: A[I].X := 7');
end;

{ ---------- the current region, nesting, R14, R15 ---------- }

function MakeNode(V: Integer): TNode;     // no region here: the result lives in the caller's region
begin
  Result := TNode.Create;
  Result.X := V;
end;

procedure Inner(out Depth: Integer);
var
  R2: TRegion;
begin
  R2 := TRegion.Create;
  Depth := CurrentRegionDepth;
end;

procedure Nesting;
var
  R1: TRegion;
  N: TNode;
  D: Integer;
begin
  R1 := TRegion.Create;
  N := MakeNode(9);
  Check(N.X = 9, 'a routine without a region allocates its result in the caller''s region');
  Inner(D);
  Check((D = 2) and (CurrentRegionDepth = 1), 'regions nest: depth 2 inside, 1 after the inner scope');
end;

procedure R14;
var
  R1, R2: TRegion;
  Raised: Boolean;
begin
  R1 := TRegion.Create;
  R2 := TRegion.Create;
  Raised := False;
  try
    R1.Release;
  except
    on E: ERegion do Raised := Pos('R14', E.Message) > 0;
  end;
  Check(Raised, 'R14: Release of a region that is not the innermost one');
  R2.Release;
  R1.Release;
end;

procedure R15;
var
  Raised: Boolean;
begin
  Raised := False;
  try
    TNode.Create;
  except
    on E: ERegion do Raised := Pos('R15', E.Message) > 0;
  end;
  Check(Raised and (CurrentRegionDepth = 0), 'R15: an allocation with no current region');
end;

procedure ResetLoop;
var
  R: TRegion;
  I, J: Integer;
  N: TNode;
  Peak: SizeUInt;
begin
  R := TRegion.Create;
  Peak := 0;
  for I := 1 to 100 do
  begin
    for J := 1 to 1000 do
    begin
      N := TNode.Create;
      N.X := J;
    end;
    if R.Used > Peak then
      Peak := R.Used;
    R.Reset;
  end;
  Check(Peak < 256 * 1024, 'Reset in a loop: the region stays small (peak ' + IntToStr(Peak div 1024) + ' KiB)');
end;

{ ---------- a goroutine has regions of its own ---------- }

var
  ThreadOk: Boolean;

function ThreadMain(P: Pointer): PtrInt;
var
  R: TRegion;
  N: TNode;
  NoneAtStart: Boolean;
begin
  NoneAtStart := CurrentRegionDepth = 0;
  R := TRegion.Create;
  N := TNode.Create;
  N.X := 3;
  ThreadOk := NoneAtStart and (CurrentRegionDepth = 1) and (N.X = 3);
  Result := 0;
end;

procedure Goroutine;
var
  R: TRegion;
  T: TThreadID;
begin
  R := TRegion.Create;
  T := BeginThread(@ThreadMain, nil);
  WaitForThreadTerminate(T, 0);
  CloseThread(T);
  Check(ThreadOk and (CurrentRegionDepth = 1), 'a goroutine starts with no region and has its own stack of regions');
end;

{ ---------- the cost of At against a dynamic array (a report, no threshold) ---------- }

procedure Speed;
const
  N = 1000000;
  Rounds = 20;
var
  R: TRegion;
  A: TPts;
  D: array of TPt;
  P: TPt;
  I, K: Integer;
  S: Int64;
  T0, T1, T2, T3, T4: QWord;
  Q: TPts.PT;
  C: TPts.TChunk;
begin
  R := TRegion.Create;
  A := TPts.Create;
  SetLength(D, N);
  for I := 0 to N - 1 do
  begin
    P.X := I; P.Y := 0;
    A.Push(P);
    D[I] := P;
  end;
  S := 0;
  T0 := GetTickCount64;
  for K := 1 to Rounds do
    for I := 0 to N - 1 do
      Inc(S, D[I].X);
  T1 := GetTickCount64;
  for K := 1 to Rounds do
    for I := 0 to N - 1 do
      Inc(S, A.At(I).X);
  T2 := GetTickCount64;
  for K := 1 to Rounds do
    for Q in A do
      Inc(S, Q^.X);
  T3 := GetTickCount64;
  for K := 1 to Rounds do
    for C in A.Chunks do
      for I := 0 to C.Count - 1 do
        Inc(S, C.Data[I].X);
  T4 := GetTickCount64;
  Check(S = 4 * Int64(Rounds) * (Int64(N) * (N - 1) div 2), 'for P in A reads every element once, in order');
  WriteLn('info 2*10^7 reads: dynamic array ', T1 - T0, ' ms, TGrowArray.At ', T2 - T1, ' ms, for P in A ', T3 - T2,
    ' ms, for C in A.Chunks ', T4 - T3, ' ms');
end;

var
  H0: PtrUInt;
begin
  RegionReleases := 0;
  ScopeRelease;
  Check((RegionReleases = 1) and (RegionCopies = 0) and (CurrentRegionDepth = 0),
    'R := TRegion.Create: released once, at the end of the scope, never copied (releases ' + IntToStr(RegionReleases) +
    ', copies ' + IntToStr(RegionCopies) + ')');
  H0 := HeapUsed;          // after the first output: the RTL allocates once on it
  Objects;
  Strings;
  Grow;
  NodesInArray;
  Nesting;
  R14;
  R15;
  ResetLoop;
  Goroutine;
  Speed;
  Check(HeapUsed <= H0, 'nothing leaks: the heap is not above where it was (' + IntToStr(HeapUsed) + ' against ' + IntToStr(H0) + ')');
  if Failures > 0 then
    Halt(1);
end.
