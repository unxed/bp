{ SPDX-License-Identifier: MIT }
{ Safe Pascal, core (interface): ownership, slices, arena, defer, FFI. Included in unit Safe and unit BP. }

type
  ESafety = class(Exception);

  { ---------- Internals. Application code does not use this. ---------- }

  { Cell for weak references. Lives while the object or at least one TWeak is alive. }
  TSafeCell = class(TInterfacedObject)
  public
    Life: TObject; // TSafeLife while the object is alive; nil after it dies
  end;

  { Object lifetime. The compiler maintains the count: the interface fields in the TOwned/TShared records
    reference TSafeLife. When the last reference is gone, the object is destroyed. }
  TSafeLife = class(TInterfacedObject)
  public
    Obj: TObject;
    CellObj: TSafeCell;
    CellRef: IInterface;
    destructor Destroy; override;
    function Cell: TSafeCell; // created on the first TShared.Weak
  end;

  TSafeArenaImpl = class(TInterfacedObject)
  public
    Items: array of TObject;
    Count: SizeInt;
    procedure FreeAll;
    destructor Destroy; override;
  end;

{ For generics: their bodies are compiled in the user's module and can
  reference interface symbols only. }
function SafeNewLife(AObj: TObject; const Who: string): TSafeLife;
procedure SafeFail(const Msg: string);

{ Counter of live owned objects (like testing.allocator in Zig): grows on Own/Share/Adopt,
  decreases on destruction. A test that "freed everything" checks SafeCheckNoLeaks (R5). }
function SafeLiveCount: LongInt;
procedure SafeCheckNoLeaks;
{ Exceptions suppressed in deferred TDefer calls (see below). }
function SafeDeferFailures: LongInt;

type
  { ---------- API (SPEC §5) ---------- }

  generic TOwned<T: class> = record
  private
    FObj: T;
    FLife: IInterface;
  public
    class function Own(AObj: T): TOwned; static;
    function Get: T;
    function TryGet(out AObj: T): Boolean;
    function IsEmpty: Boolean;
    function Move: TOwned;
    procedure Reset;
  end;

  generic TWeak<T: class> = record
  private
    FCellObj: TSafeCell;
    FCell: IInterface;
  public
    procedure SetCell(ACell: TSafeCell); // internal
    function CellObj: TSafeCell;         // internal
    function IsAlive: Boolean;
    procedure Reset;
  end;

  generic TShared<T: class> = record
  private
    FObj: T;
    FLifeObj: TSafeLife;
    FLife: IInterface;
  public
    class function Share(AObj: T): TShared; static;
    function Get: T;
    function TryGet(out AObj: T): Boolean;
    function IsEmpty: Boolean;
    procedure Reset;
    function Weak: specialize TWeak<T>;
    function TryLock(const W: specialize TWeak<T>): Boolean;
  end;

  generic TSlice<T> = record
  private
    FData: specialize TArray<T>;
    FStart, FLen: SizeInt;
    function GetItem(I: SizeInt): T;
    procedure SetItem(I: SizeInt; const V: T);
  public
    class function From(const A: specialize TArray<T>): TSlice; static;
    function Sub(AStart, ALen: SizeInt): TSlice;
    function Len: SizeInt;
    function ToArray: specialize TArray<T>;
    property Items[I: SizeInt]: T read GetItem write SetItem; default;
  end;

  TArena = record
  private
    FImpl: TSafeArenaImpl;
    FRef: IInterface;
    procedure Check;
  public
    class function Create: TArena; static;
    function Adopt(AObj: TObject): TObject;
    procedure FreeAll;
    function Count: SizeInt;
  end;

  { ---------- defer (an idea from Zig) ----------
    A guard record: calls a procedure when the variable leaves scope, including on an exception.
    D := TDefer.Call(@Self.CloseHandle);  // ... any code follows ...   // CloseHandle will be called by itself
    Cancel is "errdefer in reverse": success, no call needed.
    An exception inside the deferred procedure cannot be thrown from a destructor during stack unwinding: it is
    suppressed and counted (SafeDeferFailures; SafeCheckNoLeaks fails too) rather than silently lost. }
  TSafeDeferProc = procedure of object;

  TSafeDeferImpl = class(TInterfacedObject)
  public
    Proc: TSafeDeferProc;
    Cancelled: Boolean;
    destructor Destroy; override;
  end;

  TDefer = record
  private
    FImpl: TSafeDeferImpl;
    FRef: IInterface;
  public
    class function Call(AProc: TSafeDeferProc): TDefer; static;
    procedure Cancel;
  end;

  { ---------- FFI (SPEC §13) ----------
    A pointer allocated by C code, under ownership: released by its own function.
      Buf := TCBox.Own(TCResource.Create(c_malloc(N), @c_free));
    Ptr is needed only by the unsafe wrapper; it is not exposed to safe code. }
  TCFreeProc = procedure(P: System.Pointer); cdecl;

  TCResource = class
  private
    FPtr: System.Pointer;
    FFree: TCFreeProc;
  public
    constructor Create(APtr: System.Pointer; AFree: TCFreeProc);
    destructor Destroy; override;
    function Ptr: System.Pointer;
  end;

{ Tasks that failed without Wait: a core counter, incremented by ext/go (R5). }
function SafeGoFailures: LongInt;
