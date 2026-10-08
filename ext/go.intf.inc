{ SPDX-License-Identifier: MIT }
{ Better Pascal, ext/go: goroutines, channels, groups, Select (interface). }
type
  { ---------- Goroutines and channels (SPEC §14) ---------- }

  { Internal: a lock + a list of waiting threads. A waiter puts its event into the list
    while it holds the lock, so a wakeup is never lost (like sudog in Go). }
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
    procedure Register;   // under the lock
    procedure Unregister; // under the lock
    procedure Broadcast;  // under the lock
    function WaitLocked(TimeoutMs: Integer): Boolean; // under the lock; check the condition in a loop
  end;

  { An untyped channel: what Select works with. }
  TSafeChan = class(TSafeSync)
  private
    FCap, FCount: SizeInt;
    FClosed: Boolean;
    FSentSeq, FRecvSeq: Int64;
  public
    procedure Close;
    function Ready: Boolean; // under the lock: a value is there or the channel is closed
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
  public // filled by TChan.GetEnumerator
    FImpl: specialize TSafeChanOf<T>;
    FRef: IInterface;
    FCur: T;
  public
    function MoveNext: Boolean;
    property Current: T read FCur;
  end;

  { A Go channel: a reference type (a copy of the record is the same channel); Cap = 0 is unbuffered (rendezvous). }
  generic TChan<T> = record
  private type
    TImpl = specialize TSafeChanOf<T>;
  private
    FImpl: TImpl;
    FRef: IInterface;
    procedure Check;
  public
    class function Create(ACap: SizeInt = 0): TChan; static;
    procedure Send(const V: T);               // into a closed channel → ESafety (R6)
    function Recv(out V: T): Boolean;          // False: closed and empty (v, ok := <-ch)
    function TryRecv(out V: T): Boolean;       // without waiting
    procedure Close;                           // a second time → ESafety (R6)
    function Sel: TSafeChan;                   // for Select
    function GetEnumerator: specialize TChanEnumerator<T>; // for V in Ch (range ch)
  end;

  TSafeGroupImpl = class;

  { A goroutine task: the data are fields (filled in the constructor), the code is Run.
    Task fields: values, TChan, TShared, TOwned passed with Move. No borrows (S11). }
  TTask = class
  private
    FGroup: TSafeGroupImpl;
  public
    procedure Run; virtual; abstract;
    function Cancelled: Boolean;
    function Done: TSafeChan;    // closed when the group is cancelled: Select([..., Done])
    procedure Go(ATask: TTask);  // start one more task in the same group
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
    function WaitAll: string; // waits for all, returns and clears the first error
    procedure TaskDone(const Err: string);
  end;

  { Structured concurrency: a group waits for all its tasks when it goes out of
    scope. An error of a task does not bring the process down (as a panic in Go does); it cancels the group
    and is raised from Wait (R7). }
  TGroup = record
  private
    FImpl: TSafeGroupImpl;
    FRef: IInterface;
    procedure Check;
  public
    class function Create: TGroup; static;
    procedure Go(ATask: TTask); overload;      // the group takes ownership of the task
    procedure Go(AProc: TProcedure); overload;
    procedure Wait;                            // an error of a task → ESafety (R7)
    procedure Cancel;
    function Cancelled: Boolean;
    function Done: TSafeChan;
  end;

{ select: the index of a ready channel (it has a value or is closed), or -1 on timeout.
  Readiness is a hint: another receiver may take the value, so
  call TryRecv next and Select again if it fails. }
function Select(const Chans: array of TSafeChan; TimeoutMs: Integer = -1): Integer;
