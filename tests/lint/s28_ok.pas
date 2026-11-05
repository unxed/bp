// EXPECT: clean
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ Views of a String (TStrView) that stay in the locals of the routine of their String. }
unit s28_ok;

{$mode objfpc}{$H+}

interface

uses
  Safe;

type
  TWords = class
  public
    Longest: String;
    procedure Keep(const W: TStrView);
  end;

function Count(const Name: String): SizeInt;
function Longest(const Text: String): SizeInt;
function FirstWord(const S: String): TStrView;  // root: S
function Run(const Text: String): SizeInt;
function AfterUse(const Name: String): SizeInt;
function PerRound(const Name: String): SizeInt;
function Refilled(const Name: String): SizeInt;

implementation

type
  TCounts = specialize TMap<TStrView, Int64>;
  TWordsBox = specialize TOwned<TWords>;

  TSpan = record
    Word: TStrView;
    Index: SizeInt;
  end;

function ReadText(const Name: String): String;
begin
  Result := Name + ' a b a';
end;

{ the word count: the text is written before the first view }
function Count(const Name: String): SizeInt;
var
  Text: String;
  W: TStrView;
  M: TCounts;
  P: TCounts.TPair;
begin
  Text := ReadText(Name);
  for W in FieldViews(Text) do
    Inc(M.Ref(W, 0)^);
  Result := 0;
  for P in M do
    if P.Value > Result then
      Result := P.Value;
end;

function Len(const W: TStrView): SizeInt;
begin
  Result := W.Len;
end;

{ a view goes down as a const parameter; a copy (ToString) is kept in a field }
procedure TWords.Keep(const W: TStrView);
begin
  if W.Len > Length(Longest) then
    Longest := W.ToString;
end;

function Longest(const Text: String): SizeInt;
var
  W: TStrView;
  Words: TWordsBox;
  Spans: array of TSpan;
begin
  Words := TWordsBox.Own(TWords.Create);
  SetLength(Spans, 0);
  for W in FieldViews(Text) do
  begin
    Words.Get.Keep(W);
    SetLength(Spans, Length(Spans) + 1);
    Spans[High(Spans)].Word := W.Sub(1, 1);
    Spans[High(Spans)].Index := Len(W);
  end;
  Result := Length(Words.Get.Longest) + Length(Spans);
end;

{ a function that returns a view names its String }
function FirstWord(const S: String): TStrView;  // root: S
var
  F: TViewFields;
begin
  F := FieldViews(S);
  Result := StrView('');
  if not F.Next(Result) then
    Result := StrView(S).Sub(1, 0);
end;

function Run(const Text: String): SizeInt;
var
  Line: String;
  W, V: TStrView;
begin
  Line := Text + ' tail';
  W := FirstWord(Line);
  V := StrView(Line);
  Result := W.Len + V.Len;
  if W.Equals('tail') or (W = V) then
    Inc(Result);
  Result := Result + Count('x') + Longest(Line);
end;

{ the String is written after the last use of its views: no view of the old bytes is read again }
function AfterUse(const Name: String): SizeInt;
var
  Text: String;
  W: TStrView;
begin
  Text := Name;
  W := StrView(Text);
  Result := W.Len;
  Text := 'other';
  W := StrView(Text);
  Result := Result + W.Len;
end;

{ in a loop: the views of one round are not used in the next one }
function PerRound(const Name: String): SizeInt;
var
  Line: String;
  W: TStrView;
  I: Integer;
begin
  Result := 0;
  for I := 1 to 3 do
  begin
    Line := Name + ' x';
    for W in FieldViews(Line) do
      Inc(Result, W.Len);
  end;
end;

{ a nested routine that writes the String is called before the first view, and after the last use }
function Refilled(const Name: String): SizeInt;
var
  Text: String;
  W: TStrView;

  procedure Refill;
  begin
    Text := Name + '!';
  end;

begin
  Refill;
  W := StrView(Text);
  Result := W.Len;
  Refill;
end;

function Marked(const Name: String): SizeInt;
var
  Text: String;
  W: TStrView;
begin
  Text := Name;
  W := StrView(Text);
  Text := 'x'; // UNSAFE: W is read below only for its length, which a test of the mark does not care about
  Result := W.Len;
end;

{ one String parameter: the // root: mark is elided }
function Head(const S: String): TStrView;
begin
  Result := StrView(S).Sub(1, 1);
end;

{ two candidates in the implementation: the root of the result (A) is inferred from the body }
function Pick(const A, B: String): TStrView;
begin
  if Length(B) > 0 then
    Result := StrView(A)
  else
    Result := StrView(A).Sub(1, 0);
end;

function Roots(const X, Y: String): SizeInt;
var
  First, Second: String;
  W: TStrView;
begin
  First := X;
  Second := Y;
  W := Pick(First, Second);
  Second := 'b';
  Result := W.Len + Head(First).Len + Length(Second);
end;

end.
