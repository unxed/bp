// EXPECT: error SAFE-S20
{ S20: no header; bpvet --fix writes "program s20_none_bad;" here. }
{$mode objfpc}{$H+}

uses
  Safe;

begin
end.
