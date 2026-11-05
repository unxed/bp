{ SPDX-License-Identifier: MIT }
{ Runtime tests of the strings and maps (safe/map.*.inc, SPEC §25.3): TStrSlice, Fields, TStrView, FieldViews, MapHash,
  TMap<K, V>, R2, R18, R19. Exit code = number of failed checks. }
program test_map;

{$mode objfpc}{$H+}

uses
  SysUtils, Safe;

type
  TCounts = specialize TMap<TStrSlice, Int64>;
  TViewCounts = specialize TMap<TStrView, Int64>;
  TNames = specialize TMap<String, String>;
  TInts = specialize TMap<Int64, Int64>;

var
  Failed: Integer = 0;

procedure Check(const Cond: Boolean; const What: String);
begin
  if Cond then
    WriteLn('ok   ', What)
  else
  begin
    WriteLn('FAIL ', What);
    Inc(Failed);
  end;
end;

function HeapUsed: PtrUInt;
begin
  Result := GetFPCHeapStatus.CurrHeapUsed;
end;

{ ---------- TStrSlice ---------- }

procedure Slices;
var
  S, T: String;
  A, B: TStrSlice;
  I, L: Integer;
  Same: Boolean;
begin
  S := 'hello, world';
  A := TStrSlice.Make(S, 8, 5);
  Check(A.ToString = 'world', 'TStrSlice.Make(S, 8, 5) is "world" (as Copy)');
  Check((A.Len = 5) and (A[1] = 'w') and (A[5] = 'd'), 'TStrSlice: Len and 1-based Items');
  B := A.Sub(2, 3);
  Check(B.ToString = 'orl', 'TStrSlice.Sub(2, 3) of "world" is "orl"');
  Check(A.Equals('world') and not A.Equals('worl'), 'TStrSlice.Equals(S) compares the bytes with a String');
  Check(A = StrSlice(Copy('a world', 3, 5)), 'two slices of different Strings with the same bytes are equal');
  Check(A <> B, 'slices of different bytes are not equal');
  B := StrSlice('world');
  Check(A = B, 'StrSlice(S) is the slice of all of S');
  Check(MapHash(A) = MapHash(String('world')), 'a slice and a String with the same bytes have the same hash');
  Check(MapHash(TStrSlice.Make(S, 1, 0)) = MapHash(String('')), 'an empty slice has the hash of the empty String');
  // the hash reads the last 1-7 bytes of a key as two overlapping words of four or as three bytes, never past the key
  T := 'the quick brown fox jumps over the lazy dog';
  Same := True;
  for I := 1 to Length(T) do
    for L := 0 to 20 do
      if I + L - 1 <= Length(T) then
        Same := Same and (MapHash(TStrSlice.Make(T, I, L)) = MapHash(Copy(T, I, L)))
          and (MapHash(TStrSlice.Make(T, I, L)) = MapHash(StrSlice(Copy(T, I, L))));
  Check(Same, 'every slice of 0 to 20 bytes at every place has the hash of a String of its bytes');
end;

{ a slice holds its String: the bytes stay while the variable it came from changes }
procedure SliceHolds;
var
  S: String;
  A: TStrSlice;
begin
  S := 'abc' + IntToStr(Random(10));
  A := TStrSlice.Make(S, 1, 3);
  S := 'xyz';
  Check(A.ToString = 'abc', 'a slice keeps the bytes of its String after the variable is assigned again');
  S := A.ToString;
  S[1] := 'Z';
  Check(A.ToString = 'abc', 'a write to a copy of the bytes does not change the slice');
end;

procedure SliceR2;
var
  S, Msg: String;
  A: TStrSlice;
  C: Char;
begin
  S := 'abc';
  C := #0;
  Msg := '';
  try
    A := TStrSlice.Make(S, 2, 3);
  except
    on E: ESafety do Msg := E.Message;
  end;
  Check(Pos('SAFE-R2', Msg) > 0, 'R2: TStrSlice.Make past the end raises ESafety');
  A := TStrSlice.Make(S);
  Msg := '';
  try
    C := A[4];
  except
    on E: ESafety do Msg := E.Message;
  end;
  Check(Pos('SAFE-R2', Msg) > 0, 'R2: TStrSlice index past the end raises ESafety');
  Msg := '';
  try
    A := A.Sub(0, 1);
  except
    on E: ESafety do Msg := E.Message;
  end;
  Check((Pos('SAFE-R2', Msg) > 0) and (C = #0), 'R2: TStrSlice.Sub(0, ...) raises ESafety');
end;

{ ---------- Fields ---------- }

procedure FieldsWords;
var
  W: TStrSlice;
  F: TFields;
  Got: String;
  N: Integer;
begin
  Got := '';
  for W in Fields('  one two'#9'three'#10#10'four  ') do
    Got := Got + '[' + W.ToString + ']';
  Check(Got = '[one][two][three][four]', 'Fields: the runs of bytes above the space (' + Got + ')');
  N := 0;
  for W in Fields('   ') do
    Inc(N);
  Check(N = 0, 'Fields of spaces only: no word');
  N := 0;
  F := Fields('a bb ccc');
  Got := '';
  while F.Next(W) do
  begin
    Inc(N);
    Got := Got + W.ToString;
  end;
  Check((N = 3) and (Got = 'abbccc'), 'Fields.Next(W): the same words without a for-in loop');
end;

{ ---------- TStrView ---------- }

procedure Views;
var
  S, T, U: String;
  A, B: TStrView;
  I, L: Integer;
  Same: Boolean;
begin
  S := 'hello world';
  A := StrView(S).Sub(7, 5);
  U := 'a world';
  B := StrView(U).Sub(3, 5);
  Check((A.Len = 5) and (A.ToString = 'world') and (A[1] = 'w') and (A[5] = 'd'), 'TStrView.Sub, Len, ToString, Items');
  Check(A = B, 'two views of different Strings with the same bytes are equal');
  Check(A.Equals('world') and not A.Equals('worlds') and (A <> StrView(S)), 'TStrView.Equals and <>');
  Check(MapHash(A) = MapHash(String('world')), 'a view and a String with the same bytes have the same hash');
  Check(MapHash(StrView(S).Sub(1, 0)) = MapHash(String('')), 'an empty view has the hash of the empty String');
  T := 'the quick brown fox jumps over the lazy dog';
  Same := True;
  for I := 1 to Length(T) do
    for L := 0 to 20 do
      if I + L - 1 <= Length(T) then
        Same := Same and (MapHash(StrView(T).Sub(I, L)) = MapHash(Copy(T, I, L)))
          and (MapHash(StrView(T).Sub(I, L)) = MapHash(TStrSlice.Make(T, I, L)));
  Check(Same, 'every view of 0 to 20 bytes at every place has the hash of a String and of a slice of its bytes');
end;

procedure ViewR2;
var
  S, Msg: String;
  A: TStrView;
  C: Char;
begin
  S := 'abc';
  A := StrView(S);
  C := #0;
  Msg := '';
  try
    C := A[4];
  except
    on E: ESafety do Msg := E.Message;
  end;
  Check(Pos('SAFE-R2', Msg) > 0, 'R2: TStrView index past the end raises ESafety');
  Msg := '';
  try
    A := A.Sub(2, 3);
  except
    on E: ESafety do Msg := E.Message;
  end;
  Check((Pos('SAFE-R2', Msg) > 0) and (C = #0), 'R2: TStrView.Sub past the end raises ESafety');
end;

procedure ViewWords;
var
  Text, Got: String;
  W: TStrView;
  F: TViewFields;
  M: TViewCounts;
  N: Integer;
begin
  Text := '  one two'#9'three'#10#10'two  one two ';
  Got := '';
  for W in FieldViews(Text) do
    Got := Got + '[' + W.ToString + ']';
  Check(Got = '[one][two][three][two][one][two]', 'FieldViews: the runs of bytes above the space (' + Got + ')');
  N := 0;
  F := FieldViews(Text);
  while F.Next(W) do
    Inc(N);
  Check(N = 6, 'FieldViews.Next(W): the same words without a for-in loop');
  for W in FieldViews(Text) do
    Inc(M.Ref(W, 0)^);
  Check((M.Count = 3) and (M[StrView(Text).Sub(7, 3)] = 3) and (M.Get(StrView(Text).Sub(3, 3), 0) = 2),
    'a map of views counts the words');
end;

{ ---------- TMap ---------- }

procedure MapBasics;
var
  M: TNames;
  V: String;
  Msg: String;
begin
  Check(M.Count = 0, 'TMap: a map that was never written is empty');
  Check(not M.TryGet('a', V) and (V = ''), 'TMap.TryGet of an empty map: False and the default value');
  M['one'] := '1';
  M.Put('two', '2');
  M['one'] := 'uno';
  Check((M.Count = 2) and (M['one'] = 'uno') and (M['two'] = '2'), 'TMap: M[K] := V adds or replaces, M[K] reads');
  Check(M.Has('two') and not M.Has('three'), 'TMap.Has');
  Check(M.Get('three', '?') = '?', 'TMap.Get(K, Default) of a missing key is Default');
  Msg := '';
  try
    V := M['three'];
  except
    on E: ESafety do Msg := E.Message;
  end;
  Check(Pos('SAFE-R18', Msg) > 0, 'R18: M[K] of a missing key raises ESafety');
  Check(M.Delete('one') and not M.Delete('one') and (M.Count = 1) and not M.Has('one'), 'TMap.Delete');
  M.Clear;
  Check((M.Count = 0) and not M.Has('two'), 'TMap.Clear');
end;

procedure MapRef;
var
  M: TCounts;
  W: TStrSlice;
  Total: Int64;
begin
  for W in Fields('a b a c a b') do
    Inc(M.Ref(W, 0)^);
  Check((M.Count = 3) and (M[StrSlice('a')] = 3) and (M[StrSlice('b')] = 2) and (M[StrSlice('c')] = 1), 'TMap.Ref(K, 0)^: one lookup per update');
  Total := 0;
  Inc(M.Ref(StrSlice('d'), 10)^, 5);
  Check(M[StrSlice('d')] = 15, 'TMap.Ref of a new key starts from Default');
  Check(Total = 0, 'TMap.Ref: nothing else changes');
end;

{ a copy of a map refers to the same map, as in Go }
procedure MapShared;
var
  A, B: TInts;
begin
  A := TInts.Create;
  B := A;
  B[1] := 100;
  Check((A.Count = 1) and (A[1] = 100), 'TMap: a copy refers to the same map');
end;

{ against a plain array as the reference: puts, deletes and lookups of many keys }
procedure MapMany;
const
  N = 200000;
var
  M: TInts;
  Ref: array of Int64;
  I: Integer;
  K: Int64;
  Ok: Boolean;
  P: TInts.TPair;
  Sum, Seen: Int64;
begin
  SetLength(Ref, N);
  for I := 0 to N - 1 do
    Ref[I] := -1;
  RandSeed := 42;
  for I := 1 to 3 * N do
  begin
    K := Random(N);
    if Random(4) = 0 then
    begin
      Ok := M.Delete(K);
      if Ok <> (Ref[K] >= 0) then
        Break;
      Ref[K] := -1;
    end
    else
    begin
      M[K] := I;
      Ref[K] := I;
    end;
  end;
  Ok := True;
  K := 0;
  for I := 0 to N - 1 do
  begin
    if Ref[I] >= 0 then
    begin
      Inc(K);
      Ok := Ok and M.Has(Int64(I)) and (M[Int64(I)] = Ref[I]);
    end
    else
      Ok := Ok and not M.Has(Int64(I));
  end;
  Check(Ok and (M.Count = K), 'TMap: 600000 random puts and deletes agree with an array (' + IntToStr(K) + ' keys)');
  Sum := 0;
  Seen := 0;
  for P in M do
  begin
    Inc(Seen);
    Sum := Sum + P.Value - Ref[P.Key];
  end;
  Check((Seen = K) and (Sum = 0), 'for P in M: every pair once, with its value');
end;

procedure MapR19;
var
  M: TInts;
  P: TInts.TPair;
  Msg: String;
begin
  M[1] := 1;
  M[2] := 2;
  for P in M do
    M[P.Key] := P.Value * 10;
  Check((M[1] = 10) and (M[2] = 20), 'for P in M: a new value of a key that is there is allowed');
  Msg := '';
  try
    for P in M do
      M[P.Key + 100] := 0;
  except
    on E: ESafety do Msg := E.Message;
  end;
  Check(Pos('SAFE-R19', Msg) > 0, 'R19: a key added while for P in M walks the map raises ESafety');
end;

{ a map of slices holds the text of its keys }
procedure MapHoldsText;
var
  M: TCounts;
  Text: String;
  W: TStrSlice;
begin
  Text := 'red green ' + IntToStr(Random(10));
  for W in Fields(Text) do
    M.Put(W, W.Len);
  Text := '';
  Check(M.Has(StrSlice('red')) and (M[StrSlice('green')] = 5), 'a map of slices keeps their text after the variable is cleared');
end;

var
  H0, H1: PtrUInt;
begin
  WriteLn('test_map');
  H0 := HeapUsed;          // after the first output: the RTL allocates once on it
  Slices;
  SliceHolds;
  SliceR2;
  FieldsWords;
  Views;
  ViewR2;
  ViewWords;
  MapBasics;
  MapRef;
  MapShared;
  MapMany;
  MapR19;
  MapHoldsText;
  H1 := HeapUsed;
  Check(H1 <= H0, 'nothing leaks: the heap is not above where it was (' + IntToStr(H1) + ' against ' + IntToStr(H0)
    + ')');
  WriteLn(Failed, ' failed');
  Halt(Failed);
end.
