{ The symbol browser without the symbol tables of the compiler.

  The embedded compiler of the original IDE hands its symbol tables to the browser (BrowCol). The compiler of
  this build is external, so the same collections are filled from the sources: the program or unit and the
  units it uses that are found next to it are read with the Pascal parser of the FCL (fcl-passrc), which does
  what the browser shows - the declarations (types, classes with their members and ancestors, procedures with
  their parameters, variables, constants, enumerations) with their places in the sources. }
unit FPSrcBrw;

{$mode objfpc}{$H+}

interface

{ (Re)builds the browser collections (Modules, ObjectTree) for the program or unit `MainFile`. False if
  nothing could be read. }
function BuildSourceBrowser(const MainFile: string): boolean;

implementation

uses
  Classes, SysUtils, Objects, PasTree, PScanner, PParser, SymConst, BrowCol;

type
  TBrowseContainer = class(TPasTreeContainer)
  public
    function CreateElement(AClass: TPTreeElement; const AName: String; AParent: TPasElement;
      AVisibility: TPasMemberVisibility; const ASourceFilename: String; ASourceLinenumber: Integer): TPasElement;
      overload; override;
    function FindElement(const AName: String): TPasElement; override;
  end;

function TBrowseContainer.CreateElement(AClass: TPTreeElement; const AName: String; AParent: TPasElement;
  AVisibility: TPasMemberVisibility; const ASourceFilename: String; ASourceLinenumber: Integer): TPasElement;
begin
  Result := AClass.Create(AName, AParent);
  Result.Visibility := AVisibility;
  Result.SourceFilename := ASourceFilename;
  Result.SourceLinenumber := ASourceLinenumber;
end;

function TBrowseContainer.FindElement(const AName: String): TPasElement;
begin
  Result := nil;
end;

var
  NextTypeID: PtrInt;
  TypeIDs: TStringList;       { lower case type name -> its TypeID (ancestors are found by name) }

function ReadModule(const FileName: string): TPasModule;
var
  resolver: TFileResolver;
  scanner: TPascalScanner;
  parser: TPasParser;
  container: TBrowseContainer;
  dir: string;
begin
  Result := nil;
  resolver := TFileResolver.Create;
  scanner := TPascalScanner.Create(resolver);
  container := TBrowseContainer.Create;
  parser := TPasParser.Create(scanner, resolver, container);
  try
    try
      dir := ExtractFilePath(ExpandFileName(FileName));
      resolver.BaseDirectory := dir;
      resolver.AddIncludePath(dir);
      scanner.AddDefine('FPC');
      scanner.AddDefine('LINUX');
      scanner.AddDefine('UNIX');
      scanner.AddDefine('CPU64');
      scanner.AddDefine('CPUX86_64');
      scanner.AddDefine('ENDIAN_LITTLE');
      scanner.OpenFile(FileName);
      parser.ParseMain(Result);
    except
      on E: Exception do
        Result := nil;          { a source the parser does not follow: it just has no symbols }
    end;
  finally
    parser.Free;
    scanner.Free;
    resolver.Free;
    container.Free;
  end;
end;

function Decl(E: TPasElement): string;
begin
  Result := '';
  if E <> nil then
    try
      Result := E.GetDeclaration(False);
    except
      Result := E.Name;
    end;
end;

function TypeText(T: TPasType): string;
begin
  if T = nil then
    Result := ''
  else if T.Name <> '' then
    Result := T.Name
  else
    Result := Decl(T);
end;

function ArgsText(Args: TFPList): string;
var
  i: integer;
  a: TPasArgument;
  s: string;
begin
  Result := '';
  if Args = nil then
    Exit;
  for i := 0 to Args.Count - 1 do
  begin
    a := TPasArgument(Args[i]);
    s := a.Name;
    if a.ArgType <> nil then
      s := s + ': ' + TypeText(a.ArgType);
    case a.Access of
      argConst: s := 'const ' + s;
      argVar: s := 'var ' + s;
      argOut: s := 'out ' + s;
      argConstRef: s := 'constref ' + s;
    end;
    if Result <> '' then
      Result := Result + '; ';
    Result := Result + s;
  end;
end;

procedure SetVType(S: PSymbol; const T: string);
begin
  if T <> '' then
    S.VType := TypeNames.Add(T);
end;

procedure SetDType(S: PSymbol; const T: string);
begin
  if T <> '' then
    S.DType := TypeNames.Add(T);
end;

procedure AddReference(S: PSymbol; E: TPasElement);
begin
  if (E.SourceFilename <> '') and (E.SourceLinenumber > 0) then
    S.References.Insert(TReference.Create(ModuleNames.Add(ExpandFileName(E.SourceFilename)),
      E.SourceLinenumber, 1));
end;

procedure AddDeclarations(Owner: PSymbolCollection; List: TFPList); forward;

function NewSymbol(Owner: PSymbolCollection; E: TPasElement; ATyp: tsymtyp; const AParams: string): PSymbol;
begin
  Result := TSymbol.Create(E.Name, ATyp, '', nil);
  if AParams <> '' then
    Result.Params := TypeNames.Add(AParams);
  AddReference(Result, E);
  Owner.Insert(Result);
end;

procedure AddProcedure(Owner: PSymbolCollection; P: TPasProcedure);
var
  S: PSymbol;
  pt: TPasProcedureType;
begin
  pt := P.ProcType;
  S := NewSymbol(Owner, P, procsym, ArgsText(pt.Args));
  if (pt is TPasFunctionType) and (TPasFunctionType(pt).ResultEl <> nil) then
    SetVType(S, TypeText(TPasFunctionType(pt).ResultEl.ResultType));
end;

procedure AddMembers(Owner: PSymbol; Members: TFPList);
var
  i: integer;
  E: TPasElement;
  S: PSymbol;
begin
  if Members = nil then
    Exit;
  for i := 0 to Members.Count - 1 do
  begin
    E := TPasElement(Members[i]);
    if E is TPasProperty then
    begin
      S := NewSymbol(Owner.Items, E, propertysym, '');
      SetVType(S, TypeText(TPasProperty(E).VarType));
    end
    else if E is TPasProcedure then
      AddProcedure(Owner.Items, TPasProcedure(E))
    else if E is TPasOverloadedProc then
    begin
      // every overload is a symbol of its own
      AddDeclarations(Owner.Items, TPasOverloadedProc(E).Overloads);
    end
    else if E is TPasVariable then
    begin
      S := NewSymbol(Owner.Items, E, fieldvarsym, '');
      SetVType(S, TypeText(TPasVariable(E).VarType));
    end;
  end;
end;

procedure AddType(Owner: PSymbolCollection; T: TPasType);
var
  S: PSymbol;
  i: integer;
  V: TPasEnumValue;
  rec: TPasRecordType;
  cls: TPasClassType;
  anc: string;
begin
  S := NewSymbol(Owner, T, typesym, '');
  Inc(NextTypeID);
  S.TypeID := NextTypeID;
  TypeIDs.AddObject(LowerCase(T.Name), TObject(PtrInt(S.TypeID)));
  if T is TPasClassType then
  begin
    cls := TPasClassType(T);
    S.Flags := S.Flags or sfObject;
    if cls.ObjKind = okClass then
      S.Flags := S.Flags or sfClass;
    if cls.AncestorType <> nil then
    begin
      anc := LowerCase(TypeText(cls.AncestorType));
      i := TypeIDs.IndexOf(anc);
      if i >= 0 then
        S.RelatedTypeID := PtrInt(TypeIDs.Objects[i]);
    end;
    if cls.ObjKind <> okInterface then
      AddMembers(S, cls.Members);
  end
  else if T is TPasRecordType then
  begin
    rec := TPasRecordType(T);
    S.Flags := S.Flags or sfRecord;
    AddMembers(S, rec.Members);
  end
  else if T is TPasEnumType then
  begin
    SetDType(S, Decl(T));
    for i := 0 to TPasEnumType(T).Values.Count - 1 do
    begin
      V := TPasEnumValue(TPasEnumType(T).Values[i]);
      NewSymbol(Owner, V, enumsym, '');
    end;
  end
  else if T is TPasPointerType then
  begin
    S.Flags := S.Flags or sfPointer;
    SetDType(S, Decl(T));
  end
  else if T is TPasAliasType then
    SetDType(S, TypeText(TPasAliasType(T).DestType))
  else if T is TPasProcedureType then
    SetDType(S, Decl(T))
  else
    SetDType(S, Decl(T));
end;

procedure AddDeclarations(Owner: PSymbolCollection; List: TFPList);
var
  i: integer;
  E: TPasElement;
  S: PSymbol;
begin
  if List = nil then
    Exit;
  for i := 0 to List.Count - 1 do
  begin
    E := TPasElement(List[i]);
    if E is TPasConst then
    begin
      S := NewSymbol(Owner, E, constsym, '');
      if TPasConst(E).Expr <> nil then
        SetDType(S, Decl(TPasConst(E).Expr));
    end
    else if E is TPasVariable then
    begin
      S := NewSymbol(Owner, E, staticvarsym, '');
      SetVType(S, TypeText(TPasVariable(E).VarType));
    end
    else if E is TPasType then
      AddType(Owner, TPasType(E))
    else if E is TPasProcedure then
      AddProcedure(Owner, TPasProcedure(E))
    else if E is TPasOverloadedProc then
      AddDeclarations(Owner, TPasOverloadedProc(E).Overloads);
  end;
end;

{ the file of a used unit next to the sources: <name>.pas / .pp in any letter case }
function FindUnitFile(const Dir, UnitName: string): string;
const
  Exts: array[0..1] of string = ('.pas', '.pp');
var
  sr: TSearchRec;
  e: integer;
begin
  Result := '';
  for e := 0 to High(Exts) do
    if FileExists(Dir + UnitName + Exts[e]) then
      Exit(Dir + UnitName + Exts[e])
    else if FileExists(Dir + LowerCase(UnitName) + Exts[e]) then
      Exit(Dir + LowerCase(UnitName) + Exts[e]);
  if FindFirst(Dir + '*', faAnyFile, sr) = 0 then
  begin
    repeat
      for e := 0 to High(Exts) do
        if SameText(sr.Name, UnitName + Exts[e]) then
        begin
          Result := Dir + sr.Name;
          Break;
        end;
    until (Result <> '') or (FindNext(sr) <> 0);
    FindClose(sr);
  end;
end;

procedure UsedUnits(M: TPasModule; Names: TStrings);
  procedure FromSection(Sec: TPasSection);
  var
    i: integer;
  begin
    if Sec = nil then
      Exit;
    for i := 0 to High(Sec.UsesClause) do
      if Sec.UsesClause[i].Name <> '' then
        Names.Add(Sec.UsesClause[i].Name);
  end;
begin
  FromSection(M.InterfaceSection);
  FromSection(M.ImplementationSection);
  if M is TPasProgram then
    FromSection(TPasProgram(M).ProgramSection)
  else if M is TPasLibrary then
    FromSection(TPasLibrary(M).LibrarySection);
end;

function BuildSourceBrowser(const MainFile: string): boolean;
var
  queue, done, uses_: TStringList;
  modules_: TList;
  M: TPasModule;
  U: PModuleSymbol;
  Sec: TPasSection;
  dir, f: string;
  i, n: integer;
begin
  Result := False;
  if (MainFile = '') or not FileExists(MainFile) then
    Exit;
  DisposeBrowserCol;
  NewBrowserCol;
  NextTypeID := 0;
  TypeIDs := TStringList.Create;
  queue := TStringList.Create;
  done := TStringList.Create;
  uses_ := TStringList.Create;
  modules_ := TList.Create;
  try
    done.CaseSensitive := False;
    dir := ExtractFilePath(ExpandFileName(MainFile));
    queue.Add(ExpandFileName(MainFile));
    { the units of a program come first as they are used: dependencies are read before their users so that the
      ancestors of classes are known; so the queue is read first and the modules are added in reverse }
    n := 0;
    while (queue.Count > 0) and (n < 200) do
    begin
      f := queue[0];
      queue.Delete(0);
      if done.IndexOf(f) >= 0 then
        Continue;
      done.Add(f);
      Inc(n);
      M := ReadModule(f);
      if M = nil then
        Continue;
      modules_.Insert(0, M);                       { used units end up before their users }
      uses_.Clear;
      UsedUnits(M, uses_);
      for i := 0 to uses_.Count - 1 do
      begin
        f := FindUnitFile(dir, uses_[i]);
        if (f <> '') and (done.IndexOf(f) < 0) and (queue.IndexOf(f) < 0) then
          queue.Add(f);
      end;
    end;
    for i := 0 to modules_.Count - 1 do
    begin
      M := TPasModule(modules_[i]);
      U := TModuleSymbol.Create(M.Name, ExpandFileName(M.SourceFilename));
      U.AddSourceFile(ExpandFileName(M.SourceFilename));
      AddReference(U, M);
      Modules.Insert(U);
      Sec := M.InterfaceSection;
      if Sec = nil then
        if M is TPasProgram then
          Sec := TPasProgram(M).ProgramSection
        else if M is TPasLibrary then
          Sec := TPasLibrary(M).LibrarySection;
      if Sec <> nil then
        AddDeclarations(U.Items, Sec.Declarations);
    end;
    Result := Modules.Count > 0;
    if Result then
      BuildObjectInfo
    else
      DisposeBrowserCol;         { nothing readable: no browser info, as before }
  finally
    for i := 0 to modules_.Count - 1 do
      TPasModule(modules_[i]).Release;
    modules_.Free;
    uses_.Free;
    done.Free;
    queue.Free;
    TypeIDs.Free;
    TypeIDs := nil;
  end;
end;

end.
