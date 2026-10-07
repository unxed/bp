{ SPDX-License-Identifier: MIT }
{ Better Pascal, ext/utf8: UTF-8 по умолчанию (интерфейс). }
type
  { ---------- UTF-8 ---------- }

  { Перечислитель символов (code points). Current: один символ как String. }
  TCodePointEnumerator = record
  private
    FS: RawByteString;
    FPos, FLen: SizeInt;
    function GetCurrent: string;
  public
    function GetEnumerator: TCodePointEnumerator;
    function MoveNext: Boolean;
    property Current: string read GetCurrent;
  end;

{ for Ch in CodePoints('aё😀') do ...  // 'a', 'ё', '😀' }
function CodePoints(const S: string): TCodePointEnumerator;
{ Длина в символах (code points), а не в байтах. }
function CPLength(const S: string): SizeInt;
