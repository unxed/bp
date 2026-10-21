// EXPECT: error SAFE-S8
{ S8: System.Move bypasses the poisoning of Safe without a // UNSAFE: mark. The file breaks S8 only: one finding. }
unit s08_bad;

{$mode objfpc}{$H+}

interface

uses
  Safe;

procedure CopyBytes(const Source: array of Byte; var Dest: array of Byte);

implementation

procedure CopyBytes(const Source: array of Byte; var Dest: array of Byte);
begin
  if Length(Source) > 0 then
    System.Move(Source[0], Dest[0], Length(Source));
end;

end.
