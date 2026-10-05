{ SPDX-License-Identifier: MIT }
{ Safe Pascal v0.1 — безопасный по умолчанию Free Pascal одним файлом.
  Спецификация: SPEC.md. Подключение: положить файл рядом с исходниками и
  написать `uses ..., Safe;` ПОСЛЕДНИМ в каждом модуле. Опции компилятора не нужны.

  Что делает модуль:
  - UTF-8 везде (initialization): строки, имена файлов, консоль; cwstring спрятан внутри;
  - TOwned/TShared/TWeak/TSlice/TArena (SPEC §4–5);
  - "отравляет" опасные примитивы затенением имён (SPEC §6): GetMem(...) в модуле,
    где Safe последний в uses, не скомпилируется. Полное имя (System.GetMem) — явный unsafe.

  Перенос в FPC/Lazarus приветствуется. }
unit Safe;

{$mode objfpc}{$H+}
{ Linux по умолчанию — переносимый режим без libc (как Go): строки — fpwidestring
  (Unicode на Паскале), потоки — SafeThreads на системных вызовах; один бинарник
  работает и на Debian, и на Alpine. -dSAFE_LIBC — режим с libc (cwstring, cthreads),
  нужен только для FFI с C-библиотеками (аналог cgo). }
{$if defined(linux) and not defined(SAFE_LIBC)}{$define SAFE_PORTABLE}{$endif}
{$modeswitch advancedrecords}

interface

uses
  {$ifdef SAFE_PORTABLE}
  unicodeducet, fpwidestring, // Unicode без libc; unicodeducet раньше: его таблица сортировки нужна fpwidestring при старте
  {$else}
  {$if defined(unix) and not defined(SAFE_NO_CWSTRING)}cwstring,{$endif} // UTF-8 <-> UTF-16 и регистр через libc
  {$endif}
  {$ifdef windows}Windows,{$endif}
  SysUtils;

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

{ Задачи, упавшие без Wait (ошибка подавлена при выходе группы из области видимости). }
function SafeGoFailures: LongInt;

type
  { ---------- UTF-8 ---------- }

  { Перечислитель символов (code points). Current: один символ как String. }
  TCodePointEnumerator = record
  private
    FS: RawByteString;
    FPos, FLen: SizeInt;
    function GetCurrent: string;
  public
    function GetEnumerator: TCodePointEnumerator;
    function MoveNext: Boolean;
    property Current: string read GetCurrent;
  end;

{ for Ch in CodePoints('aё😀') do ...  // 'a', 'ё', '😀' }
function CodePoints(const S: string): TCodePointEnumerator;
{ Длина в символах (code points), а не в байтах. }
function CPLength(const S: string): SizeInt;

type
  { ---------- Отравленные примитивы (SPEC §6) ----------
    Тип-заглушка с тем же именем закрывает процедуру из System/SysUtils:
    вызов превращается в недопустимое приведение типа (ошибка компиляции),
    а deprecated-сообщение объясняет, что писать вместо. }
  TSafeForbidden = record end;

  GetMem     = TSafeForbidden deprecated 'SAFE-S1: raw allocation. Use TOwned/TShared/TArena or TArray<T>; in unsafe code write System.GetMem with // UNSAFE: comment';
  AllocMem   = TSafeForbidden deprecated 'SAFE-S1: raw allocation. Use TOwned/TShared/TArena or TArray<T>; in unsafe code write System.AllocMem';
  ReallocMem = TSafeForbidden deprecated 'SAFE-S1: raw allocation. Use TArray<T> + SetLength; in unsafe code write System.ReallocMem';
  FreeMem    = TSafeForbidden deprecated 'SAFE-S1: raw deallocation. Owners free memory; in unsafe code write System.FreeMem';
  New        = TSafeForbidden deprecated 'SAFE-S1: raw allocation. Use a record value or TOwned; in unsafe code write System.New';
  Dispose    = TSafeForbidden deprecated 'SAFE-S1: raw deallocation. Owners free memory; in unsafe code write System.Dispose';
  Move       = TSafeForbidden deprecated 'SAFE-S2: raw memory copy. Use assignment or Copy(); in unsafe code write System.Move';
  FillChar   = TSafeForbidden deprecated 'SAFE-S2: raw memory fill. Use X := Default(TType); in unsafe code write System.FillChar';
  FreeAndNil = TSafeForbidden deprecated 'SAFE-S3: manual destruction. Use TOwned.Reset; in unsafe code write SysUtils.FreeAndNil';

  { Типы оставлены рабочими (миграция), но каждое использование — предупреждение. }
  Pointer   = System.Pointer   deprecated 'SAFE-S4: raw pointer. Use TOwned/TSlice/open array; in unsafe code write System.Pointer';
  PByte     = System.PByte     deprecated 'SAFE-S4: raw pointer. Use TSlice<Byte> or array of Byte; in unsafe code write System.PByte';
  PChar     = System.PChar     deprecated 'SAFE-S4: raw pointer. Use String; at OS boundary write System.PChar in unsafe code';
  PAnsiChar = System.PAnsiChar deprecated 'SAFE-S4: raw pointer. Use String; at OS boundary write System.PAnsiChar in unsafe code';
  PWideChar = System.PWideChar deprecated 'SAFE-S4: raw pointer. Use String; at OS boundary write System.PWideChar in unsafe code';

  { Free — метод TObject; его закрывает хелпер с тем же именем, но с обязательным
    параметром, которого в безопасном коде не создать. Поэтому Obj.Free — ОШИБКА
    компиляции без всяких опций, а объяснение правила — имя типа параметра, которое
    компилятор печатает в строке "Found declaration: Free(const SAFE_S3_...)".
    В unsafe-коде — Obj.Destroy с // UNSAFE:. Ограничение: другой хелпер для TObject,
    подключённый после Safe, перекроет этот (S7). }
  SAFE_S3_NoFree_UseTOwnedReset_or_UnsafeDestroy = record end;
  TSafeObjectHelper = class helper for TObject
  public
    procedure Free(const Forbidden: SAFE_S3_NoFree_UseTOwnedReset_or_UnsafeDestroy);
  end;

implementation

{ ---------- внутреннее ---------- }

var
  GLive: LongInt = 0;         // объекты под владением (TOwned/TShared/TArena), живые сейчас
  GDeferFailures: LongInt = 0; // исключения, подавленные в отложенных вызовах
  GGoFailures: LongInt = 0;    // ошибки задач, которые никто не забрал через TGroup.Wait

function SafeLiveCount: LongInt;
begin
  Result := GLive;
end;

function SafeDeferFailures: LongInt;
begin
  Result := GDeferFailures;
end;

procedure SafeCheckNoLeaks;
begin
  if GLive <> 0 then
    SafeFail(Format('SAFE-R5: %d owned object(s) still alive', [GLive]));
  if GDeferFailures <> 0 then
    SafeFail(Format('SAFE-R5: %d exception(s) were suppressed in deferred calls', [GDeferFailures]));
  if GGoFailures <> 0 then
    SafeFail(Format('SAFE-R5: %d task failure(s) were never observed by TGroup.Wait', [GGoFailures]));
end;

procedure SafeFail(const Msg: string);
begin
  raise ESafety.Create(Msg);
end;

function SafeNewLife(AObj: TObject; const Who: string): TSafeLife;
begin
  if AObj = nil then
    Exit(nil);
  if AObj is TInterfacedObject then
    SafeFail('SAFE-R3: ' + Who + '(' + AObj.ClassName +
      '): TInterfacedObject is owned by its interface refcount; hold it through an interface');
  Result := TSafeLife.Create;
  Result.Obj := AObj;
  InterlockedIncrement(GLive);
end;

destructor TSafeLife.Destroy;
var
  O: TObject;
begin
  if CellObj <> nil then
    CellObj.Life := nil; // слабые ссылки больше не залочат объект
  O := Obj;
  Obj := nil;
  if O <> nil then
  begin
    O.Destroy; // Free здесь затенён хелпером
    InterlockedDecrement(GLive);
  end;
  CellRef := nil;
  inherited Destroy;
end;

function TSafeLife.Cell: TSafeCell;
begin
  if CellObj = nil then
  begin
    CellObj := TSafeCell.Create;
    CellObj.Life := Self;
    CellRef := CellObj;
  end;
  Result := CellObj;
end;

procedure TSafeArenaImpl.FreeAll;
var
  I: SizeInt;
  O: TObject;
begin
  for I := Count - 1 downto 0 do // обратный порядок: позже созданные могут ссылаться на ранние
  begin
    O := Items[I];
    Items[I] := nil;
    O.Destroy;
    InterlockedDecrement(GLive);
  end;
  Count := 0;
  SetLength(Items, 0);
end;

destructor TSafeArenaImpl.Destroy;
begin
  FreeAll;
  inherited Destroy;
end;

{ ---------- TOwned ---------- }

class function TOwned.Own(AObj: T): TOwned;
begin
  Result.FLife := SafeNewLife(AObj, 'TOwned.Own');
  Result.FObj := AObj;
end;

function TOwned.Get: T;
begin
  if FLife = nil then
    SafeFail('SAFE-R1: TOwned.Get on empty owner (after Move or Reset)');
  Result := FObj;
end;

function TOwned.TryGet(out AObj: T): Boolean;
begin
  Result := FLife <> nil;
  if Result then AObj := FObj else AObj := nil;
end;

function TOwned.IsEmpty: Boolean;
begin
  Result := FLife = nil;
end;

function TOwned.Move: TOwned;
var
  L: IInterface;
  O: T;
begin
  // Через локальные: корректно даже если Result и Self — одна память (A := A.Move).
  L := FLife;
  O := FObj;
  FLife := nil;
  FObj := nil;
  Result.FObj := O;
  Result.FLife := L;
end;

procedure TOwned.Reset;
begin
  FObj := nil;
  FLife := nil;
end;

{ ---------- TWeak ---------- }

procedure TWeak.SetCell(ACell: TSafeCell);
begin
  FCellObj := ACell;
  FCell := ACell;
end;

function TWeak.CellObj: TSafeCell;
begin
  Result := FCellObj;
end;

function TWeak.IsAlive: Boolean;
begin
  Result := (FCellObj <> nil) and (FCellObj.Life <> nil);
end;

procedure TWeak.Reset;
begin
  FCellObj := nil;
  FCell := nil;
end;

{ ---------- TShared ---------- }

class function TShared.Share(AObj: T): TShared;
begin
  Result.FLifeObj := SafeNewLife(AObj, 'TShared.Share');
  Result.FLife := Result.FLifeObj;
  Result.FObj := AObj;
end;

function TShared.Get: T;
begin
  if FLife = nil then
    SafeFail('SAFE-R1: TShared.Get on empty reference (after Reset or failed TryLock)');
  Result := FObj;
end;

function TShared.TryGet(out AObj: T): Boolean;
begin
  Result := FLife <> nil;
  if Result then AObj := FObj else AObj := nil;
end;

function TShared.IsEmpty: Boolean;
begin
  Result := FLife = nil;
end;

procedure TShared.Reset;
begin
  FObj := nil;
  FLifeObj := nil;
  FLife := nil;
end;

function TShared.Weak: specialize TWeak<T>;
begin
  if FLife = nil then
    Result.SetCell(nil)
  else
    Result.SetCell(FLifeObj.Cell);
end;

function TShared.TryLock(const W: specialize TWeak<T>): Boolean;
var
  C: TSafeCell;
  L: TSafeLife;
begin
  C := W.CellObj;
  Result := (C <> nil) and (C.Life <> nil);
  if Result then
  begin
    L := TSafeLife(C.Life);
    FLife := L; // сильная ссылка: объект не умрёт, пока она есть
    FLifeObj := L;
    FObj := T(L.Obj);
  end
  else
    Reset;
end;

{ ---------- TSlice ---------- }

class function TSlice.From(const A: specialize TArray<T>): TSlice;
begin
  Result.FData := A;
  Result.FStart := 0;
  Result.FLen := Length(A);
end;

function TSlice.Sub(AStart, ALen: SizeInt): TSlice;
begin
  if (AStart < 0) or (ALen < 0) or (AStart > FLen - ALen) then
    SafeFail(Format('SAFE-R2: TSlice.Sub(%d, %d) out of bounds, length %d', [AStart, ALen, FLen]));
  Result.FData := FData;
  Result.FStart := FStart + AStart;
  Result.FLen := ALen;
end;

function TSlice.Len: SizeInt;
begin
  Result := FLen;
end;

function TSlice.ToArray: specialize TArray<T>;
begin
  Result := Copy(FData, FStart, FLen);
end;

function TSlice.GetItem(I: SizeInt): T;
begin
  if (I < 0) or (I >= FLen) then
    SafeFail(Format('SAFE-R2: TSlice index %d out of bounds, length %d', [I, FLen]));
  Result := FData[FStart + I];
end;

procedure TSlice.SetItem(I: SizeInt; const V: T);
begin
  if (I < 0) or (I >= FLen) then
    SafeFail(Format('SAFE-R2: TSlice index %d out of bounds, length %d', [I, FLen]));
  FData[FStart + I] := V;
end;

{ ---------- TArena ---------- }

class function TArena.Create: TArena;
begin
  Result.FImpl := TSafeArenaImpl.Create;
  Result.FRef := Result.FImpl;
end;

procedure TArena.Check;
begin
  if FRef = nil then
    SafeFail('SAFE-R4: TArena used before TArena.Create');
end;

function TArena.Adopt(AObj: TObject): TObject;
begin
  Check;
  Result := AObj;
  if AObj = nil then
    Exit;
  if AObj is TInterfacedObject then
    SafeFail('SAFE-R3: TArena.Adopt(' + AObj.ClassName +
      '): TInterfacedObject is owned by its interface refcount; hold it through an interface');
  if FImpl.Count = Length(FImpl.Items) then
    SetLength(FImpl.Items, 2 * FImpl.Count + 8);
  FImpl.Items[FImpl.Count] := AObj;
  Inc(FImpl.Count);
  InterlockedIncrement(GLive);
end;

procedure TArena.FreeAll;
begin
  Check;
  FImpl.FreeAll;
end;

function TArena.Count: SizeInt;
begin
  Check;
  Result := FImpl.Count;
end;

{ ---------- defer ---------- }

destructor TSafeDeferImpl.Destroy;
begin
  if (not Cancelled) and Assigned(Proc) then
    try
      Proc();
    except
      InterlockedIncrement(GDeferFailures); // из деструктора бросать нельзя: учитываем, SafeCheckNoLeaks заметит
    end;
  inherited Destroy;
end;

class function TDefer.Call(AProc: TSafeDeferProc): TDefer;
begin
  Result.FImpl := TSafeDeferImpl.Create;
  Result.FImpl.Proc := AProc;
  Result.FRef := Result.FImpl;
end;

procedure TDefer.Cancel;
begin
  if FImpl <> nil then
    FImpl.Cancelled := True;
end;

{ ---------- FFI ---------- }

constructor TCResource.Create(APtr: System.Pointer; AFree: TCFreeProc);
begin
  inherited Create;
  FPtr := APtr;
  FFree := AFree;
end;

destructor TCResource.Destroy;
begin
  if (FPtr <> nil) and Assigned(FFree) then
    FFree(FPtr);
  FPtr := nil;
  inherited Destroy;
end;

function TCResource.Ptr: System.Pointer;
begin
  Result := FPtr;
end;

{ ---------- горутины: синхронизация ---------- }

threadvar
  TMyEvent: PRTLEvent; // событие текущего потока для ожиданий; создаётся лениво

function MyEvent: PRTLEvent;
begin
  if TMyEvent = nil then
    TMyEvent := RTLEventCreate;
  Result := TMyEvent;
end;

function SafeGoFailures: LongInt;
begin
  Result := GGoFailures;
end;

constructor TSafeSync.Create;
begin
  inherited Create;
  InitCriticalSection(FLock);
end;

destructor TSafeSync.Destroy;
begin
  DoneCriticalSection(FLock);
  inherited Destroy;
end;

procedure TSafeSync.Lock;
begin
  EnterCriticalSection(FLock);
end;

procedure TSafeSync.Unlock;
begin
  LeaveCriticalSection(FLock);
end;

procedure TSafeSync.Register;
begin
  if FWaitCount = Length(FWaiters) then
    SetLength(FWaiters, 2 * FWaitCount + 4);
  FWaiters[FWaitCount] := MyEvent;
  Inc(FWaitCount);
end;

procedure TSafeSync.Unregister;
var
  I: SizeInt;
  E: PRTLEvent;
begin
  E := MyEvent;
  for I := 0 to FWaitCount - 1 do
    if FWaiters[I] = E then
    begin
      FWaiters[I] := FWaiters[FWaitCount - 1];
      Dec(FWaitCount);
      Exit;
    end;
end;

procedure TSafeSync.Broadcast;
var
  I: SizeInt;
begin
  for I := 0 to FWaitCount - 1 do
    RTLEventSetEvent(FWaiters[I]);
  FWaitCount := 0;
end;

function TSafeSync.WaitLocked(TimeoutMs: Integer): Boolean;
begin
  // Событие «залипает» (RTLEvent — двоичный семафор): SetEvent между Unlock и
  // WaitFor не теряется. Лишние пробуждения безвредны: вызывающий проверяет условие в цикле.
  Register;
  Unlock;
  if TimeoutMs < 0 then
    RTLEventWaitFor(MyEvent)
  else
    RTLEventWaitFor(MyEvent, TimeoutMs);
  Lock;
  Unregister; // после таймаута; если нас вычеркнул Broadcast — ничего не найдёт
  Result := True;
end;

{ ---------- каналы ---------- }

procedure TSafeChan.Close;
begin
  Lock;
  try
    if FClosed then
      SafeFail('SAFE-R6: close of closed channel');
    FClosed := True;
    Broadcast;
  finally
    Unlock;
  end;
end;

function TSafeChan.Ready: Boolean;
begin
  Result := (FCount > 0) or FClosed;
end;

constructor TSafeChanOf.Create(ACap: SizeInt);
begin
  inherited Create;
  if ACap < 0 then
    ACap := 0;
  FCap := ACap;
  if ACap = 0 then
    SetLength(FBuf, 1)
  else
    SetLength(FBuf, ACap);
end;

procedure TSafeChanOf.Send(const V: T);
var
  Ticket: Int64;
begin
  Lock;
  try
    while (not FClosed) and (FCount >= Length(FBuf)) do
      WaitLocked(-1);
    if FClosed then
      SafeFail('SAFE-R6: send on closed channel');
    FBuf[(FHead + FCount) mod Length(FBuf)] := V;
    Inc(FCount);
    Inc(FSentSeq);
    Ticket := FSentSeq;
    Broadcast;
    if FCap = 0 then // рандеву: ждём, пока значение заберут
      while FRecvSeq < Ticket do
        WaitLocked(-1);
  finally
    Unlock;
  end;
end;

function TSafeChanOf.TakeLocked(out V: T): Boolean;
begin
  Result := FCount > 0;
  if not Result then
  begin
    V := Default(T);
    Exit;
  end;
  V := FBuf[FHead];
  FBuf[FHead] := Default(T); // не держим ссылку на отданное значение
  FHead := (FHead + 1) mod Length(FBuf);
  Dec(FCount);
  Inc(FRecvSeq);
  Broadcast;
end;

function TSafeChanOf.Recv(out V: T): Boolean;
begin
  Lock;
  try
    while (FCount = 0) and not FClosed do
      WaitLocked(-1);
    Result := TakeLocked(V);
  finally
    Unlock;
  end;
end;

function TSafeChanOf.TryRecv(out V: T): Boolean;
begin
  Lock;
  try
    Result := TakeLocked(V);
  finally
    Unlock;
  end;
end;

function TChanEnumerator.MoveNext: Boolean;
begin
  Result := FImpl.Recv(FCur);
end;

class function TChan.Create(ACap: SizeInt): TChan;
begin
  Result.FImpl := TImpl.Create(ACap);
  Result.FRef := Result.FImpl;
end;

procedure TChan.Check;
begin
  if FRef = nil then
    SafeFail('SAFE-R4: TChan used before TChan.Create');
end;

procedure TChan.Send(const V: T);
begin
  Check;
  FImpl.Send(V);
end;

function TChan.Recv(out V: T): Boolean;
begin
  Check;
  Result := FImpl.Recv(V);
end;

function TChan.TryRecv(out V: T): Boolean;
begin
  Check;
  Result := FImpl.TryRecv(V);
end;

procedure TChan.Close;
begin
  Check;
  FImpl.Close;
end;

function TChan.Sel: TSafeChan;
begin
  Check;
  Result := FImpl;
end;

function TChan.GetEnumerator: specialize TChanEnumerator<T>;
begin
  Check;
  Result.FImpl := FImpl;
  Result.FRef := FRef;
end;

function Select(const Chans: array of TSafeChan; TimeoutMs: Integer): Integer;
var
  I, J: Integer;
  Deadline, Now: QWord;
  Left: Integer;
begin
  Deadline := GetTickCount64 + QWord(TimeoutMs);
  repeat
    // Проверка и регистрация — под замком каждого канала: пробуждение не теряется.
    for I := 0 to High(Chans) do
    begin
      Chans[I].Lock;
      if Chans[I].Ready then
      begin
        Chans[I].Unlock;
        for J := 0 to I - 1 do
        begin
          Chans[J].Lock;
          Chans[J].Unregister;
          Chans[J].Unlock;
        end;
        Exit(I);
      end;
      Chans[I].Register;
      Chans[I].Unlock;
    end;
    if TimeoutMs < 0 then
      RTLEventWaitFor(MyEvent)
    else
    begin
      Now := GetTickCount64;
      if Now >= Deadline then
        Left := 0
      else
        Left := Deadline - Now;
      if Left > 0 then
        RTLEventWaitFor(MyEvent, Left);
    end;
    for J := 0 to High(Chans) do
    begin
      Chans[J].Lock;
      Chans[J].Unregister;
      Chans[J].Unlock;
    end;
  until (TimeoutMs >= 0) and (GetTickCount64 >= Deadline);
  // последний шанс после таймаута
  for I := 0 to High(Chans) do
  begin
    Chans[I].Lock;
    try
      if Chans[I].Ready then
        Exit(I);
    finally
      Chans[I].Unlock;
    end;
  end;
  Result := -1;
end;

{ ---------- группы и задачи ---------- }

function SafeGoThread(P: System.Pointer): PtrInt;
var
  T: TTask;
  G: TSafeGroupImpl;
  Err: string;
begin
  T := TTask(P);
  G := T.FGroup;
  Err := '';
  try
    T.Run;
  except
    on E: Exception do
      Err := E.ClassName + ': ' + E.Message;
    else
      Err := 'non-Exception object raised';
  end;
  try
    T.Destroy;
  except
    on E: Exception do
      if Err = '' then
        Err := 'in task destructor: ' + E.ClassName + ': ' + E.Message;
  end;
  if TMyEvent <> nil then
  begin
    RTLEventDestroy(TMyEvent);
    TMyEvent := nil;
  end;
  G.TaskDone(Err); // после этого группа может быть уже уничтожена: G больше не трогаем
  Result := 0;
end;

function TTask.Cancelled: Boolean;
begin
  Result := FGroup.Cancelled;
end;

function TTask.Done: TSafeChan;
begin
  Result := FGroup.FDone;
end;

procedure TTask.Go(ATask: TTask);
begin
  FGroup.Go(ATask);
end;

type
  TSafeDoneChan = specialize TSafeChanOf<Boolean>;

  TSafeProcTask = class(TTask)
  public
    Proc: TProcedure;
    procedure Run; override;
  end;

procedure TSafeProcTask.Run;
begin
  Proc();
end;

constructor TSafeGroupImpl.Create;
begin
  inherited Create;
  FDone := TSafeDoneChan.Create(0);
  FDoneRef := FDone;
end;

destructor TSafeGroupImpl.Destroy;
begin
  // Структурная конкурентность: группа не умирает раньше своих задач.
  if WaitAll <> '' then
    InterlockedIncrement(GGoFailures); // бросать из деструктора нельзя: учитываем (R5)
  inherited Destroy;
end;

procedure TSafeGroupImpl.Go(ATask: TTask);
var
  Id: TThreadID;
  Probe: PRTLEvent;
begin
  if ATask = nil then
    Exit;
  if ATask.FGroup <> nil then
    SafeFail('SAFE-R3: TGroup.Go: task already started');
  ATask.FGroup := Self;
{$if defined(go32v2) or defined(msdos)}
  // DOS однозадачна: потоков нет, BeginThread не вернёт управление осмысленно (проверено на go32v2 под DOSBox-X: тест зависал).
  ATask.Destroy;
  SafeFail('SAFE-R8: this target (DOS) has no threads; goroutines are not available. Use plain procedures');
{$endif}
  // Без менеджера потоков (Unix без cthreads) RTLEventCreate возвращает nil.
  Probe := RTLEventCreate;
  if Probe = nil then
  begin
    ATask.Destroy;
    SafeFail('SAFE-R8: no thread manager. On Unix put cthreads FIRST in the program uses: uses {$ifdef unix}cthreads,{$endif} ...');
  end;
  RTLEventDestroy(Probe);
  Lock;
  Inc(FRunning);
  Unlock;
  Id := BeginThread(@SafeGoThread, ATask);
  if Id = TThreadID(0) then
  begin
    ATask.Destroy;
    TaskDone('');
    SafeFail('SAFE-R7: cannot start thread');
  end;
  CloseThread(Id);
end;

procedure TSafeGroupImpl.Cancel;
var
  WasClosed: Boolean;
begin
  FDone.Lock;
  WasClosed := FDone.FClosed;
  FDone.Unlock;
  if not WasClosed then
    try
      FDone.Close;
    except
      on ESafety do ; // закрыли параллельно — то же самое
    end;
end;

function TSafeGroupImpl.Cancelled: Boolean;
begin
  FDone.Lock;
  Result := FDone.FClosed;
  FDone.Unlock;
end;

function TSafeGroupImpl.WaitAll: string;
begin
  Lock;
  try
    while FRunning > 0 do
      WaitLocked(-1);
    Result := FError;
    FError := '';
  finally
    Unlock;
  end;
end;

procedure TSafeGroupImpl.TaskDone(const Err: string);
var
  Failed: Boolean;
begin
  Lock;
  Failed := (Err <> '') and (FError = '');
  if Failed then
    FError := Err;
  Unlock;
  if Failed then
    Cancel; // первая ошибка отменяет остальных (errgroup)
  Lock;
  Dec(FRunning);
  Broadcast;
  Unlock;
end;

class function TGroup.Create: TGroup;
begin
  Result.FImpl := TSafeGroupImpl.Create;
  Result.FRef := Result.FImpl;
end;

procedure TGroup.Check;
begin
  if FRef = nil then
    SafeFail('SAFE-R4: TGroup used before TGroup.Create');
end;

procedure TGroup.Go(ATask: TTask);
begin
  Check;
  FImpl.Go(ATask);
end;

procedure TGroup.Go(AProc: TProcedure);
var
  T: TSafeProcTask;
begin
  Check;
  T := TSafeProcTask.Create;
  T.Proc := AProc;
  FImpl.Go(T);
end;

procedure TGroup.Wait;
var
  Err: string;
begin
  Check;
  Err := FImpl.WaitAll;
  if Err <> '' then
    SafeFail('SAFE-R7: task failed: ' + Err);
end;

procedure TGroup.Cancel;
begin
  Check;
  FImpl.Cancel;
end;

function TGroup.Cancelled: Boolean;
begin
  Check;
  Result := FImpl.Cancelled;
end;

function TGroup.Done: TSafeChan;
begin
  Check;
  Result := FImpl.FDone;
end;

{ ---------- UTF-8 ---------- }

{ Длина символа по ведущему байту. Битый байт или "хвост" — отдельный символ:
  обход никогда не зацикливается и не теряет байты. }
function CPByteLen(B: Byte): SizeInt; inline;
begin
  case B of
    $C0..$DF: Result := 2;
    $E0..$EF: Result := 3;
    $F0..$F7: Result := 4;
  else
    Result := 1;
  end;
end;

function TCodePointEnumerator.GetCurrent: string;
begin
  Result := Copy(FS, FPos, FLen);
end;

function TCodePointEnumerator.GetEnumerator: TCodePointEnumerator;
begin
  Result := Self;
end;

function TCodePointEnumerator.MoveNext: Boolean;
begin
  Inc(FPos, FLen);
  Result := FPos <= Length(FS);
  if Result then
  begin
    FLen := CPByteLen(Byte(FS[FPos]));
    if FLen > Length(FS) - FPos + 1 then // обрезанный символ в конце строки
      FLen := Length(FS) - FPos + 1;
  end;
end;

function CodePoints(const S: string): TCodePointEnumerator;
begin
  Result.FS := S;
  Result.FPos := 1;
  Result.FLen := 0;
end;

function CPLength(const S: string): SizeInt;
var
  Ch: string;
begin
  Result := 0;
  for Ch in CodePoints(S) do
    Inc(Result);
end;

{ ---------- хелпер Free ---------- }

procedure TSafeObjectHelper.Free(const Forbidden: SAFE_S3_NoFree_UseTOwnedReset_or_UnsafeDestroy);
begin
end;

initialization
{$ifndef SAFE_NO_UTF8}
  // Кодировка String по умолчанию (а с ней и всех неявных конверсий).
  DefaultSystemCodePage := CP_UTF8;
  // Имена файлов: на входе в RTL и на выходе (FindFirst, GetCurrentDir...).
  DefaultFileSystemCodePage := CP_UTF8;
  DefaultRTLFileSystemCodePage := CP_UTF8;
  // Консоль и стандартные потоки.
  SetTextCodePage(Input, CP_UTF8);
  SetTextCodePage(Output, CP_UTF8);
  SetTextCodePage(ErrOutput, CP_UTF8);
  SetTextCodePage(StdOut, CP_UTF8);
  SetTextCodePage(StdErr, CP_UTF8);
  {$ifdef windows}
  SetConsoleOutputCP(CP_UTF8);
  SetConsoleCP(CP_UTF8);
  {$endif}
{$endif}
end.
