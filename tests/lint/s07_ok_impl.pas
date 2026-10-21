// EXPECT: clean
{ S7: the interface does not need Safe, so Safe is the last unit of the implementation uses. }
unit s07_ok_impl;

{$mode objfpc}{$H+}

interface

uses
  Classes;

procedure Fill(const List: TStrings);

implementation

uses
  SysUtils, Safe;

procedure Fill(const List: TStrings);
begin
  List.Add(IntToStr(List.Count));
end;

end.
