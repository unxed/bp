// EXPECT: clean
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ The typed mode reads what FPC accepts (unxed/bp#162): Round and Trunc of a Double, a constant above the Int64 range,
  and, or, xor of an Int64 and a QWord value, and a unit with a dotted name. }
program typed_numeric_ok;

{$mode objfpc}{$H+}

uses
  SysUtils, Generics.Collections, Safe;

const
  Basis = QWord($CBF29CE484222325);
  Mixed = QWord($CBF29CE4) or $84222325;
  Prime = QWord($100000001B3);

type
  TCounts = specialize TDictionary<String, Integer>;
  TNames = specialize TList<String>;
  TCountsBox = specialize TOwned<TCounts>;
  TNamesBox = specialize TOwned<TNames>;

function Hash(const S: String): QWord;
var
  I: SizeInt;
begin
  Result := QWord($CBF29CE484222325);
  for I := 1 to Length(S) do
    Result := (Result xor Ord(S[I])) * Prime;
  Result := Result xor $84222325 xor Mixed xor Basis;
  Result := QWord($CBF29CE4) and $84222325 or Result;
end;

function Scaled(X: Double): Int64;
begin
  Result := Round(X * 100.0) + Trunc(X);
  Result := Trunc(X) - Round(X);
end;

var
  Counts: TCountsBox;
  Names: TNamesBox;
  N: Integer;
  S: String;
begin
  Counts := TCountsBox.Own(TCounts.Create);
  Names := TNamesBox.Own(TNames.Create);
  Counts.Get.Add('a', 1);
  Counts.Get.AddOrSetValue('b', 2);
  Counts.Get['b'] := Counts.Get['a'] + 1;
  if Counts.Get.TryGetValue('a', N) then
    WriteLn(N);
  Names.Get.Add('a');
  for S in Names.Get do
    WriteLn(S, Hash(S), Scaled(2.5), Counts.Get.Count);
end.
