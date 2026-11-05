{ SPDX-License-Identifier: MIT }
{ Safe Pascal, strings and maps (interface): TStrSlice, Fields, TMap<K, V> (SPEC §25.3). Included in unit Safe and unit
  BP after region.intf.inc.
  TStrSlice is a part of a String that holds the String, as a slice of Go does: no copy of the bytes, and the text stays
  alive while a slice of it does. StrSlice(S) is the slice of all of S (a String does not convert by itself yet: the typed
  bpvet does not read an implicit operator of a record), W.Equals(S) compares with a String. A change of the String variable later makes a new String (copy on write), so a slice
  never sees it. Fields(S) are the words of S: the runs of bytes above the space.
  TMap<K, V> is a hash map with open addressing (linear probing, the hash kept in the entry), for keys of the types that
  MapHash takes: String, TStrSlice, the integers, Pointer. A copy of a TMap refers to the same map, as in Go and as
  TSlice does; a map is made by Create or by its first write.
      Inc(Counts.Ref(W, 0)^);          // one lookup: the place of the value of W, added with 0 when W is new
      Counts[StrSlice('a')] := 5;       // N := Counts[W] of a key that is not there raises ESafety (R18)
      for P in Counts do ... P.Key ... P.Value ...  // a change of the map in the loop raises ESafety (R19)
  The checks:
    R2   a TStrSlice index or Sub out of range;
    R18  M[K] of a key that is not in the map (Get(K, Default) and TryGet do not raise);
    R19  a change of the map while for P in M walks it;
    S27  (bpvet) the result of Ref is used at once: M.Ref(K, D)^ in the statement that calls it, never kept, because the
         next change of the map may move it. }
type
  { eight bytes at any address: a packed record is read without an alignment fault on every target }
  TSafeQWordAt = packed record
    V: QWord;
  end;
  // UNSAFE: the hash and the comparison of keys read eight bytes of a String at once
  PSafeQWordAt = ^TSafeQWordAt;

{ The same N bytes at P and Q, eight at a time; for TStrSlice and TMap, in the interface to be inlined there. }
function SafeSameBytes(P, Q: System.PByte; N: SizeInt): Boolean; inline;
{ The hash of the N bytes at P, of which Avail (at least N) may be read: with eight to spare the last bytes are read
  at once. For MapHash, in the interface to be inlined there. }
function SafeHashBytes(P: System.PByte; N, Avail: SizeInt): QWord; inline;

type
  { ---------- TStrSlice ---------- }
  TStrSlice = record
  private
    FStr: String;         // the whole String; the slice holds a reference
    FStart: SizeInt;      // 0-based offset of the first byte in FStr
    FLen: SizeInt;
    function GetItem(I: SizeInt): Char;
  public
    class function Make(const S: String): TStrSlice; static; overload;                        // all of S
    class function Make(const S: String; AStart, ALen: SizeInt): TStrSlice; static; overload; // as Copy: 1-based (R2)
    function Sub(AStart, ALen: SizeInt): TStrSlice; // a part of this slice, 1-based as Copy (R2)
    function Len: SizeInt; inline;
    function ToString: String;                       // a copy of the bytes
    function Data: System.PChar; inline;             // UNSAFE: the first byte, for a raw loop or FFI
    function Equals(const S: String): Boolean;       // the same bytes as S
    property Items[I: SizeInt]: Char read GetItem; default; // 1-based as a String (R2)
    class operator =(const A, B: TStrSlice): Boolean; inline;
    class operator <>(const A, B: TStrSlice): Boolean;
  end;

  { for W in Fields(S): the words of S, each a TStrSlice; while F.Next(W) is the same without the copy of a record per
    word that a for-in loop makes }
  TFields = record
  private
    FText: String;
    FPos: SizeInt;        // 0-based: where the search for the next word starts
    FCur: TStrSlice;
  public
    function GetEnumerator: TFields;
    function MoveNext: Boolean;
    function Next(var W: TStrSlice): Boolean;
    property Current: TStrSlice read FCur;
  end;

function Fields(const S: String): TFields;

type
  { SPIKE: a view of bytes of a String without a reference to it (16 bytes, not managed) }
  TStrView = record
  private
    FP: System.PChar;
    FLen: SizeInt;
  public
    function Len: SizeInt; inline;
    function ToString: String;
    class operator =(const A, B: TStrView): Boolean; inline;
  end;

  TViewFields = record
  private
    FText: String;
    FPos: SizeInt;
    FCur: TStrView;
  public
    function GetEnumerator: TViewFields;
    function MoveNext: Boolean; inline;
    property Current: TStrView read FCur;
  end;

function FieldViews(const S: String): TViewFields;
function StrSlice(const S: String): TStrSlice; // the slice of all of S: TStrSlice.Make(S)

{ the hash of a key of a TMap; equal keys have equal hashes, and a String has the hash of the slice of all of it }
function MapHash(const K: TStrSlice): QWord; overload; inline;
function MapHash(const K: String): QWord; overload; inline;
function MapHash(const K: TStrView): QWord; overload; inline;
function MapHash(const K: Int64): QWord; overload;
function MapHash(const K: QWord): QWord; overload;
function MapHash(const K: System.Pointer): QWord; overload;

type
  { ---------- TMap ---------- }
  generic TMap<K, V> = record
  public type
    PV = ^V;
    TPair = record
      Key: K;
      Value: V;
    end;
  private type
    TEntry = record
      Hash: QWord;        // 0: a free slot; a key's hash has bit 0 set
      Key: K;
      Value: V;
    end;
    TData = record
      Count: SizeInt;
      Version: SizeInt;   // changes with every added or deleted key (R19)
      Shift: Byte;        // the slot of a hash: Hash shr Shift
      Slots: array of TEntry;
    end;
  public type
    TEnum = record
    private
      FD: array of TData;
      FVersion: SizeInt;
      FI: SizeInt;
      function GetCurrent: TPair;
    public
      function MoveNext: Boolean;
      property Current: TPair read GetCurrent;
    end;
  private
    FD: array of TData;   // one element, shared by the copies of the map
    procedure Make;
    procedure Grow;
    function Find(const Key: K; Hash: QWord): SizeInt; inline;
    function GetItem(const Key: K): V;
    procedure SetItem(const Key: K; const Value: V);
  public
    class function Create: TMap; static;
    function Count: SizeInt;
    // UNSAFE: the place of the value of Key, added with Default when Key is new; valid until the next change of the map
    // (S27: the typed bpvet keeps it to M.Ref(K, D)^ in one statement)
    function Ref(const Key: K; const Default: V): PV; inline;
    procedure Put(const Key: K; const Value: V);
    function TryGet(const Key: K; out Value: V): Boolean;
    function Get(const Key: K; const Default: V): V;
    function Has(const Key: K): Boolean;
    function Delete(const Key: K): Boolean;
    procedure Clear;
    function GetEnumerator: TEnum;
    property Items[const Key: K]: V read GetItem write SetItem; default;
  end;
