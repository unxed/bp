{ SPDX-License-Identifier: MIT }
{ Benchmark suite (tests/bench/compare.sh): a word count over a file, strings.
  The file (made by compare.sh) is read whole. A word is a run of bytes above the space; each word is counted in a hash
  table. The program prints the number of words, the number of different words, the largest count and the sum of the
  squares of the counts.
  Here each word is a String of its own (Copy) and the table is the one below (FNV-1a of 32 bits, open addressing, a size that is
  fixed for the file of compare.sh: no TDictionary, because the typed bpvet does not read a unit with a dot in its name).
  C counts the words in place and has a table of the same kind (wordcount.c); Rust and Go slice the text and use their
  standard maps (wordcount.rs, wordcount.go).
  usage: wordcount FILE }
program wordcount;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, BP;

const
  TableBits = 17;
  TableSize = 1 shl TableBits;

type
  TStreamBox = specialize TOwned<TFileStream>;

  TEntry = record
    Key: String;           // '' marks a free slot: a word is never empty
    Count: Int64;
  end;

var
  Table: array of TEntry;

function ReadAll(const Name: String): String;
var
  F: TStreamBox;
begin
  F := TStreamBox.Own(TFileStream.Create(Name, fmOpenRead));
  SetLength(Result, F.Get.Size);
  if Length(Result) > 0 then
    F.Get.ReadBuffer(Result[1], Length(Result));
end;

function Hash(const Key: String): QWord;
var
  I: SizeInt;
begin
  Result := 2166136261;
  for I := 1 to Length(Key) do
    Result := ((Result xor Ord(Key[I])) * 16777619) and $FFFFFFFF;
end;

{ adds one to the count of Key; True when the word is new }
function Add(const Key: String): Boolean;
var
  Slot: SizeInt;
begin
  Slot := SizeInt(Hash(Key) and (TableSize - 1));
  while Table[Slot].Key <> '' do
  begin
    if Table[Slot].Key = Key then
    begin
      Inc(Table[Slot].Count);
      Exit(False);
    end;
    Slot := (Slot + 1) and (TableSize - 1);
  end;
  Table[Slot].Key := Key;
  Table[Slot].Count := 1;
  Result := True;
end;

var
  Text, Key: String;
  Start, I, Len, Slot: SizeInt;
  Total, Distinct, MaxCount, SumSquares: Int64;

begin
  if ParamCount < 1 then
  begin
    WriteLn(StdErr, 'usage: wordcount FILE');
    Halt(2);
  end;
  Text := ReadAll(ParamStr(1));
  SetLength(Table, TableSize);
  Len := Length(Text);
  Total := 0;
  Distinct := 0;
  I := 1;
  while I <= Len do
  begin
    while (I <= Len) and (Text[I] <= ' ') do
      Inc(I);
    Start := I;
    while (I <= Len) and (Text[I] > ' ') do
      Inc(I);
    if I > Start then
    begin
      Key := Copy(Text, Start, I - Start);
      if Add(Key) then
      begin
        Inc(Distinct);
        if Distinct * 2 > TableSize then
        begin
          WriteLn(StdErr, 'wordcount: more different words than the table holds');
          Halt(3);
        end;
      end;
      Inc(Total);
    end;
  end;
  MaxCount := 0;
  SumSquares := 0;
  for Slot := 0 to TableSize - 1 do
    if Table[Slot].Key <> '' then
    begin
      if Table[Slot].Count > MaxCount then
        MaxCount := Table[Slot].Count;
      SumSquares := SumSquares + Table[Slot].Count * Table[Slot].Count;
    end;
  WriteLn('wordcount ', Total, ' ', Distinct, ' ', MaxCount, ' ', SumSquares);
end.
