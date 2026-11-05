// EXPECT: error SAFE-S24
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S24: a cast from TObject to a class is a downcast too (the usual `Sender`). }
unit s24_object_bad;

{$mode objfpc}{$H+}

interface

uses
  Safe;

type
  TButton = class
  public
    Tag: Integer;
  end;

function TagOf(Sender: TObject): Integer;

implementation

function TagOf(Sender: TObject): Integer;
begin
  Result := TButton(Sender).Tag;
end;

end.
