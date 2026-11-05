// EXPECT: error SAFE-S28
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ A // root: function returns a view of a String that its mark does not name. }
unit s28_mark_bad;

{$mode objfpc}{$H+}

interface

uses
  BP;

function Run(const A, B: String): TStrView;  // root: A

implementation

function Run(const A, B: String): TStrView;  // root: A
begin
  if Length(A) > 0 then
    Result := StrView(A)
  else
    Result := StrView(B);
end;

end.
