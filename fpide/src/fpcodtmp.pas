{
    This file is part of the Free Pascal Integrated Development Environment
    Copyright (c) 1998 by Berczi Gabor

    Code Template routines

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}

unit FPCodTmp; { Code Templates }
{$modeswitch nestedprocvars}{$modeswitch autoderef}

{2.0 compatibility}
{$ifdef VER2_0}
  {$macro on}
  {$define resourcestring := const}
{$endif}

interface

uses Objects,Drivers,Dialogs,
     WUtils,WViews,WEditor,
     FPViews;

type
    TCodeTemplate = class;
  PCodeTemplate = TCodeTemplate;
    TCodeTemplate = class(TObject)
      constructor Create(const AShortCut: string; AText: PUnsortedStringCollection); overload;
      function    GetShortCut: string;
      procedure   GetText(AList: PUnsortedStringCollection);
      procedure   SetShortCut(const AShortCut: string);
      procedure   SetText(AList: PUnsortedStringCollection);
      procedure   GetParams(var AShortCut: string; Lines: PUnsortedStringCollection);
      procedure   SetParams(const AShortCut: string; Lines: PUnsortedStringCollection);
      function Read(Ip: ipstream): Pointer; override;
      function StreamableName: ShortString; override;
      class function Build: TStreamable; static;
      procedure Write(Os: opstream); override;
      destructor Destroy; override;
    private
      ShortCut: PString;
      Text: PUnsortedStringCollection;
    public
      constructor Create(AInit: TStreamableInit); overload;
    end;

    TCodeTemplateCollection = class;
  PCodeTemplateCollection = TCodeTemplateCollection;
    TCodeTemplateCollection = class(TSortedCollection)
      function Compare(Key1, Key2: Pointer): sw_Integer; override;
      function SearchByShortCut(const ShortCut: string): PCodeTemplate; virtual;
      function LookUp(const S: string; AcceptMulti: boolean; var Idx: sw_integer): string; virtual;
      function StreamableName: ShortString; override;
      class function Build: TStreamable; static;
      protected
        function ReadItem(Ip: ipstream): Pointer; override;
        procedure WriteItem(Item: Pointer; Os: opstream); override;
    end;

    TCodeTemplateListBox = class;
  PCodeTemplateListBox = TCodeTemplateListBox;
    TCodeTemplateListBox = class(TAdvancedListBox)
      function GetText(Item,MaxLen: Sw_Integer): String; override;
    end;

    TCodeTemplateDialog = class;
  PCodeTemplateDialog = TCodeTemplateDialog;
    TCodeTemplateDialog = class(TCenterDialog)
      constructor Create(const ATitle: string; ATemplate: PCodeTemplate);
      function    Execute: Word; override;
    private
      Template   : PCodeTemplate;
      ShortcutIL : PInputLine;
      CodeMemo   : PFPCodeMemo;
    end;

    TCodeTemplatesDialog = class;
  PCodeTemplatesDialog = TCodeTemplatesDialog;
    TCodeTemplatesDialog = class(TCenterDialog)
      SelMode: boolean;
      constructor Create(ASelMode: boolean;const AShortCut : string);
      function    Execute: Word; override;
      procedure   HandleEvent(var Event: TEvent); override;
      function    GetSelectedShortCut: string;
    private
      CodeTemplatesLB : PCodeTemplateListBox;
      TemplateViewer  : PFPCodeMemo;
      StartIdx : sw_integer;
      procedure Add;
      procedure Edit;
      procedure Delete;
      procedure Update; override;
    end;

const CodeTemplates : PCodeTemplateCollection = nil;

function FPTranslateCodeTemplate(var Shortcut: string; ALines: PUnsortedStringCollection): boolean;

procedure InitCodeTemplates;
function  LoadCodeTemplates(S: TStream): boolean;
function  StoreCodeTemplates(S: TStream): boolean;
procedure DoneCodeTemplates;

procedure RegisterCodeTemplates;

implementation

uses Views,App,Validate,
     FVConsts,
     FPConst;

resourcestring  label_codetemplate_shortcut = '~S~hortcut';
                label_codetemplate_content = '~T~emplate content';
                label_codetemplate_templates = '~T~emplates';
                msg_codetemplate_alreadyinlist = 'A template named "%s" is already in the list';
                dialog_modifytemplate = 'Modify template';
                dialog_newtemplate = 'New template';

                { standard button texts }
                button_OK          = 'O~K~';
                button_Cancel      = 'Cancel';
                button_New         = '~N~ew';
                button_Edit        = '~E~dit';
                button_Delete      = '~D~elete';

{$ifndef NOOBJREG}
{$ifndef NOOBJREG}
{$ifndef NOOBJREG}

{$endif}
{$endif}
{$endif}

constructor TCodeTemplate.Create(const AShortCut: string; AText: PUnsortedStringCollection);
procedure CopyIt(P: PString); {$ifndef FPC}far;{$endif}
begin
  Text.Insert(NewStr(GetStr(P)));
end;
begin
  inherited Create;
  ShortCut:=NewStr(AShortCut);
  SetText(AText);
end;

function TCodeTemplate.GetShortCut: string;
begin
  GetShortCut:=GetStr(ShortCut);
end;

procedure TCodeTemplate.GetText(AList: PUnsortedStringCollection);
procedure CopyIt(P: PString); {$ifndef FPC}far;{$endif}
begin
  AList.Insert(NewStr(GetStr(P)));
end;
begin
  if Assigned(AList) and Assigned(Text) then
    Text.ForEach(TNestedActionProc(@CopyIt));
end;

procedure TCodeTemplate.SetShortCut(const AShortCut: string);
begin
  if Assigned(ShortCut) then DisposeStr(ShortCut);
  ShortCut:=NewStr(AShortCut);
end;

procedure TCodeTemplate.SetText(AList: PUnsortedStringCollection);
begin
  if Assigned(Text) then Text.Free;
  Text := TUnsortedStringCollection.CreateFrom(AList);
end;

procedure TCodeTemplate.GetParams(var AShortCut: string; Lines: PUnsortedStringCollection);
begin
  AShortCut:=GetShortCut;
  GetText(Lines);
end;

procedure TCodeTemplate.SetParams(const AShortCut: string; Lines: PUnsortedStringCollection);
begin
  SetShortCut(AShortCut);
  SetText(Lines);
end;

function TCodeTemplate.Read(Ip: ipstream): Pointer;
begin
  Result := Self;
  ShortCut:=Ip.ReadString;
  Text := TUnsortedStringCollection(Ip.ReadPointer);
end;

procedure TCodeTemplate.Write(Os: opstream);
begin
  Os.WriteString(ShortCut);
  Os.WritePointer(Text);
end;

constructor TCodeTemplate.Create(AInit: TStreamableInit);
begin
end;

class function TCodeTemplate.Build: TStreamable;
begin
  Result := TCodeTemplate.Create(streamableInit);
end;

function TCodeTemplate.StreamableName: ShortString;
begin
  Result := 'fpcodtmp.TCodeTemplate';
end;

destructor TCodeTemplate.Destroy;
begin
  if Assigned(ShortCut) then DisposeStr(ShortCut); ShortCut:=nil;
  if Assigned(Text) then Text.Free; Text:=nil;
  inherited Destroy;
end;

{ the items are streamable objects }
function TCodeTemplateCollection.ReadItem(Ip: ipstream): Pointer;
begin
  Result := Ip.ReadPointer;
end;

procedure TCodeTemplateCollection.WriteItem(Item: Pointer; Os: opstream);
begin
  Os.WritePointer(TStreamable(Item));
end;

function TCodeTemplateCollection.Compare(Key1, Key2: Pointer): sw_Integer;
var K1: PCodeTemplate absolute Key1;
    K2: PCodeTemplate absolute Key2;
    R: Sw_integer;
    S1,S2: string;
begin
  S1:=UpCaseStr(K1.GetShortCut);
  S2:=UpCaseStr(K2.GetShortCut);
  if S1<S2 then R:=-1 else
  if S1>S2 then R:=1 else
  R:=0;
  Compare:=R;
end;

function TCodeTemplateCollection.SearchByShortCut(const ShortCut: string): PCodeTemplate;
var T: TCodeTemplate;
    Index: sw_integer;
    P: PCodeTemplate;
begin
  T := TCodeTemplate.Create(ShortCut,nil);
  if Search(T,Index)=false then P:=nil else
    P:=TCodeTemplate(At(Index));
  T.Free;
  SearchByShortCut:=P;
end;

function TCodeTemplateCollection.LookUp(const S: string; AcceptMulti: boolean; var Idx: sw_integer): string;
var OLI,ORI,Left,Right,Mid: sw_integer;
    MidP: PCodeTemplate;
    MidS: string;
    FoundS: string;
    UpS : string;
begin
  Idx:=-1; FoundS:='';
  Left:=0; Right:=Count-1;
  UpS:=UpCaseStr(S);
  while Left<=Right do
    begin
      OLI:=Left; ORI:=Right;
      Mid:=Left+(Right-Left) div 2;
      MidP:=TCodeTemplate(At(Mid));
      MidS:=UpCaseStr(MidP.GetShortCut);
      if copy(MidS,1,length(UpS))=UpS then
        begin
          if (Idx<>-1) and (Idx<>Mid) and not AcceptMulti then
            begin
              { several solutions possible, return nothing }
              Idx:=-1;
              FoundS:='';
              break;
            end
          else if Idx=-1 then
            begin
              Idx:=Mid;
              FoundS:=MidP.GetShortCut;
            end;
        end;
      if UpS<MidS then
        Right:=Mid
      else
        Left:=Mid;
      if (OLI=Left) and (ORI=Right) then
        begin
          if (Left<Right) then
            Left:=Right
          else
            Break;
        end;
    end;
  { check if next also fits...
    return '' in that case }
  if (Idx<>-1) and (Idx<Count-1) and not AcceptMulti then
    begin
      MidP:=TCodeTemplate(At(Idx+1));
      MidS:=UpCaseStr(MidP.GetShortCut);
      if copy(MidS,1,length(UpS))=UpS then
        begin
          Idx:=-1;
          FoundS:='';
        end;
    end;
  LookUp:=FoundS;
end;


function FPTranslateCodeTemplate(var Shortcut: string; ALines: PUnsortedStringCollection): boolean;
var OK: boolean;
    P: PCodeTemplate;
    CompleteName: String;
    Idx : sw_integer;
begin
  OK:=Assigned(CodeTemplates);
  if OK then
  begin
    P:=CodeTemplates.SearchByShortCut(ShortCut);
    if not assigned(P) then
      begin
        CompleteName:=CodeTemplates.Lookup(ShortCut,false,Idx);
        if Idx<>-1 then
          begin
            P:=TCodeTemplate(CodeTemplates.At(Idx));
            ShortCut:=CompleteName;
          end;
      end;
    OK:=Assigned(P);
    if OK then
      P.GetText(ALines);
  end;
  FPTranslateCodeTemplate:=OK;
end;

procedure InitCodeTemplates;
begin
  if Assigned(CodeTemplates) then Exit;

  CodeTemplates := TCodeTemplateCollection.Create(10,10);
end;

function LoadCodeTemplates(S: TStream): boolean;
var C: PCodeTemplateCollection;
    OK: boolean;
begin
  C := TCodeTemplateCollection(GetObject(S));
  OK:=Assigned(C) and (S.Status=stOk);
  if OK then
    begin
      if Assigned(CodeTemplates) then CodeTemplates.Free;
      CodeTemplates:=C;
    end
  else
    if Assigned(C) then
      C.Free;
  LoadCodeTemplates:=OK;
end;

function StoreCodeTemplates(S: TStream): boolean;
var OK: boolean;
begin
  OK:=Assigned(CodeTemplates);
  if OK then
  begin
    PutObject(S, CodeTemplates);
    OK:=OK and (S.Status=stOK);
  end;
  StoreCodeTemplates:=OK;
end;

procedure DoneCodeTemplates;
begin
  if Assigned(CodeTemplates) then CodeTemplates.Free;
  CodeTemplates:=nil;
end;

function TCodeTemplateListBox.GetText(Item,MaxLen: Sw_Integer): String;
var P: PCodeTemplate;
begin
  P:=TCodeTemplate(List.At(Item));
  GetText:=P.GetShortCut;
end;

constructor TCodeTemplateDialog.Create(const ATitle: string; ATemplate: PCodeTemplate);
var R,R2,R3: TRect;
begin
  R := TRect.Create(0, 0, 52, 15);
  inherited Create(R,ATitle);
  Template:=ATemplate;

  R := GetExtent; R.Grow(-3,-2); R3 := R;
  Inc(R.A.Y); R.B.Y:=R.A.Y+1; R.B.X:=R.A.X+46;
  ShortCutIL := TInputLine.Create(R, 128); Insert(ShortcutIL);
  ShortCutIL.SetValidator(TFilterValidator.Create(NumberChars+AlphaChars));
  R2 := R; R2.Move(-1,-1);
  Insert(TLabel.Create(R2, label_codetemplate_shortcut, ShortcutIL));
  R.Move(0,3); R.B.Y:=R.A.Y+8;
  CodeMemo := TFPCodeMemo.Create(R, nil,nil,nil{,4096 does not compile !! });
  Insert(CodeMemo);
  R2 := R; R2.Move(-1,-1); R2.B.Y:=R2.A.Y+1;
  Insert(TLabel.Create(R2, label_codetemplate_content, CodeMemo));

  InsertButtons(Self);

  ShortcutIL.Select;
end;

function TCodeTemplateDialog.Execute: Word;
var R: word;
    S: string;
    L: PUnsortedStringCollection;
begin
  L := TUnsortedStringCollection.Create(10,10);
  S:=Template.GetShortCut;
  Template.GetText(L);
  ShortcutIL.SetData(S);
  CodeMemo.SetContent(L);
  R:=inherited Execute;
  if R=cmOK then
  begin
    L.FreeAll;
    ShortcutIL.GetData(S);
    CodeMemo.GetContent(L);
    Template.SetShortcut(S);
    Template.SetText(L);
  end;
  Execute:=R;
end;

constructor TCodeTemplatesDialog.Create(ASelMode: boolean;const AShortCut : string);
function B2I(B: boolean; I1,I2: longint): longint;
begin
  if B then B2I:=I1 else B2I:=I2;
end;
var R,R2,R3: TRect;
    SB: PScrollBar;
begin
  R := TRect.Create(0, 0, 46, 20);
  inherited Create(R,'Code Templates');
  HelpCtx:=hcCodeTemplateOptions;
  SelMode:=ASelMode;
  R := GetExtent; R.Grow(-3,-2); Inc(R.A.Y); R.B.Y:=R.A.Y+10;
  R3 := R; Dec(R.B.X,12);
  R2 := R; R2.Move(1,0); R2.A.X:=R2.B.X-1;
  SB := TScrollBar.Create(R2); Insert(SB);
  CodeTemplatesLB := TCodeTemplateListBox.Create(R,1,SB);
  Insert(CodeTemplatesLB);
  if AShortCut<>'' then
    begin
      If assigned(CodeTemplates) then
        CodeTemplates.Lookup(AShortCut,true,StartIdx)
      else
        StartIdx:=-1;
    end
  else
    StartIdx:=-1;
  R2 := R; R2.Move(0,-1); R2.B.Y:=R2.A.Y+1; Dec(R2.A.X);
  Insert(TLabel.Create(R2, label_codetemplate_templates, CodeTemplatesLB));

  R := GetExtent; R.Grow(-2,-2); Inc(R.A.Y,12);
  R2 := R; R2.Move(1,0); R2.A.X:=R2.B.X-1;
  SB := TScrollBar.Create(R2); Insert(SB);
  TemplateViewer := TFPCodeMemo.Create(R,nil,SB,nil{,4096 does not compile });
  with TemplateViewer do
  begin
    ReadOnly:=true;
    AlwaysShowScrollBars:=true;
  end;
  Insert(TemplateViewer);

  R := R3; R.A.X:=R.B.X-10; R.B.Y:=R.A.Y+2;
  Insert(TButton.Create(R, button_OK, cmOK, B2I(SelMode,bfDefault,bfNormal)));
  R.Move(0,2);
  Insert(TButton.Create(R, button_Edit, cmEditItem, B2I(SelMode,bfNormal,bfDefault)));
  R.Move(0,2);
  Insert(TButton.Create(R, button_New, cmAddItem, bfNormal));
  R.Move(0,2);
  Insert(TButton.Create(R, button_Delete, cmDeleteItem, bfNormal));
  R.Move(0,2);
  Insert(TButton.Create(R, button_Cancel, cmCancel, bfNormal));
  SelectNext(false);
end;

procedure TCodeTemplatesDialog.Update;
var C: PUnsortedStringCollection;
begin
  if CodeTemplatesLB.Range=0 then C:=nil else
    C:=PCodeTemplate(CodeTemplatesLB.GetFocusedItem).Text;
  TemplateViewer.SetContent(C);
  ReDraw;
end;

function TCodeTemplatesDialog.GetSelectedShortCut: string;
var S: string;
begin
  if CodeTemplatesLB.Range=0 then S:='' else
    S:=GetStr(PCodeTemplate(CodeTemplatesLB.GetFocusedItem).ShortCut);
  GetSelectedShortCut:=S;
end;

procedure TCodeTemplatesDialog.HandleEvent(var Event: TEvent);
var DontClear: boolean;
begin
  case Event.What of
    evKeyDown :
      begin
        DontClear:=false;
        case Event.KeyDown.KeyCode of
          kbIns  :
            Message(Self,evCommand,cmAddItem,nil);
          kbDel  :
            Message(Self,evCommand,cmDeleteItem,nil);
        else DontClear:=true;
        end;
        if DontClear=false then ClearEvent(Event);
      end;
    evBroadcast :
      case Event.Message.Command of
        cmListItemSelected :
          if Event.Message.InfoPtr=pointer(CodeTemplatesLB) then
            Message(Self,evCommand,cmEditItem,nil);
        cmListFocusChanged :
          if Event.Message.InfoPtr=pointer(CodeTemplatesLB) then
            Message(Self,evBroadcast,cmUpdate,nil);
        cmUpdate :
          Update;
      end;
    evCommand :
      begin
        DontClear:=false;
        case Event.Message.Command of
          cmAddItem    : Add;
          cmDeleteItem : Delete;
          cmEditItem   : Edit;
        else DontClear:=true;
        end;
        if DontClear=false then ClearEvent(Event);
      end;
  end;
  inherited HandleEvent(Event);
end;

function TCodeTemplatesDialog.Execute: Word;
var R: word;
    P: PCodeTemplate;
    C: PCodeTemplateCollection;
    L: PUnsortedStringCollection;
    I: integer;
begin
  C := TCodeTemplateCollection.Create(10,20);
  if Assigned(CodeTemplates) then
  for I:=0 to CodeTemplates.Count-1 do
    begin
      P:=TCodeTemplate(CodeTemplates.At(I));
      L := TUnsortedStringCollection.Create(10,50);
      P.GetText(L);
      C.Insert(TCodeTemplate.Create(P.GetShortCut,L));
      L.Free;
    end;
  CodeTemplatesLB.NewList(C);
  if StartIdx<>-1 then
    CodeTemplatesLB.SetFocusedItem(CodeTemplates.At(StartIdx));
  Update;
  R:=inherited Execute;
  if R=cmOK then
    begin
      if Assigned(CodeTemplates) then CodeTemplates.Free;
      CodeTemplates:=C;
    end
  else
    C.Free;
  Execute:=R;
end;

procedure TCodeTemplatesDialog.Add;
var P,P2: PCodeTemplate;
    IC: boolean;
    S: string;
    L: PUnsortedStringCollection;
    Cmd: word;
    CanExit: boolean;
begin
  L := TUnsortedStringCollection.Create(10,10);
  IC:=CodeTemplatesLB.Range=0;
  if IC=false then
    begin
      P:=TCodeTemplate(CodeTemplatesLB.List.At(CodeTemplatesLB.Focused));
      P.GetParams(S,L);
    end
  else
    begin
      S:='';
    end;
  P := TCodeTemplate.Create(S,L);
  repeat
    Cmd:=TProgram.Application.ExecuteDialog(TCodeTemplateDialog.Create(dialog_newtemplate,P), nil);
    CanExit:=(Cmd<>cmOK);
    if CanExit=false then
      begin
        P2:=PCodeTemplateCollection(CodeTemplatesLB.List).SearchByShortCut(P.GetShortCut);
        CanExit:=(Assigned(P2)=false);
        if CanExit=false then
        begin
          ClearFormatParams; AddFormatParamStr(P.GetShortCut);
          ErrorBox(msg_codetemplate_alreadyinlist,@FormatParams);
        end;
      end;
  until CanExit;
  if Cmd=cmOK then
    begin
      CodeTemplatesLB.List.Insert(P);
      CodeTemplatesLB.SetRange(CodeTemplatesLB.List.Count);
      CodeTemplatesLB.SetFocusedItem(P);
      Update;
    end
  else
    P.Free;
  L.Free;
end;

procedure TCodeTemplatesDialog.Edit;
var P,O,P2: PCodeTemplate;
    I: sw_integer;
    S: string;
    L: PUnsortedStringCollection;
    Cmd: word;
    CanExit: boolean;
begin
  if CodeTemplatesLB.Range=0 then Exit;
  L := TUnsortedStringCollection.Create(10,10);
  I:=CodeTemplatesLB.Focused;
  O:=TCodeTemplate(CodeTemplatesLB.List.At(I));
  O.GetParams(S,L);
  P := TCodeTemplate.Create(S, L);
  repeat
    Cmd:=TProgram.Application.ExecuteDialog(TCodeTemplateDialog.Create(dialog_modifytemplate,P), nil);
    CanExit:=(Cmd<>cmOK);
    if CanExit=false then
      begin
        P2:=PCodeTemplateCollection(CodeTemplatesLB.List).SearchByShortCut(P.GetShortCut);
        CanExit:=(Assigned(P2)=false) or (CodeTemplatesLB.List.IndexOf(P2)=I);
        if CanExit=false then
        begin
          ClearFormatParams; AddFormatParamStr(P.GetShortCut);
          ErrorBox(msg_codetemplate_alreadyinlist,@FormatParams);
        end;
      end;
  until CanExit;
  if Cmd=cmOK then
    begin
      with CodeTemplatesLB do
      begin
        List.AtFree(I); O:=nil;
        List.Insert(P);
        SetFocusedItem(P);
      end;
      Update;
    end;
  L.Free;
end;

procedure TCodeTemplatesDialog.Delete;
begin
  if CodeTemplatesLB.Range=0 then Exit;
  CodeTemplatesLB.List.AtFree(CodeTemplatesLB.Focused);
  CodeTemplatesLB.SetRange(CodeTemplatesLB.List.Count);
  Update;
end;


{$ifndef NOOBJREG}
{ the classes of the unit in the streams of tv3 (opstream, ipstream), registered by their names }


procedure RegisterStreamables_fpcodtmp;
begin
  TStreamableClass.Create('fpcodtmp.TCodeTemplate', @TCodeTemplate.Build);
  TStreamableClass.Create('fpcodtmp.TCodeTemplateCollection', @TCodeTemplateCollection.Build);
end;

{$endif}

procedure RegisterCodeTemplates;
begin
{$ifndef NOOBJREG}
  RegisterStreamables_fpcodtmp;
{$endif}
end;


class function TCodeTemplateCollection.Build: TStreamable;
begin
  Result := TCodeTemplateCollection.Create(streamableInit);
end;

function TCodeTemplateCollection.StreamableName: ShortString;
begin
  Result := 'fpcodtmp.TCodeTemplateCollection';
end;

END.
