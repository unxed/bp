{ SPDX-License-Identifier: MIT }
{ bpvet core: findings and their output in the format of FPC messages, reading a source, parsing it with fcl-passrc.
  The rules live in bpvetrules.pas, the command line in bpvet.pas (safe/SPEC.md §6). }
unit BpvetCore;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, PasTree, PParser, PScanner, Safe;

type
  { vsFatal: the file could not be read or parsed, so no rule was checked in it }
  TVetSeverity = (vsWarning, vsError, vsFatal);

  { How findings are printed and what fails the run (the migration modes of safe/SPEC.md §6):
      vmDefault  errors fail (exit code 1), warnings are printed;
      vmReport   every finding is printed as a warning and nothing fails (permissive: the list for a migration);
      vmStrict   warnings are errors too (strict). }
  TVetMode = (vmDefault, vmReport, vmStrict);

  TVetFinding = record
    FileName: String;
    Row, Col: Integer;
    Severity: TVetSeverity;
    Rule: String;   // 'S7'; empty for a fatal
    Msg: String;    // one line: what is wrong and how to fix it
  end;

  TVetReport = record
    Findings: array of TVetFinding;
  end;

  { A source file as text: the rules take columns and comments from it. Lines[0] is line 1. }
  TVetSource = record
    FileName: String;
    Lines: array of String;
  end;

procedure VetAdd(var Report: TVetReport; const AFileName: String; const ARow, ACol: Integer;
  const ASeverity: TVetSeverity; const ARule, AMsg: String);
function VetReadSource(const AFileName: String; out Src: TVetSource; out Err: String): Boolean;
{ The parsed module, or nil: then a fatal with the position of the parse error is in Report.
  The caller releases the module with Release (the tree of fcl-passrc counts references). }
function VetParse(const Src: TVetSource; const Defines, IncludeDirs: array of String;
  var Report: TVetReport): TPasModule;
{ Line ARow (1-based) of the source, '' outside it. }
function VetLine(const Src: TVetSource; const ARow: Integer): String;
{ The 1-based column of the identifier Word in Line (a whole word, any letter case); 1 when it is not there. }
function VetWordColumn(const Line, Word: String): Integer;
{ Prints the findings in the given mode and counts them by the severity they were printed with. }
procedure VetPrint(const Report: TVetReport; const Mode: TVetMode; var Errors, Warnings, Fatals: Integer);

implementation

type
  { The tree container of fcl-passrc. bpvet resolves no names: every element is created as it is, and FindElement
    finds nothing, so the parser keeps the references unresolved (no other unit is read). }
  TVetEngine = class(TPasTreeContainer)
  public
    function CreateElement(AClass: TPTreeElement; const AName: String; AParent: TPasElement;
      const AVisibility: TPasMemberVisibility; const ASourceFilename: String;
      const ASourceLinenumber: Integer): TPasElement;
      overload; override;
    function FindElement(const AName: String): TPasElement; override;
  end;

  { fcl-passrc 3.2.2 stops with a Fatal on the procedure directive nostackframe, which FPC accepts on an assembler
    routine (ext/bpthreads.pas). The parser reads every file and include file through this reader, and the reader
    blanks "nostackframe;" with spaces, so the rest of the module is parsed and checked and rows and columns stay
    those of the file. The rules read the text of the file itself (TVetSource), not this one. }
  TVetLineReader = class(TFileLineReader)
  public
    function ReadLine: String; override;
  end;

  TVetFileResolver = class(TFileResolver)
  protected
    function CreateFileReader(const AFileName: String): TLineReader; override;
  public
    function FindIncludeFile(const AName: String): TLineReader; override;
  end;

  TEngineBox = specialize TOwned<TVetEngine>;
  TLinesBox = specialize TOwned<TStringList>;

const
  { the directive that fcl-passrc 3.2.2 does not parse (see TVetLineReader) }
  UnparsedDirective = 'nostackframe';
  SeverityWord: array[TVetSeverity] of String = ('Warning', 'Error', 'Fatal');

function TVetEngine.CreateElement(AClass: TPTreeElement; const AName: String; AParent: TPasElement;
  const AVisibility: TPasMemberVisibility; const ASourceFilename: String;
  const ASourceLinenumber: Integer): TPasElement;
begin
  // UNSAFE: the element goes into the tree of fcl-passrc, which counts references to it and frees it by Release
  Result := AClass.Create(AName, AParent);
  Result.Visibility := AVisibility;
  Result.SourceFilename := ASourceFilename;
  Result.SourceLinenumber := ASourceLinenumber;
end;

function TVetEngine.FindElement(const AName: String): TPasElement;
begin
  Result := nil;
end;

procedure VetAdd(var Report: TVetReport; const AFileName: String; const ARow, ACol: Integer;
  const ASeverity: TVetSeverity; const ARule, AMsg: String);
var
  N: Integer;
begin
  N := Length(Report.Findings);
  SetLength(Report.Findings, N + 1);
  Report.Findings[N].FileName := AFileName;
  Report.Findings[N].Row := ARow;
  Report.Findings[N].Col := ACol;
  Report.Findings[N].Severity := ASeverity;
  Report.Findings[N].Rule := ARule;
  Report.Findings[N].Msg := AMsg;
end;

function VetReadSource(const AFileName: String; out Src: TVetSource; out Err: String): Boolean;
var
  L: TLinesBox;
  I: Integer;
begin
  Src.FileName := AFileName;
  Src.Lines := nil;
  Err := '';
  L := TLinesBox.Own(TStringList.Create);
  try
    L.Get.LoadFromFile(AFileName);
  except
    on E: Exception do
    begin
      Err := E.Message;
      Exit(False);
    end;
  end;
  SetLength(Src.Lines, L.Get.Count);
  for I := 0 to L.Get.Count - 1 do
    Src.Lines[I] := L.Get[I];
  Result := True;
end;

function VetParse(const Src: TVetSource; const Defines, IncludeDirs: array of String;
  var Report: TVetReport): TPasModule;
var
  Engine: TEngineBox;
  Args: array of String;
  I, N: Integer;
  Where: String;
begin
  Result := nil;
  Engine := TEngineBox.Own(TVetEngine.Create);
  SetLength(Args, Length(Defines) + Length(IncludeDirs) + 1);
  N := 0;
  for I := 0 to High(Defines) do
  begin
    Args[N] := '-d' + Defines[I];
    Inc(N);
  end;
  for I := 0 to High(IncludeDirs) do
  begin
    Args[N] := '-Fi' + IncludeDirs[I];
    Inc(N);
  end;
  Args[N] := Src.FileName;
  DefaultFileResolverClass := TVetFileResolver;
  try
    Result := ParseSource(Engine.Get, Args, 'linux', 'x86_64', []);
  except
    on E: EParserError do
    begin
      Where := E.Filename;
      if Where = '' then
        Where := Src.FileName;
      VetAdd(Report, Where, E.Row, E.Column, vsFatal, '', 'bpvet cannot parse this file: ' + E.Message);
    end;
    on E: Exception do
      VetAdd(Report, Src.FileName, 1, 1, vsFatal, '', 'bpvet cannot parse this file: ' + E.Message);
  end;
end;

function VetLine(const Src: TVetSource; const ARow: Integer): String;
begin
  if (ARow >= 1) and (ARow <= Length(Src.Lines)) then
    Result := Src.Lines[ARow - 1]
  else
    Result := '';
end;

function IsIdentChar(const C: Char): Boolean;
begin
  Result := C in ['A'..'Z', 'a'..'z', '0'..'9', '_'];
end;

{ Line with every UnparsedDirective that is a whole word followed by a semicolon (blanks between them allowed)
  replaced by spaces, the semicolon too; the length of the line stays. }
function BlankUnparsedDirective(const Line: String): String;
var
  L: String;
  P, K, I, N: Integer;
begin
  Result := Line;
  L := LowerCase(Line);
  N := Length(UnparsedDirective);
  P := 1;
  while P <= Length(L) - N + 1 do
  begin
    if (Copy(L, P, N) = UnparsedDirective)
      and ((P = 1) or not IsIdentChar(L[P - 1]))
      and ((P + N > Length(L)) or not IsIdentChar(L[P + N])) then
    begin
      K := P + N;
      while (K <= Length(L)) and (L[K] in [' ', #9]) do
        Inc(K);
      if (K <= Length(L)) and (L[K] = ';') then
      begin
        for I := P to K do
          Result[I] := ' ';
        P := K + 1;
        Continue;
      end;
    end;
    Inc(P);
  end;
end;

function TVetLineReader.ReadLine: String;
var
  S: String;
begin
  S := inherited ReadLine;
  Result := BlankUnparsedDirective(S);
end;

function TVetFileResolver.CreateFileReader(const AFileName: String): TLineReader;
begin
  // UNSAFE: the reader goes to the scanner of fcl-passrc, which frees it when the file is read
  Result := TVetLineReader.Create(AFileName);
end;

function TVetFileResolver.FindIncludeFile(const AName: String): TLineReader;
var
  FN: String;
begin
  Result := nil;
  FN := FindIncludeFileName(AName);
  if FN <> '' then
    try
      // UNSAFE: the reader goes to the scanner of fcl-passrc, which frees it when the file is read
      Result := TVetLineReader.Create(FN);
    except
      Result := nil;
    end;
end;

function VetWordColumn(const Line, Word: String): Integer;
var
  U, W: String;
  P, Last: Integer;
begin
  Result := 1;
  U := UpperCase(Line);
  W := UpperCase(Word);
  if W = '' then
    Exit;
  Last := Length(U) - Length(W) + 1;
  for P := 1 to Last do
    if (Copy(U, P, Length(W)) = W)
      and ((P = 1) or not IsIdentChar(U[P - 1]))
      and ((P + Length(W) > Length(U)) or not IsIdentChar(U[P + Length(W)])) then
      Exit(P);
end;

procedure VetPrint(const Report: TVetReport; const Mode: TVetMode; var Errors, Warnings, Fatals: Integer);
var
  I: Integer;
  Sev: TVetSeverity;
  F: TVetFinding;
begin
  for I := 0 to High(Report.Findings) do
  begin
    Sev := Report.Findings[I].Severity;
    if Sev <> vsFatal then
      case Mode of
        vmDefault: ;
        vmReport: Sev := vsWarning;
        vmStrict: Sev := vsError;
      end;
    case Sev of
      vsWarning: Inc(Warnings);
      vsError: Inc(Errors);
      vsFatal: Inc(Fatals);
    end;
    F := Report.Findings[I];
    if F.Rule <> '' then
      WriteLn(Format('%s(%d,%d) %s: SAFE-%s %s', [F.FileName, F.Row, F.Col, SeverityWord[Sev], F.Rule, F.Msg]))
    else
      WriteLn(Format('%s(%d,%d) %s: %s', [F.FileName, F.Row, F.Col, SeverityWord[Sev], F.Msg]));
  end;
end;

end.
