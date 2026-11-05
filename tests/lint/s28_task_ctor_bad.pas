// EXPECT: error SAFE-S28
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ A view passed to the constructor of a task, which may run after the routine returns. }
unit s28_task_ctor_bad;

{$mode objfpc}{$H+}

interface

uses
  BP;

type
  TCount = class(TTask)
  public
    N: SizeInt;
    constructor Create(const W: TStrView);
  end;

procedure Run(const Text: String);

implementation

constructor TCount.Create(const W: TStrView);
begin
  inherited Create;
  N := W.Len;
end;

procedure Run(const Text: String);
var
  T: specialize TOwned<TCount>;
begin
  T := specialize TOwned<TCount>.Own(TCount.Create(StrView(Text)));
  T.Get.N := 0;
end;

end.
