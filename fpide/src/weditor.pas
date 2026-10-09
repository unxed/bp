{
    This file is part of the Free Pascal Integrated Development Environment
    Copyright (c) 1998 by Berczi Gabor

    Code editor template objects

    The engine of the editor is tve (the editor view of the tv3 family): the text is a
    piece table (TTveDoc), the view is a TTveView. This unit keeps the interface that the
    rest of the IDE knows (TCustomCodeEditor and its commands, the dialogs, the search flow).

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}
{$I globdir.inc}
unit WEditor;

{$mode objfpc}{$H-}
{$modeswitch nestedprocvars}
{$modeswitch autoderef}

interface
{tes}
uses
  Dos,Objects,Drivers,Views,Dialogs,Menus,
  FVConsts,
  WUtils,WViews,
  TveBuf,TveDoc,TveEditor,TveView,TveHl,TveFold,TveSearch;


const
      cmFileNameChanged      = 51234;
      cmASCIIChar            = 51235;
      cmClearLineHighlights  = 51236;
      cmSaveCancelled        = 51237;
      cmBreakLine            = 51238;
      cmSelStart             = 51239;
      cmSelEnd               = 51240;
      cmLastCursorPos        = 51241;
      cmIndentBlock          = 51242;
      cmUnIndentBlock        = 51243;
      cmSelectLine           = 51244;
      cmWriteBlock           = 51245;
      cmReadBlock            = 51246;
      cmPrintBlock           = 51247;
      cmResetDebuggerRow     = 51248;
      cmAddChar              = 51249;
      cmExpandCodeTemplate   = 51250;
      cmUpperCase            = 51251;
      cmLowerCase            = 51252;
      cmWindowStart          = 51253;
      cmWindowEnd            = 51254;
      cmFindMatchingDelimiter= 51255;
      cmFindMatchingDelimiterBack=51256;
      cmActivateMenu         = 51257;
      cmWordLowerCase        = 51258;
      cmWordUpperCase        = 51259;
      cmOpenAtCursor         = 51260;
      cmBrowseAtCursor       = 51261;
      cmInsertOptions        = 51262;
      cmToggleCase           = 51263;
      cmCreateFold           = 51264;
      cmToggleFold           = 51265;
      cmCollapseFold         = 51266;
      cmExpandFold           = 51267;
      cmDelToEndOfWord       = 51268;
      cmInputLineLen         = 51269;

      EditorTextBufSize = 32768;
      MaxLineLength     = 255;
      MaxLineCount      = 2000000;

      CodeTemplateCursorChar = '|'; { char to signal cursor pos in templates }

      efBackupFiles         = $00000001;
      efInsertMode          = $00000002;
      efAutoIndent          = $00000004;
      efUseTabCharacters    = $00000008;
      efBackSpaceUnindents  = $00000010;
      efPersistentBlocks    = $00000020;
      efSyntaxHighlight     = $00000040;
      efBlockInsCursor      = $00000080;
      efVerticalBlocks      = $00000100;
      efHighlightColumn     = $00000200;
      efHighlightRow        = $00000400;
      efAutoBrackets        = $00000800;
      efExpandAllTabs       = $00001000;
      efKeepTrailingSpaces  = $00002000;
      efCodeComplete        = $00004000;
      efFolds               = $00008000;
      efNoIndent            = $00010000;
      efKeepLineAttr        = $00020000;
      efSoftWrap            = $00040000;
      efStoreContent        = $80000000;

      attrAsm       = 1;
      attrComment   = 2;
      attrForceFull = 128;
      attrAll       = attrAsm+attrComment;

      edOutOfMemory   = 0;
      edReadError     = 1;
      edWriteError    = 2;
      edCreateError   = 3;
      edSaveModify    = 4;
      edSaveUntitled  = 5;
      edSaveAs        = 6;
      edFind          = 7;
      edSearchFailed  = 8;
      edReplace       = 9;
      edReplacePrompt = 10;
      edTooManyLines  = 11;
      edGotoLine      = 12;
      edReplaceFile   = 13;
      edWriteBlock    = 14;
      edReadBlock     = 15;
      edFileOnDiskChanged = 16;
      edChangedOnloading = 17;
      edSaveError     = 18;
      edReloadDiskmodifiedFile = 19;
      edReloadDiskAndIDEModifiedFile = 20;

      ffmOptions      = $0007; ffsOptions     = 0;
      ffmDirection    = $0008; ffsDirection   = 3;
      ffmScope        = $0010; ffsScope       = 4;
      ffmOrigin       = $0020; ffsOrigin      = 5;
      ffDoReplace     = $0040;
      ffReplaceAll    = $0080;


      ffCaseSensitive    = $0001;
      ffWholeWordsOnly   = $0002;
      ffPromptOnReplace  = $0004;

      ffForward          = $0000;
      ffBackward         = $0008;

      ffGlobal           = $0000;
      ffSelectedText     = $0010;

      ffFromCursor       = $0000;
      ffEntireScope      = $0020;

{$ifdef TEST_REGEXP}
      ffUseRegExp        = $0100;
      ffmUseRegExpFind   = $0004;
      ffmOptionsFind     = $0003;
      ffsUseRegExpFind   = 8 - 2;
      ffmUseRegExpReplace = $0008;
      ffsUseRegExpReplace = 8 - 3;
{$endif TEST_REGEXP}

      coTextColor         = 0;
      coWhiteSpaceColor   = 1;
      coCommentColor      = 2;
      coReservedWordColor = 3;
      coIdentifierColor   = 4;
      coStringColor       = 5;
      coNumberColor       = 6;
      coAssemblerColor    = 7;
      coSymbolColor       = 8;
      coDirectiveColor    = 9;
      coHexNumberColor    = 10;
      coTabColor          = 11;
      coAsmReservedColor  = 12;
      coBreakColor        = 13;
      coFirstColor        = 0;
      coLastColor         = coBreakColor;

      lfBreakpoint        = $0001;
      lfHighlightRow      = $0002;
      lfDebuggerRow       = $0004;
      lfSpecialRow        = $0008;

      eaMoveCursor        = 1;
      eaInsertLine        = 2;
      eaInsertText        = 3;
      eaDeleteLine        = 4;
      eaDeleteText        = 5;
      eaSelectionChanged  = 6;
      eaCut               = 7;
      eaPaste             = 8;
      eaPasteWin          = 9;
      eaDelChar           = 10;
      eaClear             = 11;
      eaCopyBlock         = 12;
      eaMoveBlock         = 13;
      eaDelBlock          = 14;
      eaReadBlock         = 15;
      eaIndentBlock       = 16;
      eaUnindentBlock     = 17;
      eaOverwriteText     = 18;
      eaUpperCase         = 19;
      eaLowerCase         = 20;
      eaToggleCase        = 21;
      eaDummy             = 22;
      LastAction          = eaDummy;

      ActionString : array [0..LastAction-1] of string[13] =
        ('','Move','InsLine','InsText','DelLine','DelText',
         'SelChange','Cut','Paste','PasteWin','DelChar','Clear',
         'CopyBlock','MoveBlock','DelBlock',
         'ReadBlock','IndentBlock','UnindentBlock','Overwrite',
         'UpperCase','LowerCase','ToggleCase');

      CIndicator    = #2#3#1;
      CEditor       = #33#34#35#36#37#38#39#40#41#42#43#44#45#46#47#48#49#50;

      TAB      = #9;
      FindStrSize = 79;



type
    Tcentre = (do_not_centre,do_centre);

    TCustomCodeEditor = class;
    PCustomCodeEditor = TCustomCodeEditor;
    TCustomCodeEditorCore = class;
    PCustomCodeEditorCore = TCustomCodeEditorCore;

    { A line as the rest of the IDE sees it: the text and the flags (breakpoint, debugger row ...). The text is in the document of the editor; a line object
      is a view of one line of it, valid until the text changes above it, so keep the number of the line instead of the object. }
    TCustomLine = class;
    PCustomLine = TCustomLine;
    TCustomLine = class(System.TObject)
    private
      FCore: TCustomCodeEditorCore;
      FIndex: sw_integer;
      FText: PString;
      FFlags: longint;
    public
      constructor Create(const AText: string; AFlags: longint);
      destructor Destroy; override;
      function    GetText: string; virtual;
      procedure   SetText(const AText: string); virtual;
      function    GetFlags: longint; virtual;
      procedure   SetFlags(AFlags: longint); virtual;
      function    IsFlagSet(AFlag: longint): boolean;
      procedure   SetFlagState(AFlag: longint; ASet: boolean);
      procedure   Attach(ACore: TCustomCodeEditorCore; AIndex: sw_integer);
    end;

    TSpecSymbolClass =
      (ssCommentPrefix,ssCommentSingleLinePrefix,ssCommentSuffix,ssStringPrefix,ssStringSuffix,
       ssDirectivePrefix,ssDirectiveSuffix,ssAsmPrefix,ssAsmSuffix);

    TEditorBookMark = record
      Valid  : boolean;
      Pos    : TPoint;
    end;

    TCompleteState = (csInactive,csOffering,csDenied);
    TCaseAction = (caToLowerCase,caToUpperCase,caToggleCase);

    { The text of a file that several editors show: the document, the flags of the lines, the editors that are bound to it. }
    TCustomCodeEditorCore = class(System.TObject)
    private
      FDoc: TTveDoc;
      FEditors: array of PCustomCodeEditor;
      FFlagAnchor: array of Integer;
      FFlagValue: array of longint;
      FLockFlag: sw_integer;
      FModifiedTime: cardinal;
      FTabSize: integer;
      FIndentSize: integer;
      FStoreUndo: boolean;
      FAddedLines: sw_integer;
      FExternalModified: boolean;
      procedure   NotifyAll(What: integer);
    public
      constructor Create;
      destructor Destroy; override;
      property    Doc: TTveDoc read FDoc;
      procedure   BindEditor(AEditor: PCustomCodeEditor);
      procedure   UnBindEditor(AEditor: PCustomCodeEditor);
      function    IsEditorBound(AEditor: PCustomCodeEditor): boolean;
      function    GetBindingCount: sw_integer;
      function    GetBindingIndex(AEditor: PCustomCodeEditor): sw_integer;
      function    CanDispose: boolean;
      function    GetEditor(Index: sw_integer): PCustomCodeEditor;
      function    GetModified: boolean; virtual;
      procedure   SetModified(AModified: boolean); virtual;
      function    GetModifyTime: cardinal; virtual;
      function    GetTabSize: integer; virtual;
      procedure   SetTabSize(ATabSize: integer); virtual;
      function    GetIndentSize: integer; virtual;
      procedure   SetIndentSize(AIndentSize: integer); virtual;
      function    GetStoreUndo: boolean; virtual;
      procedure   SetStoreUndo(AStore: boolean); virtual;
      function    IsClipboard: Boolean;
      { the flags of the lines }
      function    GetLineFlags(LineNo: sw_integer): longint;
      procedure   SetLineFlags(LineNo: sw_integer; AFlags: longint);
      procedure   Lock;
      procedure   UnLock;
      function    Locked: boolean;
      { text }
      function    GetLineCount: sw_integer; virtual;
      function    GetLineText(LineNo: sw_integer): string; virtual;
      procedure   SetLineText(LineNo: sw_integer; const S: string); virtual;
      procedure   DeleteAllLines; virtual;
      procedure   DeleteLine(LineNo: sw_integer); virtual;
      function    InsertLine(LineNo: sw_integer; const S: string): PCustomLine; virtual;
      procedure   AddLine(const S: string); virtual;
      procedure   ContentsChanged;
      procedure   ModifiedChanged;
      procedure   LimitsChanged;
      procedure   TabSizeChanged;
      procedure   StoreUndoChanged;
    end;

    TCustomCodeEditor = class(TTveView)
      SelStart   : TPoint;
      SelEnd     : TPoint;
      Highlight  : TRect;
      CurPos     : TPoint;
      ELockFlag   : integer;
      NoSelect   : Boolean;
      AlwaysShowScrollBars: boolean;
    private
      FCore: TCustomCodeEditorCore;
      FLines: array[0..3] of TCustomLine;
      FNextLine: integer;
      FFlags: longint;
      FKeyState: integer;
      FInASCII: boolean;
      FCompleteState: TCompleteState;
      FCompleteWord: string;
      FCompleteFrag: string;
      FErrorMessage: string;
      FHistory: array[0..31] of TPoint;
      FHistoryCount: integer;
      FInfoStack: array[0..7] of string;
      FInfoCount: integer;
      FUpdatingState: boolean;
      FSyncSkip: boolean;
      FSrch: TTveSearcher;
      FLastUndo,FLastRedo: sw_integer;
      FLastSel: boolean;
      FLastModified: boolean;
      procedure   UpdateCommandStates;
      procedure   PasteSelecting(const S: AnsiString);
      procedure   SyncFromEditor;
      procedure   ApplyFlags;
      procedure   RememberPos;
      function    OffsetOf(P: TPoint): int64;
      function    ColToCell(L: int64; Col: integer): integer;
      function    CellToCol(L: int64; Cell: integer): integer;
      function    PointOf(Offset: int64): TPoint;
    protected
      LastLocalCmd: word;
      KeyState    : Integer;
      DrawCalled,
      DrawCursorCalled: boolean;
      CurEvent    : PEvent;
      Bookmarks   : array[0..9] of TEditorBookmark;
      function    ClassAttr(C: Integer): TColorAttr; override;
      function    NormalAttr: TColorAttr; override;
      function    SelectedAttr: TColorAttr; override;
      function    MessageAttr: TColorAttr; override;
      function    HighlightAttr: TColorAttr; override;
      procedure   Changed; override;
      function    LineAttrHook(Sender: System.TObject; Line: Int64; var Attr: TColorAttr): Boolean;
      procedure   DrawLines(FirstLine: sw_integer);
      function    Overwrite: boolean;
      function    IsModal: boolean;
      procedure   CheckSels;
      procedure   CodeCompleteCheck;
      procedure   CodeCompleteApply;
      procedure   CodeCompleteCancel;
      procedure   UpdateUndoRedo(cm : word; action : byte);
      procedure   HideHighlight;
      function    ShouldExtend: boolean;
      function    ValidBlock: boolean;
      procedure   PushInfo(Const st : string);virtual;
      procedure   PopInfo;virtual;
    public
      constructor Create(var Bounds: TRect; AHScrollBar, AVScrollBar: PScrollBar; ACore: PCustomCodeEditorCore); overload;
      destructor Destroy; override;
      property    Core_: TCustomCodeEditorCore read FCore;
      procedure   ConvertEvent(var Event: TEvent); virtual;
      procedure   HandleEvent(var Event: TEvent); override;
      procedure   SetState(AState: Word; Enable: Boolean); override;
      procedure   LocalMenu(P: TPoint); virtual;
      function    GetLocalMenu: PMenu; virtual;
      function    GetCommandTarget: PView; virtual;
      function    CreateLocalMenuView(var Bounds: TRect; M: PMenu): PMenuPopup; virtual;
      function    GetPalette: TPalette; override;
    public
      procedure   DrawCursor; virtual;
      procedure   ResetCursor; override;
      procedure   DrawIndicator; virtual;
    public
      function    GetFlags: longint; virtual;
      procedure   SetFlags(AFlags: longint); virtual;
      function    GetModified: boolean; virtual;
      procedure   SetModified(AModified: boolean); virtual;
      function    GetStoreUndo: boolean; virtual;
      procedure   SetStoreUndo(AStore: boolean); virtual;
      function    GetSyntaxCompleted: boolean; virtual;
      procedure   SetSyntaxCompleted(SC: boolean); virtual;
      function    GetLastSyntaxedLine: sw_integer; virtual;
      procedure   SetLastSyntaxedLine(ALine: sw_integer); virtual;
      function    IsFlagSet(AFlag: longint): boolean;
      function    GetReservedColCount: sw_integer; virtual;
      function    GetTabSize: integer; virtual;
      procedure   SetTabSize(ATabSize: integer); virtual;
      function    GetIndentSize: integer; virtual;
      procedure   SetIndentSize(AIndentSize: integer); virtual;
      function    IsReadOnly: boolean; virtual;
      function    IsClipboard: Boolean; virtual;
      function    GetInsertMode: boolean; virtual;
      procedure   SetInsertMode(InsertMode: boolean); virtual;
      procedure   SetCurPtr(X,Y: sw_integer); virtual;
      procedure   GetSelectionArea(var StartP,EndP: TPoint); virtual;
      procedure   SetSelection(A, B: TPoint); virtual;
      procedure   SetHighlight(A, B: TPoint); virtual;
      procedure   ChangeCaseArea(StartP,EndP: TPoint; CaseAction: TCaseAction); virtual;
      procedure   SetLineFlagState(LineNo: sw_integer; Flags: longint; ASet: boolean);
      procedure   SetLineFlagExclusive(Flags: longint; LineNo: sw_integer);
      procedure   Update; override;
      procedure   ScrollTo(X, Y: sw_Integer);
      procedure   TrackCursor(centre:Tcentre); virtual;
      procedure   Lock; virtual;
      procedure   UnLock; virtual;
    public
      function    GetLineCount: sw_integer; virtual;
      function    GetLine(LineNo: sw_integer): PCustomLine; virtual;
      function    CharIdxToLinePos(Line,CharIdx: sw_integer): sw_integer; virtual;
      function    LinePosToCharIdx(Line,X: sw_integer): sw_integer; virtual;
      function    CursorCells(Line,Col: sw_integer): sw_integer;
      function    GetLineText(I: sw_integer): string; virtual;
      procedure   SetDisplayText(I: sw_integer;const S: string); virtual;
      function    GetDisplayText(I: sw_integer): string; virtual;
      procedure   SetLineText(I: sw_integer;const S: string); virtual;
      procedure   GetDisplayTextFormat(I: sw_integer;var DT,DF:string); virtual;
      function    GetLineFormat(I: sw_integer): string; virtual;
      procedure   SetLineFormat(I: sw_integer;const S: string); virtual;
      procedure   DeleteAllLines; virtual;
      procedure   DeleteLine(I: sw_integer); virtual;
      function    InsertLine(LineNo: sw_integer; const S: string): PCustomLine; virtual;
      procedure   AddLine(const S: string); virtual;
      function    GetErrorMessage: string; virtual;
      procedure   SetErrorMessage(const S: string); virtual;
      procedure   AdjustSelection(DeltaX, DeltaY: sw_integer);
      procedure   AdjustSelectionBefore(DeltaX, DeltaY: sw_integer);
      procedure   AdjustSelectionPos(OldCurPosX, OldCurPosY: sw_integer; DeltaX, DeltaY: sw_integer);
      procedure   GetContent(ALines: PUnsortedStringCollection); virtual;
      procedure   SetContent(ALines: PUnsortedStringCollection); virtual;
      function    LoadFromStream(Stream: PFastBufStream): boolean; virtual;
      function    SaveToStream(Stream: TStream): boolean; virtual;
      function    SaveAreaToStream(Stream: TStream; StartP,EndP: TPoint): boolean;virtual;
      function    LoadFromFile(const AFileName: string): boolean; virtual;
      function    SaveToFile(const AFileName: string): boolean; virtual;
    public
      function    InsertFrom(AEditor: PCustomCodeEditor): Boolean; virtual;
      function    InsertText(const S: string): Boolean; virtual;
    public
      procedure   FlagsChanged(OldFlags: longint); virtual;
      procedure   BindingsChanged; virtual;
      procedure   ContentsChanged; virtual;
      procedure   LimitsChanged; virtual;
      procedure   ModifiedChanged; virtual;
      procedure   PositionChanged; virtual;
      procedure   TabSizeChanged; virtual;
      procedure   SyntaxStateChanged; virtual;
      procedure   StoreUndoChanged; virtual;
      procedure   SelectionChanged; virtual;
      procedure   HighlightChanged; virtual;
      procedure   DoLimitsChanged; virtual;
    public
      function    GetSpecSymbolCount(SpecClass: TSpecSymbolClass): integer; virtual;
      function    GetSpecSymbol(SpecClass: TSpecSymbolClass; Index: integer): pstring; virtual;
      function    IsReservedWord(const S: string): boolean; virtual;
      function    IsAsmReservedWord(const S: string): boolean; virtual;
    public
      function    TranslateCodeTemplate(var Shortcut: string; ALines: PUnsortedStringCollection): boolean; virtual;
      function    SelectCodeTemplate(var ShortCut: string): boolean; virtual;
      function    CompleteCodeWord(const WordS: string; var Text: string): boolean; virtual;
      function    GetCodeCompleteWord: string; virtual;
      procedure   SetCodeCompleteWord(const S: string); virtual;
      function    GetCodeCompleteFrag: string; virtual;
      procedure   SetCodeCompleteFrag(const S: string); virtual;
      function    GetCompleteState: TCompleteState; virtual;
      procedure   SetCompleteState(AState: TCompleteState); virtual;
      procedure   ClearCodeCompleteWord; virtual;
    public
      function    UpdateAttrs(FromLine: sw_integer; Attrs: byte): sw_integer; virtual;
      function    UpdateAttrsRange(FromLine, ToLine: sw_integer; Attrs: byte): sw_integer; virtual;
    public
      procedure   AddAction(AAction: byte; AStartPos, AEndPos: TPoint; AText: string;AFlags : longint); virtual;
      procedure   AddGroupedAction(AAction : byte); virtual;
      procedure   CloseGroupedAction(AAction : byte); virtual;
      function    GetUndoActionCount: sw_integer; virtual;
      function    GetRedoActionCount: sw_integer; virtual;
    public
      SearchRunCount: integer;
      InASCIIMode: boolean;
      procedure Indent; virtual;
      procedure CharLeft; virtual;
      procedure CharRight; virtual;
      procedure WordLeft; virtual;
      procedure WordRight; virtual;
      procedure LineStart; virtual;
      procedure LineEnd; virtual;
      procedure LineUp; virtual;
      procedure LineDown; virtual;
      procedure PageUp; virtual;
      procedure PageDown; virtual;
      procedure TextStart; virtual;
      procedure TextEnd; virtual;
      procedure WindowStart; virtual;
      procedure WindowEnd; virtual;
      procedure JumpSelStart; virtual;
      procedure JumpSelEnd; virtual;
      procedure JumpMark(MarkIdx: integer); virtual;
      procedure DefineMark(MarkIdx: integer); virtual;
      procedure JumpToLastCursorPos; virtual;
      procedure FindMatchingDelimiter(ScanForward: boolean); virtual;
      procedure CreateFoldFromBlock; virtual;
      procedure ToggleFold; virtual;
      procedure CollapseFold; virtual;
      procedure ExpandFold; virtual;
      procedure UpperCase; virtual;
      procedure LowerCase; virtual;
      procedure WordLowerCase; virtual;
      procedure WordUpperCase; virtual;
      procedure InsertOptions; virtual;
      procedure ToggleCase; virtual;
      function  InsertNewLine: Sw_integer; virtual;
      procedure BreakLine; virtual;
      procedure BackSpace; virtual;
      procedure DelChar; virtual;
      procedure DelWord; virtual;
      procedure DelToEndOfWord; virtual;
      procedure DelStart; virtual;
      procedure DelEnd; virtual;
      procedure DelLine; virtual;
      procedure InsMode; virtual;
      procedure StartSelect; virtual;
      procedure EndSelect; virtual;
      procedure DelSelect; virtual;
      procedure HideSelect; virtual;
      procedure CopyBlock; virtual;
      procedure MoveBlock; virtual;
      procedure IndentBlock; virtual;
      procedure UnindentBlock; virtual;
      procedure SelectWord; virtual;
      procedure SelectLine; virtual;
      procedure WriteBlock; virtual;
      procedure ReadBlock; virtual;
      procedure PrintBlock; virtual;
      procedure ExpandCodeTemplate; virtual;
      procedure AddChar(C: char); virtual;
      procedure AddCharStr(const Ch: string); virtual;
      procedure AddString(const S: string);
      function  SelectionText: AnsiString;
      procedure InsertBlockText(const S: AnsiString);
      function  ClipCopy: Boolean; virtual;
      procedure ClipCut; virtual;
      procedure ClipPaste; virtual;
      function  GetCurrentWord : string;
      function  GetCurrentWordArea(var StartP,EndP: TPoint): boolean;
      procedure Undo; virtual;
      procedure Redo; virtual;
      procedure Find; virtual;
      procedure Replace; virtual;
      procedure DoSearchReplace; virtual;
      procedure GotoLine; virtual;
      procedure SelectAll(Enable: boolean); virtual;
    end;

    TCodeEditorDialog = function(Dialog: Integer; Info: Pointer): Word;

    TEditorInputLine = class(TInputLine)
         Procedure   HandleEvent(var Event : TEvent);override;
    end;
    PEditorInputLine = TEditorInputLine;

    TSearchHelperDialog = class(TDialog)
             OkButton: PButton;
             Procedure   HandleEvent(var Event : TEvent);override;
    end;

    PSearchHelperDialog = TSearchHelperDialog;

const
     { used for ShiftDel and ShiftIns to avoid
       GetShiftState to be considered for extending
       selection (PM) }
     DontConsiderShiftState: boolean  = false;

     CodeCompleteMinLen : byte = 4; { minimum length of text to try to complete }

     ToClipCmds         : TCommandBytes = ([cmCut,cmCopy,
       { cmUnselect should because like cut, copy, copywin:
         if there is a selection, it is active, else it isn't }
       cmUnselect]);
     FromClipCmds       : TCommandBytes = ([cmPaste]);
     NulClipCmds        : TCommandBytes = ([cmClear]);
     UndoCmd            : TCommandBytes = ([cmUndo]);
     RedoCmd            : TCommandBytes = ([cmRedo]);

function ExtractTabs(S: string; TabSize: Sw_integer): string;

function StdEditorDialog(Dialog: Integer; Info: Pointer): word;

const
     DefaultSaveExt     : string[12] = '.pas';
     FileDir            : DirStr = '';

     EditorDialog       : TCodeEditorDialog = {$ifdef fpc}@{$endif}StdEditorDialog;
     Clipboard          : PCustomCodeEditor = nil;
     FindStr            : String[FindStrSize] = '';
     ReplaceStr         : String[FindStrSize] = '';
     FindReplaceEditor  : PCustomCodeEditor = nil;
     FindFlags          : word = ffPromptOnReplace;
{$ifndef NO_UNTYPEDSET}
  {$define USE_UNTYPEDSET}
{$endif ndef NO_UNTYPEDSET}
     WhiteSpaceChars    {$ifdef USE_UNTYPEDSET}: set of char {$endif} = [#0,#32,#255];
     TabChars           {$ifdef USE_UNTYPEDSET}: set of char {$endif} = [#9];
     HashChars          {$ifdef USE_UNTYPEDSET}: set of char {$endif} = ['#'];
     AlphaChars         {$ifdef USE_UNTYPEDSET}: set of char {$endif} = ['A'..'Z','a'..'z','_'];
     NumberChars        {$ifdef USE_UNTYPEDSET}: set of char {$endif} = ['0'..'9'];
     HexNumberChars     {$ifdef USE_UNTYPEDSET}: set of char {$endif} = ['0'..'9','A'..'F','a'..'f'];
     RealNumberChars    {$ifdef USE_UNTYPEDSET}: set of char {$endif} = ['E','e','.'{,'+','-'}];

procedure RegisterWEditor;

implementation

uses
  Strings,Video,MsgBox,App,StdDlg,Validate,
  TvClip,TvColors,TvKeys,TvEvents,TvDrawBuf,
  TveLayout,TveBlocks,TveCmds,TveLang,
  WConsts,WCEdit,TvUStr,TvUtf8,TvPath;


type
    RecordWord = sw_word;

     TFindDialogRec = packed record
       Find     : String[FindStrSize];
       Options  : RecordWord{longint};
       { checkboxes need 32  bits PM  }
       { reverted to word in dialogs.TCluster for TP compatibility (PM) }
       { anyhow its complete nonsense : you can only have 16 fields
         but use a longint to store it !! }
       Direction: RecordWord;{ and tcluster has word size }
       Scope    : RecordWord;
       Origin   : RecordWord;
     end;

     TReplaceDialogRec = packed record
       Find     : String[FindStrSize];
       Replace  : String[FindStrSize];
       Options  : RecordWord{longint};
       Direction: RecordWord;
       Scope    : RecordWord;
       Origin   : RecordWord;
     end;

     TGotoLineDialogRec = packed record
       LineNo  : string[5];
       Lines   : sw_integer;
     end;

const
     kbShift = kbLeftShift+kbRightShift;

const
  FirstKeyCount = 46;
  FirstKeys: array[0..FirstKeyCount * 2] of Word = (FirstKeyCount,
    Ord(^A), cmWordLeft, Ord(^B), cmJumpLine, Ord(^C), cmPageDown,
    Ord(^D), cmCharRight, Ord(^E), cmLineUp,
    Ord(^F), cmWordRight, Ord(^G), cmDelChar,
    Ord(^H), cmBackSpace, Ord(^J), cmExpandCodeTemplate,
    Ord(^K), $FF02, Ord(^L), cmSearchAgain,
    Ord(^M), cmNewLine, Ord(^N), cmBreakLine,
    Ord(^O), $FF03,
    Ord(^P), cmASCIIChar, Ord(^Q), $FF01,
    Ord(^R), cmPageUp, Ord(^S), cmCharLeft,
    Ord(^T), cmDelToEndOfWord, Ord(^U), cmUndo,
    Ord(^V), cmInsMode, Ord(^X), cmLineDown,
    Ord(^Y), cmDelLine, kbLeft, cmCharLeft,
    kbRight, cmCharRight, kbCtrlLeft, cmWordLeft,
    kbCtrlRight, cmWordRight, kbHome, cmLineStart,
    kbCtrlHome, cmWindowStart, kbCtrlEnd, cmWindowEnd,
    kbEnd, cmLineEnd, kbUp, cmLineUp,
    kbDown, cmLineDown, kbPgUp, cmPageUp,
    kbPgDn, cmPageDown, kbCtrlPgUp, cmTextStart,
    kbCtrlPgDn, cmTextEnd, kbIns, cmInsMode,
    kbDel, cmDelChar, kbShiftIns, cmPaste,
    kbShiftDel, cmCut, kbCtrlIns, cmCopy,
    kbCtrlDel, cmClear,
    kbCtrlGrayMul, cmToggleFold, kbCtrlGrayMinus, cmCollapseFold, kbCtrlGrayPlus, cmExpandFold);
  QuickKeyCount = 29;
  QuickKeys: array[0..QuickKeyCount * 2] of Word = (QuickKeyCount,
    Ord('A'), cmReplace, Ord('C'), cmTextEnd,
    Ord('D'), cmLineEnd, Ord('F'), cmFind,
    Ord('H'), cmDelStart, Ord('R'), cmTextStart,
    Ord('S'), cmLineStart, Ord('Y'), cmDelEnd,
    Ord('G'), cmJumpLine, Ord('A'), cmReplace,
    Ord('B'), cmSelStart, Ord('K'), cmSelEnd,
    Ord('P'), cmLastCursorPos,
    Ord('E'), cmWindowStart, Ord('T'), cmWindowStart,
    Ord('U'), cmWindowEnd, Ord('X'), cmWindowEnd,
    Ord('['), cmFindMatchingDelimiter, Ord(']'), cmFindMatchingDelimiterBack,
    Ord('0'), cmJumpMark0, Ord('1'), cmJumpMark1, Ord('2'), cmJumpMark2,
    Ord('3'), cmJumpMark3, Ord('4'), cmJumpMark4, Ord('5'), cmJumpMark5,
    Ord('6'), cmJumpMark6, Ord('7'), cmJumpMark7, Ord('8'), cmJumpMark8,
    Ord('9'), cmJumpMark9);
  BlockKeyCount = 30;
  BlockKeys: array[0..BlockKeyCount * 2] of Word = (BlockKeyCount,
    Ord('B'), cmStartSelect, Ord('C'), cmCopyBlock,
    Ord('H'), cmHideSelect, Ord('K'), cmEndSelect,
    Ord('Y'), cmDelSelect, Ord('V'), cmMoveBlock,
    Ord('I'), cmIndentBlock, Ord('U'), cmUnindentBlock,
    Ord('T'), cmSelectWord, Ord('L'), cmSelectLine,
    Ord('W'), cmWriteBlock, Ord('R'), cmReadBlock,
    Ord('P'), cmPrintBlock,
    Ord('N'), cmUpperCase, Ord('O'), cmLowerCase,
    Ord('D'), cmActivateMenu,
    Ord('E'), cmWordLowerCase, Ord('F'), cmWordUpperCase,
    Ord('S'), cmSave, Ord('A'), cmCreateFold,
    Ord('0'), cmSetMark0, Ord('1'), cmSetMark1, Ord('2'), cmSetMark2,
    Ord('3'), cmSetMark3, Ord('4'), cmSetMark4, Ord('5'), cmSetMark5,
    Ord('6'), cmSetMark6, Ord('7'), cmSetMark7, Ord('8'), cmSetMark8,
    Ord('9'), cmSetMark9);
  MiscKeyCount = 6;
  MiscKeys: array[0..MiscKeyCount * 2] of Word = (MiscKeyCount,
    Ord('A'), cmOpenAtCursor, Ord('B'), cmBrowseAtCursor,
    Ord('G'), cmJumpLine, Ord('O'), cmInsertOptions,
    Ord('U'), cmToggleCase, Ord('L'), cmSelectLine);
  KeyMap: array[0..3] of Pointer = (@FirstKeys, @QuickKeys, @BlockKeys, @MiscKeys);

function ScanKeyMap(KeyMap: Pointer; KeyCode: Word): Word;
type
  pword = ^word;
var
  p : pword;
  count : sw_word;
begin
  p:=keymap;
  count:=p^;
  inc(p);
  while (count>0) do
   begin
     if (lo(p^)=lo(keycode)) and
        ((hi(p^)=0) or (hi(p^)=hi(keycode))) then
      begin
        inc(p);
        scankeymap:=p^;
        Exit;
      end;
     inc(p,2);
     dec(count);
   end;
  scankeymap:=0;
end;

function IsWordSeparator(C: char): boolean;
begin
  IsWordSeparator:=C in
      [' ',#0,#255,':','=','''','"',
      '.',',','/',';','$','#',
      '(',')','<','>','^','*',
      '+','-','?','&','[',']',
      '{','}','@','~','%','\',
      '!'];
end;

{function IsSpace(C: char): boolean;
begin
  IsSpace:=C in[' ',#0,#255];
end;}

function LTrim(S: string): string;
begin
  while (length(S)>0) and (S[1] in [#0,TAB,#32]) do
    Delete(S,1,1);
  LTrim:=S;
end;

{ TAB are not same as spaces if UseTabs is set PM }
function RTrim(S: string;cut_tabs : boolean): string;
begin
  while (length(S)>0) and
    ((S[length(S)] in [#0,#32]) or
    ((S[Length(S)]=TAB) and cut_tabs)) do
    Delete(S,length(S),1);
  RTrim:=S;
end;

function Trim(S: string): string;
begin
  Trim:=RTrim(LTrim(S),true);
end;

function EatIO: integer;
begin
  EatIO:=IOResult;
end;

function ExistsFile(const FileName: string): boolean;
var f: file;
    Exists: boolean;
begin
  if FileName='' then Exists:=false else
 begin
  {$I-}
  Assign(f,FileName);
  Reset(f,1);
  Exists:=EatIO=0;
  Close(f);
  EatIO;
  {$I+}
 end;
  ExistsFile:=Exists;
end;

function StrToInt(const S: string): longint;
var L: longint;
    C: integer;
begin
  Val(S,L,C); if C<>0 then L:=-1;
  StrToInt:=L;
end;

function RExpand(const S: string; MinLen: byte): string;
begin
  if length(S)<MinLen then
   RExpand:=S+CharStr(' ',MinLen-length(S))
  else
   RExpand:=S;
end;

{
function upper(const s : string) : string;
var
  i  : Sw_word;
begin
  for i:=1 to length(s) do
   if s[i] in ['a'..'z'] then
    upper[i]:=char(byte(s[i])-32)
   else
    upper[i]:=s[i];
  upper[0]:=s[0];
end;
}
type TPosOfs = int64;

function PosToOfs(const X,Y: sw_integer): TPosOfs;
begin
  PosToOfs:=TPosOfs(y) shl (sizeof(sw_integer)*8) or x;
end;

function PosToOfsP(const P: TPoint): TPosOfs;
begin
  PosToOfsP:=PosToOfs(P.X,P.Y);
end;

function PointOfs(P: TPoint): TPosOfs;
begin
  PointOfs:={longint(P.Y)*MaxLineLength+P.X}PosToOfsP(P);
end;


function ExtractTabs(S: string; TabSize: Sw_integer): string;
var
  I,Col,PAdd,L: Sw_integer;
  R: string;
begin
  if Pos(TAB,S)=0 then
    begin
      ExtractTabs:=S;
      Exit;
    end;
  R:='';
  I:=1; Col:=0;
  while I<=length(S) do
   begin
     if S[I]=TAB then
      begin
        PAdd:=TabSize-(Col mod TabSize);
        R:=R+CharStr(' ',PAdd);
        Inc(Col,PAdd);
        Inc(I);
      end
     else
      begin
        L:=U8CharBytes(S,I);
        R:=R+copy(S,I,L);
        Inc(I,L);
        Inc(Col);
      end;
   end;
  ExtractTabs:=R;
end;

{ --- TCustomLine: a view of one line --- }

constructor TCustomLine.Create(const AText: string; AFlags: longint);
begin
  inherited Create;
  FText:=NewStr(AText);
  FFlags:=AFlags;
  FCore:=nil;
  FIndex:=-1;
end;

destructor TCustomLine.Destroy;
begin
  if Assigned(FText) then
    DisposeStr(FText);
  FText:=nil;
  inherited Destroy;
end;

procedure TCustomLine.Attach(ACore: TCustomCodeEditorCore; AIndex: sw_integer);
begin
  FCore:=ACore;
  FIndex:=AIndex;
end;

function TCustomLine.GetText: string;
begin
  if Assigned(FCore) then
    GetText:=FCore.GetLineText(FIndex)
  else
    GetText:=GetStr(FText);
end;

procedure TCustomLine.SetText(const AText: string);
begin
  if Assigned(FCore) then
    FCore.SetLineText(FIndex,AText)
  else
    SetStr(FText,AText);
end;

function TCustomLine.GetFlags: longint;
begin
  if Assigned(FCore) then
    GetFlags:=FCore.GetLineFlags(FIndex)
  else
    GetFlags:=FFlags;
end;

procedure TCustomLine.SetFlags(AFlags: longint);
begin
  if Assigned(FCore) then
    FCore.SetLineFlags(FIndex,AFlags)
  else
    FFlags:=AFlags;
end;

function TCustomLine.IsFlagSet(AFlag: longint): boolean;
begin
  IsFlagSet:=(GetFlags and AFlag)=AFlag;
end;

procedure TCustomLine.SetFlagState(AFlag: longint; ASet: boolean);
begin
  if ASet then
    SetFlags(GetFlags or AFlag)
  else
    SetFlags(GetFlags and not AFlag);
end;

{ --- TCustomCodeEditorCore --- }

constructor TCustomCodeEditorCore.Create;
begin
  inherited Create;
  FDoc:=TTveDoc.Create;
  FTabSize:=8;
  FIndentSize:=1;
  FStoreUndo:=true;
end;

destructor TCustomCodeEditorCore.Destroy;
begin
  FDoc.Free;
  inherited Destroy;
end;

procedure TCustomCodeEditorCore.BindEditor(AEditor: PCustomCodeEditor);
begin
  if IsEditorBound(AEditor) then
    Exit;
  SetLength(FEditors,Length(FEditors)+1);
  FEditors[High(FEditors)]:=AEditor;
  NotifyAll(0);
end;

procedure TCustomCodeEditorCore.UnBindEditor(AEditor: PCustomCodeEditor);
var I,J: sw_integer;
begin
  for I:=0 to High(FEditors) do
    if FEditors[I]=AEditor then
      begin
        for J:=I to High(FEditors)-1 do
          FEditors[J]:=FEditors[J+1];
        SetLength(FEditors,Length(FEditors)-1);
        Break;
      end;
  NotifyAll(0);
end;

function TCustomCodeEditorCore.IsEditorBound(AEditor: PCustomCodeEditor): boolean;
begin
  IsEditorBound:=GetBindingIndex(AEditor)>=0;
end;

function TCustomCodeEditorCore.GetBindingCount: sw_integer;
begin
  GetBindingCount:=Length(FEditors);
end;

function TCustomCodeEditorCore.GetBindingIndex(AEditor: PCustomCodeEditor): sw_integer;
var I: sw_integer;
begin
  for I:=0 to High(FEditors) do
    if FEditors[I]=AEditor then
      Exit(I);
  GetBindingIndex:=-1;
end;

function TCustomCodeEditorCore.GetEditor(Index: sw_integer): PCustomCodeEditor;
begin
  GetEditor:=FEditors[Index];
end;

function TCustomCodeEditorCore.CanDispose: boolean;
begin
  CanDispose:=Length(FEditors)=0;
end;

{ What: 0 bindings, 1 contents, 2 modified, 3 limits, 4 tab size, 5 store undo }
procedure TCustomCodeEditorCore.NotifyAll(What: integer);
var I: sw_integer;
    E: PCustomCodeEditor;
begin
  for I:=0 to High(FEditors) do
    begin
      E:=FEditors[I];
      case What of
        0: E.BindingsChanged;
        1: E.ContentsChanged;
        2: E.ModifiedChanged;
        3: E.DoLimitsChanged;
        4: E.TabSizeChanged;
        5: E.StoreUndoChanged;
      end;
    end;
end;

procedure TCustomCodeEditorCore.ContentsChanged;
begin
  if FLockFlag=0 then NotifyAll(1);
end;

procedure TCustomCodeEditorCore.ModifiedChanged;
begin
  NotifyAll(2);
end;

procedure TCustomCodeEditorCore.LimitsChanged;
begin
  if FLockFlag=0 then NotifyAll(3);
end;

procedure TCustomCodeEditorCore.TabSizeChanged;
begin
  NotifyAll(4);
end;

procedure TCustomCodeEditorCore.StoreUndoChanged;
begin
  NotifyAll(5);
end;

function TCustomCodeEditorCore.GetModified: boolean;
begin
  GetModified:=FDoc.Modified or FExternalModified;
end;

procedure TCustomCodeEditorCore.SetModified(AModified: boolean);
var Old: boolean;
begin
  Old:=GetModified;
  if AModified then
    FExternalModified:=true
  else
    begin
      FExternalModified:=false;
      FDoc.MarkSaved;
    end;
  FModifiedTime:=cardinal(WUtils.Now);
  if Old<>GetModified then
    ModifiedChanged;
end;

function TCustomCodeEditorCore.GetModifyTime: cardinal;
begin
  GetModifyTime:=FModifiedTime;
end;

function TCustomCodeEditorCore.GetTabSize: integer;
begin
  GetTabSize:=FTabSize;
end;

procedure TCustomCodeEditorCore.SetTabSize(ATabSize: integer);
begin
  if (ATabSize>0) and (ATabSize<>FTabSize) then
    begin
      FTabSize:=ATabSize;
      TabSizeChanged;
    end;
end;

function TCustomCodeEditorCore.GetIndentSize: integer;
begin
  GetIndentSize:=FIndentSize;
end;

procedure TCustomCodeEditorCore.SetIndentSize(AIndentSize: integer);
begin
  if AIndentSize>0 then
    FIndentSize:=AIndentSize;
end;

function TCustomCodeEditorCore.GetStoreUndo: boolean;
begin
  GetStoreUndo:=FStoreUndo;
end;

procedure TCustomCodeEditorCore.SetStoreUndo(AStore: boolean);
begin
  if FStoreUndo<>AStore then
    begin
      FStoreUndo:=AStore;
      StoreUndoChanged;
    end;
end;

function TCustomCodeEditorCore.IsClipboard: Boolean;
begin
  IsClipboard:=(Clipboard<>nil) and (Clipboard.Core_=Self);
end;

function TCustomCodeEditorCore.GetLineFlags(LineNo: sw_integer): longint;
var I: sw_integer;
begin
  Result:=0;
  for I:=0 to High(FFlagAnchor) do
    if FDoc.AnchorAlive(FFlagAnchor[I]) and
       (FDoc.Buffer.LineOfOffset(FDoc.AnchorPos(FFlagAnchor[I]))=LineNo) then
      Result:=Result or FFlagValue[I];
end;

procedure TCustomCodeEditorCore.SetLineFlags(LineNo: sw_integer; AFlags: longint);
var I,J: sw_integer;
    Done: boolean;
begin
  if (LineNo<0) or (LineNo>=FDoc.Buffer.LineCount) then
    Exit;
  Done:=false;
  { forget the anchors of lines that are gone }
  I:=0;
  while I<=High(FFlagAnchor) do
    if not FDoc.AnchorAlive(FFlagAnchor[I]) then
      begin
        for J:=I to High(FFlagAnchor)-1 do
          begin
            FFlagAnchor[J]:=FFlagAnchor[J+1];
            FFlagValue[J]:=FFlagValue[J+1];
          end;
        SetLength(FFlagAnchor,Length(FFlagAnchor)-1);
        SetLength(FFlagValue,Length(FFlagValue)-1);
      end
    else
      Inc(I);
  for I:=0 to High(FFlagAnchor) do
    if FDoc.Buffer.LineOfOffset(FDoc.AnchorPos(FFlagAnchor[I]))=LineNo then
      begin
        if not Done then
          begin
            FFlagValue[I]:=AFlags;
            Done:=true;
          end
        else
          FFlagValue[I]:=0;
      end;
  if (not Done) and (AFlags<>0) then
    begin
      SetLength(FFlagAnchor,Length(FFlagAnchor)+1);
      SetLength(FFlagValue,Length(FFlagValue)+1);
      FFlagAnchor[High(FFlagAnchor)]:=FDoc.AddAnchor(FDoc.Buffer.LineStart(LineNo));
      FFlagValue[High(FFlagValue)]:=AFlags;
    end;
  ContentsChanged;
end;

procedure TCustomCodeEditorCore.Lock;
begin
  Inc(FLockFlag);
end;

procedure TCustomCodeEditorCore.UnLock;
begin
  if FLockFlag>0 then
    Dec(FLockFlag);
  if FLockFlag=0 then
    begin
      NotifyAll(1);
      NotifyAll(3);
    end;
end;

function TCustomCodeEditorCore.Locked: boolean;
begin
  Locked:=FLockFlag>0;
end;

function TCustomCodeEditorCore.GetLineCount: sw_integer;
begin
  GetLineCount:=FDoc.Buffer.LineCount;
end;

function TCustomCodeEditorCore.GetLineText(LineNo: sw_integer): string;
begin
  if (LineNo<0) or (LineNo>=FDoc.Buffer.LineCount) then
    GetLineText:=''
  else
    GetLineText:=FDoc.Buffer.LineText(LineNo);
end;

procedure TCustomCodeEditorCore.SetLineText(LineNo: sw_integer; const S: string);
var Start: int64;
begin
  if (LineNo<0) or (LineNo>=FDoc.Buffer.LineCount) then
    Exit;
  if FDoc.Buffer.LineText(LineNo)=S then
    Exit;
  Start:=FDoc.Buffer.LineStart(LineNo);
  FDoc.Replace(Start,FDoc.Buffer.LineLength(LineNo),S);
  ContentsChanged;
end;

procedure TCustomCodeEditorCore.DeleteAllLines;
begin
  FDoc.Replace(0,FDoc.Buffer.Length,'');
  FAddedLines:=0;
  ContentsChanged;
  LimitsChanged;
end;

procedure TCustomCodeEditorCore.DeleteLine(LineNo: sw_integer);
var Start,Stop: int64;
begin
  if (LineNo<0) or (LineNo>=FDoc.Buffer.LineCount) then
    Exit;
  Start:=FDoc.Buffer.LineStart(LineNo);
  if LineNo+1<FDoc.Buffer.LineCount then
    Stop:=FDoc.Buffer.LineStart(LineNo+1)
  else
    begin
      Stop:=FDoc.Buffer.Length;
      if Start>0 then Dec(Start);          { the line break before the last line goes with it }
    end;
  FDoc.Delete(Start,Stop-Start);
  ContentsChanged;
end;

function TCustomCodeEditorCore.InsertLine(LineNo: sw_integer; const S: string): PCustomLine;
begin
  if LineNo>=FDoc.Buffer.LineCount then
    begin
      AddLine(S);
      LineNo:=FDoc.Buffer.LineCount-1;
    end
  else
    begin
      if LineNo<0 then LineNo:=0;
      FDoc.Insert(FDoc.Buffer.LineStart(LineNo),S+#10);
    end;
  ContentsChanged;
  Result:=nil;
end;

procedure TCustomCodeEditorCore.AddLine(const S: string);
begin
  if (FDoc.Buffer.Length=0) and (FAddedLines=0) then
    FDoc.Insert(0,S)
  else
    FDoc.Insert(FDoc.Buffer.Length,#10+S);
  Inc(FAddedLines);
  ContentsChanged;
end;

{ --- TCustomCodeEditor: the editor, on tve --- }



constructor TCustomCodeEditor.Create(var Bounds: TRect; AHScrollBar, AVScrollBar: PScrollBar; ACore: PCustomCodeEditorCore);
begin
  inherited Create(Bounds,AHScrollBar,AVScrollBar,ACore.Doc,false);
  FCore:=ACore;
  Options:=Options or ofFirstClick;
  KeysEnabled:=false;
  MultiClick:=false;
  OnLineAttr:=@LineAttrHook;
  Gutter:=false;
  FFlags:=0;
  KeyState:=0;
  Editor.Opt.TabSize:=ACore.GetTabSize;
  Editor.Opt.IndentSize:=ACore.GetIndentSize;
  FCore.BindEditor(Self);
end;

destructor TCustomCodeEditor.Destroy;
begin
  if Clipboard=Self then
    Clipboard:=nil;
  FSrch.Free;
  FCore.UnBindEditor(Self);
  if FCore.CanDispose then
    FCore.Free;
  inherited Destroy;
end;

{ the colours: the 18 entries of the palette of the editor (see CEditor) }
function TCustomCodeEditor.NormalAttr: TColorAttr;
begin
  Result:=GetColor(1)[0];
end;

function TCustomCodeEditor.SelectedAttr: TColorAttr;
begin
  Result:=GetColor(10)[0];
end;

function TCustomCodeEditor.MessageAttr: TColorAttr;
begin
  Result:=GetColor(16)[0];
end;

function TCustomCodeEditor.HighlightAttr: TColorAttr;
begin
  Result:=GetColor(10)[0];
end;

function TCustomCodeEditor.ClassAttr(C: Integer): TColorAttr;
begin
  case C of
    hcComment: Result:=GetColor(3)[0];
    hcKeyword,hcType: Result:=GetColor(4)[0];
    hcBuiltin: Result:=GetColor(4)[0];
    hcString,hcEscape: Result:=GetColor(6)[0];
    hcNumber: Result:=GetColor(7)[0];
    hcAsm: Result:=GetColor(8)[0];
    hcOperator,hcDelimiter: Result:=GetColor(9)[0];
    hcPreproc: Result:=GetColor(13)[0];
  else
    Result:=GetColor(1)[0];
  end;
end;

function TCustomCodeEditor.LineAttrHook(Sender: System.TObject; Line: Int64; var Attr: TColorAttr): Boolean;
var F: longint;
begin
  Result:=false;
  F:=FCore.GetLineFlags(Line);
  if F=0 then
    Exit;
  if (F and (lfHighlightRow or lfDebuggerRow))<>0 then
    begin
      { the row where the debugger stopped / a highlighted row; on a breakpoint it still differs from the breakpoint colour }
      Attr:=GetColor(12)[0];
      Result:=true;
    end
  else if (F and lfBreakpoint)<>0 then
    begin
      Attr:=GetColor(16)[0];
      Result:=true;
    end
  else if (F and lfSpecialRow)<>0 then
    begin
      Attr:=GetColor(3)[0];
      Result:=true;
    end;
end;

function TCustomCodeEditor.GetPalette: TPalette;
begin
  Result:=MakePalette(CEditor);
end;

{ --- state kept in the fields the IDE reads --- }

{ The IDE counts columns in characters of the text with its tabs expanded (a wide character is one column); tve counts cells. }
function TCustomCodeEditor.ColToCell(L: int64; Col: integer): integer;
var DT: AnsiString;
    N: integer;
begin
  if (L<0) or (L>=Doc.Buffer.LineCount) then
    Exit(Col);
  DT:=ExtractTabs(Doc.Buffer.LineText(L),Editor.Opt.TabSize);
  N:=U8Len(DT);
  if Col<=N then
    ColToCell:=U8Cells(DT,0,Col)
  else
    ColToCell:=U8Cells(DT,0,N)+(Col-N);
end;

function TCustomCodeEditor.CellToCol(L: int64; Cell: integer): integer;
var DT: AnsiString;
    Cells: integer;
begin
  if (L<0) or (L>=Doc.Buffer.LineCount) then
    Exit(Cell);
  DT:=ExtractTabs(Doc.Buffer.LineText(L),Editor.Opt.TabSize);
  Cells:=U8Cells(DT,0,U8Len(DT));
  if Cell<=Cells then
    CellToCol:=U8ColAtCell(DT,Cell)
  else
    CellToCol:=U8Len(DT)+(Cell-Cells);
end;

function TCustomCodeEditor.OffsetOf(P: TPoint): int64;
begin
  OffsetOf:=Editor.LineCellToOffset(P.Y,ColToCell(P.Y,P.X));
end;

function TCustomCodeEditor.PointOf(Offset: int64): TPoint;
var L: int64;
    S: AnsiString;
begin
  if Offset<0 then Offset:=0;
  if Offset>Doc.Buffer.Length then Offset:=Doc.Buffer.Length;
  L:=Doc.Buffer.LineOfOffset(Offset);
  S:=Doc.Buffer.LineText(L);
  Result.Y:=L;
  Result.X:=CellToCol(L,LayoutIndexToCell(S,Offset-Doc.Buffer.LineStart(L)+1,Editor.Opt.TabSize));
end;

procedure TCustomCodeEditor.SyncFromEditor;
var A,B: int64;
    L1,L2: int64;
    C1,C2: integer;
begin
  CurPos.X:=CellToCol(Editor.Line,Editor.Cell);
  CurPos.Y:=Editor.Line;
  if Editor.HasSelection then
    begin
      if (Editor.SelKind=skColumn) and Editor.ColumnRect(L1,L2,C1,C2) then
        begin
          SelStart.X:=CellToCol(L1,C1); SelStart.Y:=L1;
          SelEnd.X:=CellToCol(L2,C2)-1; SelEnd.Y:=L2;
        end
      else if Editor.SelectionRange(A,B) then
        begin
          SelStart:=PointOf(A);
          SelEnd:=PointOf(B);
        end;
    end
  else
    begin
      SelStart:=CurPos;
      SelEnd:=CurPos;
    end;
end;

procedure TCustomCodeEditor.Changed;
var OldPos,OldS,OldE: TPoint;
    OldMod: boolean;
begin
  OldPos:=CurPos; OldS:=SelStart; OldE:=SelEnd;
  SyncFromEditor;
  if (OldPos.X<>CurPos.X) or (OldPos.Y<>CurPos.Y) then
    begin
      if (FErrorMessage<>'') then
        SetErrorMessage('');
      PositionChanged;
    end;
  if (OldS.X<>SelStart.X) or (OldS.Y<>SelStart.Y) or (OldE.X<>SelEnd.X) or (OldE.Y<>SelEnd.Y) then
    SelectionChanged;
  if (Highlight.A.X<>Highlight.B.X) or (Highlight.A.Y<>Highlight.B.Y) then
    if (OldPos.X<>CurPos.X) or (OldPos.Y<>CurPos.Y) then
      HideHighlight;
  if (GetUndoActionCount<>FLastUndo) or (GetRedoActionCount<>FLastRedo) or (Editor.HasSelection<>FLastSel) then
    UpdateCommandStates;
  if GetModified<>FLastModified then
    begin
      FLastModified:=GetModified;
      ModifiedChanged;
    end;
end;

procedure TCustomCodeEditor.RememberPos;
var I: integer;
begin
  if (FHistoryCount>0) and (FHistory[FHistoryCount-1].X=CurPos.X) and (FHistory[FHistoryCount-1].Y=CurPos.Y) then
    Exit;
  if FHistoryCount=High(FHistory)+1 then
    begin
      for I:=0 to High(FHistory)-1 do
        FHistory[I]:=FHistory[I+1];
      Dec(FHistoryCount);
    end;
  FHistory[FHistoryCount]:=CurPos;
  Inc(FHistoryCount);
end;

{ --- the flags --- }

function TCustomCodeEditor.GetFlags: longint;
begin
  GetFlags:=FFlags;
end;

procedure TCustomCodeEditor.SetFlags(AFlags: longint);
var Old: longint;
begin
  if AFlags<>FFlags then
    begin
      Old:=FFlags;
      FFlags:=AFlags;
      ApplyFlags;
      FlagsChanged(Old);
    end;
end;

procedure TCustomCodeEditor.ApplyFlags;
begin
  with Editor.Opt do
    begin
      InsertMode:=(FFlags and efInsertMode)<>0;
      AutoIndent:=(FFlags and efAutoIndent)<>0;
      UseTabChars:=(FFlags and efUseTabCharacters)<>0;
      BackspaceUnindent:=(FFlags and efBackSpaceUnindents)<>0;
      PersistentBlocks:=(FFlags and efPersistentBlocks)<>0;
      AutoBrackets:=(FFlags and efAutoBrackets)<>0;
      SmartHome:=false;
      TabSize:=GetTabSize;
      IndentSize:=GetIndentSize;
      FreeCursor:=true;
      OverwriteBlocks:=false;
      ColumnBlocks:=(FFlags and efVerticalBlocks)<>0;
    end;
  Wrap:=(FFlags and efSoftWrap)<>0;
  HighlightColumn:=(FFlags and efHighlightColumn)<>0;
  ShowCurrentLine:=(FFlags and efHighlightRow)<>0;
  if (FFlags and efSyntaxHighlight)=0 then
    SetLanguage(nil);
end;

function TCustomCodeEditor.IsFlagSet(AFlag: longint): boolean;
begin
  IsFlagSet:=(GetFlags and AFlag)=AFlag;
end;

procedure TCustomCodeEditor.FlagsChanged(OldFlags: longint);
begin
  if ((OldFlags xor GetFlags) and efBlockInsCursor)<>0 then
    DrawView;
  DrawView;
end;

function TCustomCodeEditor.GetModified: boolean;
begin
  GetModified:=FCore.GetModified;
end;

procedure TCustomCodeEditor.SetModified(AModified: boolean);
begin
  FCore.SetModified(AModified);
end;

function TCustomCodeEditor.GetStoreUndo: boolean;
begin
  GetStoreUndo:=FCore.GetStoreUndo;
end;

procedure TCustomCodeEditor.SetStoreUndo(AStore: boolean);
begin
  FCore.SetStoreUndo(AStore);
end;

function TCustomCodeEditor.GetSyntaxCompleted: boolean;
begin
  GetSyntaxCompleted:=true;
end;

procedure TCustomCodeEditor.SetSyntaxCompleted(SC: boolean);
begin
end;

function TCustomCodeEditor.GetLastSyntaxedLine: sw_integer;
begin
  GetLastSyntaxedLine:=GetLineCount;
end;

procedure TCustomCodeEditor.SetLastSyntaxedLine(ALine: sw_integer);
begin
end;

function TCustomCodeEditor.GetReservedColCount: sw_integer;
begin
  GetReservedColCount:=0;
end;

function TCustomCodeEditor.GetTabSize: integer;
begin
  GetTabSize:=FCore.GetTabSize;
end;

procedure TCustomCodeEditor.SetTabSize(ATabSize: integer);
begin
  FCore.SetTabSize(ATabSize);
end;

function TCustomCodeEditor.GetIndentSize: integer;
begin
  GetIndentSize:=FCore.GetIndentSize;
end;

procedure TCustomCodeEditor.SetIndentSize(AIndentSize: integer);
begin
  FCore.SetIndentSize(AIndentSize);
end;

function TCustomCodeEditor.IsReadOnly: boolean;
begin
  IsReadOnly:=Doc.ReadOnly;
end;

function TCustomCodeEditor.IsClipboard: Boolean;
begin
  IsClipboard:=(Clipboard=Self) or FCore.IsClipboard;
end;

function TCustomCodeEditor.GetInsertMode: boolean;
begin
  GetInsertMode:=(GetFlags and efInsertMode)<>0;
end;

procedure TCustomCodeEditor.SetInsertMode(InsertMode: boolean);
begin
  if InsertMode then
    SetFlags(GetFlags or efInsertMode)
  else
    SetFlags(GetFlags and not efInsertMode);
  if InsertMode then NormalCursor else BlockCursor;
end;

function TCustomCodeEditor.Overwrite: boolean;
begin
  Overwrite:=(GetFlags and efInsertMode)=0;
end;

function TCustomCodeEditor.IsModal: boolean;
begin
  IsModal:=(State and sfModal)<>0;
end;

procedure TCustomCodeEditor.Lock;
begin
  Inc(ELockFlag);
end;

procedure TCustomCodeEditor.UnLock;
begin
  if ELockFlag>0 then
    Dec(ELockFlag);
  if ELockFlag=0 then
    begin
      Refresh;
      DrawView;
    end;
end;

procedure TCustomCodeEditor.DrawIndicator;
begin
end;

procedure TCustomCodeEditor.DrawCursor;
begin
  DrawCursorCalled:=true;
end;

procedure TCustomCodeEditor.ResetCursor;
begin
  if ELockFlag=0 then
    inherited ResetCursor;
end;

procedure TCustomCodeEditor.Update;
begin
  DrawView;
end;

procedure TCustomCodeEditor.DrawLines(FirstLine: sw_integer);
begin
  DrawView;
end;

procedure TCustomCodeEditor.ScrollTo(X, Y: sw_Integer);
begin
  inherited ScrollTo(X,Y);
end;

procedure TCustomCodeEditor.TrackCursor(centre:Tcentre);
var Row: int64;
begin
  if centre=do_centre then
    begin
      Row:=Editor.Line-Size.Y div 2;
      if Row<0 then Row:=0;
      inherited ScrollTo(Delta.X,Row);
    end;
  Refresh;
end;

procedure TCustomCodeEditor.PushInfo(Const st : string);
begin
  if FInfoCount<=High(FInfoStack) then
    begin
      FInfoStack[FInfoCount]:=st;
      Inc(FInfoCount);
    end;
end;

procedure TCustomCodeEditor.PopInfo;
begin
  if FInfoCount>0 then
    Dec(FInfoCount);
end;

{ --- text --- }

function TCustomCodeEditor.GetLineCount: sw_integer;
begin
  GetLineCount:=FCore.GetLineCount;
end;

function TCustomCodeEditor.GetLine(LineNo: sw_integer): PCustomLine;
var L: TCustomLine;
begin
  if (LineNo<0) or (LineNo>=GetLineCount) then
    Exit(nil);
  L:=FLines[FNextLine];
  if L=nil then
    begin
      L:=TCustomLine.Create('',0);
      FLines[FNextLine]:=L;
    end;
  FNextLine:=(FNextLine+1) mod (High(FLines)+1);
  L.Attach(FCore,LineNo);
  GetLine:=L;
end;

function TCustomCodeEditor.CharIdxToLinePos(Line,CharIdx: sw_integer): sw_integer;
var S: string;
begin
  S:=GetLineText(Line);
  if CharIdx<=Length(S)+1 then
    CharIdxToLinePos:=U8Len(ExtractTabs(Copy(S,1,CharIdx-1),Editor.Opt.TabSize))
  else
    CharIdxToLinePos:=U8Len(ExtractTabs(S,Editor.Opt.TabSize))+(CharIdx-Length(S)-1);
end;

{ the byte index in the line of the column X (columns of the text with tabs expanded) }
function TCustomCodeEditor.LinePosToCharIdx(Line,X: sw_integer): sw_integer;
var S: string;
    I,Col,W,L: sw_integer;
begin
  S:=GetLineText(Line);
  I:=1; Col:=0;
  while (I<=Length(S)) and (Col<X) do
    begin
      if S[I]=TAB then
        begin
          W:=Editor.Opt.TabSize-(Col mod Editor.Opt.TabSize);
          Inc(Col,W);
          Inc(I);
        end
      else
        begin
          L:=U8CharBytes(S,I);
          Inc(I,L);
          Inc(Col);
        end;
    end;
  if Col<X then
    I:=Length(S)+1+(X-Col);
  LinePosToCharIdx:=I;
end;

function TCustomCodeEditor.CursorCells(Line,Col: sw_integer): sw_integer;
begin
  CursorCells:=ColToCell(Line,Col);
end;

function TCustomCodeEditor.GetLineText(I: sw_integer): string;
begin
  GetLineText:=FCore.GetLineText(I);
end;

procedure TCustomCodeEditor.SetDisplayText(I: sw_integer;const S: string);
begin
  SetLineText(I,S);
end;

function TCustomCodeEditor.GetDisplayText(I: sw_integer): string;
begin
  { the text as it is shown: tabs expanded }
  GetDisplayText:=ExtractTabs(GetLineText(I),Editor.Opt.TabSize);
end;

procedure TCustomCodeEditor.SetLineText(I: sw_integer;const S: string);
begin
  FCore.SetLineText(I,S);
end;

procedure TCustomCodeEditor.GetDisplayTextFormat(I: sw_integer;var DT,DF:string);
begin
  DT:=GetDisplayText(I);
  DF:='';
end;

function TCustomCodeEditor.GetLineFormat(I: sw_integer): string;
begin
  GetLineFormat:='';
end;

procedure TCustomCodeEditor.SetLineFormat(I: sw_integer;const S: string);
begin
end;

procedure TCustomCodeEditor.DeleteAllLines;
begin
  FCore.DeleteAllLines;
  Editor.GotoOffset(0);
  Refresh;
end;

procedure TCustomCodeEditor.DeleteLine(I: sw_integer);
begin
  FCore.DeleteLine(I);
  Refresh;
end;

function TCustomCodeEditor.InsertLine(LineNo: sw_integer; const S: string): PCustomLine;
begin
  FCore.InsertLine(LineNo,S);
  Refresh;
  InsertLine:=GetLine(LineNo);
end;

procedure TCustomCodeEditor.AddLine(const S: string);
begin
  FCore.AddLine(S);
  Refresh;
end;

function TCustomCodeEditor.GetErrorMessage: string;
begin
  GetErrorMessage:=FErrorMessage;
end;

procedure TCustomCodeEditor.SetErrorMessage(const S: string);
begin
  if S<>FErrorMessage then
    begin
      FErrorMessage:=S;
      MessageText:=S;
      DrawView;
    end;
end;

procedure TCustomCodeEditor.AdjustSelection(DeltaX, DeltaY: sw_integer);
begin
end;

procedure TCustomCodeEditor.AdjustSelectionBefore(DeltaX, DeltaY: sw_integer);
begin
end;

procedure TCustomCodeEditor.AdjustSelectionPos(OldCurPosX, OldCurPosY: sw_integer; DeltaX, DeltaY: sw_integer);
begin
end;

procedure TCustomCodeEditor.GetContent(ALines: PUnsortedStringCollection);
var I: sw_integer;
begin
  for I:=0 to GetLineCount-1 do
    ALines.Insert(NewStr(GetLineText(I)));
end;

procedure TCustomCodeEditor.SetContent(ALines: PUnsortedStringCollection);
var I: sw_integer;
    T: AnsiString;
begin
  { nil is no lines (an empty text) }
  T:='';
  if Assigned(ALines) then
    for I:=0 to ALines.Count-1 do
      begin
        if I>0 then T:=T+#10;
        T:=T+GetStr(ALines.At(I));
      end;
  Doc.LoadText(T);
  if Assigned(ALines) then
    FCore.FAddedLines:=ALines.Count
  else
    FCore.FAddedLines:=0;
  Editor.GotoOffset(0);
  Refresh;
end;

function StripCR(const T: AnsiString): AnsiString;
var I,N: longint;
begin
  SetLength(Result,Length(T));
  N:=0;
  for I:=1 to Length(T) do
    if not ((T[I]=#13) and (I<Length(T)) and (T[I+1]=#10)) then
      begin
        Inc(N);
        Result[N]:=T[I];
      end;
  SetLength(Result,N);
end;

function TCustomCodeEditor.LoadFromStream(Stream: PFastBufStream): boolean;
var T: AnsiString;
    N: longint;
begin
  T:='';
  SetLength(T,Stream.GetSize-Stream.GetPos);
  N:=Length(T);
  if N>0 then
    Stream.Read(T[1],N);
  Doc.LoadText(StripCR(T));
  Editor.GotoOffset(0);
  Refresh;
  LoadFromStream:=Stream.Status=stOK;
end;

function TCustomCodeEditor.SaveToStream(Stream: TStream): boolean;
var T: AnsiString;
begin
  T:=Doc.Buffer.AsString;
  if Length(T)>0 then
    Stream.Write(T[1],Length(T));
  SaveToStream:=Stream.Status=stOK;
end;

function TCustomCodeEditor.SaveAreaToStream(Stream: TStream; StartP,EndP: TPoint): boolean;
var T: AnsiString;
    A,B: int64;
begin
  A:=OffsetOf(StartP);
  B:=OffsetOf(EndP);
  if B<A then B:=A;
  T:=Doc.Buffer.Copy(A,B-A);
  if Length(T)>0 then
    Stream.Write(T[1],Length(T));
  SaveAreaToStream:=Stream.Status=stOK;
end;

function TCustomCodeEditor.LoadFromFile(const AFileName: string): boolean;
var S: PFastBufStream;
begin
  S := TFastBufStream.Create(AFileName,stOpenRead,EditorTextBufSize);
  LoadFromFile:=false;
  if Assigned(S) then
    begin
      LoadFromFile:=LoadFromStream(S);
      S.Free;
    end;
end;

function TCustomCodeEditor.SaveToFile(const AFileName: string): boolean;
var S: PBufStream;
begin
  S := TFastBufStream.Create(AFileName,stCreate,EditorTextBufSize);
  SaveToFile:=false;
  if Assigned(S) then
    begin
      SaveToFile:=SaveToStream(S);
      S.Free;
    end;
end;

function TCustomCodeEditor.InsertFrom(AEditor: PCustomCodeEditor): Boolean;
var T: AnsiString;
begin
  T:=AEditor.SelectionText;
  InsertFrom:=T<>'';
  if T<>'' then
    begin
      if (Clipboard=PCustomCodeEditor(Self)) then
        begin
          { the clipboard keeps the last block only }
          Doc.LoadText(T);
          Editor.SelectAll;
          Refresh;
        end
      else
        InsertBlockText(T);
    end;
end;

function TCustomCodeEditor.InsertText(const S: string): Boolean;
begin
  InsertText:=Editor.TypeText(S);
  Refresh;
end;

{ --- notifications (abstract here) --- }

procedure TCustomCodeEditor.BindingsChanged;
begin
end;

procedure TCustomCodeEditor.ContentsChanged;
begin
  DrawView;
end;

procedure TCustomCodeEditor.LimitsChanged;
begin
  DoLimitsChanged;
end;

procedure TCustomCodeEditor.DoLimitsChanged;
begin
  Refresh;
end;

procedure TCustomCodeEditor.ModifiedChanged;
begin
end;

procedure TCustomCodeEditor.PositionChanged;
begin
end;

procedure TCustomCodeEditor.TabSizeChanged;
begin
  Editor.Opt.TabSize:=GetTabSize;
  DrawView;
end;

procedure TCustomCodeEditor.SyntaxStateChanged;
begin
end;

procedure TCustomCodeEditor.StoreUndoChanged;
begin
end;

procedure TCustomCodeEditor.UpdateCommandStates;
var Enable,CanPaste: boolean;
begin
  if ((State and sfFocused)<>0) then
    begin
      Enable:=Editor.HasSelection and (Clipboard<>nil);
      SetCmdState(CommandSetOf(ToClipCmds),Enable and (Clipboard<>TCustomCodeEditor(Self)));
      SetCmdState(CommandSetOf(NulClipCmds),Enable);
      CanPaste:=Clipboard<>nil;
      SetCmdState(CommandSetOf(FromClipCmds),CanPaste and (Clipboard<>TCustomCodeEditor(Self)));
      SetCmdState(CommandSetOf(UndoCmd),(GetUndoActionCount>0));
      SetCmdState(CommandSetOf(RedoCmd),(GetRedoActionCount>0));
      Message(TProgram.Application,evBroadcast,cmCommandSetChanged,nil);
      FLastUndo:=GetUndoActionCount;
      FLastRedo:=GetRedoActionCount;
      FLastSel:=Editor.HasSelection;
    end;
end;

procedure TCustomCodeEditor.SelectionChanged;
begin
  UpdateCommandStates;
  DrawView;
end;

procedure TCustomCodeEditor.HighlightChanged;
begin
  DrawView;
end;

procedure TCustomCodeEditor.SetState(AState: Word; Enable: Boolean);
  procedure ShowSBar(SBar: PScrollBar);
  begin
    if Assigned(SBar) and (SBar.GetState(sfVisible)=false) then
        SBar.Show;
  end;
begin
  inherited SetState(AState,Enable);
  if AlwaysShowScrollBars then
   begin
     ShowSBar(HScrollBar);
     ShowSBar(VScrollBar);
   end;
  if (AState and (sfActive+sfSelected+sfFocused))<>0 then
    begin
      SelectionChanged;
      if ((State and sfFocused)=0) and (GetCompleteState=csOffering) then
        ClearCodeCompleteWord;
    end;
end;

{ --- syntax: the highlighter is tve's; these are kept for the subclasses --- }

function TCustomCodeEditor.GetSpecSymbolCount(SpecClass: TSpecSymbolClass): integer;
begin
  GetSpecSymbolCount:=0;
end;

function TCustomCodeEditor.GetSpecSymbol(SpecClass: TSpecSymbolClass; Index: integer): pstring;
begin
  GetSpecSymbol:=nil;
end;

function TCustomCodeEditor.IsReservedWord(const S: string): boolean;
begin
  IsReservedWord:=false;
end;

function TCustomCodeEditor.IsAsmReservedWord(const S: string): boolean;
begin
  IsAsmReservedWord:=false;
end;

function TCustomCodeEditor.UpdateAttrs(FromLine: sw_integer; Attrs: byte): sw_integer;
begin
  UpdateAttrs:=FromLine;
end;

function TCustomCodeEditor.UpdateAttrsRange(FromLine, ToLine: sw_integer; Attrs: byte): sw_integer;
begin
  UpdateAttrsRange:=ToLine;
end;

function TCustomCodeEditor.TranslateCodeTemplate(var Shortcut: string; ALines: PUnsortedStringCollection): boolean;
begin
  TranslateCodeTemplate:=false;
end;

function TCustomCodeEditor.SelectCodeTemplate(var ShortCut: string): boolean;
begin
  SelectCodeTemplate:=false;
end;

function TCustomCodeEditor.CompleteCodeWord(const WordS: string; var Text: string): boolean;
begin
  CompleteCodeWord:=false;
end;

function TCustomCodeEditor.GetCodeCompleteWord: string;
begin
  GetCodeCompleteWord:=FCompleteWord;
end;

procedure TCustomCodeEditor.SetCodeCompleteWord(const S: string);
begin
  FCompleteWord:=S;
end;

function TCustomCodeEditor.GetCodeCompleteFrag: string;
begin
  GetCodeCompleteFrag:=FCompleteFrag;
end;

procedure TCustomCodeEditor.SetCodeCompleteFrag(const S: string);
begin
  FCompleteFrag:=S;
end;

function TCustomCodeEditor.GetCompleteState: TCompleteState;
begin
  GetCompleteState:=FCompleteState;
end;

procedure TCustomCodeEditor.SetCompleteState(AState: TCompleteState);
begin
  FCompleteState:=AState;
end;

procedure TCustomCodeEditor.ClearCodeCompleteWord;
begin
  { through the virtual setters: the tip of the source editor is freed by SetCodeCompleteWord('') }
  SetCompleteState(csInactive);
  SetCodeCompleteWord('');
  SetCodeCompleteFrag('');
end;

procedure TCustomCodeEditor.CodeCompleteCheck;
var Frag,Txt: string;
    S: string;
    I: integer;
begin
  if not IsFlagSet(efCodeComplete) then Exit;
  S:=GetLineText(CurPos.Y);
  I:=LinePosToCharIdx(CurPos.Y,CurPos.X);
  Frag:='';
  while (I>1) and (S[I-1] in AlphaChars+NumberChars) do
    begin
      Frag:=S[I-1]+Frag;
      Dec(I);
    end;
  if Length(Frag)>=CodeCompleteMinLen then
    begin
      if CompleteCodeWord(Frag,Txt) then
        begin
          SetCodeCompleteFrag(Frag);
          SetCodeCompleteWord(Txt);
          SetCompleteState(csOffering);
          Exit;
        end;
    end;
  ClearCodeCompleteWord;
end;

procedure TCustomCodeEditor.CodeCompleteApply;
var W,F: string;
begin
  W:=GetCodeCompleteWord;
  F:=GetCodeCompleteFrag;
  ClearCodeCompleteWord;
  if W<>'' then
    AddString(Copy(W,Length(F)+1,255));
end;

procedure TCustomCodeEditor.CodeCompleteCancel;
begin
  SetCompleteState(csDenied);
end;

{ --- undo --- }

procedure TCustomCodeEditor.AddAction(AAction: byte; AStartPos, AEndPos: TPoint; AText: string;AFlags : longint);
begin
end;

procedure TCustomCodeEditor.AddGroupedAction(AAction : byte);
begin
  Doc.BeginGroup;
end;

procedure TCustomCodeEditor.CloseGroupedAction(AAction : byte);
begin
  Doc.EndGroup;
end;

function TCustomCodeEditor.GetUndoActionCount: sw_integer;
begin
  GetUndoActionCount:=Doc.UndoCount;
end;

function TCustomCodeEditor.GetRedoActionCount: sw_integer;
begin
  GetRedoActionCount:=Doc.RedoCount;
end;

procedure TCustomCodeEditor.UpdateUndoRedo(cm : word; action : byte);
begin
end;

procedure TCustomCodeEditor.Undo;
begin
  Editor.Undo;
  Refresh;
end;

procedure TCustomCodeEditor.Redo;
begin
  Editor.Redo;
  Refresh;
end;

{ --- selection --- }

function TCustomCodeEditor.ShouldExtend: boolean;
var ShiftInEvent: boolean;
begin
  ShiftInEvent:=false;
  if Assigned(CurEvent) then
    if CurEvent^.What=evKeyDown then
      ShiftInEvent:=((CurEvent^.KeyDown.ControlKeyState and kbShift)<>0);
  ShouldExtend:=ShiftInEvent and not DontConsiderShiftState and not NoSelect;
end;

procedure TCustomCodeEditor.CheckSels;
begin
end;

function TCustomCodeEditor.ValidBlock: boolean;
begin
  ValidBlock:=Editor.HasSelection;
end;

procedure TCustomCodeEditor.GetSelectionArea(var StartP,EndP: TPoint);
begin
  StartP:=SelStart; EndP:=SelEnd;
  if EndP.X=0 then
    begin
      Dec(EndP.Y);
      EndP.X:=U8Len(GetDisplayText(EndP.Y))-1;
    end
  else
   Dec(EndP.X);
end;

procedure TCustomCodeEditor.SetSelection(A, B: TPoint);
var OA,OB: int64;
begin
  OA:=OffsetOf(A);
  OB:=OffsetOf(B);
  if OB<OA then
    begin
      OA:=OA xor OB; OB:=OA xor OB; OA:=OA xor OB;
    end;
  if OA=OB then
    Editor.ClearSelection
  else
    Editor.SetBlockMarks(OA,OB);
  SyncFromEditor;
  SelectionChanged;
end;

procedure TCustomCodeEditor.SetHighlight(A, B: TPoint);
begin
  Highlight.A:=A; Highlight.B:=B;
  if (A.X=B.X) and (A.Y=B.Y) then
    SetHighlightRange(-1,-1)
  else
    SetHighlightRange(OffsetOf(A),OffsetOf(B));
  HighlightChanged;
end;

procedure TCustomCodeEditor.HideHighlight;
var Z: TPoint;
begin
  Z.X:=0; Z.Y:=0;
  Highlight.A:=Z; Highlight.B:=Z;
  SetHighlightRange(-1,-1);
end;

procedure TCustomCodeEditor.SelectAll(Enable: boolean);
begin
  if Enable and (GetLineCount>0) then
    Editor.SelectAll
  else
    Editor.ClearSelection;
  Refresh;
end;

procedure TCustomCodeEditor.SetCurPtr(X,Y: sw_integer);
var Extend: boolean;
begin
  Y:=Max(0,Min(GetLineCount-1,Y));
  X:=Max(0,Min(MaxLineLength+1,X));
  Extend:=ShouldExtend;
  if Extend then
    begin
      if not Editor.HasSelection then
        Editor.SetSelection(skStream,Editor.Offset);
      Editor.GotoLineCell(Y,ColToCell(Y,X));
    end
  else
    begin
      if not Editor.Opt.PersistentBlocks then
        Editor.ClearSelection;
      Editor.GotoLineCell(Y,ColToCell(Y,X));
    end;
  Refresh;
end;

procedure TCustomCodeEditor.StartSelect;
begin
  Editor.SetSelection(skStream,Editor.Offset);
  Editor.GotoOffset(Editor.Offset);
  Refresh;
end;

procedure TCustomCodeEditor.EndSelect;
begin
  Editor.GotoOffset(Editor.Offset);
  Refresh;
end;

procedure TCustomCodeEditor.HideSelect;
begin
  Editor.ClearSelection;
  Refresh;
end;

procedure TCustomCodeEditor.DelSelect;
begin
  if IsReadOnly then Exit;
  Editor.DeleteSelection;
  Refresh;
end;

procedure TCustomCodeEditor.SelectWord;
begin
  Editor.SelectWord;
  Refresh;
end;

procedure TCustomCodeEditor.SelectLine;
begin
  Editor.SelectLine;
  Refresh;
end;

procedure TCustomCodeEditor.JumpSelStart;
var A,B: int64;
begin
  if Editor.SelectionRange(A,B) then
    begin
      RememberPos;
      Editor.GotoOffset(A);
      Refresh;
    end;
end;

procedure TCustomCodeEditor.JumpSelEnd;
var A,B: int64;
begin
  if Editor.SelectionRange(A,B) then
    begin
      RememberPos;
      Editor.GotoOffset(B);
      Refresh;
    end;
end;

procedure TCustomCodeEditor.JumpMark(MarkIdx: integer);
begin
  RememberPos;
  Editor.GotoBookmark(MarkIdx);
  Refresh;
end;

procedure TCustomCodeEditor.DefineMark(MarkIdx: integer);
begin
  Editor.SetBookmark(MarkIdx);
  DrawView;
end;

procedure TCustomCodeEditor.JumpToLastCursorPos;
begin
  if FHistoryCount>0 then
    begin
      Dec(FHistoryCount);
      SetCurPtr(FHistory[FHistoryCount].X,FHistory[FHistoryCount].Y);
    end;
end;

procedure TCustomCodeEditor.FindMatchingDelimiter(ScanForward: boolean);
begin
  Editor.GotoMatchingBracket;
  Refresh;
end;

{ --- movement --- }

procedure TCustomCodeEditor.CharLeft;
begin
  Editor.MoveLeft(ShouldExtend); Refresh;
end;

procedure TCustomCodeEditor.CharRight;
begin
  Editor.MoveRight(ShouldExtend); Refresh;
end;

procedure TCustomCodeEditor.WordLeft;
begin
  Editor.MoveWordLeft(ShouldExtend); Refresh;
end;

procedure TCustomCodeEditor.WordRight;
begin
  Editor.MoveWordRight(ShouldExtend); Refresh;
end;

procedure TCustomCodeEditor.LineStart;
begin
  Editor.MoveHome(ShouldExtend); Refresh;
end;

procedure TCustomCodeEditor.LineEnd;
begin
  Editor.MoveEnd(ShouldExtend); Refresh;
end;

procedure TCustomCodeEditor.LineUp;
begin
  if ShouldExtend then Execute(tcSelUp) else Execute(tcUp);
  Refresh;
end;

procedure TCustomCodeEditor.LineDown;
begin
  if ShouldExtend then Execute(tcSelDown) else Execute(tcDown);
  Refresh;
end;

procedure TCustomCodeEditor.PageUp;
begin
  Editor.MovePageUp(ShouldExtend); Refresh;
end;

procedure TCustomCodeEditor.PageDown;
begin
  Editor.MovePageDown(ShouldExtend); Refresh;
end;

procedure TCustomCodeEditor.TextStart;
begin
  RememberPos;
  Editor.MoveTextStart(ShouldExtend); Refresh;
end;

procedure TCustomCodeEditor.TextEnd;
begin
  RememberPos;
  Editor.MoveTextEnd(ShouldExtend); Refresh;
end;

procedure TCustomCodeEditor.WindowStart;
begin
  Editor.GotoLineCell(ViewToLine(Delta.Y),Editor.Cell); Refresh;
end;

procedure TCustomCodeEditor.WindowEnd;
begin
  Editor.GotoLineCell(ViewToLine(Delta.Y+Size.Y-1),Editor.Cell); Refresh;
end;

{ --- editing --- }

procedure TCustomCodeEditor.Indent;
begin
  Editor.Tab; Refresh;
end;

procedure TCustomCodeEditor.UpperCase;
begin
  if Editor.HasSelection then
    begin
      ChangeCase(Editor,caseUpper); Refresh;
    end;
end;

procedure TCustomCodeEditor.LowerCase;
begin
  if Editor.HasSelection then
    begin
      ChangeCase(Editor,caseLower); Refresh;
    end;
end;

procedure TCustomCodeEditor.ToggleCase;
begin
  if Editor.HasSelection then
    begin
      ChangeCase(Editor,caseToggle); Refresh;
    end;
end;

procedure TCustomCodeEditor.WordUpperCase;
begin
  Editor.SelectWord;
  ChangeCase(Editor,caseUpper);
  Refresh;
end;

procedure TCustomCodeEditor.WordLowerCase;
begin
  Editor.SelectWord;
  ChangeCase(Editor,caseLower);
  Refresh;
end;

procedure TCustomCodeEditor.ChangeCaseArea(StartP,EndP: TPoint; CaseAction: TCaseAction);
var Save: boolean;
begin
  SetSelection(StartP,EndP);
  case CaseAction of
    caToLowerCase: ChangeCase(Editor,caseLower);
    caToUpperCase: ChangeCase(Editor,caseUpper);
    caToggleCase: ChangeCase(Editor,caseToggle);
  end;
  Save:=false;
  if Save then ;
  Refresh;
end;

procedure TCustomCodeEditor.InsertOptions;
begin
end;

function TCustomCodeEditor.InsertNewLine: Sw_integer;
begin
  if IsReadOnly then Exit(0);
  Editor.NewLine;
  Refresh;
  InsertNewLine:=0;
end;

procedure TCustomCodeEditor.BreakLine;
begin
  if IsReadOnly then Exit;
  BreakLineStay(Editor);
  Refresh;
end;

procedure TCustomCodeEditor.BackSpace;
begin
  if IsReadOnly then Exit;
  Editor.Backspace; Refresh;
end;

procedure TCustomCodeEditor.DelChar;
begin
  if IsReadOnly then Exit;
  Editor.DeleteChar; Refresh;
end;

procedure TCustomCodeEditor.DelWord;
begin
  if IsReadOnly then Exit;
  Editor.SelectWord;
  Editor.DeleteSelection;
  Refresh;
end;

procedure TCustomCodeEditor.DelToEndOfWord;
begin
  if IsReadOnly then Exit;
  Editor.DeleteWordRight; Refresh;
end;

procedure TCustomCodeEditor.DelStart;
begin
  if IsReadOnly then Exit;
  Editor.DeleteToBol; Refresh;
end;

procedure TCustomCodeEditor.DelEnd;
begin
  if IsReadOnly then Exit;
  Editor.DeleteToEol; Refresh;
end;

procedure TCustomCodeEditor.DelLine;
begin
  if IsReadOnly then Exit;
  if GetLineCount>0 then
    begin
      Doc.BeginGroup;
      DeleteLine(Editor.Line);
      Doc.EndGroup;
      Editor.GotoLineCell(Min(Editor.Line,GetLineCount-1),0);
      Refresh;
    end;
end;

procedure TCustomCodeEditor.InsMode;
begin
  SetInsertMode(Overwrite);
end;

procedure TCustomCodeEditor.CopyBlock;
begin
  if IsReadOnly then Exit;
  CopyBlockHere(Editor); Refresh;
end;

procedure TCustomCodeEditor.MoveBlock;
begin
  if IsReadOnly then Exit;
  MoveBlockHere(Editor); Refresh;
end;

procedure TCustomCodeEditor.IndentBlock;
begin
  if IsReadOnly then Exit;
  BlockIndent(Editor); Refresh;
end;

procedure TCustomCodeEditor.UnindentBlock;
begin
  if IsReadOnly then Exit;
  BlockUnindent(Editor); Refresh;
end;

procedure TCustomCodeEditor.WriteBlock;
var FileName: string;
begin
  if not Editor.HasSelection then Exit;
  FileName:=GetLineText(0);
  FileName:='';
  if EditorDialog(edWriteBlock,@FileName)<>cmCancel then
    if not TveBlocks.WriteBlock(Editor,FileName) then
      EditorDialog(edCreateError,@FileName);
end;

procedure TCustomCodeEditor.ReadBlock;
var FileName: string;
begin
  if IsReadOnly then Exit;
  FileName:='';
  if EditorDialog(edReadBlock,@FileName)<>cmCancel then
    begin
      if not TveBlocks.ReadBlock(Editor,FileName) then
        EditorDialog(edReadError,@FileName);
      Refresh;
    end;
end;

procedure TCustomCodeEditor.PrintBlock;
begin
end;

procedure TCustomCodeEditor.ExpandCodeTemplate;
var Short: string;
    Lines: PUnsortedStringCollection;
    I: sw_integer;
    Text: AnsiString;
    S: string;
    P: sw_integer;
begin
  if IsReadOnly then Exit;
  S:=GetLineText(CurPos.Y);
  P:=LinePosToCharIdx(CurPos.Y,CurPos.X);
  Short:='';
  while (P>1) and (S[P-1] in AlphaChars+NumberChars) do
    begin
      Short:=S[P-1]+Short;
      Dec(P);
    end;
  if Short='' then
    if not SelectCodeTemplate(Short) then Exit;
  Lines:=TUnsortedStringCollection.Create(10,10);
  if TranslateCodeTemplate(Short,Lines) then
    begin
      Text:='';
      for I:=0 to Lines.Count-1 do
        begin
          if I>0 then Text:=Text+#10;
          Text:=Text+GetStr(Lines.At(I));
        end;
      Doc.BeginGroup;
      Editor.TypeText(Text);
      Doc.EndGroup;
      Refresh;
    end;
  Lines.Free;
end;

procedure TCustomCodeEditor.AddChar(C: char);
begin
  if IsReadOnly then Exit;
  Editor.TypeText(C);
  Refresh;
end;

procedure TCustomCodeEditor.AddCharStr(const Ch: string);
begin
  if IsReadOnly then Exit;
  Editor.TypeText(Ch);
  Refresh;
end;

procedure TCustomCodeEditor.AddString(const S: string);
begin
  if IsReadOnly then Exit;
  Editor.TypeText(S);
  Refresh;
end;

function TCustomCodeEditor.SelectionText: AnsiString;
var Col: boolean;
begin
  Result:=Editor.SelectionText(Col);
end;

{ The text is inserted and, as the blocks of this editor persist, it is the selected block afterwards. }
procedure TCustomCodeEditor.PasteSelecting(const S: AnsiString);
var Start: int64;
begin
  if IsReadOnly then Exit;
  Start:=Editor.Offset;
  if Editor.PasteText(S,false) and Editor.Opt.PersistentBlocks and (Editor.Offset>Start) then
    Editor.SetBlockMarks(Start,Editor.Offset);
  Refresh;
end;

procedure TCustomCodeEditor.InsertBlockText(const S: AnsiString);
begin
  PasteSelecting(S);
end;

function TCustomCodeEditor.GetCurrentWordArea(var StartP,EndP: TPoint): boolean;
const WordChars = ['A'..'Z','a'..'z','0'..'9','_'];
var S: string;
    I,J: integer;
begin
  S:=GetLineText(CurPos.Y);
  I:=LinePosToCharIdx(CurPos.Y,CurPos.X);
  J:=I;
  while (I>1) and (S[I-1] in WordChars) do Dec(I);
  while (J<=Length(S)) and (S[J] in WordChars) do Inc(J);
  StartP.Y:=CurPos.Y; EndP.Y:=CurPos.Y;
  StartP.X:=CharIdxToLinePos(CurPos.Y,I);
  EndP.X:=CharIdxToLinePos(CurPos.Y,J);
  GetCurrentWordArea:=J>I;
end;

function TCustomCodeEditor.GetCurrentWord: string;
var A,B: TPoint;
    S: string;
begin
  GetCurrentWord:='';
  if GetCurrentWordArea(A,B) then
    begin
      S:=GetLineText(A.Y);
      GetCurrentWord:=Copy(S,LinePosToCharIdx(A.Y,A.X),LinePosToCharIdx(A.Y,B.X)-LinePosToCharIdx(A.Y,A.X));
    end;
end;

{ --- clipboard --- }

var
  { what the system clipboard held when we last wrote it or looked at it: Paste takes the clipboard window, unless
    another program has put something else onto the system clipboard since }
  LastSystemClip: AnsiString = '';

procedure SendToSystemClipboard(const Text: AnsiString);
begin
  LastSystemClip:=ToLf(Text);
  TClipboard.SetText(Text);
end;

{ Something new on the system clipboard becomes the text of the clipboard window (and is selected there). }
procedure TakeSystemClipboard;
var
  Text: AnsiString;
begin
  if Clipboard=nil then
    Exit;
  Text:=ToLf(ClipboardGetText);
  if (Text='') or (Text=LastSystemClip) then
    Exit;
  LastSystemClip:=Text;
  Clipboard.Doc.LoadText(Text);
  Clipboard.Editor.SelectAll;
  Clipboard.Refresh;
end;

function TCustomCodeEditor.ClipCopy: Boolean;
var T: AnsiString;
begin
  ClipCopy:=false;
  if not Editor.HasSelection then Exit;
  T:=SelectionText;
  if (Clipboard<>nil) and (Clipboard<>Self) then
    begin
      Clipboard.Doc.LoadText(T);
      Clipboard.Editor.SelectAll;
      Clipboard.Refresh;
      SendToSystemClipboard(T);
      SetCmdState(CommandSetOf(FromClipCmds),true);
      ClipCopy:=true;
    end;
end;

procedure TCustomCodeEditor.ClipCut;
begin
  if IsReadOnly then Exit;
  if ClipCopy then
    begin
      DontConsiderShiftState:=true;
      DelSelect;
      DontConsiderShiftState:=false;
    end;
end;

procedure TCustomCodeEditor.ClipPaste;
var T: AnsiString;
begin
  if IsReadOnly then Exit;
  if Clipboard=nil then Exit;
  TakeSystemClipboard;
  T:=Clipboard.Doc.Buffer.AsString;
  if T='' then Exit;
  DontConsiderShiftState:=true;
  Doc.BeginGroup;
  PasteSelecting(T);
  Doc.EndGroup;
  DontConsiderShiftState:=false;
end;

{ --- folds --- }

procedure TCustomCodeEditor.CreateFoldFromBlock;
begin
  Execute(tcFoldFromBlock);
end;

procedure TCustomCodeEditor.ToggleFold;
begin
  Execute(tcFoldToggle);
end;

procedure TCustomCodeEditor.CollapseFold;
begin
  Execute(tcFoldCollapse);
end;

procedure TCustomCodeEditor.ExpandFold;
begin
  Execute(tcFoldExpand);
end;

{ --- go to, find, replace --- }

procedure TCustomCodeEditor.GotoLine;
const
  GotoRec: TGotoLineDialogRec = (LineNo:'1';Lines:0);  {keep previous goto line number}
begin
  with GotoRec do
  begin
    Lines:=GetLineCount;
    if lines=0 then
      lines:=1;
    if EditorDialog(edGotoLine, @GotoRec) <> cmCancel then
    begin
      Lock;
      RememberPos;
      SetCurPtr(0,StrToInt(LineNo)-1);
      TrackCursor(do_centre);
      UnLock;
    end;
  end;
end;

procedure TCustomCodeEditor.Find;
var
  FindRec: TFindDialogRec;
  DoConf: boolean;
begin
  with FindRec do
  begin
    Find := FindStr;
    if GetCurrentWord<>'' then
      Find:=GetCurrentWord;
{$ifdef TEST_REGEXP}
    Options := ((FindFlags and ffmOptionsFind) shr ffsOptions) or
               ((FindFlags and ffUseRegExp) shr ffsUseRegExpFind);
{$else not TEST_REGEXP}
    Options := (FindFlags and ffmOptions) shr ffsOptions;
{$endif TEST_REGEXP}
    Direction := (FindFlags and ffmDirection) shr ffsDirection;
    Scope := (FindFlags and ffmScope) shr ffsScope;
    Origin := (FindFlags and ffmOrigin) shr ffsOrigin;
    DoConf:= (FindFlags and ffPromptOnReplace)<>0;
    FindReplaceEditor:=Self;
    if EditorDialog(edFind, @FindRec) <> cmCancel then
    begin
      FindStr := Find;
{$ifdef TEST_REGEXP}
      FindFlags := ((Options and ffmOptionsFind) shl ffsOptions) or (Direction shl ffsDirection) or
         ((Options and ffmUseRegExpFind) shl ffsUseRegExpFind) or
         (Scope shl ffsScope) or (Origin shl ffsOrigin);
{$else : not TEST_REGEXP}
      FindFlags := ((Options and ffmOptions) shl ffsOptions) or (Direction shl ffsDirection) or
         (Scope shl ffsScope) or (Origin shl ffsOrigin);
{$endif TEST_REGEXP}
      FindFlags := FindFlags and not ffDoReplace;
      if DoConf then
        FindFlags := (FindFlags or ffPromptOnReplace);
      SearchRunCount:=0;
      if FindStr<>'' then
        DoSearchReplace
      else
        EditorDialog(edSearchFailed,nil);
    end;
    FindReplaceEditor:=nil;
  end;
end;

procedure TCustomCodeEditor.Replace;
var
  ReplaceRec: TReplaceDialogRec;
  Re: word;
begin
  if IsReadOnly then Exit;
  with ReplaceRec do
  begin
    Find := FindStr;
    if GetCurrentWord<>'' then
      Find:=GetCurrentWord;
    Replace := ReplaceStr;
{$ifdef TEST_REGEXP}
    Options := (FindFlags and ffmOptions) shr ffsOptions or
               (FindFlags and ffUseRegExp) shr ffsUseRegExpReplace;
{$else not TEST_REGEXP}
    Options := (FindFlags and ffmOptions) shr ffsOptions;
{$endif TEST_REGEXP}
    Direction := (FindFlags and ffmDirection) shr ffsDirection;
    Scope := (FindFlags and ffmScope) shr ffsScope;
    Origin := (FindFlags and ffmOrigin) shr ffsOrigin;
    FindReplaceEditor:=Self;
    Re:=EditorDialog(edReplace, @ReplaceRec);
    FindReplaceEditor:=nil;
    if Re <> cmCancel then
    begin
      FindStr := Find;
      ReplaceStr := Replace;
      FindFlags := (Options shl ffsOptions) or (Direction shl ffsDirection) or
{$ifdef TEST_REGEXP}
         ((Options and ffmUseRegExpReplace) shl ffsUseRegExpReplace) or
{$endif TEST_REGEXP}
         (Scope shl ffsScope) or (Origin shl ffsOrigin);
      FindFlags := FindFlags or ffDoReplace;
      if Re = cmYes then
        FindFlags := FindFlags or ffReplaceAll;
      SearchRunCount:=0;
      if FindStr<>'' then
        DoSearchReplace
      else
        EditorDialog(edSearchFailed,nil);
    end;
  end;
end;

procedure TCustomCodeEditor.DoSearchReplace;
var
  O: TTveSearchOptions;
  M: TTveMatch;
  SForward,DoReplace,DoReplaceAll,Confirm: boolean;
  From,SelA,SelB: int64;
  HasScope,CanExit,CanReplace: boolean;
  FoundCount: sw_integer;
  Re: word;
  Pt: TPoint;
  NewText: AnsiString;
  St: TTveFindStatus;
  N: sw_integer;
begin
  if FindStr='' then
    begin
      Find;
      exit;
    end;
  Inc(SearchRunCount);
  if FSrch=nil then
    FSrch:=TTveSearcher.Create(Doc.Buffer);
  SForward:=(FindFlags and ffmDirection)=ffForward;
  DoReplace:=(FindFlags and ffDoReplace)<>0;
  Confirm:=(FindFlags and ffPromptOnReplace)<>0;
  DoReplaceAll:=(FindFlags and ffReplaceAll)<>0;
  O:=TveDefaultSearch;
  O.Pattern:=FindStr;
  O.CaseSensitive:=(FindFlags and ffCaseSensitive)<>0;
  O.WholeWord:=(FindFlags and ffWholeWordsOnly)<>0;
{$ifdef TEST_REGEXP}
  O.UseRegex:=(FindFlags and ffUseRegExp)<>0;
{$endif TEST_REGEXP}
  O.Backward:=not SForward;
  HasScope:=false;
  if (FindFlags and ffmScope)=ffSelectedText then
    HasScope:=Editor.HasSelection and Editor.SelectionRange(SelA,SelB);
  if HasScope then
    begin
      O.ScopeFrom:=SelA;
      O.ScopeTo:=SelB;
    end;
  if GetLineCount=0 then
    begin
      EditorDialog(edSearchFailed,nil);
      exit;
    end;
  FoundCount:=0;
  { where to begin }
  if SForward then From:=Editor.Offset else From:=Editor.Offset;
  if (SearchRunCount=1) and ((FindFlags and ffmOrigin)=ffEntireScope) then
    begin
      if HasScope then
        begin
          if SForward then From:=SelA else From:=SelB;
        end
      else
        begin
          if SForward then From:=0 else From:=Doc.Buffer.Length;
        end;
    end
  else if HasScope then
    begin
      if From<SelA then From:=SelA;
      if From>SelB then From:=SelB;
    end;
  if FindStr<>'' then
    PushInfo('Looking for "'+FindStr+'"');
  if DoReplace and DoReplaceAll and not Confirm then
    begin
      Doc.BeginGroup;
      N:=FSrch.ReplaceAll(Doc,O,ReplaceStr);
      Doc.EndGroup;
      FoundCount:=N;
      Refresh;
    end
  else
    begin
      CanExit:=false;
      repeat
        St:=FSrch.Find(O,From,M);
        if St<>fsFound then
          Break;
        Inc(FoundCount);
        Lock;
        if SForward then
          Editor.GotoOffset(M.Stop)
        else
          Editor.GotoOffset(M.Start);
        TrackCursor(do_centre);
        SetHighlight(PointOf(M.Start),PointOf(M.Stop));
        UnLock;
        if not DoReplace then
          Break;
        if not Confirm then
          CanReplace:=true
        else
          begin
            Pt:=CurPos;
            Re:=EditorDialog(edReplacePrompt,@Pt);
            case Re of
              cmYes: CanReplace:=true;
              cmNo: CanReplace:=false;
            else
              begin
                CanReplace:=false;
                CanExit:=true;
              end;
            end;
          end;
        if CanReplace then
          begin
            NewText:=FSrch.ReplacementFor(M,ReplaceStr);
            Doc.Replace(M.Start,M.Stop-M.Start,NewText);
            if HasScope then
              Inc(O.ScopeTo,Length(NewText)-(M.Stop-M.Start));
            if SForward then
              begin
                From:=M.Start+Length(NewText);
                Editor.GotoOffset(From);
              end
            else
              From:=M.Start;
          end
        else
          begin
            if SForward then From:=M.Stop else From:=M.Start;
          end;
        if not DoReplaceAll then
          CanExit:=true;
        { an empty match: go on from the next character }
        if (M.Stop=M.Start) then
          if SForward then Inc(From) else Dec(From);
        Refresh;
      until CanExit;
    end;
  if (FoundCount=0) or (DoReplace) then
    SetHighlight(CurPos,CurPos);
  if FoundCount=0 then
    EditorDialog(edSearchFailed,nil);
  if FindStr<>'' then
    PopInfo;
  if HasScope and DoReplace=false then
    Editor.SetBlockMarks(SelA,SelB);
  Refresh;
end;

{ --- keys and commands --- }

procedure TCustomCodeEditor.ConvertEvent(var Event: TEvent);
var
  Key: Word;
begin
  if Event.What = evKeyDown then
  begin
    if (Event.KeyDown.ControlKeyState and kbShift <> 0) and
      (Event.KeyDown.CharScan.ScanCode >= $47) and (Event.KeyDown.CharScan.ScanCode <= $51) then
      Event.KeyDown.CharScan.CharCode := 0;
    Key := Event.KeyDown.KeyCode;
    if KeyState <> 0 then
    begin
      if (Lo(Key) >= $01) and (Lo(Key) <= $1A) then Inc(Key, $40);
      if (Lo(Key) >= $61) and (Lo(Key) <= $7A) then Dec(Key, $20);
    end;
    Key := ScanKeyMap(WEditor.KeyMap[KeyState], Key);
    if (KeyState<>0) and (Key=0) then
      ClearEvent(Event); { eat second key if unrecognized after ^Q or ^K }
    KeyState := 0;
    if Key <> 0 then
      if Hi(Key) = $FF then
        begin
          KeyState := Lo(Key);
          ClearEvent(Event);
        end
      else
        begin
          Event.What := evCommand;
          Event.Message.Command := Key;
        end;
  end;
end;

procedure TCustomCodeEditor.SetLineFlagState(LineNo: sw_integer; Flags: longint; ASet: boolean);
var F: longint;
begin
  if (LineNo<0) or (LineNo>=GetLineCount) then
    exit;
  F:=FCore.GetLineFlags(LineNo);
  if ASet then
    F:=F or Flags
  else
    F:=F and not Flags;
  FCore.SetLineFlags(LineNo,F);
end;

procedure TCustomCodeEditor.SetLineFlagExclusive(Flags: longint; LineNo: sw_integer);
var I,Count: sw_integer;
begin
  Lock;
  Count:=GetLineCount;
  for I:=0 to Count-1 do
    if I=LineNo then
      SetLineFlagState(I,Flags,true)
    else if (FCore.GetLineFlags(I) and Flags)<>0 then
      SetLineFlagState(I,Flags,false);
  UnLock;
end;

function TCustomCodeEditor.GetLocalMenu: PMenu;
begin
  GetLocalMenu:=nil;
end;

function TCustomCodeEditor.GetCommandTarget: PView;
begin
  GetCommandTarget:=Self;
end;

function TCustomCodeEditor.CreateLocalMenuView(var Bounds: TRect; M: PMenu): PMenuPopup;
var MV: PMenuPopup;
begin
  MV := TMenuPopup.Create(Bounds, M, nil);
  CreateLocalMenuView:=MV;
end;

procedure TCustomCodeEditor.LocalMenu(P: TPoint);
var M: PMenu;
    MV: PMenuPopUp;
    R: TRect;
    Re: word;
begin
  M:=GetLocalMenu;
  if M=nil then Exit;
  if LastLocalCmd<>0 then
     M.Deflt:=SearchMenuItem(M,LastLocalCmd);
  R := TProgram.DeskTop.GetExtent;
  R.A := MakeGlobal(P);
  MV:=CreateLocalMenuView(R,M);
  Re:=TProgram.Application.ExecView(MV);
  if M.Deflt=nil then LastLocalCmd:=0
     else LastLocalCmd:=M.Deflt.Command;
  MV.Free;
  if Re<>0 then
    Message(GetCommandTarget, evCommand, Re, Pointer(Self));
end;

procedure TCustomCodeEditor.HandleEvent(var Event: TEvent);
type TCCAction = (ccCheck,ccClear,ccDontCare);
var
  DontClear: boolean;
  PasteStr: AnsiString;
  E: TEvent;
  OldEvent: PEvent;
  CCAction: TCCAction;
  P: TPoint;
begin
  CCAction:=ccClear;
  E:=Event;
  OldEvent:=CurEvent;
  if (E.What and (evMouse or evKeyboard))<>0 then
    CurEvent:=@E;
  if (InASCIIMode=false) or (Event.What<>evKeyDown) then
   if (Event.What<>evKeyDown) or (Event.KeyDown.KeyCode<>kbEnter) or (IsReadOnly=false) then
   if (Event.What<>evKeyDown) or
      ((Event.KeyDown.KeyCode<>kbEnter) and (Event.KeyDown.KeyCode<>kbEsc)) or
      (GetCompleteState<>csOffering) then
    ConvertEvent(Event);
  case Event.What of
    evMouseDown :
      if MouseInView(Event.Mouse.Where) then
       if (Event.Mouse.Buttons=mbRightButton) then
         begin
           P := MakeLocal(Event.Mouse.Where); Inc(P.X); Inc(P.Y);
           LocalMenu(P);
           ClearEvent(Event);
         end;
    evKeyDown :
      if ((Event.KeyDown.ControlKeyState and kbPaste)<>0) and not IsReadOnly and not InASCIIMode and
         TextEvent(Event,PasteStr) then
        begin
          AddGroupedAction(eaPaste);
          InsertBlockText(PasteStr);
          CloseGroupedAction(eaPaste);
          Event.What:=evNothing;
        end
      else
      begin
        if InASCIIMode then
          begin
            AddChar(Char(Event.KeyDown.CharScan.CharCode));
            if (GetCompleteState<>csDenied) or (Event.KeyDown.CharScan.CharCode=32) then
              CCAction:=ccCheck
            else
              CCAction:=ccClear;
          end
        else
          begin
           DontClear:=false;
           case Event.KeyDown.KeyCode of
             kbAltF10 :
               Message(Self, evCommand, cmLocalMenu, Pointer(Self));
             kbEnter  :
               if IsReadOnly then
                 DontClear:=true else
               if GetCompleteState=csOffering then
                 CodeCompleteApply
               else
                 Message(Self,evCommand,cmNewLine,nil);
             kbEsc :
               if GetCompleteState=csOffering then
                 CodeCompleteCancel else
                if IsModal then
                  DontClear:=true;
           else
            if Utf8Enabled and (Event.KeyDown.TextLength>0) and (Byte(Event.KeyDown.Text[0])>=$80) then
              begin
                NoSelect:=true;
                AddString(EventText(Event));
                NoSelect:=false;
                CCAction:=ccClear;
              end
            else
            case Event.KeyDown.CharScan.CharCode of
             9,32..255 :
               if (Event.KeyDown.CharScan.CharCode=9) and IsModal then
                 DontClear:=true
               else
                 begin
                   NoSelect:=true;
                   if Event.KeyDown.CharScan.CharCode=9 then
                     Indent
                   else
                     AddChar(Char(Event.KeyDown.CharScan.CharCode));
                   NoSelect:=false;
                   if (GetCompleteState<>csDenied) or (Event.KeyDown.CharScan.CharCode=32) then
                     CCAction:=ccCheck
                   else
                     CCAction:=ccClear;
                 end;
            else
              DontClear:=true;
            end;
           end;
            if not DontClear then
             ClearEvent(Event);
          end;
        InASCIIMode:=false;
      end;
    evCommand :
      begin
        DontClear:=false;
        case Event.Message.Command of
          cmASCIIChar   : InASCIIMode:=not InASCIIMode;
          cmAddChar     :
            { InfoPtr is the code of the character }
            if Utf8Enabled and (PtrUInt(Event.Message.InfoPtr)>=128) then
              AddCharStr(U8Encode(longint(PtrUInt(Event.Message.InfoPtr))))
            else
              AddChar(chr(PtrUInt(Event.Message.InfoPtr)));
          cmCharLeft    : CharLeft;
          cmCharRight   : CharRight;
          cmWordLeft    : WordLeft;
          cmWordRight   : WordRight;
          cmLineStart   : LineStart;
          cmLineEnd     : LineEnd;
          cmLineUp      : LineUp;
          cmLineDown    : LineDown;
          cmPageUp      : PageUp;
          cmPageDown    : PageDown;
          cmTextStart   : TextStart;
          cmTextEnd     : TextEnd;
          cmWindowStart : WindowStart;
          cmWindowEnd   : WindowEnd;
          cmNewLine     : begin
                            InsertNewLine;
                            TrackCursor(do_not_centre);
                          end;
          cmBreakLine   : BreakLine;
          cmBackSpace   : BackSpace;
          cmDelChar     : DelChar;
          cmDelWord     : DelWord;
          cmDelToEndOfWord : DelToEndOfWord;
          cmDelStart    : DelStart;
          cmDelEnd      : DelEnd;
          cmDelLine     : DelLine;
          cmInsMode     : InsMode;
          cmStartSelect : StartSelect;
          cmHideSelect  : HideSelect;
          cmUpdateTitle : ;
          cmEndSelect   : EndSelect;
          cmDelSelect   : DelSelect;
          cmCopyBlock   : CopyBlock;
          cmMoveBlock   : MoveBlock;
          cmIndentBlock   : IndentBlock;
          cmUnindentBlock : UnindentBlock;
          cmSelStart    : JumpSelStart;
          cmSelEnd      : JumpSelEnd;
          cmLastCursorPos : JumpToLastCursorPos;
          cmFindMatchingDelimiter : FindMatchingDelimiter(true);
          cmFindMatchingDelimiterBack : FindMatchingDelimiter(false);
          cmUpperCase     : UpperCase;
          cmLowerCase     : LowerCase;
          cmWordLowerCase : WordLowerCase;
          cmWordUpperCase : WordUpperCase;
          cmInsertOptions : InsertOptions;
          cmToggleCase    : ToggleCase;
          cmCreateFold    : CreateFoldFromBlock;
          cmToggleFold    : ToggleFold;
          cmExpandFold    : ExpandFold;
          cmCollapseFold  : CollapseFold;
          cmJumpMark0..cmJumpMark9 : JumpMark(Event.Message.Command-cmJumpMark0);
          cmSetMark0..cmSetMark9 : DefineMark(Event.Message.Command-cmSetMark0);
          cmSelectWord  : SelectWord;
          cmSelectLine  : SelectLine;
          cmWriteBlock  : WriteBlock;
          cmReadBlock   : ReadBlock;
          cmPrintBlock  : PrintBlock;
          cmFind        : Find;
          cmReplace     : Replace;
          cmSearchAgain : DoSearchReplace;
          cmJumpLine    : GotoLine;
          cmCut         : ClipCut;
          cmCopy        : ClipCopy;
          cmPaste       : ClipPaste;
          cmSelectAll   : SelectAll(true);
          cmUnselect    : SelectAll(false);
          cmUndo        : Undo;
          cmRedo        : Redo;
          cmClear       : DelSelect;
          cmExpandCodeTemplate: ExpandCodeTemplate;
          cmLocalMenu :
            begin
              P:=CurPos; Inc(P.X); Inc(P.Y);
              LocalMenu(P);
            end;
          cmActivateMenu :
            Message(TProgram.Application,evCommand,cmMenu,nil);
        else
          begin
            DontClear:=true;
            CCAction:=ccDontCare;
          end;
        end;
        if DontClear=false then
          ClearEvent(Event);
      end;
    evBroadcast :
      begin
        CCAction:=ccDontCare;
        case Event.Message.Command of
          cmUpdate :
            Update;
          cmClearLineHighlights :
            SetLineFlagExclusive(lfHighlightRow,-1);
          cmResetDebuggerRow :
            SetLineFlagExclusive(lfDebuggerRow,-1);
        end;
      end;
  else CCAction:=ccDontCare;
  end;
  inherited HandleEvent(Event);
  CurEvent:=OldEvent;
  case CCAction of
    ccCheck : CodeCompleteCheck;
    ccClear : ClearCodeCompleteWord;
  end;
end;

procedure TEditorInputLine.HandleEvent(var Event : TEvent);
var
  s,s2 : string;
  i : longint;
begin
     If (Event.What=evKeyDown) then
       begin
         if (Event.KeyDown.KeyCode=kbRight) and
            (CurPos = Length(Data^)) and
            Assigned(FindReplaceEditor) then
           Begin
             s:=FindReplaceEditor.GetDisplayText(FindReplaceEditor.CurPos.Y);
             s:=Copy(s,FindReplaceEditor.CurPos.X + 1 -length(Data^),high(s));
             i:=pos(Data^,s);
             if i>0 then
               begin
                 s:=Data^+s[i+length(Data^)];
                 If not assigned(validator) or
                    Validator.IsValidInput(s,False)  then
                   Begin
                     Event.KeyDown.CharScan.CharCode:=Ord(s[length(s)]);
                     Event.KeyDown.CharScan.ScanCode:=0;
                     Inherited HandleEvent(Event);
                   End;
               end;
             ClearEvent(Event);
           End
         else if (Event.KeyDown.KeyCode=kbShiftIns)  and
                 Assigned(Clipboard) and (Clipboard.ValidBlock) then
           { paste from clipboard }
           begin
             i:=Clipboard.SelStart.Y;
             s:=Clipboard.GetDisplayText(i);
             i:=Clipboard.SelStart.X;
             if i>0 then
              s:=copy(s,i+1,high(s));
             if (Clipboard.SelStart.Y=Clipboard.SelEnd.Y) then
               begin
                 i:=Clipboard.SelEnd.X-i;
                 s:=copy(s,1,i);
               end;
             for i:=1 to length(s) do
               begin
                 s2:=Data^+s[i];
                 If not assigned(validator) or
                    Validator.IsValidInput(s2,False)  then
                   Begin
                     Event.What:=evKeyDown;
                     Event.KeyDown.CharScan.CharCode := Ord(s[i]);
                     Event.KeyDown.CharScan.ScanCode:=0;
                     Inherited HandleEvent(Event);
                   End;
               end;
             ClearEvent(Event);
           end
         else if (Event.KeyDown.KeyCode=kbCtrlIns)  and
                 Assigned(Clipboard) then
           { Copy to clipboard }
           begin
             s:=GetStr(Data);
             s:=copy(s,selstart+1,selend-selstart);
             Clipboard.SelStart:=Clipboard.CurPos;
             Clipboard.InsertText(s);
             Clipboard.SelEnd:=Clipboard.CurPos;
             ClearEvent(Event);
           end
         else if (Event.KeyDown.KeyCode=kbShiftDel)  and
                 Assigned(Clipboard) then
           { Cut to clipboard }
           begin
             s:=GetStr(Data);
             s:=copy(s,selstart+1,selend-selstart);
             Clipboard.SelStart:=Clipboard.CurPos;
             Clipboard.InsertText(s);
             Clipboard.SelEnd:=Clipboard.CurPos;
             s2:=GetStr(Data);
             { now remove the selected part }
             Event.KeyDown.KeyCode:=kbDel;
             inherited HandleEvent(Event);
             ClearEvent(Event);
           end
         else
           Inherited HandleEvent(Event);
       End
     else
       Inherited HandleEvent(Event);
  s:=getstr(data);
  Message(Owner,evBroadCast,cminputlinelen,pointer(PtrUInt(length(s))));
end;

procedure TSearchHelperDialog.HandleEvent(var Event : TEvent);
begin
 case Event.What of
     evBroadcast :
           case Event.Message.Command of
                   cminputlinelen : begin
                                      if PtrUInt(Event.Message.InfoPtr)=0 then
                                        okbutton.DisableCommands(CommandSetOf([cmok]))
                                      else
                                        okbutton.EnableCommands(CommandSetOf([cmok]));
                                      clearevent(event);
                                    end;
             end;
       end;
  inherited HandleEvent(Event);
end;


function CreateFindDialog: PDialog;
var R,R1,R2: TRect;
    D: PSearchHelperDialog;
    IL1: PEditorInputLine;
    Control : PView;
    CB1: PCheckBoxes;
    RB1,RB2,RB3: PRadioButtons;
    but : PButton;
begin
  R := TRect.Create(0, 0, 56, 15);
  D := TSearchHelperDialog.Create(R, dialog_find);
  with D do
  begin
    Options:=Options or ofCentered;
    R := GetExtent; R.Grow(-3,-2);
    R1 := R; R1.B.X:=17; R1.B.Y:=R1.A.Y+1;
    R2 := R; R2.B.X:=R2.B.X-3;R2.A.X:=17; R2.B.Y:=R2.A.Y+1;
    IL1 := TEditorInputLine.Create(R2, FindStrSize);
    IL1.Data^:=FindStr;
    Insert(IL1);
    Insert(TLabel.Create(R1, label_find_texttofind, IL1));
    R1 := TRect.Create(R2.B.X, R2.A.Y, R2.B.X+3, R2.B.Y);
    Control := THistory.Create(R1, IL1, TextFindId);
    Insert(Control);

    R1 := R; Inc(R1.A.Y,2); R1.B.Y:=R1.A.Y+1; R1.B.X:=R1.A.X+(R1.B.X-R1.A.X) div 2-1;
    R2 := R1; R2.Move(0,1);
    R2.B.Y:=R2.A.Y+{$ifdef TEST_REGEXP}3{$else}2{$endif};
    CB1 := TCheckBoxes.Create(R2,
      TSItem.Create(label_find_casesensitive,
      TSItem.Create(label_find_wholewordsonly,
{$ifdef TEST_REGEXP}
      TSItem.Create(label_find_useregexp,
{$endif TEST_REGEXP}
      nil))){$ifdef TEST_REGEXP}){$endif TEST_REGEXP};
    Insert(CB1);
    Insert(TLabel.Create(R1, label_find_options, CB1));

    R1 := R; Inc(R1.A.Y,2); R1.B.Y:=R1.A.Y+1; R1.A.X:=R1.B.X-(R1.B.X-R1.A.X) div 2+1;
    R2 := R1; R2.Move(0,1); R2.B.Y:=R2.A.Y+2;
    RB1 := TRadioButtons.Create(R2,
      TSItem.Create(label_find_forward,
      TSItem.Create(label_find_backward,
      nil)));
    Insert(RB1);
    Insert(TLabel.Create(R1, label_find_direction, RB1));

    R1 := R; Inc(R1.A.Y,6); R1.B.Y:=R1.A.Y+1; R1.B.X:=R1.A.X+(R1.B.X-R1.A.X) div 2-1;
    R2 := R1; R2.Move(0,1); R2.B.Y:=R2.A.Y+2;
    RB2 := TRadioButtons.Create(R2,
      TSItem.Create(label_find_global,
      TSItem.Create(label_find_selectedtext,
      nil)));
    Insert(RB2);
    Insert(TLabel.Create(R1, label_find_scope, RB2));

    R1 := R; Inc(R1.A.Y,6); R1.B.Y:=R1.A.Y+1; R1.A.X:=R1.B.X-(R1.B.X-R1.A.X) div 2+1;
    R2 := R1; R2.Move(0,1); R2.B.Y:=R2.A.Y+2;
    RB3 := TRadioButtons.Create(R2,
      TSItem.Create(label_find_fromcursor,
      TSItem.Create(label_find_entirescope,
      nil)));
    Insert(RB3);
    Insert(TLabel.Create(R1, label_find_origin, RB3));

    R := GetExtent; R.Grow(-13,-1); R.A.Y:=R.B.Y-2; R.B.X:=R.A.X+10;
    Okbutton := TButton.Create(R, btn_OK, cmOK, bfDefault);
    Insert(OkButton);
    R.Move(19,0);
    Insert(TButton.Create(R, btn_Cancel, cmCancel, bfNormal));
  end;
  IL1.Select;
  CreateFindDialog := D;
end;

function CreateReplaceDialog: PDialog;
var R,R1,R2: TRect;
    D: PDialog;
    Control : PView;
    IL1: PEditorInputLine;
    IL2: PEditorInputLine;
    CB1: PCheckBoxes;
    RB1,RB2,RB3: PRadioButtons;
begin
  R := TRect.Create(0, 0, 56, 18);
  D := TSearchHelperDialog.Create(R, dialog_replace);
  with D do
  begin
    Options:=Options or ofCentered;
    R := GetExtent; R.Grow(-3,-2);
    R1 := R; R1.B.X:=17; R1.B.Y:=R1.A.Y+1;
    R2 := R; R2.B.X:=R2.B.X-3;R2.A.X:=17; R2.B.Y:=R2.A.Y+1;
    IL1 := TEditorInputLine.Create(R2, FindStrSize);
    IL1.Data^:=FindStr;
    Insert(IL1);
    Insert(TLabel.Create(R1, label_replace_texttofind, IL1));
    R1 := TRect.Create(R2.B.X, R2.A.Y, R2.B.X+3, R2.B.Y);
    Control := THistory.Create(R1, IL1, TextFindId);
    Insert(Control);

    R1 := R; R1.Move(0,2); R1.B.X:=17; R1.B.Y:=R1.A.Y+1;
    R2 := R; R2.Move(0,2);R2.B.X:=R2.B.X-3;
    R2.A.X:=17; R2.B.Y:=R2.A.Y+1;
    IL2 := TEditorInputLine.Create(R2, FindStrSize);
    IL2.Data^:=ReplaceStr;
    Insert(IL2);
    Insert(TLabel.Create(R1, label_replace_newtext, IL2));
    R1 := TRect.Create(R2.B.X, R2.A.Y, R2.B.X+3, R2.B.Y);
    Control := THistory.Create(R1, IL2, TextReplaceId);
    Insert(Control);

    R1 := R; Inc(R1.A.Y,4); R1.B.Y:=R1.A.Y+1; R1.B.X:=R1.A.X+(R1.B.X-R1.A.X) div 2-1;
    R2 := R1; R2.Move(0,1);
    R2.B.Y:=R2.A.Y+{$ifdef TEST_REGEXP}4{$else}3{$endif};
    CB1 := TCheckBoxes.Create(R2,
      TSItem.Create(label_replace_casesensitive,
      TSItem.Create(label_replace_wholewordsonly,
      TSItem.Create(label_replace_promptonreplace,
{$ifdef TEST_REGEXP}
      TSItem.Create(label_find_useregexp,
{$endif TEST_REGEXP}
      nil)))){$ifdef TEST_REGEXP}){$endif TEST_REGEXP};
    Insert(CB1);
    Insert(TLabel.Create(R1, label_replace_options, CB1));

    R1 := R; Inc(R1.A.Y,4); R1.B.Y:=R1.A.Y+1; R1.A.X:=R1.B.X-(R1.B.X-R1.A.X) div 2+1;
    R2 := R1; R2.Move(0,1); R2.B.Y:=R2.A.Y+2;
    RB1 := TRadioButtons.Create(R2,
      TSItem.Create(label_replace_forward,
      TSItem.Create(label_replace_backward,
      nil)));
    Insert(RB1);
    Insert(TLabel.Create(R1, label_replace_direction, RB1));

    R1 := R; Inc(R1.A.Y,9); R1.B.Y:=R1.A.Y+1; R1.B.X:=R1.A.X+(R1.B.X-R1.A.X) div 2-1;
    R2 := R1; R2.Move(0,1); R2.B.Y:=R2.A.Y+2;
    RB2 := TRadioButtons.Create(R2,
      TSItem.Create(label_replace_global,
      TSItem.Create(label_replace_selectedtext,
      nil)));
    Insert(RB2);
    Insert(TLabel.Create(R1, label_replace_scope, RB2));

    R1 := R; Inc(R1.A.Y,9); R1.B.Y:=R1.A.Y+1; R1.A.X:=R1.B.X-(R1.B.X-R1.A.X) div 2+1;
    R2 := R1; R2.Move(0,1); R2.B.Y:=R2.A.Y+2;
    RB3 := TRadioButtons.Create(R2,
      TSItem.Create(label_replace_fromcursor,
      TSItem.Create(label_replace_entirescope,
      nil)));
    Insert(RB3);
    Insert(TLabel.Create(R1, label_replace_origin, RB3));

    R := GetExtent; R.Grow(-13,-1); R.A.Y:=R.B.Y-2; R.B.X:=R.A.X+10; R.Move(-10,0);
    Insert(TButton.Create(R, btn_OK, cmOK, bfDefault));
    R.Move(11,0); R.B.X:=R.A.X+14;
    Insert(TButton.Create(R, btn_replace_changeall, cmYes, bfNormal));
    R.Move(15,0); R.B.X:=R.A.X+10;
    Insert(TButton.Create(R, btn_Cancel, cmCancel, bfNormal));
  end;
  IL1.Select;
  CreateReplaceDialog := D;
end;

function CreateGotoLineDialog(Info: pointer): PDialog;
var D: PDialog;
    R,R1,R2: TRect;
    Control : PView;
    IL: PEditorInputLine;
begin
  R := TRect.Create(0, 0, 40, 7);
  D := TSearchHelperDialog.Create(R, dialog_gotoline);
  with D do
  begin
    Options:=Options or ofCentered;
    R := GetExtent; R.Grow(-3,-2); R.B.Y:=R.A.Y+1;
    R1 := R; R1.B.X:=27; R2 := R;
    R2.B.X:=R2.B.X-3;R2.A.X:=27;
    IL := TEditorInputLine.Create(R2,5);
    with TGotoLineDialogRec(Info^) do
    IL.SetValidator(TRangeValidator.Create(1, Lines));
    Insert(IL);
    Insert(TLabel.Create(R1, label_gotoline_linenumber, IL));
    R1 := TRect.Create(R2.B.X, R2.A.Y, R2.B.X+3, R2.B.Y);
    Control := THistory.Create(R1, IL, GotoId);
    Insert(Control);

    R := GetExtent; R.Grow(-8,-1); R.A.Y:=R.B.Y-2; R.B.X:=R.A.X+10;
    Insert(TButton.Create(R, btn_OK, cmOK, bfDefault));
    R.Move(15,0);
    Insert(TButton.Create(R, btn_Cancel, cmCancel, bfNormal));
  end;
  IL.Select;
  CreateGotoLineDialog:=D;
end;

function StdEditorDialog(Dialog: Integer; Info: Pointer): Word;
var
  R: TRect;
  T: TPoint;
  Re: word;
  Name: string;
  DriveNumber : byte;
  StoreDir,StoreDir2 : DirStr;
  Title,DefExt: string;
  AskOW: boolean;
begin
  case Dialog of
    edOutOfMemory:
      StdEditorDialog := AdvMessageBox(msg_notenoughmemoryforthisoperation,
   nil, mfInsertInApp+ mfError + mfOKButton);
    edReadError:
      StdEditorDialog := AdvMessageBox(msg_errorreadingfile,
   @Info, mfInsertInApp+ mfError + mfOKButton);
    edWriteError:
      StdEditorDialog := AdvMessageBox(msg_errorwritingfile,
   @Info, mfInsertInApp+ mfError + mfOKButton);
    edSaveError:
      StdEditorDialog := AdvMessageBox(msg_errorsavingfile,
   @Info, mfInsertInApp+ mfError + mfOKButton);
    edCreateError:
      StdEditorDialog := AdvMessageBox(msg_errorcreatingfile,
   @Info, mfInsertInApp+ mfError + mfOKButton);
    edSaveModify:
      StdEditorDialog := AdvMessageBox(msg_filehasbeenmodifiedsave,
   @Info, mfInsertInApp+ mfInformation + mfYesNoCancel);
    edSaveUntitled:
      StdEditorDialog := AdvMessageBox(msg_saveuntitledfile,
   nil, mfInsertInApp+ mfInformation + mfYesNoCancel);
    edChangedOnloading:
      StdEditorDialog := AdvMessageBox(msg_filehadtoolonglines,
   Info, mfInsertInApp+ mfOKButton + mfInformation);
    edFileOnDiskChanged:
      StdEditorDialog := AdvMessageBox(msg_filewasmodified,
   @info, mfInsertInApp+ mfInformation + mfYesNoCancel);
    edReloadDiskmodifiedFile:
      StdEditorDialog := AdvMessageBox(msg_reloaddiskmodifiedfile,
   @info, mfInsertInApp+ mfInformation + mfYesNoCancel);
    edReloadDiskAndIDEModifiedFile:
      StdEditorDialog := AdvMessageBox(msg_reloaddiskandidemodifiedfile,
   @info, mfInsertInApp+ mfInformation + mfYesNoCancel);
    edSaveAs,edWriteBlock,edReadBlock:
      begin
        Name:=PString(Info)^;
        GetDir(0,StoreDir);
        DriveNumber:=0;
        { a drive letter (there are none on Unix) }
        if Length(PathDrive(FileDir))=2 then
          begin
            { does not assume that lowercase are greater then uppercase ! }
            if (FileDir[1]>='a') and (FileDir[1]<='z') then
              DriveNumber:=Ord(FileDir[1])-ord('a')+1
            else
              DriveNumber:=Ord(FileDir[1])-ord('A')+1;
            GetDir(DriveNumber,StoreDir2);
            {$I-}
            ChDir(Copy(FileDir,1,2));
            EatIO;
            {$I+}
          end;
        if FileDir<>'' then
          begin
            {$I-}
            ChDir(TrimEndSlash(FileDir));
            EatIO;
            {$I+}
          end;
        case Dialog of
          edSaveAs     :
            begin
              Title:=dialog_savefileas;
              DefExt:='*'+DefaultSaveExt;
            end;
          edWriteBlock :
            begin
              Title:=dialog_writeblocktofile;
              DefExt:=AllFilesMask;
            end;
          edReadBlock  :
            begin
              Title:=dialog_readblockfromfile;
              DefExt:=AllFilesMask;
            end;
        else begin Title:='???'; DefExt:=''; end;
        end;
        Re:=TProgram.Application.ExecuteDialog(TFileDialog.Create(DefExt,
          Title, label_name, fdOkButton, FileId), @Name);
        case Dialog of
          edSaveAs     :
            begin
              if ExtOf(Name)='' then
                Name:=Name+DefaultSaveExt;
              AskOW:=(Name<>PString(Info)^);
            end;
          edWriteBlock :
            begin
              if ExtOf(Name)='' then
                Name:=Name+DefaultSaveExt;
              AskOW:=true;
            end;
          edReadBlock  : AskOW:=false;
        else AskOW:=true;
        end;
        if (Re<>cmCancel) and AskOW then
          begin
            FileDir:=DirOf(ExpandPath(Name));
            if ExistsFile(Name) then
              if EditorDialog(edReplaceFile,@Name)<>cmYes then
                Re:=cmCancel;
          end;
        if DriveNumber<>0 then
          ChDir(StoreDir2);
        if StoreDir<>'' then
          ChDir(TrimEndSlash(StoreDir));

        if Re<>cmCancel then
          PString(Info)^:=Name;
        StdEditorDialog := Re;
      end;
    edGotoLine:
      StdEditorDialog :=
   TProgram.Application.ExecuteDialog(CreateGotoLineDialog(Info), Info);
    edFind:
      StdEditorDialog :=
   TProgram.Application.ExecuteDialog(CreateFindDialog, Info);
    edSearchFailed:
      StdEditorDialog := AdvMessageBox(msg_searchstringnotfound,
   nil, mfInsertInApp+ mfError + mfOKButton);
    edReplace:
      StdEditorDialog :=
   TProgram.Application.ExecuteDialog(CreateReplaceDialog, Info);
    edReplacePrompt:
      begin
   { Avoid placing the dialog on the same line as the cursor }
   R := TRect.Create(0, 1, 40, 8);
   R.Move((TProgram.DeskTop.Size.X - R.B.X) div 2, 0);
   T := TProgram.DeskTop.MakeGlobal(R.B);
   Inc(T.Y);
   if PPoint(Info)^.Y <= T.Y then
     R.Move(0, TProgram.DeskTop.Size.Y - R.B.Y - 2);
   StdEditorDialog := AdvMessageBoxRect(R, msg_replacethisoccourence,
     nil, mfInsertInApp+ mfYesNoCancel + mfInformation);
      end;
    edReplaceFile :
      StdEditorDialog :=
   AdvMessageBox(msg_fileexistsoverwrite,@Info,mfInsertInApp+mfConfirmation+
     mfYesButton+mfNoButton);
  end;
end;

procedure RegisterWEditor;
begin
end;

END.
