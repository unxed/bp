{ SPDX-License-Identifier: MIT }
{ Safe Pascal, region style (interface): TRegion, TRegionObject, TGrowArray<T> (SPEC §20). Included in unit Safe and
  unit BP after core.intf.inc.

  A region is a bump pointer in a list of blocks that double in size (from 4 KiB): nothing it holds ever moves, and it
  needs no reserved range of addresses. Every goroutine has a stack of regions (a threadvar): TRegion.Create pushes the
  new region, Release (or the end of the scope of its variable) pops it. TFoo.Create of a TRegionObject class and
  TGrowArray.Create allocate in the current region, the innermost one of the goroutine; a routine that declares no
  TRegion allocates in the region of its caller. The root analysis of bpvet (S17) keeps every reference of the style
  inside the life of its region; the runtime checks only what costs one comparison:
    R2   TGrowArray index out of range (At, A[I]), in every build;
    R12  SAFE_DEBUG on unix: each block is pages of its own, and Reset/Release take all access away from them (they are
         never reused), so a use of a released region stops at once with EAccessViolation;
    R14  Release of a region that is not the innermost one of the goroutine;
    R15  an allocation in the current region when the goroutine has none; Hold or Defer of a released region;
    R16  Own/Share/Adopt/Hold of a region object (it belongs to its region).
  Strings and other managed fields are allowed: only types with managed fields go into the finalizer list of the
  region (one entry per object or per chunk of an array), and Reset/Release finalize them.

  The same list holds what a scope undoes when it ends (SPEC §21.1): a held object (Hold: Destroy is called) and a
  deferred action (Defer). Reset and Release run the whole list, the newest entry first; an exception in a destructor
  or a deferred action is counted (SafeDeferFailures, SafeCheckNoLeaks) and the rest of the list still runs. }

type
  { ---------- API (SPEC §20) ---------- }

  { A handle of a region: the loop variable of for S in Scope. A pointer, no ownership; bpvet (S17) keeps it inside
    the block of its loop.
      S.Hold(Lines, TStringList.Create);  // Lines := the new object; Lines.Destroy runs when the scope ends
      S.Defer(@Term.Restore);             // runs when the scope ends, an exception included
    The typed bpvet checks every Hold (S6, S17): V is a plain local of a class type, Obj a constructor call of that
    class or of a descendant, and V neither escapes nor is read after the scope. }
  TScopeRef = record
  private
    D: System.Pointer;    // the data of the region; nil for a handle that was never given one
  public
    // UNSAFE: V is any variable of a class type; the typed bpvet checks that it is a local of the class of Obj
    procedure Hold(out V; Obj: TObject);
    procedure Defer(AProc: TSafeDeferProc);
    function Depth: Integer; // the number of regions of the goroutine up to this one (1: the outermost)
  end;

  { A region of the current goroutine. A managed record: it is released when its variable leaves its scope; a copy
    raises ESafety (a region has one owner), except the move of a result of Create that has allocated nothing yet.
    R := TRegion.Create makes the new region the current one; a region R held before is released. }
  TRegion = record
  private
    D: System.Pointer;    // the data of the region; nil when released
  public
    class function Create: TRegion; static;
    procedure Reset;      // everything allocated in it, at once; keeps the largest block for the next round
    procedure Release;    // everything allocated in it, at once, and the region itself (R14 if it is not innermost)
    function Used: SizeUInt; // the bytes of its blocks
    { as TScopeRef.Hold and Defer; the entries run on Reset and on Release (R15 on a released region) }
    // UNSAFE: V is any variable of a class type; the typed bpvet checks that it is a local of the class of Obj
    procedure Hold(out V; Obj: TObject);
    procedure Defer(AProc: TSafeDeferProc);
    class operator Initialize(var R: TRegion);
    class operator Finalize(var R: TRegion);
    class operator Copy(constref Src: TRegion; var Dst: TRegion);
  end;

  { for R in Scope do begin ... end: a region for one block. The region is made by the first MoveNext (FPC copies the
    enumerator before it) and released by the second; Exit and exceptions release it when the routine finalizes the
    loop. S17 forbids Break out of it (the region would be released late, out of order). R is a handle of the region
    (TScopeRef: R.Hold, R.Defer, R.Depth). }
  TScope = record
  private
    D: System.Pointer;
    N: Integer;
    function GetCurrent: TScopeRef;
  public
    function MoveNext: Boolean;
    property Current: TScopeRef read GetCurrent;
    class operator Initialize(var S: TScope);
    class operator Finalize(var S: TScope);
    class operator Copy(constref Src: TScope; var Dst: TScope);
  end;

  TScopes = record
    function GetEnumerator: TScope;
  end;

  { for Line in Each(Lines) do ...: a region per iteration; each MoveNext resets it. }
  TEachString = record
  private
    D: System.Pointer;
    Items: array of String;
    I: SizeInt;
    function GetCurrent: String;
  public
    function MoveNext: Boolean;
    property Current: String read GetCurrent;
    function GetEnumerator: TEachString;
    class operator Initialize(var S: TEachString);
    class operator Finalize(var S: TEachString);
    class operator Copy(constref Src: TEachString; var Dst: TEachString);
  end;

  { Internal: the region of an enumerator (TGrowArray.Each), released when the enumerator is finalized. }
  TSafeRegionHold = record
    D: System.Pointer;
    class operator Initialize(var H: TSafeRegionHold);
    class operator Finalize(var H: TSafeRegionHold);
    class operator Copy(constref Src: TSafeRegionHold; var Dst: TSafeRegionHold);
  end;

  { A class whose objects live in the current region: N := TNode.Create allocates there, Free and Destroy release
    nothing, and the region releases its objects at once. A region class has no destructor (S17a).
    Create has no frame that frees the object when a constructor raises (the region frees it), and NewInstance bumps in
    place and, for a class with neither managed fields nor interfaces, writes the VMT and zeroes the fields itself. }
  TRegionObject = class
  public
    constructor Create;
    class function NewInstance: TObject; override;
    procedure FreeInstance; override;
  end;

  { An array that only grows and never moves: its elements lie in chunks of 16, 32, 64, ... elements in the region
    (the chunk of an index is its highest bit). The header is in the region too, so a copy of the record refers to the
    same array; chunks added later go into the region of the header.
      A := TPts.Create; A.Push(P); A.At(I).X := 1 (with the modeswitch autoderef); V := A[I]; A[I] := V;
      for P in A do ... (P points at each element in place; P.X with autoderef);
      for C in A.Chunks do for I := 0 to C.Count - 1 do ... C.Data[I] ... (a plain array loop per chunk);
      for P in A.Each do ... (the elements in place and a region per iteration). }
  generic TGrowArray<T> = record
  public type
    PT = ^T;
  private const
    ChunkLog2 = 4;        // the first chunk holds 16 elements
  private type
    PCell = ^TCell;       // an element; the typed bpvet reads a field of a record through a pointer, not T itself
    TCell = record
      V: T;
    end;
    PData = ^TData;
    TData = record
      Len: SizeInt;
      Region: System.Pointer;  // the region of the header: its chunks go there
      Chunks: array[0..8 * SizeOf(SizeUInt) - ChunkLog2 - 1] of PT;
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
    { for C in A.Chunks: the elements a chunk at a time, C.Data[0..C.Count-1] }
    TChunk = record
      Data: PT;
      Count: SizeInt;
    end;
    TChunkEnum = record
    private
      Cur: TChunk;
      Data: PData;
      Chunk: Integer;
      Left: SizeInt;
    public
      function MoveNext: Boolean;
      property Current: TChunk read Cur;
      function GetEnumerator: TChunkEnum;
    end;
    { for P in A.Each: the elements in place, and a region per iteration (reset by each MoveNext) }
    TEachEnum = record
    private
      E: TEnum;
      H: TSafeRegionHold;
      function GetCurrent: PT;
    public
      function MoveNext: Boolean;
      property Current: PT read GetCurrent;
      function GetEnumerator: TEachEnum;
    end;
  private
    P: PData;
    function GetItem(I: SizeInt): T;
    procedure SetItem(I: SizeInt; const V: T);
    class function Make(Region: System.Pointer): TGrowArray; static;
  public
    class function Create: TGrowArray; static; overload;                // in the current region (R15 without one)
    class function Create(var R: TRegion): TGrowArray; static; overload; // in the region R
    function Push(const V: T): SizeInt;   // the index of the new element
    function Len: SizeInt; inline;
    function At(I: SizeInt): PT; inline;  // the element in place (R2)
    property Items[I: SizeInt]: T read GetItem write SetItem; default; // by value (R2)
    function GetEnumerator: TEnum;
    function Chunks: TChunkEnum;
    function Each: TEachEnum;
  end;

function Scope: TScopes;
function Each(const Lines: array of String): TEachString;
{ The number of regions of the current goroutine (0: none). }
function CurrentRegionDepth: Integer;

{ ---------- Internals. Application code does not use this. ----------
  For generics: their bodies are compiled in the user's module and can reference interface symbols only. }
{ Size bytes, aligned to 16, in the region Region (its data pointer), or in the current one when Region is nil (R15). }
function SafeRegionAlloc(Region: System.Pointer; Size: SizeUInt): System.Pointer;
{ The data pointer of the current region (R15 without one). }
function SafeRegionCurrent: System.Pointer;
{ Count elements of type Info at P are finalized when Region is reset or released. }
procedure SafeRegionAddFinalizer(Region, P, Info: System.Pointer; Count: SizeInt);
{ Raises ESafety R2 for the index I of a TGrowArray of Len elements (out of the inlined At). }
procedure SafeGrowIndexFail(I, Len: SizeInt);
{ For the enumerators that own a region (D: its data, nil before the first round): makes the region, or resets it. }
procedure SafeRegionRound(var D: System.Pointer);
{ Releases the region D of such an enumerator; D becomes nil. }
procedure SafeRegionReleaseData(var D: System.Pointer);
