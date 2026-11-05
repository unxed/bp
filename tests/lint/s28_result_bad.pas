// EXPECT: error SAFE-S28
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ An exported function returns a view of one of two Strings, and no // root: mark says which. }
unit s28_result_bad;

{$mode objfpc}{$H+}

interface

uses
  BP;

function Run(const A, B: String): TStrView;

implementation

function Run(const A, B: String): TStrView;
begin
  if Length(A) > Length(B) then
    Result := StrView(A)
  else
    Result := StrView(A).Sub(1, 0);
end;

end.
