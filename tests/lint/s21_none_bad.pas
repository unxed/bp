// EXPECT: error SAFE-S21
{ S21: no header; bpvet --fix writes "program s21_none_bad;" here. }
{$mode objfpc}{$H+}

uses
  Safe;

begin
end.
