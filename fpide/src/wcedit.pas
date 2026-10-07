{
    This file is part of the Free Pascal Integrated Development Environment
    Copyright (c) 1998-2000 by Berczi Gabor

    Code editor template objects: the editor of a file (on tve)

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}
{$i globdir.inc}
unit WCEdit;


{$mode objfpc}{$H-}
{$modeswitch nestedprocvars}
{$modeswitch autoderef}
interface

uses Objects,Drivers,Views,
     WUtils,WEditor,TveDoc;

type
    TCodeEditor = class;
    PCodeEditor = TCodeEditor;

    TIndicator = class;
    PIndicator = TIndicator;
    TIndicator = class(TView)
      Location: TPoint;
      Modified : Boolean;
      CodeOwner : PCodeEditor;
      constructor Create(var Bounds: TRect);
      procedure   Draw; override;
      function    GetPalette: TPalette; override;
      procedure   SetState(AState: Word; Enable: Boolean); override;
      procedure   SetValue(ALocation: TPoint; AModified: Boolean);
    end;

    { A line that has its own text and flags (not a view of a line of an editor): the base of line objects that a subclass keeps for itself. }
    TLine = class;
    PLine = TLine;
    TLine = class(TCustomLine)
    end;

    TLineCollection = class;
    PLineCollection = TLineCollection;
    TLineCollection = class(TCollection)
      function  At(Index: sw_Integer): PCustomLine;
    end;

    TCodeEditorCore = class;
    PCodeEditorCore = TCodeEditorCore;
    TCodeEditorCore = class(TCustomCodeEditorCore)
    public
      OnDiskLoadTime : cardinal;
      SystemLoadTime : cardinal;
      constructor Create;
      function    GetChangedLine: sw_integer;
    end;

    TCodeEditor = class(TCustomCodeEditor)
      Core       : PCodeEditorCore;
      Indicator  : PIndicator;
      HighlightRow: sw_integer;
      DebuggerRow: sw_integer;
      IndicatorDrawCalled  : boolean;
    private
      FReadOnly: boolean;
      procedure   SetReadOnly(V: boolean);
    public
      constructor Create(var Bounds: TRect; AHScrollBar, AVScrollBar:
          PScrollBar; AIndicator: PIndicator; ACore: PCodeEditorCore);
      destructor Destroy; override;
      property    ReadOnly: boolean read FReadOnly write SetReadOnly;
      property    Flags: longint read GetFlags write SetFlags;
      procedure   DrawIndicator; override;
      function    IsReadOnly: boolean; override;
      procedure   UpdateIndicator; virtual;
      procedure   ModifiedChanged; override;
      procedure   PositionChanged; override;
      procedure   LimitsChanged; override;
      procedure   Lock; override;
      procedure   UnLock; override;
      procedure   ClearUndoList;
    end;

    TFileEditor = class;
    PFileEditor = TFileEditor;
    TFileEditor = class(TCodeEditor)
      FileName: string;
      constructor Create(var Bounds: TRect; AHScrollBar, AVScrollBar:
          PScrollBar; AIndicator: PIndicator; ACore: PCodeEditorCore; const AFileName: string);
      function    Save: Boolean; virtual;
      function    SaveAs: Boolean; virtual;
      function    SaveAsk(Force: boolean): Boolean; virtual;
      function    LoadFile: boolean; virtual;
      function    ReloadFile: boolean; virtual;
      function    SaveFile: boolean; virtual;
      function    Valid(Command: Word): Boolean; override;
      procedure   HandleEvent(var Event: TEvent); override;
      function    ShouldSave: boolean; virtual;
      function    IsChangedOnDisk : boolean;
    public
      procedure   BindingsChanged; override;
    end;

function DefUseSyntaxHighlight(Editor: PFileEditor): boolean;
function DefUseTabsPattern(Editor: PFileEditor): boolean;

const
     DefaultCodeEditorFlags : longint =
       efBackupFiles+efInsertMode+efAutoIndent+efPersistentBlocks+
       {efUseTabCharacters+}efBackSpaceUnindents+efSyntaxHighlight+
       efExpandAllTabs+efCodeComplete{+efFolds};
     DefaultTabSize     : integer = 8;
     DefaultIndentSize   : integer = 1;
     UseSyntaxHighlight : function(Editor: PFileEditor): boolean = {$ifdef fpc}@{$endif}DefUseSyntaxHighlight;
     UseTabsPattern     : function(Editor: PFileEditor): boolean = {$ifdef fpc}@{$endif}DefUseTabsPattern;

procedure RegisterWCEdit;

implementation

uses Dos,
     WConsts,
     FVConsts,
     App,WViews,TvUStr,TvUtf8,
     TveEditor,TveFile,TveBlocks,TveLang,TveHl;

function TLineCollection.At(Index: sw_Integer): PCustomLine;
begin
  At:=PCustomLine(Inherited At(Index));
end;

constructor TCodeEditorCore.Create;
begin
  inherited Create;
  SetTabSize(DefaultTabSize);
  SetIndentSize(DefaultIndentSize);
  OnDiskLoadTime:=0;
  SystemLoadTime:=0;
end;

function TCodeEditorCore.GetChangedLine: sw_integer;
begin
  GetChangedLine:=-1;
end;

constructor TIndicator.Create(var Bounds: TRect);
begin
  inherited Create(Bounds);
  GrowMode := gfGrowLoY + gfGrowHiY;
end;

procedure TIndicator.Draw;
var
  Color: Byte;
  Frame: string[3];
  L: array[0..1] of PtrInt;
  S: String[15];
  B: TFVDrawBuffer;
begin
  if assigned(CodeOwner) and
     (CodeOwner.ELockFlag>0) then
    begin
      CodeOwner.IndicatorDrawCalled:=true;
      exit;
    end;
  if (State and sfDragging = 0) and (State and sfActive <> 0) then
   begin
     Color := Lo(GetColorW(1));
     Frame := '═';
   end
  else
   begin
     if (State and sfDragging)<>0 then
      Color := Lo(GetColorW(2))
     else
      Color := Lo(GetColorW(3));
     Frame := '─';
   end;
  MoveFill(B, Frame, Color, Size.X);
  if State and sfActive<>0 then
   begin
     if Modified then
       SetCellChar(B[0], '*');
{$ifdef debug}
     if StoreUndo then
       SetCellChar(B[1], 'S');
     if SyntaxComplete then
       SetCellChar(B[2], 'C');
     if UseTabs then
       SetCellChar(B[3], 'T');
{$endif debug}
     L[0] := Location.Y + 1;
     L[1] := Location.X + 1;
     FormatStr(S, ' %d:%d ', L);
     MoveStr(B[8 - Pos(':', S)], S, Color);
   end;
  WriteBufC(0, 0, Size.X, 1, B);
end;

function TIndicator.GetPalette: TPalette;
begin
  Result := MakePalette(CIndicator);
end;

procedure TIndicator.SetState(AState: Word; Enable: Boolean);
begin
  inherited SetState(AState, Enable);
  if (AState = sfDragging) or (AState=sfActive) then
   DrawView;
end;

procedure TIndicator.SetValue(ALocation: TPoint; AModified: Boolean);
begin
  if (Location.X<>ALocation.X) or
     (Location.Y<>ALocation.Y) or
     (Modified <> AModified) then
  begin
    Location := ALocation;
    Modified := AModified;
    DrawView;
  end;
end;


{*****************************************************************************
                TCodeEditor
*****************************************************************************}

constructor TCodeEditor.Create(var Bounds: TRect; AHScrollBar, AVScrollBar:
          PScrollBar; AIndicator: PIndicator; ACore: PCodeEditorCore);
begin
  if ACore=nil then ACore:=TCodeEditorCore.Create;
  inherited Create(Bounds,AHScrollBar,AVScrollBar,ACore);
  Core:=ACore;
  SetState(sfCursorVis,true);
  SetFlags(DefaultCodeEditorFlags);
  SetCurPtr(0,0);
  Indicator:=AIndicator;
  if assigned(Indicator) then
    Indicator.CodeOwner:=Self;
  UpdateIndicator;
  LimitsChanged;
end;

destructor TCodeEditor.Destroy;
begin
  Core:=nil;
  inherited Destroy;
end;

procedure TCodeEditor.SetReadOnly(V: boolean);
begin
  FReadOnly:=V;
  Doc.ReadOnly:=V;
end;

function TCodeEditor.IsReadOnly: boolean;
begin
  IsReadOnly:=FReadOnly or Doc.ReadOnly;
end;

procedure TCodeEditor.ClearUndoList;
begin
  { the undo list is the one of the document; it is emptied when the text is loaded }
end;

procedure TCodeEditor.DrawIndicator;
begin
  if Assigned(Indicator) then
    Indicator.DrawView;
end;

procedure TCodeEditor.Lock;
begin
  inherited Lock;
  Core.Lock;
end;

procedure TCodeEditor.UnLock;
begin
  Core.UnLock;
  inherited UnLock;
  If (ELockFlag=0) and IndicatorDrawCalled then
    begin
      DrawIndicator;
      IndicatorDrawCalled:=false;
    end;
end;

procedure TCodeEditor.UpdateIndicator;
begin
  if Indicator<>nil then
  begin
    Indicator.Location:=CurPos;
    Indicator.Modified:=GetModified;
    if Elockflag>0 then
      IndicatorDrawCalled:=true
    else
      Indicator.DrawView;
  end;
end;

procedure TCodeEditor.LimitsChanged;
begin
  Core.LimitsChanged;
end;

procedure TCodeEditor.ModifiedChanged;
begin
  UpdateIndicator;
end;

procedure TCodeEditor.PositionChanged;
begin
  UpdateIndicator;
end;

{*****************************************************************************
                TFileEditor
*****************************************************************************}

function FileOptions(E: TFileEditor): TTveFileOptions;
begin
  Result:=TveDefaultOptions;
  Result.Backup:=false;                      { the backup is made by SaveFile }
  Result.StripTrailing:=false;
end;

constructor TFileEditor.Create(var Bounds: TRect; AHScrollBar, AVScrollBar:
       PScrollBar; AIndicator: PIndicator;ACore: PCodeEditorCore; const AFileName: string);
begin
  inherited Create(Bounds,AHScrollBAr,AVScrollBAr,AIndicator,ACore);
  FileName:=AFileName;
  UpdateIndicator;
  Message(Self,evBroadcast,cmFileNameChanged,Self);
end;

function TFileEditor.LoadFile: boolean;
var Err: AnsiString;
    OK: boolean;
begin
  OK:=TveLoadDoc(Doc,FileName,FileOptions(Self),Err);
  if OK then
    begin
      Editor.GotoOffset(0);
      Core.SetModified(false);
      Refresh;
    end;
  Core.OnDiskLoadTime:=Cardinal(GetFileTime(FileName));
  Core.SystemLoadTime:=Core.OnDiskLoadTime;
  LoadFile:=OK;
end;

function TFileEditor.IsChangedOnDisk : boolean;
begin
  if (FileName<>'') and Doc.Info.Known then
    { size and time of the file, as of the last read or write }
    IsChangedOnDisk:=TveDiskChanged(FileName,Doc.Info)
  else
    IsChangedOnDisk:=(Core.OnDiskLoadTime<>Cardinal(GetFileTime(FileName))) and
      (Core.OnDiskLoadTime<>0);
end;

function TFileEditor.SaveFile: boolean;
var OK: boolean;
    BAKName: string;
    f: text;
    SaveTime : cardinal;
    Lost: integer;
    Err: AnsiString;
begin
  If IsChangedOnDisk then
    begin
      if EditorDialog(edFileOnDiskChanged, @FileName) <> cmYes then
        begin
          SaveFile:=false;
          exit;
        end;
    end;
{$I-}
  if IsFlagSet(efBackupFiles) and ExistsFile(FileName) then
  begin
     BAKName:=DirAndNameOf(FileName)+'.bak';
     Assign(f,BAKName);
     Erase(f);
     EatIO;
     Assign(f,FileName);
     Rename(F,BAKName);
     EatIO;
  end;
{$I+}
  SaveTime:=cardinal(WUtils.Now);
  if not IsFlagSet(efKeepTrailingSpaces) then
    TrimTrailing(Editor);
  OK:=TveSaveDoc(Doc,FileName,FileOptions(Self),Lost,Err);
  if OK then
    SetModified(false)
  else if IsFlagSet(efBackupFiles) and ExistsFile(BakName) then
    begin
{$I-}
     Assign(f,BakName);
     Rename(F,FileName);
     EatIO;
{$I+}
    end;
  if OK then
    begin
      Core.OnDiskLoadTime:=Cardinal(GetFileTime(FileName));
      Core.SystemLoadTime:=SaveTime;
    end;
  if not OK then
    EditorDialog(edSaveError,@FileName);
  SaveFile:=OK;
end;

function TFileEditor.ReloadFile: boolean;
var OK,WasModified: boolean;
begin
  If not IsChangedOnDisk then
    begin
      ReloadFile:=false;
      exit;
    end;
  WasModified:=GetModified;
  if not WasModified then
    OK:=EditorDialog(edreloaddiskmodifiedfile, @FileName)=cmYes
  else
    OK:=EditorDialog(edreloaddiskandidemodifiedfile, @FileName)=cmYes;
  if not OK then
    begin
      ReloadFile:=false;
      exit;
    end;
  if WasModified then
    SetModified(false);
  OK:=LoadFile;
  if OK then
    begin
      SetModified(false);
      Core.OnDiskLoadTime:=Cardinal(GetFileTime(FileName));
      Core.SystemLoadTime:=Core.OnDiskLoadTime;
      DrawView;
    end
  else
    begin
      if WasModified then
        SetModified(true);
      EditorDialog(edReadError,@FileName);
    end;
  ReloadFile:=OK;
end;

function TFileEditor.ShouldSave: boolean;
begin
  ShouldSave:=GetModified;
end;

function TFileEditor.Save: Boolean;
begin
  if ShouldSave=false then begin Save:=true; Exit; end;
  if FileName = '' then Save := SaveAs else Save := SaveFile;
end;

function TFileEditor.SaveAs: Boolean;
var
  SavedName : String;
  SavedDiskLoadTime : cardinal;
  Inf : TTveFileInfo;
begin
  SaveAs := False;
  SavedName:=FileName;
  SavedDiskLoadTime:=Core.OnDiskLoadTime;
  if EditorDialog(edSaveAs, @FileName) <> cmCancel then
  begin
    FileName:=FExpand(FileName);
    Message(Owner, evBroadcast, cmUpdateTitle, Self);
    { the new name has no known state on disk }
    Core.OnDiskLoadTime:=0;
    Inf:=Doc.Info; Inf.Known:=false; Doc.Info:=Inf;
    if SaveFile then
      begin
        SaveAs := true;
      end
    else
      begin
        FileName:=SavedName;
        Core.OnDiskLoadTime:=SavedDiskLoadTime;
        Message(Owner, evBroadcast, cmUpdateTitle, Self);
      end;
    if IsClipboard then FileName := '';
    Message(Application,evBroadcast,cmFileNameChanged,Self);
  end;
end;

function TFileEditor.SaveAsk(Force: boolean): boolean;
var OK: boolean;
    D: Sw_integer;
begin
  if Force then
   begin
     if GetModified then
      OK:=Save
     else
      OK:=true;
   end
  else
   begin
     OK:=(GetModified=false);
     if (OK=false) and (Core.GetBindingCount>1) then
      OK:=true;
     if OK=false then
      begin
        if FileName = '' then D := edSaveUntitled else D := edSaveModify;
        case EditorDialog(D, @FileName) of
          cmYes    : OK := Save;
          cmNo     : OK:=true;
          cmCancel : begin
                      OK := False;
                      Message(Application,evBroadcast,cmSaveCancelled,Self);
                    end;
        end;
      end;
   end;
  SaveAsk:=OK;
end;

procedure TFileEditor.BindingsChanged;
begin
  Message(Application,evBroadcast,cmUpdateTitle,Self);
end;

procedure TFileEditor.HandleEvent(var Event: TEvent);
var SH,B: boolean;
    L: TTveLanguage;
begin
  case Event.What of
    evBroadcast :
      case Event.Command of
   cmFileNameChanged :
     if (Event.InfoPtr=nil) or (Event.InfoPtr = Pointer(Self)) then
     begin
       B:=IsFlagSet(efSyntaxHighlight);
       SH:=UseSyntaxHighlight(Self);
       if SH<>B then
         if SH then
           SetFlags(Flags or efSyntaxHighlight)
         else
           SetFlags(Flags and not efSyntaxHighlight);
       if UseTabsPattern(Self) then
         SetFlags(Flags or efUseTabCharacters);
       { the language of the file by its name }
       if IsFlagSet(efSyntaxHighlight) and (FileName<>'') then
         begin
           L:=TveLangForFile(FileName);
           SetLanguage(L);
         end;
     end;
      end;
  end;
  inherited HandleEvent(Event);
end;

function TFileEditor.Valid(Command: Word): Boolean;
var OK: boolean;
begin
  OK:=inherited Valid(Command);
  if OK and (Command=cmClose) then
    if IsClipboard=false then
      OK:=SaveAsk(false);
  Valid:=OK;
end;

function DefUseSyntaxHighlight(Editor: PFileEditor): boolean;
begin
  DefUseSyntaxHighlight:=Editor.IsFlagSet(efSyntaxHighlight);
end;

function DefUseTabsPattern(Editor: PFileEditor): boolean;
begin
  DefUseTabsPattern:=Editor.IsFlagSet(efUseTabCharacters);
end;

procedure RegisterWCEdit;
begin
  { stream registration deferred until class Load/Store builders are restored }
end;

end.
