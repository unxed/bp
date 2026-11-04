{ SPDX-License-Identifier: MIT }
{ A declaration stub for the spike resolver: only what the modules of this repository use. }
unit system;
{$mode objfpc}
interface
type
  SizeInt = Int64; SizeUInt = QWord; PtrInt = Int64; PtrUInt = QWord; ValSInt = LongInt; NativeInt = Int64; NativeUInt = QWord;
  TVarRec = record VType: SizeInt; VPointer: Pointer; end;
  HRESULT = LongInt;
  PRTLEvent = type Pointer;
  PPtrUInt = ^PtrUInt; PPtrInt = ^PtrInt; PPointer = ^Pointer; PLongInt = ^LongInt; PLongWord = ^LongWord; PQWord = ^QWord; PInt64 = ^Int64; PWord = ^Word; PBoolean = ^Boolean;
  PTypeInfo = Pointer; TThreadFunc = function(parameter: Pointer): PtrInt;
  TProcedure = procedure;
  Integer = LongInt; PInteger = ^Integer;
  generic TArray<T> = array of T;
  TGUID = record D1: LongWord; D2, D3: Word; D4: array[0..7] of Byte; end;
  PChar = ^Char; PAnsiChar = ^AnsiChar; PWideChar = ^WideChar; PByte = ^Byte; PSizeInt = ^SizeInt;
  TClass = class of TObject;
  TObject = class
  public
    constructor Create;
    destructor Destroy; virtual;
    procedure Free;
    class function ClassName: ShortString;
    function ClassType: TClass;
    class function InstanceSize: SizeInt; virtual;
    class function NewInstance: TObject; virtual;
    procedure FreeInstance; virtual;
    class function InitInstance(instance: Pointer): TObject;
    procedure CleanupInstance;
    class function InheritsFrom(aclass: TClass): Boolean;
    procedure AfterConstruction; virtual;
    procedure BeforeDestruction; virtual;
  end;
  IUnknown = interface
    ['{00000000-0000-0000-C000-000000000046}']
    function QueryInterface(constref iid: TGUID; out obj): LongInt;
    function _AddRef: LongInt;
    function _Release: LongInt;
  end;
  IInterface = IUnknown;
  TInterfacedObject = class(TObject, IUnknown)
  protected
    FRefCount: LongInt;
    function QueryInterface(constref iid: TGUID; out obj): LongInt; virtual;
    function _AddRef: LongInt; virtual;
    function _Release: LongInt; virtual;
  public
    property RefCount: LongInt read FRefCount;
  end;
  TThreadID = PtrUInt;
  TRTLCriticalSection = record Data: array[0..39] of Byte; end;
var
  ExitCode: LongInt;
const
  Pi = 3.14159265358979;
var
  DummyVar: LongInt;
function InterLockedIncrement(var Target: LongInt): LongInt; external;
function InterLockedDecrement(var Target: LongInt): LongInt; external;
function InterlockedExchange(var Target: LongInt; Source: LongInt): LongInt; external;
function InterlockedCompareExchange(var Target: LongInt; NewValue, Comperand: LongInt): LongInt; external;
procedure InitCriticalSection(var cs: TRTLCriticalSection); external;
procedure DoneCriticalSection(var cs: TRTLCriticalSection); external;
procedure EnterCriticalSection(var cs: TRTLCriticalSection); external;
procedure LeaveCriticalSection(var cs: TRTLCriticalSection); external;
procedure GetMem(out p: Pointer; Size: PtrUInt); external;
procedure FreeMem(p: Pointer); external;
procedure Move(const source; var dest; count: SizeInt); external;
procedure FillChar(var x; count: SizeInt; Value: Byte); external;
procedure ThreadSwitch; external;
function ParamStr(l: LongInt): String; external;
function ParamCount: LongInt; external;
procedure RunError(w: Word); external;
function RTLEventCreate: PRTLEvent; external;
procedure RTLEventDestroy(state: PRTLEvent); external;
procedure RTLEventSetEvent(state: PRTLEvent); external;
procedure RTLEventResetEvent(state: PRTLEvent); external;
procedure RTLEventWaitFor(state: PRTLEvent); external;
procedure RTLEventWaitFor(state: PRTLEvent; timeout: LongInt); external;
function BeginThread(ThreadFunction: TThreadFunc; p: Pointer): TThreadID; external;
function BeginThread(ThreadFunction: TThreadFunc; p: Pointer; var ThreadId: TThreadID): TThreadID; external;
function GetCurrentThreadId: TThreadID; external;
function InterlockedExchangeAdd(var Target: LongInt; Source: LongInt): LongInt; external;
procedure ReadWriteBarrier; external;
function Pos(const Substr, S: String): SizeInt; external;
function Pos(const Substr, S: String; Offset: SizeInt): SizeInt; external;
procedure Delete(var S: String; Index, Count: SizeInt); external;
procedure Insert(const Source: String; var S: String; Index: SizeInt); external;
function StringOfChar(c: Char; l: SizeInt): String; external;
function UpCase(c: Char): Char; external;
function IntToStrMagic(v: Int64): String; external;

implementation
constructor TObject.Create;
begin
end;
destructor TObject.Destroy;
begin
end;
procedure TObject.Free;
begin
end;
class function TObject.ClassName: ShortString;
begin
end;
function TObject.ClassType: TClass;
begin
end;
class function TObject.InstanceSize: SizeInt;
begin
end;
class function TObject.NewInstance: TObject;
begin
end;
procedure TObject.FreeInstance;
begin
end;
class function TObject.InitInstance(instance: Pointer): TObject;
begin
end;
procedure TObject.CleanupInstance;
begin
end;
class function TObject.InheritsFrom(aclass: TClass): Boolean;
begin
end;
procedure TObject.AfterConstruction;
begin
end;
procedure TObject.BeforeDestruction;
begin
end;
function TInterfacedObject.QueryInterface(constref iid: TGUID; out obj): LongInt;
begin
end;
function TInterfacedObject._AddRef: LongInt;
begin
end;
function TInterfacedObject._Release: LongInt;
begin
end;
end.
