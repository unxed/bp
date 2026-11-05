{ SPDX-License-Identifier: MIT }
{ Safe Pascal, strings and maps (implementation): TStrSlice, Fields, TMap<K, V> (SPEC §25.3). Included in unit Safe and
  unit BP after region.impl.inc. }

{ ---------- the hash and the comparison of bytes ---------- }

const
  SafeHashMul = QWord($9E3779B97F4A7C15); // 2^64 divided by the golden ratio, odd

{$push}{$Q-}{$R-} // the hashes multiply modulo 2^64 by design

{ Eight bytes at a time; the slot of a map is the top bits of the result, which the last multiplication mixes. }
function SafeHashBytes(P: System.PByte; N, Avail: SizeInt): QWord;
var
  H, W: QWord;
  I, J: SizeInt;
begin
  H := QWord(N) * SafeHashMul;
  I := 0;
  while I + 8 <= N do
  begin
    // UNSAFE: reads eight bytes of the key at once; P points into a String of at least N bytes
    W := PSafeQWordAt(P + I)^.V;
    H := (H xor W) * SafeHashMul;
    H := H xor (H shr 29);
    Inc(I, 8);
  end;
  if I < N then
  begin
    {$ifdef ENDIAN_LITTLE}
    if Avail - I >= 8 then
      // UNSAFE: eight bytes of the String at once, the ones past the key masked off; Avail bytes from P are its own
      W := PSafeQWordAt(P + I)^.V and (High(QWord) shr (8 * (8 - (N - I))))
    else
    {$endif}
    begin
      W := 0;
      for J := 0 to N - I - 1 do
        W := W or (QWord(P[I + J]) shl (8 * J));
    end;
    H := (H xor W) * SafeHashMul;
    H := H xor (H shr 29);
  end;
  Result := (H * SafeHashMul) or 1;
end;

function SafeSameBytes(P, Q: System.PByte; N: SizeInt): Boolean;
var
  I: SizeInt;
begin
  I := 0;
  while I + 8 <= N do
  begin
    // UNSAFE: compares eight bytes at once; both point into Strings of at least N bytes
    if PSafeQWordAt(P + I)^.V <> PSafeQWordAt(Q + I)^.V then
      Exit(False);
    Inc(I, 8);
  end;
  while I < N do
  begin
    if P[I] <> Q[I] then
      Exit(False);
    Inc(I);
  end;
  Result := True;
end;

function MapHash(const K: TStrSlice): QWord;
begin
  Result := SafeHashBytes(System.PByte(System.Pointer(K.FStr)) + K.FStart, K.FLen, Length(K.FStr) - K.FStart);
end;

function MapHash(const K: String): QWord;
begin
  Result := SafeHashBytes(System.PByte(System.Pointer(K)), Length(K), Length(K));
end;

function MapHash(const K: Int64): QWord;
begin
  Result := (QWord(K) * SafeHashMul) or 1;
end;

function MapHash(const K: QWord): QWord;
begin
  Result := (K * SafeHashMul) or 1;
end;

function MapHash(const K: System.Pointer): QWord;
begin
  Result := (QWord(PtrUInt(K)) * SafeHashMul) or 1;
end;

{$pop}

{ ---------- TStrSlice ---------- }

class function TStrSlice.Make(const S: String): TStrSlice;
begin
  Result.FStr := S;
  Result.FStart := 0;
  Result.FLen := Length(S);
end;

class function TStrSlice.Make(const S: String; AStart, ALen: SizeInt): TStrSlice;
begin
  if (AStart < 1) or (ALen < 0) or (AStart - 1 > Length(S) - ALen) then
    SafeFail(Format('SAFE-R2: TStrSlice.Make(S, %d, %d) out of bounds, length %d', [AStart, ALen, Length(S)]));
  Result.FStr := S;
  Result.FStart := AStart - 1;
  Result.FLen := ALen;
end;

function TStrSlice.Sub(AStart, ALen: SizeInt): TStrSlice;
begin
  if (AStart < 1) or (ALen < 0) or (AStart - 1 > FLen - ALen) then
    SafeFail(Format('SAFE-R2: TStrSlice.Sub(%d, %d) out of bounds, length %d', [AStart, ALen, FLen]));
  Result.FStr := FStr;
  Result.FStart := FStart + AStart - 1;
  Result.FLen := ALen;
end;

function TStrSlice.Len: SizeInt;
begin
  Result := FLen;
end;

function TStrSlice.ToString: String;
begin
  Result := Copy(FStr, FStart + 1, FLen);
end;

function TStrSlice.Data: System.PChar;
begin
  Result := System.PChar(System.Pointer(FStr)) + FStart;
end;

function TStrSlice.GetItem(I: SizeInt): Char;
begin
  if (I < 1) or (I > FLen) then
    SafeFail(Format('SAFE-R2: TStrSlice index %d out of bounds, length %d', [I, FLen]));
  Result := FStr[FStart + I];
end;

class operator TStrSlice.=(const A, B: TStrSlice): Boolean;
begin
  Result := (A.FLen = B.FLen) and SafeSameBytes(System.PByte(System.Pointer(A.FStr)) + A.FStart,
    System.PByte(System.Pointer(B.FStr)) + B.FStart, A.FLen);
end;

function TStrSlice.Equals(const S: String): Boolean;
begin
  Result := (FLen = Length(S)) and SafeSameBytes(System.PByte(System.Pointer(FStr)) + FStart,
    System.PByte(System.Pointer(S)), FLen);
end;

function StrSlice(const S: String): TStrSlice;
begin
  Result := TStrSlice.Make(S);
end;

class operator TStrSlice.<>(const A, B: TStrSlice): Boolean;
begin
  Result := not (A = B);
end;

{ ---------- Fields ---------- }

function Fields(const S: String): TFields;
begin
  Result.FText := S;
  Result.FPos := 0;
  Result.FCur := Default(TStrSlice);
end;

function TFields.GetEnumerator: TFields;
begin
  Result := Self;
end;

function TFields.Next(var W: TStrSlice): Boolean;
var
  P: System.PChar;
  N, I, Start: SizeInt;
begin
  P := System.PChar(System.Pointer(FText));
  N := Length(FText);
  I := FPos;
  while (I < N) and (P[I] <= ' ') do
    Inc(I);
  Start := I;
  while (I < N) and (P[I] > ' ') do
    Inc(I);
  FPos := I;
  Result := I > Start;
  if Result then
  begin
    if System.Pointer(W.FStr) <> System.Pointer(FText) then
      W.FStr := FText;
    W.FStart := Start;
    W.FLen := I - Start;
  end;
end;

function TFields.MoveNext: Boolean;
begin
  Result := Next(FCur);
end;

{ ---------- TMap ---------- }

class function TMap.Create: TMap;
begin
  Result.FD := nil;
  Result.Make;
end;

procedure TMap.Make;
begin
  SetLength(FD, 1);
  FD[0].Count := 0;
  FD[0].Version := 0;
  FD[0].Shift := 64 - 4;
  SetLength(FD[0].Slots, 16);
end;

function TMap.Count: SizeInt;
begin
  if Length(FD) = 0 then
    Result := 0
  else
    Result := FD[0].Count;
end;

{ the slot of Key, or the free slot where it would go }
function TMap.Find(const Key: K; Hash: QWord): SizeInt;
var
  Mask: SizeInt;
begin
  Mask := Length(FD[0].Slots) - 1;
  Result := SizeInt(Hash shr FD[0].Shift);
  while FD[0].Slots[Result].Hash <> 0 do
  begin
    if (FD[0].Slots[Result].Hash = Hash) and (FD[0].Slots[Result].Key = Key) then
      Exit;
    Result := (Result + 1) and Mask;
  end;
end;

procedure TMap.Grow;
var
  Old: array of TEntry;
  I, J, Mask: SizeInt;
begin
  Old := FD[0].Slots;
  FD[0].Slots := nil;
  SetLength(FD[0].Slots, 2 * Length(Old));
  Dec(FD[0].Shift);
  Mask := Length(FD[0].Slots) - 1;
  for I := 0 to High(Old) do
    if Old[I].Hash <> 0 then
    begin
      J := SizeInt(Old[I].Hash shr FD[0].Shift);
      while FD[0].Slots[J].Hash <> 0 do
        J := (J + 1) and Mask;
      FD[0].Slots[J] := Old[I];
    end;
end;

function TMap.Ref(const Key: K; const Default: V): PV;
var
  H: QWord;
  J: SizeInt;
begin
  if Length(FD) = 0 then
    Make;
  H := MapHash(Key);
  J := Find(Key, H);
  if FD[0].Slots[J].Hash = 0 then
  begin
    if 2 * (FD[0].Count + 1) > Length(FD[0].Slots) then
    begin
      Grow;
      J := Find(Key, H);
    end;
    FD[0].Slots[J].Hash := H;
    FD[0].Slots[J].Key := Key;
    FD[0].Slots[J].Value := Default;
    Inc(FD[0].Count);
    Inc(FD[0].Version);
  end;
  Result := @FD[0].Slots[J].Value;
end;

procedure TMap.Put(const Key: K; const Value: V);
var
  H: QWord;
  J: SizeInt;
begin
  if Length(FD) = 0 then
    Make;
  H := MapHash(Key);
  J := Find(Key, H);
  if FD[0].Slots[J].Hash = 0 then
  begin
    if 2 * (FD[0].Count + 1) > Length(FD[0].Slots) then
    begin
      Grow;
      J := Find(Key, H);
    end;
    FD[0].Slots[J].Hash := H;
    FD[0].Slots[J].Key := Key;
    Inc(FD[0].Count);
    Inc(FD[0].Version);
  end;
  FD[0].Slots[J].Value := Value;
end;

procedure TMap.SetItem(const Key: K; const Value: V);
begin
  Put(Key, Value);
end;

function TMap.TryGet(const Key: K; out Value: V): Boolean;
var
  J: SizeInt;
begin
  Result := False;
  Value := Default(V);
  if Length(FD) = 0 then
    Exit;
  J := Find(Key, MapHash(Key));
  if FD[0].Slots[J].Hash <> 0 then
  begin
    Value := FD[0].Slots[J].Value;
    Result := True;
  end;
end;

function TMap.Get(const Key: K; const Default: V): V;
begin
  if not TryGet(Key, Result) then
    Result := Default;
end;

function TMap.GetItem(const Key: K): V;
begin
  if not TryGet(Key, Result) then
    SafeFail('SAFE-R18: TMap: the key is not in the map (Get(K, Default) and TryGet do not raise)');
end;

function TMap.Has(const Key: K): Boolean;
begin
  Result := (Length(FD) > 0) and (FD[0].Slots[Find(Key, MapHash(Key))].Hash <> 0);
end;

{ linear probing deletes by moving back the entries after the hole that may live in it }
function TMap.Delete(const Key: K): Boolean;
var
  I, J, Home, Mask: SizeInt;
begin
  Result := False;
  if Length(FD) = 0 then
    Exit;
  I := Find(Key, MapHash(Key));
  if FD[0].Slots[I].Hash = 0 then
    Exit;
  Mask := Length(FD[0].Slots) - 1;
  J := I;
  while True do
  begin
    J := (J + 1) and Mask;
    if FD[0].Slots[J].Hash = 0 then
      Break;
    Home := SizeInt(FD[0].Slots[J].Hash shr FD[0].Shift);
    // the entry at J may move to the hole at I when its home is not in the cyclic range (I, J]
    if ((J > I) and ((Home <= I) or (Home > J))) or ((J < I) and (Home <= I) and (Home > J)) then
    begin
      FD[0].Slots[I] := FD[0].Slots[J];
      I := J;
    end;
  end;
  FD[0].Slots[I] := Default(TEntry);
  Dec(FD[0].Count);
  Inc(FD[0].Version);
  Result := True;
end;

procedure TMap.Clear;
var
  N: SizeInt;
begin
  if Length(FD) = 0 then
    Exit;
  N := FD[0].Version;
  FD[0].Slots := nil;
  Make;
  FD[0].Version := N + 1;
end;

function TMap.GetEnumerator: TEnum;
begin
  Result.FD := FD;
  Result.FI := -1;
  if Length(FD) > 0 then
    Result.FVersion := FD[0].Version
  else
    Result.FVersion := 0;
end;

function TMap.TEnum.MoveNext: Boolean;
begin
  if Length(FD) = 0 then
    Exit(False);
  if FD[0].Version <> FVersion then
    SafeFail('SAFE-R19: TMap: a key was added or deleted while for-in walks the map');
  repeat
    Inc(FI);
  until (FI > High(FD[0].Slots)) or (FD[0].Slots[FI].Hash <> 0);
  Result := FI <= High(FD[0].Slots);
end;

function TMap.TEnum.GetCurrent: TPair;
begin
  Result.Key := FD[0].Slots[FI].Key;
  Result.Value := FD[0].Slots[FI].Value;
end;
