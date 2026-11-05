{ SPDX-License-Identifier: MIT }
// UNSAFE-UNIT: a test of the heap itself works on raw blocks of GetMem and FreeMem
{ Tests of the heap (SPEC §25.4): the same checks pass with the memory manager of BP (the default) and with the heap of
  the RTL (BP_HEAP=rtl; tests/run.sh modes rtlheap and mnrtlheap). Blocks are filled with a pattern of their own and
  checked before they are freed, so two blocks that overlap or a block written by the allocator are found. Exit code =
  number of failures. }
program test_heap;

{$mode objfpc}{$H+}

uses
  SysUtils, BP;

type
  TAddrChan = specialize TChan<PtrUInt>;

  { Allocates FN blocks of sizes from FSeed, fills each with a pattern and sends it. }
  TMaker = class(TTask)
  private
    FOut: TAddrChan;
    FN, FSeed: Integer;
  public
    constructor Create(const AOut: TAddrChan; const AN, ASeed: Integer);
    procedure Run; override;
  end;

  { Checks the pattern of every block it receives and frees it; a broken block counts in AcrossBad. }
  TFreer = class(TTask)
  private
    FIn: TAddrChan;
  public
    constructor Create(const AIn: TAddrChan);
    procedure Run; override;
  end;

var
  Failed: Integer = 0;
  AcrossBad: LongInt = 0;

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

{ A block: its size in the first word, then bytes of a value from the address. }
procedure Fill(P: System.Pointer; Size: PtrUInt);
var
  B: System.PByte;
  I: PtrUInt;
  V: Byte;
begin
  B := System.PByte(P);
  V := Byte(PtrUInt(P) shr 4) or 1;
  for I := 0 to Size - 1 do
    B[I] := V;
end;

function Intact(P: System.Pointer; Size: PtrUInt): Boolean;
var
  B: System.PByte;
  I: PtrUInt;
  V: Byte;
begin
  B := System.PByte(P);
  V := Byte(PtrUInt(P) shr 4) or 1;
  for I := 0 to Size - 1 do
    if B[I] <> V then
      Exit(False);
  Result := True;
end;

procedure NextSeed(var Seed: Cardinal);
begin
  Seed := Cardinal((QWord(Seed) * 1103515245 + 12345) and $FFFFFFFF);
end;

function SizeFor(var Seed: Cardinal): PtrUInt;
begin
  NextSeed(Seed);
  case (Seed shr 16) mod 16 of
    0: Result := 33000 + (Seed shr 8) mod 200000;   // a run of pages
    1..3: Result := 1024 + (Seed shr 8) mod 31000;
  else
    Result := (Seed shr 8) mod 600;
  end;
  if Result = 0 then
    Result := 1;
end;

constructor TMaker.Create(const AOut: TAddrChan; const AN, ASeed: Integer);
begin
  inherited Create;
  FOut := AOut;
  FN := AN;
  FSeed := ASeed;
end;

procedure TMaker.Run;
var
  W: System.PPtrUInt;
  I: Integer;
  Seed: Cardinal;
  S: PtrUInt;
  P: System.Pointer;
begin
  Seed := FSeed;
  for I := 1 to FN do
  begin
    S := SizeFor(Seed) + SizeOf(PtrUInt);
    P := System.GetMem(S);
    Fill(P, S);
    W := System.PPtrUInt(P);
    W^ := S;
    FOut.Send(PtrUInt(P));
  end;
end;

constructor TFreer.Create(const AIn: TAddrChan);
begin
  inherited Create;
  FIn := AIn;
end;

procedure TFreer.Run;
var
  W: System.PPtrUInt;
  A: PtrUInt;
  S: PtrUInt;
begin
  while FIn.Recv(A) do
  begin
    S := System.PPtrUInt(A)^;
    W := System.PPtrUInt(A);
    W^ := 0;
    Fill(System.Pointer(A), SizeOf(PtrUInt));          // restore the first word to the pattern
    if not Intact(System.Pointer(A), S) then
      InterlockedIncrement(AcrossBad);
    System.FreeMem(System.Pointer(A));
  end;
end;

{ ---------- one thread ---------- }

procedure Sizes;
const
  Big = 9 * 1024 * 1024;  // more than a segment
var
  P: System.Pointer;
  S: PtrUInt;
  Ok: Boolean;
begin
  Ok := True;
  S := 0;
  while S <= 70000 do
  begin
    P := System.GetMem(S);
    Ok := Ok and ((S = 0) or (System.MemSize(P) >= S));
    if S > 0 then
    begin
      Fill(P, S);
      Ok := Ok and Intact(P, S);
    end;
    System.FreeMem(P);
    if S < 300 then
      Inc(S)
    else
      Inc(S, 997);
  end;
  Check(Ok, 'GetMem of sizes 0..70000: MemSize covers the size, the block holds its bytes');
  P := System.GetMem(Big);
  Fill(P, Big);
  Check(Intact(P, Big) and (System.MemSize(P) >= Big), 'a block of 9 MiB');
  System.FreeMem(P);
end;

procedure Realloc;
var
  B: System.PByte;
  P: System.Pointer;
  S, I: PtrUInt;
  Ok: Boolean;
begin
  Ok := True;
  P := System.GetMem(8);
  B := System.PByte(P);
  for I := 0 to 7 do
    B[I] := I + 1;
  S := 8;
  while S < 3000000 do
  begin
    S := S * 3 div 2 + 5;
    System.ReAllocMem(P, S);
    for I := 0 to 7 do
      Ok := Ok and (System.PByte(P)[I] = I + 1);
  end;
  while S > 30 do   // the last size stays above the 8 bytes checked
  begin
    S := S div 3;
    System.ReAllocMem(P, S);
    for I := 0 to 7 do
      Ok := Ok and (System.PByte(P)[I] = I + 1);
  end;
  System.ReAllocMem(P, 0);
  Check(Ok and (P = nil), 'ReAllocMem keeps the bytes while it grows to 3 MB and shrinks; to 0 it frees');
end;

{ Bytes of a value from their index and K, so a block keeps them when it moves. }
procedure Mark(P: System.Pointer; Size: PtrUInt; K: Byte);
var
  I: PtrUInt;
begin
  for I := 0 to Size - 1 do
    System.PByte(P)[I] := Byte(I * 7 + K);
end;

function Marked(P: System.Pointer; Size: PtrUInt; K: Byte): Boolean;
var
  I: PtrUInt;
begin
  for I := 0 to Size - 1 do
    if System.PByte(P)[I] <> Byte(I * 7 + K) then
      Exit(False);
  Result := True;
end;

{ Runs of pages: a block that grows keeps all its bytes, in place or moved; a freed run of 1 MiB or more stays in memory
  for the next one and goes back to the kernel when another is freed, and a block made in its pages meanwhile keeps its
  bytes. }
procedure BigRuns;
const
  MiB = 1024 * 1024;
var
  P, A, B, C: System.Pointer;
  S, Round: PtrUInt;
  Ok: Boolean;
begin
  Ok := True;
  S := 40000;
  P := System.GetMem(S);
  Mark(P, S, 3);
  while S < 6000000 do
  begin
    System.ReAllocMem(P, S * 2);
    Ok := Ok and Marked(P, S, 3);
    S := S * 2;
    Mark(P, S, 3);
  end;
  System.FreeMem(P);
  Check(Ok, 'a block that grows to 6 MB by ReAllocMem keeps all its bytes');
  Ok := True;
  for Round := 1 to 3 do
  begin
    A := System.GetMem(2 * MiB);
    Mark(A, 2 * MiB, 1);
    B := System.GetMem(3 * MiB div 2);
    Mark(B, 3 * MiB div 2, 2);
    System.FreeMem(A);
    C := System.GetMem(MiB + 100);
    Mark(C, MiB + 100, 4);
    System.FreeMem(B);   // the pages of A still free go back to the kernel; those of C stay
    Ok := Ok and Marked(C, MiB + 100, 4);
    A := System.GetMem(2 * MiB);
    Mark(A, 2 * MiB, 5);
    Ok := Ok and Marked(C, MiB + 100, 4) and Marked(A, 2 * MiB, 5);
    System.FreeMem(A);
    System.FreeMem(C);
  end;
  Check(Ok, 'runs of 1 MiB and more freed and made again: a block in the pages of a freed run keeps its bytes');
end;

procedure Zeroed;
var
  A: array[0..999] of System.Pointer;
  I, J: Integer;
  Ok: Boolean;
begin
  for I := 0 to High(A) do
  begin
    A[I] := System.GetMem(200);
    System.FillChar(A[I]^, 200, $AB);
  end;
  for I := 0 to High(A) do
    System.FreeMem(A[I]);
  Ok := True;
  for I := 0 to High(A) do
  begin
    A[I] := System.AllocMem(200);
    for J := 0 to 199 do
      Ok := Ok and (System.PByte(A[I])[J] = 0);
  end;
  for I := 0 to High(A) do
    System.FreeMem(A[I]);
  Check(Ok, 'AllocMem clears a block that was used before');
end;

{ Against an array of the live blocks: random allocations and frees, every block checked before it is freed. }
procedure Random1;
const
  N = 20000;
var
  A: array of System.Pointer;
  Sz: array of PtrUInt;
  I, K: Integer;
  Seed: Cardinal;
  Ok: Boolean;
begin
  SetLength(A, N);
  SetLength(Sz, N);
  Seed := 7;
  Ok := True;
  for I := 1 to 400000 do
  begin
    NextSeed(Seed);
    K := (Seed shr 8) mod N;
    if A[K] <> nil then
    begin
      Ok := Ok and Intact(A[K], Sz[K]);
      System.FreeMem(A[K]);
      A[K] := nil;
    end
    else
    begin
      Sz[K] := SizeFor(Seed);
      A[K] := System.GetMem(Sz[K]);
      Fill(A[K], Sz[K]);
    end;
  end;
  for K := 0 to N - 1 do
    if A[K] <> nil then
    begin
      Ok := Ok and Intact(A[K], Sz[K]);
      System.FreeMem(A[K]);
    end;
  Check(Ok, '400000 random GetMem and FreeMem: no block was written by another');
end;

{ Rounds of many blocks freed: the heap does not grow round after round. }
procedure Reuse;
const
  N = 50000;
var
  A: array of System.Pointer;
  I, R: Integer;
  After1, AfterAll: PtrUInt;
begin
  SetLength(A, N);
  After1 := 0;
  for R := 1 to 20 do
  begin
    for I := 0 to N - 1 do
      A[I] := System.GetMem(16 + (I mod 40) * 24);
    for I := N - 1 downto 0 do
      System.FreeMem(A[I]);
    if R = 1 then
      After1 := GetFPCHeapStatus.CurrHeapSize;
  end;
  AfterAll := GetFPCHeapStatus.CurrHeapSize;
  Check(AfterAll <= After1 + 4 * 1024 * 1024, 'the heap does not grow over 20 rounds of 50000 blocks (' +
    IntToStr(After1) + ' -> ' + IntToStr(AfterAll) + ')');
end;

{ ---------- across goroutines ---------- }

{ Pairs of a maker and a freer: every block is freed by another goroutine (on another carrier under M:N). }
procedure Across;
const
  Pairs = 4;
  N = 30000;
var
  Makers, Freers: TGroup;
  Ch: array[0..Pairs - 1] of TAddrChan;
  I: Integer;
begin
  Makers := TGroup.Create;
  Freers := TGroup.Create;
  for I := 0 to Pairs - 1 do
  begin
    Ch[I] := TAddrChan.Create(64);
    Freers.Go(TFreer.Create(Ch[I]));
    Makers.Go(TMaker.Create(Ch[I], N, I + 1));
  end;
  Makers.Wait;
  for I := 0 to Pairs - 1 do
    Ch[I].Close;
  Freers.Wait;
  Check(AcrossBad = 0, '4 pairs, 120000 blocks made by one goroutine and freed by another');
end;

var
  Before, After: PtrUInt;
begin
  WriteLn('test_heap');
  Before := GetFPCHeapStatus.CurrHeapUsed;
  Sizes;
  Realloc;
  BigRuns;
  Zeroed;
  Random1;
  Reuse;
  After := GetFPCHeapStatus.CurrHeapUsed;
  Check(After <= Before, 'the bytes in use are back where they were (' + IntToStr(After) + ' against ' + IntToStr(Before)
    + ')');
  Across;
  WriteLn(Failed, ' failed');
  Halt(Failed);
end.
