{ SPDX-License-Identifier: MIT }
{ Safe Pascal, ядро (интерфейс): владение, срезы, арена, defer, FFI. Включается в unit Safe и unit BP. }

type
  ESafety = class(Exception);

  { ---------- Внутреннее устройство. Прикладной код это не использует. ---------- }

  { Ячейка для слабых ссылок. Живёт, пока жив объект или хоть один TWeak. }
  TSafeCell = class(TInterfacedObject)
  public
    Life: TObject; // TSafeLife, пока объект жив; nil после смерти
  end;

  { Время жизни объекта. Счётчик ведёт компилятор: на TSafeLife ссылаются
    поля-интерфейсы в записях TOwned/TShared. Последняя ссылка ушла — объект уничтожен. }
  TSafeLife = class(TInterfacedObject)
  public
    Obj: TObject;
    CellObj: TSafeCell;
    CellRef: IInterface;
    destructor Destroy; override;
    function Cell: TSafeCell; // создаётся при первом TShared.Weak
  end;

  TSafeArenaImpl = class(TInterfacedObject)
  public
    Items: array of TObject;
    Count: SizeInt;
    procedure FreeAll;
    destructor Destroy; override;
  end;

{ Для обобщений: их тела компилируются в модуле пользователя и могут
  ссылаться только на символы интерфейса. }
function SafeNewLife(AObj: TObject; const Who: string): TSafeLife;
procedure SafeFail(const Msg: string);

{ Счётчик живых объектов под владением (аналог testing.allocator из Zig): растёт при Own/Share/Adopt,
  убывает при уничтожении. Тест, который «всё освободил», проверяет SafeCheckNoLeaks (R5). }
function SafeLiveCount: LongInt;
procedure SafeCheckNoLeaks;
{ Исключения, подавленные в отложенных вызовах TDefer (см. ниже). }
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
    procedure SetCell(ACell: TSafeCell); // внутреннее
    function CellObj: TSafeCell;         // внутреннее
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

  { ---------- defer (идея из Zig) ----------
    Запись-сторож: вызывает процедуру при выходе переменной из области видимости, в том числе при исключении.
    D := TDefer.Call(@Self.CloseHandle);  // ... дальше любой код ...   // CloseHandle вызовется сама
    Cancel — «errdefer наоборот»: успех, вызывать не нужно.
    Исключение внутри отложенной процедуры нельзя бросить из деструктора во время раскрутки стека: оно
    подавляется и учитывается (SafeDeferFailures; SafeCheckNoLeaks тоже падает), а не теряется молча. }
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
    Указатель, выделенный C-кодом, под владением: освобождается его же функцией.
      Buf := TCBox.Own(TCResource.Create(c_malloc(N), @c_free));
    Ptr нужен только unsafe-обвязке; в безопасный код наружу не отдаётся. }
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

{ Задачи, упавшие без Wait: счётчик ядра, его увеличивает ext/go (R5). }
function SafeGoFailures: LongInt;
