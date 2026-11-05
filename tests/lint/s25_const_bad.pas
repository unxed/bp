// EXPECT: error SAFE-S25
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S25: a const parameter without a type, in a method. }
unit s25_const_bad;

{$mode objfpc}{$H+}

interface

uses
  Safe;

type
  TSink = class
  public
    procedure Take(const Data; N: Integer);
  end;

implementation

procedure TSink.Take(const Data; N: Integer);
begin
  if N < 0 then
    N := 0;
end;

end.
