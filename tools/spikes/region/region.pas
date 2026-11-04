{ SPDX-License-Identifier: MIT }
{ Spike 2 of unxed/bp#108 (safe/SPEC.md §20, region style): a prototype of TRegion, TRegionObject and TGrowArray<T>.
  A region is a bump pointer in a list of blocks that double in size: nothing it holds ever moves, and it needs no
  reserved range of addresses. A TGrowArray keeps its elements in chunks of 16, 32, 64, ... elements (the chunk of an
  index is its highest bit), so an element never moves either and growth needs no reservation (no R11). }
{$mode objfpc}{$H+}{$modeswitch advancedrecords}
unit Region;

interface

uses
  SysUtils;

const
  ChunkLog2 = 4;          // the first chunk of a TGrowArray holds 16 elements

type
  ERegion = class(Exception);

  { A region of the current goroutine; a managed record: it is released when its variable leaves its scope. }
  TRegion = record
  private
    D: Pointer;           // PRegionData
  public
    class function Create: TRegion; static;
    procedure Reset;
    procedure Release;
    function Used: SizeUInt;
    class operator Initialize(var R: TRegion);
    class operator Finalize(var R: TRegion);
    class operator Copy(constref Src: TRegion; var Dst: TRegion);
  end;

  { A class whose objects live in the current region. }
  TRegionObject = class
  public
    class function NewInstance: TObject; override;
    procedure FreeInstance; override;
  end;

  { Grow-only, never moves; the header is in the region too, so a copy of the record refers to the same array. }
  generic TGrowArray<T> = record
  public type
    PT = ^T;
  private type
    PData = ^TData;
    TData = record
      Len: SizeInt;
      Chunks: array[0..47] of PT;
    end;
  public type
    { for P in A: a pointer to each element in place; the bounds are checked once per chunk }
    TEnum = record
    private
      Cur, Stop: PT;
      Data: PData;
      Chunk: Integer;
      Left: SizeInt;
      function NextChunk: Boolean;
    public
      function MoveNext: Boolean; inline;
      property Current: PT read Cur;
    end;
  private
    P: PData;
    function GetItem(I: SizeInt): T;
    procedure SetItem(I: SizeInt; const V: T);
  public
    class function Create: TGrowArray; static;
    function Push(const V: T): SizeInt;
    function Len: SizeInt; inline;
    function At(I: SizeInt): PT; inline;
    property Items[I: SizeInt]: T read GetItem write SetItem; default;
    function GetEnumerator: TEnum;
  end;

{ For the tests: counters of the management operators of TRegion and of released regions. }
var
  RegionCopies, RegionReleases: Integer;

function RegionAlloc(Size: SizeUInt): Pointer;
procedure RegionAddFinalizer(P: Pointer; Info: Pointer; Count: SizeInt; IsObject: Boolean);
function CurrentRegionDepth: Integer;

implementation

const
  FirstBlock = 4096;

type
  PBlock = ^TBlock;
  TBlock = record
    Next: PBlock;
    Size: SizeUInt;
  end;

  TFinalizer = record
    P: Pointer;
    Info: Pointer;          // the type info of an array element, or nil for an object
    Count: SizeInt;         // elements of an array; an object: 1
    IsObject: Boolean;
  end;

  PRegionData = ^TRegionData;
  TRegionData = record
    Cur, Limit: PByte;
    Blocks: PBlock;
    Fin: array of TFinalizer;
    FinCount: SizeInt;
    Outer: PRegionData;     // the region that was current before this one
    Owner: Pointer;         // the TRegion variable that releases it
  end;

threadvar
  Current: PRegionData;     // the innermost region of this goroutine

function CurrentRegionDepth: Integer;
var
  D: PRegionData;
begin
  Result := 0;
  D := Current;
  while D <> nil do
  begin
    Inc(Result);
    D := D^.Outer;
  end;
end;

procedure NewBlock(D: PRegionData; Need: SizeUInt);
var
  Size: SizeUInt;
  B: PBlock;
begin
  if D^.Blocks = nil then
    Size := FirstBlock
  else
    Size := 2 * D^.Blocks^.Size;
  while Size < Need + SizeOf(TBlock) + 16 do
    Size := 2 * Size;
  GetMem(B, Size);
  B^.Next := D^.Blocks;
  B^.Size := Size;
  D^.Blocks := B;
  D^.Cur := PByte(Align(PByte(B) + SizeOf(TBlock), 16));
  D^.Limit := PByte(B) + Size;
end;

function RegionAlloc(Size: SizeUInt): Pointer;
var
  D: PRegionData;
begin
  D := Current;
  if D = nil then
    raise ERegion.Create('SAFE-R15: an allocation in the current region, and the goroutine has none');
  Size := (Size + 15) and not SizeUInt(15);
  if D^.Cur + Size > D^.Limit then
    NewBlock(D, Size);
  Result := D^.Cur;
  Inc(D^.Cur, Size);
end;

procedure RegionAddFinalizer(P: Pointer; Info: Pointer; Count: SizeInt; IsObject: Boolean);
var
  D: PRegionData;
begin
  D := Current;
  if D^.FinCount = Length(D^.Fin) then
    SetLength(D^.Fin, 2 * D^.FinCount + 8);
  D^.Fin[D^.FinCount].P := P;
  D^.Fin[D^.FinCount].Info := Info;
  D^.Fin[D^.FinCount].Count := Count;
  D^.Fin[D^.FinCount].IsObject := IsObject;
  Inc(D^.FinCount);
end;

procedure RunFinalizers(D: PRegionData);
var
  I: SizeInt;
begin
  for I := D^.FinCount - 1 downto 0 do
    with D^.Fin[I] do
      if IsObject then
        TObject(P).CleanupInstance
      else
        FinalizeArray(P, Info, Count);
  D^.FinCount := 0;
end;

procedure FreeBlocks(D: PRegionData; KeepFirst: Boolean);
var
  B, N: PBlock;
begin
  B := D^.Blocks;
  while B <> nil do
  begin
    N := B^.Next;
    if KeepFirst and (N = nil) then
      Break;
    FreeMem(B);
    B := N;
  end;
  D^.Blocks := B;
  if B <> nil then
  begin
    D^.Cur := PByte(Align(PByte(B) + SizeOf(TBlock), 16));
    D^.Limit := PByte(B) + B^.Size;
  end;
end;

class function TRegion.Create: TRegion;
var
  N: PRegionData;
begin
  New(N);
  N^.Blocks := nil;
  N^.FinCount := 0;
  N^.Outer := Current;
  Current := N;
  NewBlock(N, 0);
  N^.Owner := nil;
  Result.D := N;
end;

procedure TRegion.Reset;
begin
  if D = nil then
    Exit;
  RunFinalizers(PRegionData(D));
  FreeBlocks(PRegionData(D), True);
end;

procedure TRegion.Release;
begin
  if D = nil then
    Exit;
  if Current <> D then
    raise ERegion.Create('SAFE-R14: Release of a region that is not the innermost one of the goroutine');
  RunFinalizers(PRegionData(D));
  FreeBlocks(PRegionData(D), False);
  Current := PRegionData(D)^.Outer;
  Dispose(PRegionData(D));
  D := nil;
  Inc(RegionReleases);
end;

function TRegion.Used: SizeUInt;
var
  B: PBlock;
begin
  Result := 0;
  if D = nil then
    Exit;
  B := PRegionData(D)^.Blocks;
  while B <> nil do
  begin
    Inc(Result, B^.Size);
    B := B^.Next;
  end;
end;

class operator TRegion.Initialize(var R: TRegion);
begin
  R.D := nil;
end;

class operator TRegion.Finalize(var R: TRegion);
begin
  R.Release;
end;

class operator TRegion.Copy(constref Src: TRegion; var Dst: TRegion);
begin
  // A region has one owner: a copy (other than the result of Create) is a mistake.
  Inc(RegionCopies);
  raise ERegion.Create('SAFE: a TRegion is copied');
end;

{ ---------- TRegionObject ---------- }

function HasManagedFields(C: TClass): Boolean;
begin
  while C <> nil do
  begin
    if PVmt(C)^.vInitTable <> nil then
      Exit(True);
    C := C.ClassParent;
  end;
  Result := False;
end;

class function TRegionObject.NewInstance: TObject;
var
  P: Pointer;
begin
  P := RegionAlloc(InstanceSize);
  Result := InitInstance(P);
  if HasManagedFields(Self) then
    RegionAddFinalizer(P, nil, 1, True);
end;

procedure TRegionObject.FreeInstance;
begin
  // the region frees its objects at once
end;

{ ---------- TGrowArray ---------- }

class function TGrowArray.Create: TGrowArray;
begin
  Result.P := RegionAlloc(SizeOf(TData));
  FillChar(Result.P^, SizeOf(TData), 0);
end;

function TGrowArray.Len: SizeInt;
begin
  Result := P^.Len;
end;

function TGrowArray.At(I: SizeInt): PT;
var
  J: SizeUInt;
  K: Integer;
begin
  if SizeUInt(I) >= SizeUInt(P^.Len) then
    raise ERegion.Create('SAFE-R2: TGrowArray index out of range');
  J := SizeUInt(I) + (SizeUInt(1) shl ChunkLog2);
  K := BsrQWord(J);
  Result := P^.Chunks[K - ChunkLog2] + (J - (SizeUInt(1) shl K));
end;

function TGrowArray.Push(const V: T): SizeInt;
var
  J: SizeUInt;
  K: Integer;
  N: SizeInt;
  C: PT;
begin
  Result := P^.Len;
  J := SizeUInt(Result) + (SizeUInt(1) shl ChunkLog2);
  K := BsrQWord(J);
  if J = SizeUInt(1) shl K then
  begin
    // the first element of a new chunk of 2^K elements
    N := SizeInt(1) shl K;
    C := RegionAlloc(N * SizeOf(T));
    FillChar(C^, N * SizeOf(T), 0);
    if IsManagedType(T) then
      RegionAddFinalizer(C, TypeInfo(T), N, False);
    P^.Chunks[K - ChunkLog2] := C;
  end;
  Inc(P^.Len);
  At(Result)^ := V;
end;

function TGrowArray.GetEnumerator: TEnum;
begin
  Result.Cur := nil;
  Result.Stop := nil;
  Result.Data := P;
  Result.Chunk := 0;
  Result.Left := P^.Len;
end;

function TGrowArray.TEnum.MoveNext: Boolean;
begin
  Inc(Cur);
  Result := (Cur < Stop) or NextChunk;
end;

function TGrowArray.TEnum.NextChunk: Boolean;
var
  N: SizeInt;
begin
  if Left <= 0 then
    Exit(False);
  N := SizeInt(1) shl (Chunk + ChunkLog2);
  if N > Left then
    N := Left;
  Cur := Data^.Chunks[Chunk];
  Stop := Cur + N;
  Dec(Left, N);
  Inc(Chunk);
  Result := True;
end;

function TGrowArray.GetItem(I: SizeInt): T;
begin
  Result := At(I)^;
end;

procedure TGrowArray.SetItem(I: SizeInt; const V: T);
begin
  At(I)^ := V;
end;

end.
