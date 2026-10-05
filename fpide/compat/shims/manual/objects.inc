{ FVCommon/Memory constants that IDE units expect via Objects (32-bit FPC).
  Values match Free Vision fvcommon.pas for FPC (not the 16-bit MaxBytes=65520). }
const
  MaxBytes = 128 * 1024 * 1024;
  MaxWords = MaxBytes div SizeOf(Word);
  MaxInts  = MaxBytes div SizeOf(Integer);
  MaxLongs = MaxBytes div SizeOf(LongInt);
  MaxPtrs  = MaxBytes div SizeOf(Pointer);
  MaxReals = MaxBytes div SizeOf(Real);
  MaxStr   = MaxBytes div SizeOf(ShortString);
