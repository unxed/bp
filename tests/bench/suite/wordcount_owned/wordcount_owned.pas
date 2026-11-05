{ SPDX-License-Identifier: MIT }
{ Benchmark suite (tests/bench/compare.sh): a word count, the Bp version of the owned tier. Each word becomes a String
  of its own (a heap block with a reference count) before the lookup; the table is TMap of unit BP keyed by String.
  usage: wordcount_owned FILE }
program wordcount_owned;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, BP;

type
  TStreamBox = specialize TOwned<TFileStream>;
  TCounts = specialize TMap<String, Int64>;

function ReadAll(const Name: String): String;
var
  F: TStreamBox;
begin
  F := TStreamBox.Own(TFileStream.Create(Name, fmOpenRead));
  SetLength(Result, F.Get.Size);
  if Length(Result) > 0 then
    F.Get.ReadBuffer(Result[1], Length(Result));
end;

var
  Text, Word: String;
  W: TStrSlice;
  Counts: TCounts;
  P: TCounts.TPair;
  Total, MaxCount, SumSquares: Int64;

begin
  if ParamCount < 1 then
  begin
    WriteLn(StdErr, 'usage: wordcount_owned FILE');
    Halt(2);
  end;
  Text := ReadAll(ParamStr(1));
  Total := 0;
  for W in Fields(Text) do
  begin
    Word := W.ToString;
    Inc(Counts.Ref(Word, 0)^);
    Inc(Total);
  end;
  MaxCount := 0;
  SumSquares := 0;
  for P in Counts do
  begin
    if P.Value > MaxCount then
      MaxCount := P.Value;
    SumSquares := SumSquares + P.Value * P.Value;
  end;
  WriteLn('wordcount ', Total, ' ', Counts.Count, ' ', MaxCount, ' ', SumSquares);
end.
