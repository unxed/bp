{ What the program calls differently from tv/ (the implementation part of the unit Views). }

function CommandSetOf(const Commands: TCommandBytes): TCommandSet;
var
  C: Byte;
begin
  Result := Default(TCommandSet);
  for C in Commands do
    Result := Result + C;
end;
