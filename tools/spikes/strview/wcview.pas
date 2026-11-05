{ SPDX-License-Identifier: MIT }
{ Spike (unxed/bp#108): the word count of tests/bench/suite/wordcount with the words as TStrView values of the text
  (FieldViews: 16 bytes each, no reference to the text, no managed copy) in a TMap<TStrView, Int64>.
  The hash tail of MapHash(TStrView): the bytes by default, -dSPIKE_EXACT two overlapping reads, -dSPIKE_OVERREAD a
  masked word past the end (unsafe, for the measurement only).
  usage: wcview FILE }
program wcview;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, BP;

type
  TStreamBox = specialize TOwned<TFileStream>;
  TCounts = specialize TMap<TStrView, Int64>;

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
  Text: String;
  W: TStrView;
  Counts: TCounts;
  P: TCounts.TPair;
  Total, MaxCount, SumSquares: Int64;

begin
  if ParamCount < 1 then
  begin
    WriteLn(StdErr, 'usage: wordcount FILE');
    Halt(2);
  end;
  Text := ReadAll(ParamStr(1));
  Total := 0;
  for W in FieldViews(Text) do
  begin
    Inc(Counts.Ref(W, 0)^);
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
