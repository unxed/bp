{ SPDX-License-Identifier: MIT }
{ Better Pascal, ext/go: горутины, каналы, группы, Select (интерфейс). }
type
  { ---------- Горутины и каналы (SPEC §14) ---------- }

  { Внутреннее: замок + список ждущих потоков. Ждущий кладёт в список своё
    событие, пока держит замок, поэтому пробуждение не теряется (как sudog в Go). }
  TSafeSync = class(TInterfacedObject)
  private
    FLock: TRTLCriticalSection;
    FWaiters: array of PRTLEvent;
    FWaitCount: SizeInt;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Lock;
    procedure Unlock;
    procedure Register;   // под замком
    procedure Unregister; // под замком
    procedure Broadcast;  // под замком
    function WaitLocked(TimeoutMs: Integer): Boolean; // под замком; условие проверять в цикле
  end;

  { Канал без типа: то, что умеет Select. }
  TSafeChan = class(TSafeSync)
  private
    FCap, FCount: SizeInt;
    FClosed: Boolean;
    FSentSeq, FRecvSeq: Int64;
  public
    procedure Close;
    function Ready: Boolean; // под замком: есть значение или канал закрыт
  end;

  generic TSafeChanOf<T> = class(TSafeChan)
  private
    FBuf: array of T;
    FHead: SizeInt;
    function TakeLocked(out V: T): Boolean;
  public
    constructor Create(ACap: SizeInt);
    procedure Send(const V: T);
    function Recv(out V: T): Boolean;
    function TryRecv(out V: T): Boolean;
  end;

  generic TChanEnumerator<T> = record
  public // заполняет TChan.GetEnumerator
    FImpl: specialize TSafeChanOf<T>;
    FRef: IInterface;
    FCur: T;
  public
    function MoveNext: Boolean;
    property Current: T read FCur;
  end;

  { Канал Go: ссылочный тип (копия записи — тот же канал), Cap = 0 — без буфера (рандеву). }
  generic TChan<T> = record
  private type
    TImpl = specialize TSafeChanOf<T>;
  private
    FImpl: TImpl;
    FRef: IInterface;
    procedure Check;
  public
    class function Create(ACap: SizeInt = 0): TChan; static;
    procedure Send(const V: T);               // в закрытый канал → ESafety (R6)
    function Recv(out V: T): Boolean;          // False: закрыт и пуст (v, ok := <-ch)
    function TryRecv(out V: T): Boolean;       // без ожидания
    procedure Close;                           // повторно → ESafety (R6)
    function Sel: TSafeChan;                   // для Select
    function GetEnumerator: specialize TChanEnumerator<T>; // for V in Ch (range ch)
  end;

  TSafeGroupImpl = class;

  { Задача-горутина: данные — поля (заполняются в конструкторе), код — Run.
    Поля задачи: значения, TChan, TShared, перенесённые (Move) TOwned. Не заёмы (S11). }
  TTask = class
  private
    FGroup: TSafeGroupImpl;
  public
    procedure Run; virtual; abstract;
    function Cancelled: Boolean;
    function Done: TSafeChan;    // закрывается при отмене группы: Select([..., Done])
    procedure Go(ATask: TTask);  // запустить ещё одну задачу в той же группе
  end;

  TSafeGroupImpl = class(TSafeSync)
  private
    FRunning: SizeInt;
    FError: string;
    FDone: TSafeChan;
    FDoneRef: IInterface;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Go(ATask: TTask);
    procedure Cancel;
    function Cancelled: Boolean;
    function WaitAll: string; // ждёт всех, возвращает и сбрасывает первую ошибку
    procedure TaskDone(const Err: string);
  end;

  { Структурная конкурентность: группа ждёт все свои задачи при выходе из области
    видимости. Ошибка задачи не роняет процесс (как panic в Go), а отменяет группу
    и бросается из Wait (R7). }
  TGroup = record
  private
    FImpl: TSafeGroupImpl;
    FRef: IInterface;
    procedure Check;
  public
    class function Create: TGroup; static;
    procedure Go(ATask: TTask); overload;      // задача переходит во владение группы
    procedure Go(AProc: TProcedure); overload;
    procedure Wait;                            // ошибка задачи → ESafety (R7)
    procedure Cancel;
    function Cancelled: Boolean;
    function Done: TSafeChan;
  end;

{ select: индекс готового канала (есть значение или закрыт) или -1 по таймауту.
  Готовность — подсказка: значение может забрать другой получатель, поэтому
  дальше TryRecv и при неудаче — снова Select. }
function Select(const Chans: array of TSafeChan; TimeoutMs: Integer = -1): Integer;
