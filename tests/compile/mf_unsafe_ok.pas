// EXPECT: clean
program mf_unsafe_ok;
{$mode objfpc}{$H+}
uses SysUtils, Safe;
var
  P: System.Pointer;
  O: TObject;
begin
  // UNSAFE: P выделен и освобождён здесь же
  System.GetMem(P, 16);
  System.FillChar(P^, 16, 0);
  System.FreeMem(P);
  O := TObject.Create;
  // UNSAFE: O создан строкой выше, больше ссылок нет
  SysUtils.FreeAndNil(O);
end.
