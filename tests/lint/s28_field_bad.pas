// EXPECT: error SAFE-S28
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ A view stored into a field of an object: the object outlives the routine and its String. }
unit s28_field_bad;

{$mode objfpc}{$H+}

interface

uses
  BP;

type
  TDoc = class
  public
    First: TStrView;
  end;

procedure Run(const D: TDoc; const Text: String);

implementation

procedure Run(const D: TDoc; const Text: String);
begin
  D.First := StrView(Text);
end;

end.
