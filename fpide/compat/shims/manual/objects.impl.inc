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
