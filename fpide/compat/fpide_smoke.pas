{ Smoke: FV names via shims resolve and link against tv3. }
{$mode objfpc}{$H-}
program fpide_smoke;

uses
  Objects, Drivers, Views, App, Menus, Dialogs, MsgBox, TvScreen;

begin
  if TScreen.ScreenWidth < 0 then
    Halt(1);
  WriteLn('fpide-smoke: shims+tv3 OK');
end.
