{ SPDX-License-Identifier: MIT }
{ Better Pascal, ext/utf8: кодировки по умолчанию (секция initialization). }
{$ifndef SAFE_NO_UTF8}
  // Кодировка String по умолчанию (а с ней и всех неявных конверсий).
  DefaultSystemCodePage := CP_UTF8;
  // Имена файлов: на входе в RTL и на выходе (FindFirst, GetCurrentDir...).
  DefaultFileSystemCodePage := CP_UTF8;
  DefaultRTLFileSystemCodePage := CP_UTF8;
  // Консоль и стандартные потоки.
  SetTextCodePage(Input, CP_UTF8);
  SetTextCodePage(Output, CP_UTF8);
  SetTextCodePage(ErrOutput, CP_UTF8);
  SetTextCodePage(StdOut, CP_UTF8);
  SetTextCodePage(StdErr, CP_UTF8);
  {$ifdef windows}
  SetConsoleOutputCP(CP_UTF8);
  SetConsoleCP(CP_UTF8);
  {$endif}
{$endif}
