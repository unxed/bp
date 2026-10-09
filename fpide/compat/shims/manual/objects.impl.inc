procedure Abstract;
begin
  { Same as classic Free Vision Objects.Abstract }
  RunError(211);
end;

function NewStr(const S: ShortString): PString;
begin
  Result := PString(TvUtil.NewStr(S));
end;

procedure DisposeStr(P: PString);
begin
  TvUtil.DisposeStr(TvUtil.PStr(P));
end;

function StrRead(Ip: ipstream): PChar;
var
  L: Word;
begin
  L := 0;
  Ip.ReadBytes(L, SizeOf(L));
  if L = 0 then
    Exit(nil);
  Result := StrAlloc(L + 1);
  Ip.ReadBytes(Result^, L);
  Result[L] := #0;
end;

procedure StrWrite(Os: opstream; P: PChar);
var
  L: Word;
begin
  L := 0;
  if P <> nil then
    L := StrLen(P);
  Os.WriteBytes(L, SizeOf(L));
  if L > 0 then
    Os.WriteBytes(P^, L);
end;

function GetObject(S: TStream): Pointer;
var
  Ip: ipstream;
begin
  Ip := ipstream.Create(S);
  Result := Ip.ReadPointer;
  Ip.Free;
end;

procedure PutObject(S: TStream; P: TStreamable);
var
  Os: opstream;
begin
  Os := opstream.Create(S);
  Os.WritePointer(P);
  Os.Free;
end;
