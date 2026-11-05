// EXPECT: error SAFE-S28
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ A call of a nested routine that writes the String (here through another nested routine) while a view of it lives. }
unit s28_nestedwrite_bad;

{$mode objfpc}{$H+}

interface

uses
  BP;

function Run(const Name: String): SizeInt;

implementation

function Run(const Name: String): SizeInt;
var
  Text: String;
  W: TStrView;

  procedure Refill;
  begin
    Text := Name + '!';
  end;

  procedure Again;
  begin
    Refill;
  end;

begin
  Refill;
  W := StrView(Text);
  Again;
  Result := W.Len;
end;

end.
