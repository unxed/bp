// EXPECT: clean
{ S6: a new object given at once to Hold of a scope or a region is owned by it (safe/SPEC.md section 21.1); the typed
  mode checks the rest of the call (tests/lint/hold_*.pas). }
unit s06_hold_ok;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Safe;

type
  TNode = class
  public
    N: Integer;
    constructor Create(const AN: Integer);
  end;

procedure Run;

implementation

constructor TNode.Create(const AN: Integer);
begin
  inherited Create;
  N := AN;
end;

procedure Run;
var
  S: TScopeRef;
  Lines: TStringList;
  Node: TNode;
begin
  for S in Scope do
  begin
    S.Hold(Lines, TStringList.Create);
    S.Hold(Node, TNode.Create(Length(IntToStr(Lines.Count))));
    Lines.Add(IntToStr(Node.N));
  end;
end;

end.
