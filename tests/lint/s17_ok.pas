// EXPECT: clean
// ARGS: --typed --rtl @rtl@ -Fu@root@/tools/spikes/region -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S17: the examples of safe/SPEC.md §20 and the forms of the region style that are proven. }
unit s17_ok;

{$mode objfpc}{$H+}

interface

uses
  Region, Safe;

type
  TFields = class(TRegionObject)
    Key, Value: String;
    Next: TFields;
  end;
  TList = specialize TGrowArray<TFields>;

function ParseLine(const S: String): TFields;
procedure ProcessFile(const Lines: array of String);
procedure Link(const Head: TFields);
function Build(const N: Integer): TList;
procedure Local;

implementation

procedure Emit(const K, V: String);
begin
  WriteLn(K, '=', V);
end;

function ParseLine(const S: String): TFields;  // no region here: the result lives in the caller's region
begin
  Result := TFields.Create;
  Result.Key := S;
  Result.Value := S;
end;

procedure ProcessFile(const Lines: array of String);
var
  Scratch: TRegion;
  Fields: TFields;
  Line: String;
begin
  Scratch := TRegion.Create;
  for Line in Lines do
  begin
    Fields := ParseLine(Line);  // allocated in Scratch, rooted in Scratch
    Emit(Fields.Key, Fields.Value);
    Scratch.Reset;
  end;
end;

procedure Link(const Head: TFields);
begin
  Head.Next := Head;
end;

function Build(const N: Integer): TList;
var
  I: Integer;
begin
  Result := TList.Create;
  for I := 1 to N do
    Result.Push(ParseLine('x'));
end;

procedure Local;
var
  R, Inner: TRegion;
  L: TList;
  F: TFields;
begin
  R := TRegion.Create;
  L := Build(3);
  F := TFields.Create;
  L.Push(F);
  L[0].Key := 'a';
  Inner := TRegion.Create;
  F := TFields.Create;
  F.Next := L[0];  // an inner object refers to an outer one
  Emit(F.Next.Key, L[1].Key);
  Inner.Release;
  R.Reset;
  F := ParseLine('b');
  Emit(F.Key, F.Value);
end;

end.
