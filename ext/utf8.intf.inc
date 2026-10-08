{ SPDX-License-Identifier: MIT }
{ Better Pascal, ext/utf8: UTF-8 by default (interface). }
type
  { ---------- UTF-8 ---------- }

  { An enumerator of characters (code points). Current: one character as a String. }
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
{ The length in characters (code points), not in bytes. }
function CPLength(const S: string): SizeInt;
