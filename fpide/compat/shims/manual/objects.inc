{ FVCommon constants/types that IDE units expect via Objects (32-bit FPC).
  Values match Free Vision fvcommon.pas for FPC. }
const
  MaxBytes = 128 * 1024 * 1024;
  MaxWords = MaxBytes div SizeOf(Word);
  MaxInts  = MaxBytes div SizeOf(Integer);
  MaxLongs = MaxBytes div SizeOf(LongInt);
  MaxPtrs  = MaxBytes div SizeOf(Pointer);
  MaxReals = MaxBytes div SizeOf(Real);
  MaxStr   = MaxBytes div SizeOf(ShortString);

type
  Sw_Word    = Cardinal;
  Sw_Integer = LongInt;
  FNameStr   = string;
  { Explicit ShortString: ^String follows $H and can become AnsiString.
    Heap helpers stay ShortString until editor/file/search paths are UTF-8. }
  PString = ^ShortString;
  { FV Objects.TObject was the streamable root; tv3 uses TStreamable. }
  TObject = TStreamable;
  PObject = TObject;
  PCollection = TCollection;
  PStream = TStream;
  PBufStream = TBufStream;
  PMemoryStream = TMemoryStream;
  PDosStream = TDosStream;
  PSortedCollection = TSortedCollection;
  PStringCollection = TStringCollection;

type
  { Free Vision (Objects) record views of the integer types. }
  WordRec = packed record Lo, Hi: Byte; end;
  LongRec = packed record Lo, Hi: Word; end;
  ByteArray = array[0..MaxBytes - 1] of Byte;
  PByteArray = ^ByteArray;

{ ShortString heap helpers (FV). PString stays ^ShortString until the IDE
  buffer/file/search path is fully UTF-8; do not switch these to AnsiString. }
function NewStr(const S: ShortString): PString;
procedure DisposeStr(P: PString);

{ FV Objects.Abstract — call from methods that must be overridden. }
procedure Abstract;
