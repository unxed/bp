// EXPECT: fatal Can't access private member FObj
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ FPC lets a helper read the private fields of the type it extends, also in another unit: this helper reads FObj of a
  TOwned and skips the check of Get (R1), or could clear FLife and end the ownership. The resolver of the typed mode
  does not: it stops with this message, so tools/bp build does not compile the module. The file is named mf_ so that
  tests/typed.sh expects it not to resolve; tests/lint.sh checks the message. }
unit mf_helper_private;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Safe;

type
  TNode = class
  public
    X: Integer;
  end;

  TNodeBox = specialize TOwned<TNode>;

  TBoxHelper = record helper for TNodeBox
    function Raw: TNode;
  end;

implementation

function TBoxHelper.Raw: TNode;
begin
  Result := FObj;
end;

end.
