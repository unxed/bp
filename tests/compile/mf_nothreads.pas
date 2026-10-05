// EXPECT: run
{ Без cthreads: Go должен дать ESafety R8, а не runerror. run.sh ещё и запускает этот файл. }
program mf_nothreads;
{$mode objfpc}{$H+}
uses SysUtils, Safe;
procedure Nop; begin end;
var G: TGroup;
begin
  G := TGroup.Create;
  try
    G.Go(@Nop);
    Halt(1);
  except
    on E: ESafety do if Pos('SAFE-R8', E.Message) > 0 then Halt(0) else Halt(2);
  end;
end.
