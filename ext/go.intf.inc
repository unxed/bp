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

  { Internal: one Send, Recv or Select in progress. The first channel that fires one of its cases wins Fired with a
    compare-and-swap, so exactly one case happens. }
  PSafeSel = ^TSafeSel;
  TSafeSel = record
    Fired: LongInt;        // -1 waiting, the index of the case that fired, -2 given up (a timeout)
    Event: PRTLEvent;      // of the waiting thread; set under the lock of the channel that fired
  end;

  { Internal: a case waiting in a queue of a channel (a sudog of Go). It lives on the stack of the waiting call, which
    takes it out of every queue before it returns. }
  PSafeWaiter = ^TSafeWaiter;
  TSafeWaiter = record
    Sel: PSafeSel;
    Index: Integer;
    Elem: Pointer;         // the value to send, or where a received value goes (nil: drop it)
    Ok: Boolean;           // set by the firing channel: a value (True), or the channel was closed (False)
    Queued: Boolean;
    Prev, Next: PSafeWaiter;
  end;

  TSafeWaitQueue = record
    First, Last: PSafeWaiter;
  end;

  TSelKind = (skRecv, skSend);
  TSafeChan = class;

  { A case of Select: made by TChan.RecvCase, TChan.SendCase or TSafeChan.RecvCase. It holds the address of a variable of
    the caller, so it lives only in the call of Select it is written in. }
  TSelCase = record
    Chan: TSafeChan;
    Kind: TSelKind;
    Elem: Pointer;
    Ok: PBoolean;
  end;

  { An untyped channel: what Select works with. A buffer of FCap values and two queues of waiting cases; a receiver
    takes from the buffer or straight from a waiting sender, a sender gives to a waiting receiver or into the buffer. }
  TSafeChan = class(TSafeSync)
  private
    FCap, FCount: SizeInt;
    FClosed: Boolean;
    FRecvQ, FSendQ: TSafeWaitQueue;
    function TrySendLocked(Src: Pointer): Boolean;
    function TryRecvLocked(Dst: Pointer; out Ok: Boolean): Boolean;
  protected
    procedure PutElem(Src: Pointer); virtual; abstract;        // to the tail of the buffer
    procedure TakeElem(Dst: Pointer); virtual; abstract;       // from the head of the buffer (Dst nil: drop it)
    procedure CopyElem(Dst, Src: Pointer); virtual; abstract;  // Dst nil: nothing
    procedure ClearElem(Dst: Pointer); virtual; abstract;      // Default(T); Dst nil: nothing
    procedure CheckSend(Src: Pointer); virtual;
    procedure SendElem(Src: Pointer);
    function RecvElem(Dst: Pointer): Boolean;
  public
    procedure Close;
    function Ready: Boolean; // under the lock: a value is there (or a sender waits) or the channel is closed
    function RecvCase: TSelCase; // a receive whose value is dropped: Done of a group
  end;

  generic TSafeChanOf<T> = class(TSafeChan)
  private type
    TCell = record         // the layout of T; a pointer to T itself is beyond the typed bpvet
      V: T;
    end;
    PCell = ^TCell;
  private
    FBuf: array of T;
    FHead: SizeInt;
  protected
    procedure PutElem(Src: Pointer); override;
    procedure TakeElem(Dst: Pointer); override;
    procedure CopyElem(Dst, Src: Pointer); override;
    procedure ClearElem(Dst: Pointer); override;
    procedure CheckSend(Src: Pointer); override;
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
    function Sel: TSafeChan;                   // for Select over channels (readiness)
    function RecvCase(var V: T): TSelCase; overload;                   // a case of the atomic Select
    function RecvCase(var V: T; var Ok: Boolean): TSelCase; overload;  // Ok: False when closed and empty
    function SendCase(constref V: T): TSelCase;                        // into a closed channel → ESafety (R6)
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

{ select over channels: the index of a ready channel (it has a value or is closed), or -1 on timeout.
  Readiness is a hint: another receiver may take the value, so
  call TryRecv next and Select again if it fails. }
function Select(const Chans: array of TSafeChan; TimeoutMs: Integer = -1): Integer; overload;
{ select of Go: exactly one case happens, and its index is returned; -1 on timeout (TimeoutMs 0: none is ready).
  Select([A.RecvCase(V), B.SendCase(X), G.Done.RecvCase], TimeoutMs). A ready case is picked at random. }
function Select(const Cases: array of TSelCase; TimeoutMs: Integer = -1): Integer; overload;
