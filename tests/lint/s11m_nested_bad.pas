// EXPECT: error SAFE-S11m
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S11m: a nested routine still reads the local that was sent. }
unit s11m_nested_bad;

{$mode objfpc}{$H+}

interface

uses
  BP;

type
  TInts = array of Integer;
  TIntsChan = specialize TChan<TInts>;

function Fill(const Ch: TIntsChan): Integer;

implementation

function Fill(const Ch: TIntsChan): Integer;
var
  A: TInts;

  function Total: Integer;
  var
    I: Integer;
  begin
    Result := 0;
    for I := 0 to High(A) do
      Result := Result + A[I];
  end;

begin
  SetLength(A, 2);
  Ch.Send(A);
  Result := Total;
end;

end.
