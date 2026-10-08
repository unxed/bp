{ SPDX-License-Identifier: MIT }
{ Better Pascal, ext/utf8: the default encodings (the initialization section). }
{$ifndef SAFE_NO_UTF8}
  // The default encoding of String (and with it of all implicit conversions).
  DefaultSystemCodePage := CP_UTF8;
  // File names: into the RTL and out of it (FindFirst, GetCurrentDir...).
  DefaultFileSystemCodePage := CP_UTF8;
  DefaultRTLFileSystemCodePage := CP_UTF8;
  // The console and the standard streams.
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
