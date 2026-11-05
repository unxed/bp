// EXPECT: error SAFE-S28
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ In a loop, the String is written while the view of the last round is still read after it. }
unit s28_loop_later_bad;

{$mode objfpc}{$H+}

interface

uses
  BP;

function Run(const Name: String): SizeInt;

implementation

function Run(const Name: String): SizeInt;
var
  Line: String;
  Prev: TStrView;
  I: Integer;
begin
  Result := 0;
  Prev := StrView('');
  for I := 1 to 3 do
  begin
    Line := Name + ' x';
    Inc(Result, Prev.Len);
    Prev := StrView(Line);
  end;
end;

end.
