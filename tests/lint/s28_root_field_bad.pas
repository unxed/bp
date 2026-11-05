// EXPECT: error SAFE-S28
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ The String of a view is a field: the object may change it behind an alias. }
unit s28_root_field_bad;

{$mode objfpc}{$H+}

interface

uses
  BP;

type
  TDoc = class
  public
    Text: String;
  end;

function Run(const D: TDoc): SizeInt;

implementation

function Run(const D: TDoc): SizeInt;
var
  W: TStrView;
begin
  W := StrView(D.Text);
  Result := W.Len;
end;

end.
