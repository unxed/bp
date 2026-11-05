// EXPECT: error SAFE-S28
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ A nested routine that reads a view is passed as a procedure value: it may run after the routine returns. }
unit s28_nested_bad;

{$mode objfpc}{$H+}{$modeswitch nestedprocvars}

interface

uses
  BP;

type
  TProc = procedure is nested;

procedure Run(const Text: String);

implementation

procedure Call(const P: TProc);
begin
  P();
end;

procedure Run(const Text: String);
var
  W: TStrView;
  N: SizeInt;

  procedure Measure;
  begin
    N := W.Len;
  end;

begin
  W := StrView(Text);
  N := 0;
  Call(@Measure);
end;

end.
