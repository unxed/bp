// EXPECT: error SAFE-S28
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ The root of Pick is inferred from its body (A): A is not written while the view lives. }
unit s28_infer_bad;

{$mode objfpc}{$H+}

interface

uses
  BP;

function Run(const X, Y: String): SizeInt;

implementation

function Pick(const A, B: String): TStrView;
begin
  if Length(B) > 0 then
    Result := StrView(A)
  else
    Result := StrView(A).Sub(1, 0);
end;

function Run(const X, Y: String): SizeInt;
var
  First, Second: String;
  W: TStrView;
begin
  First := X;
  Second := Y;
  W := Pick(First, Second);
  Second := 'b';
  First := 'a';
  Result := W.Len + Length(First) + Length(Second);
end;

end.
