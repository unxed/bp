// EXPECT: clean
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ Ref of a TMap dereferenced at once: one lookup per update. }
unit s27_ok;

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
  W: TStrSlice;
begin
  for W in Fields(Text) do
    Inc(Counts.Ref(W, 0)^);
  Result := Counts.Ref(StrSlice('x'), 7)^ + Counts.Count;
end;

end.
