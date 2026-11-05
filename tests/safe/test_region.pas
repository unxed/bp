{ Runtime tests of the region style (safe/region.*.inc, SPEC §20): TRegion, Scope, Each, TRegionObject, TGrowArray<T>,
  R2, R12 (SAFE_DEBUG on unix only), R14, R15, R16. Exit code = number of failed checks. }
// UNSAFE-UNIT: the checks break R2, R12, R14, R15 and R16 on purpose, and only the typed mode of bpvet knows that a region owns its objects (S6)
program test_region;

{$mode objfpc}{$H+}{$modeswitch autoderef}

uses
  SysUtils, Safe;

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
  TNodeBox = specialize TOwned<TNode>;
  TNodeRef = specialize TShared<TNode>;

var
  Failed: Integer = 0;

procedure Check(const Cond: Boolean; const What: String);
begin
  if Cond then
    WriteLn('ok   ', What)
  else
  begin
    WriteLn('FAIL ', What);
    Inc(Failed);
  end;
end;

function HeapUsed: PtrUInt;
begin
  Result := GetFPCHeapStatus.CurrHeapUsed;
end;

{ ---------- a region variable: released once, at the end of its scope ---------- }

procedure MakeAndLeave;
var
  R: TRegion;
  N: TNode;
begin
  R := TRegion.Create;
  N := TNode.Create;
  N.X := 1;
end;

procedure ScopeExit;
var
  H: PtrUInt;
begin
  MakeAndLeave;
  H := HeapUsed;
  MakeAndLeave;
  Check((CurrentRegionDepth = 0) and (HeapUsed <= H), 'R := TRegion.Create: released when the routine returns');
end;

function UsedOf(var R: TRegion): SizeUInt;
begin
  Result := R.Used;
end;

procedure ByReference;
var
  R: TRegion;
  N: TNode;
begin
  // a variable passed by reference: FPC builds the result of Create in a temporary and copies it (a move)
  R := TRegion.Create;
  N := TNode.Create;
  N.X := 1;
  Check((UsedOf(R) > 0) and (CurrentRegionDepth = 1), 'a TRegion passed by reference: Create moves into it');
  R := TRegion.Create;
  Check((UsedOf(R) = 0) and (CurrentRegionDepth = 1), 'a TRegion passed by reference: Create again replaces it');
end;

procedure Reassign;
var
  R: TRegion;
  N: TNode;
begin
  R := TRegion.Create;
  N := TNode.Create;
  N.X := 1;
  R := TRegion.Create;
  Check((R.Used = 0) and (CurrentRegionDepth = 1), 'R := TRegion.Create again releases the region R held');
end;

procedure CopyRaises;
var
  R, R2: TRegion;
  N: TNode;
  Msg: String;
begin
  R := TRegion.Create;
  N := TNode.Create;
  N.X := 1;
  Msg := '';
  try
    R2 := R;
  except
    on E: ESafety do Msg := E.Message;
  end;
  Check((Pos('copied', Msg) > 0) and (R2.Used = 0), 'a copy of a TRegion raises ESafety: a region has one owner');
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
  Check(B.X = 5, 'region objects: N.Next.X := 5 through ordinary class references');
  Check(R.Used > 0, 'region objects: the region holds them (' + IntToStr(R.Used) + ' bytes)');
end;

{ ---------- strings and other managed fields ---------- }

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
  Check(StringRefCount(S) = 102, 'strings: held by the object and by 100 elements (refcount ' +
    IntToStr(StringRefCount(S)) + ')');
  R.Release;
  Check(StringRefCount(S) = 1, 'strings: Release finalizes the objects and the elements (refcount ' +
    IntToStr(StringRefCount(S)) + ')');
end;

procedure StringsReset;
var
  R: TRegion;
  S: String;
  N: TNamed;
  I: Integer;
begin
  S := 'kept ' + IntToStr(Random(1000));
  R := TRegion.Create;
  for I := 1 to 50 do
  begin
    N := TNamed.Create;
    N.Name := S;
    R.Reset;
  end;
  Check(StringRefCount(S) = 1, 'strings: Reset finalizes what the region held (refcount ' + IntToStr(StringRefCount(S))
    + ')');
end;

{ ---------- TGrowArray ---------- }

procedure Grow;
const
  N = 1000000;
var
  R: TRegion;
  A: TPts;
  P: TPt;
  First: PtrUInt;
  I: Integer;
  Ok: Boolean;
begin
  R := TRegion.Create;
  A := TPts.Create;
  P.X := 0;
  P.Y := 0;
  A.Push(P);
  // UNSAFE: the address of the first element, only compared below
  First := PtrUInt(A.At(0));
  for I := 1 to N - 1 do
  begin
    P.X := I;
    P.Y := -I;
    A.Push(P);
  end;
  // UNSAFE: the address of the first element, only compared
  Check(PtrUInt(A.At(0)) = First, 'grow: the address of an element does not change over 10^6 Push');
  A.At(500000).X := 42;
  Check(A[500000].X = 42, 'grow: A.At(I).X := 42 in place, read back by value as A[I].X');
  Ok := True;
  for I := 0 to A.Len - 1 do
    if (I <> 500000) and (A.At(I).X <> I) then
      Ok := False;
  Check(Ok and (A.Len = N), 'grow: all 10^6 elements are where they were put');
  Check(R.Used < 3 * N * SizeOf(TPt), 'grow: the region for 10^6 elements: ' + IntToStr(R.Used div 1024) + ' KiB');
end;

procedure NodesInArray;
var
  R: TRegion;
  A: TNodes;
begin
  R := TRegion.Create;
  A := TNodes.Create;
  A.Push(TNode.Create);
  A[0].X := 7;
  Check(A[0].X = 7, 'an array of region objects: A[I].X := 7');
end;

procedure Enumerate;
var
  R: TRegion;
  A: TPts;
  P: TPt;
  Q: TPts.PT;
  C: TPts.TChunk;
  I, K: Integer;
  S, S2: Int64;
  Count: Integer;
begin
  R := TRegion.Create;
  A := TPts.Create;
  S := 0;
  for I := 0 to 99999 do
  begin
    P.X := I;
    P.Y := 0;
    A.Push(P);
    Inc(S, I);
  end;
  S2 := 0;
  Count := 0;
  for Q in A do
  begin
    Inc(S2, Q.X);
    Inc(Count);
  end;
  Check((S2 = S) and (Count = A.Len), 'for P in A: every element once (' + IntToStr(Count) + ')');
  for Q in A do
    Q.Y := Q.X;
  Check(A[99999].Y = 99999, 'for P in A: P.Y := P.X writes in place');
  S2 := 0;
  K := 0;
  for C in A.Chunks do
  begin
    for I := 0 to C.Count - 1 do
      Inc(S2, C.Data[I].X);
    Inc(K, C.Count);
  end;
  Check((S2 = S) and (K = A.Len), 'for C in A.Chunks: every element once, a plain loop per chunk');
end;

procedure ExplicitRegion;
var
  Outer: TRegion;
  A: TPts;
  P: TPt;
  I, R: Integer;
  Ok: Boolean;
begin
  Outer := TRegion.Create;
  A := TPts.Create(Outer);
  for R in Scope do
  begin
    // the inner region is the current one: the chunks still go into the region of the header
    for I := 0 to 999 do
    begin
      P.X := I;
      P.Y := 0;
      A.Push(P);
    end;
  end;
  Ok := A.Len = 1000;
  for I := 0 to A.Len - 1 do
    if A[I].X <> I then
      Ok := False;
  Check(Ok and (CurrentRegionDepth = 1), 'TGrowArray.Create(R): chunks pushed under an inner region live in R');
end;

procedure R2;
var
  R: TRegion;
  A: TPts;
  P: TPt;
  Msg: String;
  Bad: SizeInt;
begin
  R := TRegion.Create;
  A := TPts.Create;
  P := Default(TPt);
  A.Push(P);
  Msg := '';
  try
    P := A[1];
  except
    on E: ESafety do Msg := E.Message;
  end;
  Check(Pos('SAFE-R2', Msg) > 0, 'R2: A[Len] raises ESafety (' + Msg + ')');
  Msg := '';
  Bad := -1;
  try
    A.At(Bad).X := 1;
  except
    on E: ESafety do Msg := E.Message;
  end;
  Check(Pos('SAFE-R2', Msg) > 0, 'R2: A.At(-1) raises ESafety');
end;

{ ---------- the current region, nesting ---------- }

function MakeNode(const V: Integer): TNode;     // no region here: the result lives in the caller's region
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
  Before: SizeUInt;
begin
  R1 := TRegion.Create;
  Before := R1.Used;
  N := MakeNode(9);
  Check((N.X = 9) and (R1.Used >= Before), 'a routine without a region allocates its result in the caller''s region');
  Inner(D);
  Check((D = 2) and (CurrentRegionDepth = 1) and (N.X = 9), 'regions nest: depth 2 inside, 1 after the inner scope');
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

{ ---------- Scope and Each ---------- }

procedure InScopeRaise;
var
  R: Integer;
begin
  for R in Scope do
    raise Exception.Create('x');
end;

procedure Scopes;
var
  R, I, J, Inside: Integer;
  N: TNode;
  Raised: Boolean;
begin
  Inside := 0;
  for I := 1 to 100 do
    for R in Scope do
    begin
      for J := 1 to 1000 do
      begin
        N := TNode.Create;
        N.X := J;
      end;
      if CurrentRegionDepth > Inside then
        Inside := CurrentRegionDepth;
    end;
  Check((Inside = 1) and (CurrentRegionDepth = 0), 'for R in Scope: a region per block, released at its end');
  for R in Scope do
    for J in Scope do
      Inside := J;
  Check((Inside = 2) and (CurrentRegionDepth = 0), 'for R in Scope: blocks nest');
  Raised := False;
  try
    InScopeRaise;
  except
    on E: Exception do Raised := True;
  end;
  Check(Raised and (CurrentRegionDepth = 0), 'for R in Scope: an exception in the block releases its region');
end;

procedure Iterations;
var
  Lines, Kept: array of String;
  Line: String;
  Named: TNamed;
  Outer: TRegion;
  Pts: TPts;
  Pt: TPt;
  Q: TPts.PT;
  Count, I, J: Integer;
  N: TNode;
  H0, Peak: PtrUInt;
begin
  SetLength(Lines, 200);
  for I := 0 to High(Lines) do
    Lines[I] := IntToStr(I);
  Count := 0;
  H0 := HeapUsed;
  Peak := 0;
  for Line in Each(Lines) do
  begin
    for J := 1 to 1000 do
    begin
      N := TNode.Create;
      N.X := Length(Line);
    end;
    Inc(Count);
    if HeapUsed - H0 > Peak then
      Peak := HeapUsed - H0;
  end;
  Check((Count = 200) and (CurrentRegionDepth = 0) and (Peak < 256 * 1024), 'for Line in Each(Lines): a region per '
    + 'iteration (peak ' + IntToStr(Peak div 1024) + ' KiB over 200 rounds of 1000 objects)');
  SetLength(Kept, Length(Lines));
  Count := 0;
  for Line in Each(Lines) do
  begin
    Named := TNamed.Create;
    Named.Name := #$D1#$91 + Line + #$F0#$9F#$98#$80;  // a Cyrillic letter and an emoji in UTF-8
    Kept[Count] := Named.Name;
    Inc(Count);
  end;
  Check((Kept[0] = #$D1#$91'0'#$F0#$9F#$98#$80) and (Kept[199] = #$D1#$91'199'#$F0#$9F#$98#$80)
    and (StringRefCount(Kept[199]) = 1), 'strings leave a region as copies, intact after the reset of each iteration');
  Outer := TRegion.Create;
  Pts := TPts.Create;
  for I := 1 to 300 do
  begin
    Pt.X := I;
    Pt.Y := 0;
    Pts.Push(Pt);
  end;
  Count := 0;
  H0 := HeapUsed;
  Peak := 0;
  for Q in Pts.Each do
  begin
    for J := 1 to 1000 do
    begin
      N := TNode.Create;
      N.X := J;
    end;
    Inc(Count, Q.X);
    if HeapUsed - H0 > Peak then
      Peak := HeapUsed - H0;
  end;
  Check((Count = 300 * 301 div 2) and (CurrentRegionDepth = 1) and (Peak < 256 * 1024), 'for P in A.Each: every '
    + 'element in place, a region per iteration (peak ' + IntToStr(Peak div 1024) + ' KiB)');
end;

{ ---------- R14, R15, R16 ---------- }

procedure R14;
var
  R1, R2: TRegion;
  Msg: String;
begin
  R1 := TRegion.Create;
  R2 := TRegion.Create;
  Msg := '';
  try
    R1.Release;
  except
    on E: ESafety do Msg := E.Message;
  end;
  Check(Pos('SAFE-R14', Msg) > 0, 'R14: Release of a region that is not the innermost one raises ESafety');
  R2.Release;
  R1.Release;
  Check(CurrentRegionDepth = 0, 'R14: the regions are released in order after it');
end;

procedure R15;
var
  Msg: String;
  N: TNode;
begin
  Msg := '';
  try
    N := TNode.Create;
    N.X := 1;
  except
    on E: ESafety do Msg := E.Message;
  end;
  Check((Pos('SAFE-R15', Msg) > 0) and (CurrentRegionDepth = 0), 'R15: TFoo.Create with no current region raises '
    + 'ESafety');
  Msg := '';
  try
    TPts.Create.Push(Default(TPt));
  except
    on E: ESafety do Msg := E.Message;
  end;
  Check(Pos('SAFE-R15', Msg) > 0, 'R15: TGrowArray.Create with no current region raises ESafety');
end;

procedure R16;
var
  R: TRegion;
  N: TNode;
  Arena: TArena;
  Box: TNodeBox;
  Ref: TNodeRef;
  Live: LongInt;
  Own, Share, Adopt: String;
begin
  R := TRegion.Create;
  N := TNode.Create;
  Arena := TArena.Create;
  Live := SafeLiveCount;
  Own := '';
  Share := '';
  Adopt := '';
  try
    Box := TNodeBox.Own(N);
  except
    on E: ESafety do Own := E.Message;
  end;
  try
    Ref := TNodeRef.Share(N);
  except
    on E: ESafety do Share := E.Message;
  end;
  try
    Arena.Adopt(N);
  except
    on E: ESafety do Adopt := E.Message;
  end;
  Check((Pos('SAFE-R16', Own) > 0) and (Pos('SAFE-R16', Share) > 0) and (Pos('SAFE-R16', Adopt) > 0)
    and (SafeLiveCount = Live) and Box.IsEmpty and Ref.IsEmpty and (Arena.Count = 0),
    'R16: Own, Share and Adopt of a region object raise ESafety and own nothing');
end;

{$if defined(SAFE_DEBUG) and defined(unix)}
procedure R12;
var
  R: TRegion;
  N: TNode;
  Caught: Boolean;
begin
  R := TRegion.Create;
  N := TNode.Create;
  N.X := 1;
  R.Reset;
  Caught := False;
  try
    // UNSAFE: a use after Reset on purpose: its block has no access any more (R12)
    N.X := 2;
  except
    on E: EAccessViolation do Caught := True;
  end;
  Check(Caught, 'R12 (SAFE_DEBUG): a use after Reset stops at once with EAccessViolation');
end;
{$endif}

{ ---------- the speed of for P in A against a dynamic array (a report, no threshold) ---------- }

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
  T0, T1, T2, T3: QWord;
  Q: TPts.PT;
  C: TPts.TChunk;
begin
  R := TRegion.Create;
  A := TPts.Create;
  SetLength(D, N);
  for I := 0 to N - 1 do
  begin
    P.X := I;
    P.Y := 0;
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
    for Q in A do
      Inc(S, Q.X);
  T2 := GetTickCount64;
  for K := 1 to Rounds do
    for C in A.Chunks do
      for I := 0 to C.Count - 1 do
        Inc(S, C.Data[I].X);
  T3 := GetTickCount64;
  Check(S = 3 * Int64(Rounds) * (Int64(N) * (N - 1) div 2), 'speed: the three loops read every element');
  WriteLn('info 2*10^7 reads: dynamic array ', T1 - T0, ' ms, for P in A ', T2 - T1, ' ms, for C in A.Chunks ',
    T3 - T2, ' ms');
end;

var
  H0, H1: PtrUInt;
begin
  WriteLn('-- region');
  H0 := HeapUsed;          // after the first output: the RTL allocates once on it
  ScopeExit;
  ByReference;
  Reassign;
  CopyRaises;
  Check(CurrentRegionDepth = 0, 'every region of the checks above is released');
  Objects;
  Strings;
  StringsReset;
  Grow;
  NodesInArray;
  Enumerate;
  ExplicitRegion;
  R2;
  Nesting;
  ResetLoop;
  Scopes;
  Iterations;
  R14;
  R15;
  R16;
  {$if defined(SAFE_DEBUG) and defined(unix)}
  R12;
  {$else}
  WriteLn('skip R12: SAFE_DEBUG on unix only');
  {$endif}
  Speed;
  H1 := HeapUsed;
  Check(H1 <= H0, 'nothing leaks: the heap is not above where it was (' + IntToStr(H1) + ' against ' + IntToStr(H0)
    + ')');
  WriteLn(Failed, ' failed');
  Halt(Failed);
end.
