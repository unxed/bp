{ SPDX-License-Identifier: MIT }
{ Benchmark suite (tests/bench/compare.sh): a word count over a file, strings.
  The file (made by compare.sh) is read whole. A word is a run of bytes above the space; each word is counted in a hash
  map. The program prints the number of words, the number of different words, the largest count and the sum of the
  squares of the counts.
  Here the words are TStrView values of the text (FieldViews: no copy of a word, no reference to the text) and the
  map is TMap of unit BP, updated with one lookup per word (Ref); the text is a local of Count, which bpvet S28 checks
  is not written while the views live. C counts the words in place in a table of its own (wordcount.c); Rust, Go and Goose
  slice the text and use their standard maps (wordcount.rs, wordcount.go, wordcount.goose).
  usage: wordcount FILE }
program wordcount;

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

procedure Count(const Name: String);
var
  Text: String;
  W: TStrView;
  Counts: TCounts;
  P: TCounts.TPair;
  Total, MaxCount, SumSquares: Int64;
begin
  Text := ReadAll(Name);
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
end;

begin
  if ParamCount < 1 then
  begin
    WriteLn(StdErr, 'usage: wordcount FILE');
    Halt(2);
  end;
  Count(ParamStr(1));
end.
