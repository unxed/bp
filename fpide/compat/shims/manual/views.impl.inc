{ What the program calls differently from tv/ (the implementation part of the unit Views). }

function CommandSetOf(const Commands: TCommandBytes): TCommandSet;
var
  C: Byte;
begin
  Result := Default(TCommandSet);
  for C in Commands do
    Result := Result + C;
end;

function MakePalette(const S: ShortString): TPalette;
begin
  Result := TPalette.Create(PChar(@S[1]), Length(S));
end;

function PaletteSize(const P: TPalette): Integer;
begin
  Result := Length(P.Data) - 1;
  if Result < 0 then
    Result := 0;
end;
