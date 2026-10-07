// EXPECT: exit 211
{ BP не первым в uses программы (SysUtils раньше): менеджер потоков опоздал, и первая горутина
  останавливается с объяснением (код 211), а не даёт тихую гонку. Только Linux в переносимом режиме. }
program mf_threads_order;
{$mode objfpc}{$H+}
uses SysUtils, BP;
procedure Nop; begin end;
var G: TGroup;
begin
  G := TGroup.Create;
  G.Go(@Nop);
  G.Wait;
end.
