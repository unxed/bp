// EXPECT: error SAFE-S11m
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S11m: a dynamic array passed by value is still the array of the caller. }
unit s11m_valparam_bad;

{$mode objfpc}{$H+}

interface

uses
  BP;

type
  TInts = array of Integer;
  TIntsChan = specialize TChan<TInts>;

// UNSAFE: a dynamic array by value (S14) is the case of this test
procedure Pass(const Ch: TIntsChan; Src: TInts);

implementation

// UNSAFE: a dynamic array by value (S14) is the case of this test
procedure Pass(const Ch: TIntsChan; Src: TInts);
begin
  Ch.Send(Src);
end;

end.
