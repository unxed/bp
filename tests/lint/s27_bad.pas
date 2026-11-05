// EXPECT: error SAFE-S27
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ Ref of a TMap kept in a variable: the next change of the map may move the place. }
unit s27_bad;

{$mode objfpc}{$H+}

interface

uses
  Safe;

function Run(const Text: String): SizeInt;

implementation

type
  TCounts = specialize TMap<TStrSlice, Int64>;

function Run(const Text: String): SizeInt;
var
  Counts: TCounts;
  P: TCounts.PV;
begin
  P := Counts.Ref(StrSlice(Text), 0);
  Inc(P^);
  Result := Counts.Count;
end;

end.
