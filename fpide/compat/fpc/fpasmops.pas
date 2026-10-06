{ The mnemonics of the x86-64 instructions (AT&T names), for the reserved words of the editor's
  assembler highlighting. In the original IDE they come from the compiler's itcpugas/cpubase units;
  the table x8664att.inc is the compiler's own (release_3_2_2, compiler/x86_64, GPL-2 or later). }
unit FPAsmOps;

{$mode objfpc}

interface

{ AsmOpName(0..AsmOpCount-1) }
function AsmOpCount: integer;
function AsmOpName(Index: integer): string;

implementation

const
  Ops: array[0..1108] of string[16] =  { 1109 names: the compiler fails here if the table changes }
    {$i x8664att.inc}

function AsmOpCount: integer;
begin
  AsmOpCount:=High(Ops);    { 'none' is not a word }
end;

function AsmOpName(Index: integer): string;
begin
  if (Index>=0) and (Index<High(Ops)) then
    AsmOpName:=Ops[Index+1]
  else
    AsmOpName:='';
end;

end.
