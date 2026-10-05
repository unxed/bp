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
  { Explicit ShortString: ^String follows $H and can become AnsiString. }
  PString = ^ShortString;
  PObject = TObject;
  PCollection = TCollection;
  PStream = TStream;
  PBufStream = TBufStream;
  PSortedCollection = TSortedCollection;
  PStringCollection = TStringCollection;

{ FV Objects.Abstract — call from methods that must be overridden. }
procedure Abstract;
