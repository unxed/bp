{
    This file is part of the Free Pascal Integrated Development Environment
    Copyright (c) 1998-2000 by Pierre Muller

    Debugger call routines for the IDE

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}
unit FPDebug;

{$mode objfpc}{$H-}
{$modeswitch nestedprocvars}
{$modeswitch autoderef}
{$ifdef NODEBUG}
interface
implementation
end.
{$else}
interface
{$i globdir.inc}
uses
{$ifdef Windows}
  Windows,
{$endif Windows}
  Objects,Dialogs,Drivers,Views,
{$ifndef NODEBUG}
  {$ifdef GDBMI}
    GDBMICon,GDBMIInt,GdbPty,
  {$else GDBMI}
    GDBCon,GDBInt,
  {$endif GDBMI}
{$endif NODEBUG}
  Menus,
  WViews,WEditor,
  FPViews;

type
{$ifndef NODEBUG}
  TDebugController = class;
  PDebugController = TDebugController;
  TDebugController= class(TGDBController)
  private
    function  GetFPCBreakErrorParameters(var ExitCode: LongInt; var ExitAddr, ExitFrame: CORE_ADDR): Boolean;
  public
     InvalidSourceLine : boolean;

     { if true the current debugger raw will stay in middle of
       editor window when debugging PM }
     CenterDebuggerRow : TCentre;
     Disableallinvalidbreakpoints : boolean;
     OrigPwd,  { pwd at startup }
     LastFileName : string;
     LastSource   : PView; {PsourceWindow !! }
     HiddenStepsCount : longint;
     { no need to switch if using another terminal }
     NoSwitch : boolean;
     HasExe   : boolean;
     RunCount : longint;
     FPCBreakErrorNumber : longint;
{$ifdef SUPPORT_REMOTE}
     isRemoteDebugging,
     isFirstRemote,
     isConnectedToRemote,
     usessh :boolean;
{$endif SUPPORT_REMOTE}
    constructor Create;
    procedure SetExe(const exefn:string);
    procedure SetSourceDirs;
    destructor Destroy; override;
    function DoSelectSourceline(const fn:string;line,BreakIndex:longint): Boolean;override;
{    procedure DoStartSession;virtual;
    procedure DoBreakSession;virtual;}
    procedure DoEndSession(code:longint);override;
    procedure DoUserSignal;override;
    procedure FlushAll; override;
    function Query(question : pchar; args : pchar) : longint; override;

    procedure AnnotateError;
    procedure InsertBreakpoints;
    procedure RemoveBreakpoints;
    procedure ReadWatches;
    procedure RereadWatches;
    procedure ResetBreakpointsValues;
    procedure DoDebuggerScreen;override;
    procedure DoUserScreen;override;
    procedure Reset;override;
    procedure ResetDebuggerRows;
    procedure Run;override;
    procedure Continue;override;
    procedure UntilReturn;override;
    procedure CommandBegin(const s:string);override;
    procedure CommandEnd(const s:string);override;
    function  IsRunning : boolean;
    function  AllowQuit : boolean;override;
    function  GetValue(Const expr : string) : pchar;
    function  GetFramePointer : CORE_ADDR;
    function  GetLongintAt(addr : CORE_ADDR) : longint;
    function  GetPointerAt(addr : CORE_ADDR) : CORE_ADDR;
  end;
{$endif NODEBUG}

  BreakpointType = (bt_function,bt_file_line,bt_watch,
                    bt_awatch,bt_rwatch,bt_address,bt_invalid);
  BreakpointState = (bs_enabled,bs_disabled,bs_deleted,bs_delete_after);

  TBreakpointCollection = class;
  PBreakpointCollection = TBreakpointCollection;

  TBreakpoint = class;
  PBreakpoint = TBreakpoint;
  TBreakpoint= class(TObject)
     typ  : BreakpointType;
     state : BreakpointState;
     owner : PBreakpointCollection;
     Name : PString;  { either function name or expr to watch }
     FileName : PString;
     OldValue,CurrentValue : Pstring;
     Line : Longint; { only used for bt_file_line type }
     Conditions : PString; { conditions relative to that breakpoint }
     IgnoreCount : Longint; { how many counts should be ignored }
     Commands : pchar; { commands that should be executed on breakpoint }
     GDBIndex : longint;
     GDBState : BreakpointState;
     constructor Init_function(Const AFunc : String);
     constructor Init_Address(Const AAddress : String);
     constructor Init_Empty;
     constructor Init_file_line(AFile : String; ALine : longint);
     constructor Init_type(atyp : BreakpointType;Const AnExpr : String);
     constructor Load(S: TStream);
     procedure   Store(S: TStream);
     procedure  Insert;
     procedure  Remove;
     procedure  Enable;
     procedure  Disable;
     procedure  UpdateSource;
     procedure  ResetValues;
     destructor Destroy;override;
  end;

  TBreakpointCollection= class(TCollection)
      function  At(Index: Integer): PBreakpoint;
      function  GetGDB(index : longint) : PBreakpoint;
      function  GetType(typ : BreakpointType;Const s : String) : PBreakpoint;
      function  ToggleFileLine(FileName: String;LineNr : Longint) : boolean;
      procedure Update;
      procedure ShowBreakpoints(W : PFPWindow);
      function  FindBreakpointAt(Editor : PSourceEditor; Line : longint) : PBreakpoint;
      procedure AdaptBreakpoints(Editor : PSourceEditor; Pos, Change : longint);
      procedure ShowAllBreakpoints;
    end;

    TBreakpointItem = class;
  PBreakpointItem = TBreakpointItem;
    TBreakpointItem = class(TObject)
      Breakpoint : PBreakpoint;
      constructor Create(ABreakpoint : PBreakpoint);
      function    GetText(MaxLen: Sw_integer): string; virtual;
      procedure   Selected; virtual;
      function    GetModuleName: string; virtual;
    end;

    TBreakpointsListBox = class;
  PBreakpointsListBox = TBreakpointsListBox;
    TBreakpointsListBox = class(THSListBox)
      Transparent : boolean;
      NoSelection : boolean;
      MaxWidth    : Sw_integer;
      (* ModuleNames : PStoreCollection; *)
      constructor Create(var Bounds: TRect; AHScrollBar, AVScrollBar: PScrollBar);
      procedure   AddBreakpoint(P: PBreakpointItem); virtual;
      function    GetText(Item,MaxLen: Sw_Integer): String; override;
      function    GetLocalMenu: PMenu;override;
      procedure   Clear; virtual;
      procedure   TrackSource; virtual;
      procedure   EditNew; virtual;
      procedure   EditCurrent; virtual;
      procedure   DeleteCurrent; virtual;
      procedure   ToggleCurrent;
      procedure   Draw; override;
      procedure   HandleEvent(var Event: TEvent); override;
      constructor Load(S: TStream);
      procedure   Store(S: TStream); override;
      destructor Destroy; override;
    end;

    TBreakpointsWindow = class;
  PBreakpointsWindow = TBreakpointsWindow;
    TBreakpointsWindow = class(TFPDlgWindow)
      BreakLB : PBreakpointsListBox;
      constructor Create;
      procedure   AddBreakpoint(ABreakpoint : PBreakpoint);
      procedure   ClearBreakpoints;
      procedure   ReloadBreakpoints;
      procedure   Close; override;
      procedure   SizeLimits(out Min, Max: TPoint);override;
      procedure   HandleEvent(var Event: TEvent); override;
      procedure   Update; override;
      constructor Load(S: TStream);
      procedure   Store(S: TStream); override;
      destructor Destroy; override;
    end;

    TBreakpointItemDialog = class;
  PBreakpointItemDialog = TBreakpointItemDialog;

    TBreakpointItemDialog = class(TCenterDialog)
      constructor Create(ABreakpoint: PBreakpoint);
      function    Execute: Word; override;
    private
      Breakpoint : PBreakpoint;
      TypeRB   : PRadioButtons;
      NameIL  : PEditorInputLine;
      ConditionsIL: PEditorInputLine;
      LineIL    : PEditorInputLine;
      IgnoreIL  : PEditorInputLine;
    end;

    TWatch = class;
  PWatch = TWatch;
    TWatch = class(TObject)
      expr : pstring;
      last_value,current_value : pchar;
      constructor Create(s : string);
      constructor Load(S: TStream);
      procedure   Store(S: TStream);
      procedure rename(s : string);
      procedure Get_new_value;
      procedure Force_new_value;
      destructor Destroy;override;
    private
      GDBRunCount : longint;
    end;

    TWatchesCollection = class;
  PWatchesCollection = TWatchesCollection;
    TWatchesCollection = class(TCollection)
      constructor Create;
      procedure Insert(Item: Pointer); override;
      function  At(Index: Integer): PWatch;
      procedure Update;
    private
      MaxW : integer;
    end;

    TWatchesListBox = class;
  PWatchesListBox = TWatchesListBox;
    TWatchesListBox = class(THSListBox)
      Transparent : boolean;
      MaxWidth    : Sw_integer;
      constructor Create(var Bounds: TRect; AHScrollBar, AVScrollBar: PScrollBar);
      (* procedure   AddWatch(P: PWatch); virtual; *)
      procedure   Update(AMaxWidth : integer);
      function    GetText (Item: Sw_Integer; MaxLen: Sw_Integer): String; override;
      function    GetIndentedText(Item,Indent,MaxLen: Sw_Integer;var Modified : boolean): String; virtual;
      function    GetLocalMenu: PMenu;override;
      (* procedure   Clear; virtual;
      procedure   TrackSource; virtual;*)
      procedure   EditNew; virtual;
      procedure   EditCurrent; virtual;
      procedure   DeleteCurrent; virtual;
      (*procedure   ToggleCurrent; *)
      procedure   Draw; override;
      procedure   HandleEvent(var Event: TEvent); override;
      constructor Load(S: TStream);
      procedure   Store(S: TStream); override;
      destructor Destroy; override;
    end;

    TWatchItemDialog = class;
  PWatchItemDialog = TWatchItemDialog;

    TWatchItemDialog = class(TCenterDialog)
      constructor Create(AWatch: PWatch);
      function    Execute: Word; override;
    private
      Watch : PWatch;
      NameIL  : PEditorInputLine;
      TextST : PAdvancedStaticText;
    end;

    TWatchesWindow = class;
  PWatchesWindow = TWatchesWindow;
    TWatchesWindow = class(TFPDlgWindow)
      WLB : PWatchesListBox;
      constructor Create;
      constructor Load(S: TStream);
      procedure   Store(S: TStream); override;
      procedure   Update; override;
      destructor Destroy; override;
    end;

    TFramesListBox = class;
  PFramesListBox = TFramesListBox;
    TFramesListBox = class(TMessageListBox)
      constructor Create(var Bounds: TRect; AHScrollBar, AVScrollBar: PScrollBar);
      procedure   Update; override;
      function    GetLocalMenu: PMenu;override;
      procedure   GotoSource; override;
      procedure   GotoAssembly; virtual;
      procedure   HandleEvent(var Event: TEvent); override;
      destructor Destroy; override;
    end;

    TStackWindow = class;
  PStackWindow = TStackWindow;
    TStackWindow = class(TFPDlgWindow)
      FLB : PFramesListBox;
      constructor Create;
      constructor Load(S: TStream);
      procedure   Store(S: TStream); override;
      procedure   Update; override;
      destructor Destroy; override;
    end;

  procedure InitStackWindow;
  procedure DoneStackWindow;

  function  ActiveBreakpoints : boolean;
  function  GDBFileName(st : string) : string;
  function  OSFileName(st : string) : string;


const
     BreakpointTypeStr : Array[BreakpointType] of String[9]
       = ( 'function','file-line','watch','awatch','rwatch','address','invalid');
     BreakpointStateStr : Array[BreakpointState] of String[8]
       = ( 'enabled','disabled','invalid',''{'to be deleted' should never be used});

var
{$ifndef NODEBUG}
  Debugger             : PDebugController;
{$endif NODEBUG}
  BreakpointsCollection : PBreakpointCollection;
  WatchesCollection    : PwatchesCollection;

type
  { The debugger of another language (Delve for Go, unit fpgodbg) serves the windows of watches, evaluation and call stack through
    these procedures while its session is open; with none set the windows talk to gdb. }
  TForeignEvalFunc = function(const Expr: string; out Value: string): boolean;
  TForeignFrameCountFunc = function: longint;
  TForeignFrameProc = procedure(Index: longint; out Name, FileName: string; out Line: longint);
  TForeignSelectFrameProc = procedure(Index: longint);

var
  ForeignEval: TForeignEvalFunc = nil;
  ForeignFrameCount: TForeignFrameCountFunc = nil;
  ForeignFrame: TForeignFrameProc = nil;
  ForeignSelectFrame: TForeignSelectFrameProc = nil;
  { changes at each stop of the foreign debugger: the values of the watches are read again }
  ForeignRunCount: longint = 1;

{ the stop of a foreign debugger or another frame: the watches (and the open windows of watches) are read again }
procedure ForeignRereadWatches;
procedure InitDebugger;
procedure DoneDebugger;
procedure InitGDBWindow;
procedure DoneGDBWindow;
procedure InitDisassemblyWindow;
procedure DoneDisassemblyWindow;
procedure InitBreakpoints;
procedure DoneBreakpoints;
procedure InitWatches;
procedure DoneWatches;

procedure RegisterFPDebugViews;

procedure UpdateDebugViews;

{$ifdef SUPPORT_REMOTE}
function TransformRemoteString(st : string) : string;
{$endif SUPPORT_REMOTE}

implementation

uses
  Dos,TvPath,
  Video,
{$ifdef DOS}
  fpusrscr,
{$endif DOS}
  fpredir,
  App,Strings,
  FVConsts,
  MsgBox,
{$ifdef Windows}
  Windebug,
{$endif Windows}
{$ifdef Unix}
  baseunix, unix, termio,
{$endif Unix}
  Systems,
{$ifdef EMBED_COMPILER}
  Globals,
{$else}
  FPExtComp,
{$endif}
  FPRegs,FPTools,
  FPVars,FPUtils,FPConst,FPSwitch,
  FPIntf,FPCompil,FPIde,FPHelp,
  Validate,WUtils,Wconsts;

{$ifndef NOOBJREG}
{$ifndef NOOBJREG}
{$ifndef NOOBJREG}
var RBreakpointsWindow: TStreamRec;


  {$endif}
{$endif}
{$endif NOOBJREG}

var RBreakpointsListBox: TStreamRec;
var RWatchesWindow: TStreamRec;
var RWatchesListBox: TStreamRec;
var RStackWindow: TStreamRec;
var RFramesListBox: TStreamRec;
var RBreakpoint: TStreamRec;
var RWatch: TStreamRec;
var RBreakpointCollection: TStreamRec;
var RWatchesCollection: TStreamRec;


{$ifdef USERESSTRINGS}
resourcestring
{$else}
const
{$endif}
      button_OK          = 'O~K~';
      button_Cancel      = 'Cancel';
      button_New         = '~N~ew';
      button_Edit        = '~E~dit';
      button_Delete      = '~D~elete';
      button_Close       = '~C~lose';
      button_ToggleButton = '~T~oggle';

      { Watches local menu items }
      menu_watchlocal_edit = '~E~dit watch';
      menu_watchlocal_new = '~N~ew watch';
      menu_watchlocal_delete = '~D~elete watch';

      { Breakpoints window local menu items }
      menu_bplocal_gotosource = '~G~oto source';
      menu_bplocal_editbreakpoint = '~E~dit breakpoint';
      menu_bplocal_newbreakpoint = '~N~ew breakpoint';
      menu_bplocal_deletebreakpoint = '~D~elete breakpoint';
      menu_bplocal_togglestate = '~T~oggle state';

      { Debugger messages and status hints }
      msg_programexitedwithcodeandsteps = #3'Program exited with '#13+
                                          #3'exitcode = %d'#13+
                                          #3'hidden steps = %d';

      msg_programexitedwithexitcode = #3'Program exited with '#13+
                                      #3'exitcode = %d';

      msg_programsignal             = #3'Program received signal %s'#13+
                                      #3'%s';

      msg_runningprogram  = 'Running...';
      msg_runningremotely = 'Executable running remotely on ';
      msg_connectingto    = 'Connecting to ';
      msg_getting_info_on = 'Getting info from ';
      msg_runninginanotherwindow = 'Executable running in another window..';
      msg_couldnotsetbreakpointat = #3'Could not set Breakpoint'#13+
                                    #3+'%s:%d';
      msg_couldnotsetbreakpointtype = #3'Could not set Breakpoint'#13+
                                      #3+'%s %s';

      button_DisableAllBreakpoints = 'Dis. ~a~ll invalid';

      { Breakpoints window }
      dialog_breakpointlist = 'Breakpoint list';
      label_breakpointpropheader = ' Type      | State   | Position          | Path                        | Ignore | Conditions ';

      dialog_modifynewbreakpoint = 'Modify/New Breakpoint';
      label_breakpoint_name = '~N~ame';
      label_breakpoint_line = '~L~ine';
      label_breakpoint_conditions = '~C~onditions';
      label_breakpoint_ignorecount = '~I~gnore count';
      label_breakpoint_type = '~T~ype';

      { Watches window }
      dialog_watches = 'Watches';
      label_watch_expressiontowatch = '~E~xpression to watch';
      label_watch_values = 'Watch values';
      msg_watch_currentvalue = 'Current value: '+#13+
                               '%s';
      msg_watch_currentandpreviousvalue = 'Current value: '+#13+
                                          '%s'+#13+
                                          'Previous value: '+#13+
                                          '%s';

      dialog_callstack = 'Call Stack';

      menu_msglocal_saveas = 'Save ~a~s';

      msg_cantdebugchangetargetto = #3'Sorry, can not debug'#13+
                                    #3'programs compiled for %s.'#13+
                                    #3'Change target to %s?';
      msg_compiledwithoutdebuginforecompile =
                                 #3'Warning, the program'#13+
                                 #3'was compiled without'#13+
                                 #3'debugging info.'#13+
                                 #3'Recompile it?';
      msg_nothingtodebug = 'Oooops, nothing to debug.';
      msg_startingdebugger = 'Starting debugger';

{$ifdef I386}
const
  FrameName = '$ebp';
{$define FrameNameKnown}
{$endif i386}
{$ifdef x86_64}
const
  FrameName = '$rbp';
{$define FrameNameKnown}
{$endif x86_64}
{$ifdef m68k}
const
  FrameName = '$fp';
{$define FrameNameKnown}
{$endif m68k}
{$ifdef powerpc}
  { stack and frame registers are the same on powerpc,
    so I am not sure that this will work PM }
const
  FrameName = '$r1';
{$define FrameNameKnown}
{$endif powerpc}

{$ifndef Unix}
const
  { gdb escapes a space in a name with it }
  GdbEscape = '\';
{$endif Unix}

function  GDBFileName(st : string) : string;
{$ifndef Unix}
var i : longint;
{$endif Unix}
begin
{$ifdef NODEBUG}
  GDBFileName:=st;
{$else NODEBUG}
{$ifdef Unix}
  GDBFileName:=st;
{$else}
{ gdb reads '/' as the separator }
  for i:=1 to Length(st) do
    if st[i]=PathSep then
{$ifdef Windows}
  { Don't touch the escape of a space in windows file names PM }
     if (i=length(st)) or (st[i+1]<>' ') then
{$endif Windows}
      st[i]:='/';
{$ifdef Windows}
  {$ifndef USE_MINGW_GDB} // see mantis 11968 because of mingw build. MvdV
{ for Windows we should convert e:/ into /cygdrive/e/ PM }
  if
    {$ifdef GDBMI}
     using_cygwin_gdb and
    {$endif}
     (Length(PathDrive(st))=2) and (PathRootLen(st)=3) then
    st:=PathJoin(CygDrivePrefix,st[1]+copy(st,3,length(st)),UnixPathRules);
  {$endif}
{ support spaces in the name by escaping them, but not those that are escaped already }
  for i:=Length(st) downto 1 do
    if (st[i]=' ') and ((i=1) or (st[i-1]<>GdbEscape)) then
      st:=copy(st,1,i-1)+GdbEscape+copy(st,i,length(st));
{$endif Windows}
{$ifdef go32v2}
{ for go32v2 we should convert //e/ back into e:/  PM }
  if (length(st)>3) and IsPathSep(st[1]) and IsPathSep(st[2]) and IsPathSep(st[4]) then
    st:=st[3]+':'+copy(st,4,length(st));
{$endif go32v2}
  GDBFileName:=LowerCaseStr(st);
{$endif}
{$endif NODEBUG}
end;

function  OSFileName(st : string) : string;
{$ifndef Unix}
var i : longint;
{$endif Unix}
begin
{$ifdef Unix}
  OSFileName:=st;
{$else}
{$ifdef Windows}
 {$ifndef NODEBUG}
{ for Windows we should convert /cygdrive/e/ into e:\ PM }
  if pos(PathAddSep(CygDrivePrefix,UnixPathRules),st)=1 then
    st:=st[Length(CygdrivePrefix)+2]+':'+copy(st,length(CygdrivePrefix)+3,length(st));
 {$endif NODEBUG}
{$endif Windows}
{ remove the escapes of spaces }
  for i:=Length(st) downto 2 do
    if (st[i]=' ') and (st[i-1]=GdbEscape) then
      st:=copy(st,1,i-2)+copy(st,i,length(st));
{$ifdef go32v2}
{ for go32v2 we should convert //e/ back into e:/  PM }
  if (length(st)>3) and IsPathSep(st[1]) and IsPathSep(st[2]) and IsPathSep(st[4]) then
    st:=st[3]+':'+copy(st,4,length(st));
{$endif go32v2}
  OSFileName:=LowerCaseStr(PathNative(st));
{$endif}
end;

{****************************************************************************
                            TDebugController
****************************************************************************}

procedure ForeignRereadWatches;

  procedure DoRead(PB : PWatch);
  begin
    PB.Get_new_value;
  end;

begin
  inc(ForeignRunCount);
  if Assigned(WatchesCollection) then
    begin
      WatchesCollection.ForEach(TNestedActionProc(@DoRead));
      WatchesCollection.Update;
    end;
  If Assigned(WatchesWindow) then
    WatchesWindow.Update;
end;

procedure UpdateDebugViews;

  begin
{$ifdef SUPPORT_REMOTE}
     if assigned(Debugger) and
        Debugger.isRemoteDebugging then
       PushStatus(msg_getting_info_on+RemoteMachine);
{$endif SUPPORT_REMOTE}
     TProgram.DeskTop.Lock;
     If assigned(StackWindow) then
       StackWindow.Update;
     If assigned(RegistersWindow) then
       RegistersWindow.Update;
{$ifndef NODEBUG}
     If assigned(Debugger) then
       Debugger.ReadWatches;
{$endif NODEBUG}
     If assigned(FPUWindow) then
       FPUWindow.Update;
     If assigned(VectorWindow) then
       VectorWindow.Update;
     TProgram.DeskTop.UnLock;
{$ifdef SUPPORT_REMOTE}
     if assigned(Debugger) and
        Debugger.isRemoteDebugging then
       PopStatus;
{$endif SUPPORT_REMOTE}
  end;

{$ifndef NODEBUG}

constructor TDebugController.Create;
begin
  inherited Create;
  CenterDebuggerRow:=IniCenterDebuggerRow;
  Disableallinvalidbreakpoints:=false;
  NoSwitch:=False;
  HasExe:=false;
  Debugger:=Self;
  switch_to_user:=true;
  GetDir(0,OrigPwd);
  SetCommand('print object off');
{$ifdef SUPPORT_REMOTE}
  isFirstRemote:=true;
{$ifdef FPC_ARMEL32}
  { GDB needs advice on exact file type }
  SetCommand('gnutarget elf32-littlearm');
{$endif FPC_ARMEL32}
{$endif SUPPORT_REMOTE}
end;

procedure TDebugController.SetExe(const exefn:string);
  var f : string;
begin
  f := GDBFileName(GetShortName(exefn));
  if (f<>'') and ExistsFile(exefn) then
    begin
      if not LoadFile(f) then
        begin
          HasExe:=false;
          if GetError<>'' then
            f:=GetError;
          MessageBox(#3'Failed to load file '#13#3+f,mfOKbutton);
          exit;
        end;
      HasExe:=true;
      { Procedure HandleErrorAddrFrame
         (Errno : longint;addr,frame : longint);
         [public,alias:'FPC_BREAK_ERROR'];}
      FPCBreakErrorNumber:=BreakpointInsert('FPC_BREAK_ERROR', []);
{$ifdef FrameNameKnown}
      { this fails in GDB 5.1 because
        GDB replies that there is an attempt to dereference
        a generic pointer...
        test delayed in DoSourceLine... PM
      Command('cond '+IntToStr(FPCBreakErrorNumber)+
        ' (('+FrameName+' + 8)^ <> 0) or'+
        ' (('+FrameName+' + 12)^ <> 0)');  }
{$endif FrameNameKnown}
      SetArgs(GetRunParameters);
      SetSourceDirs;
      InsertBreakpoints;
      ReadWatches;
    end
  else
    begin
      HasExe:=false;
      reset_command:=true;
{$ifdef GDBMI}
      Command('-file-exec-and-symbols');
{$else GDBMI}
      Command('file');
{$endif GDBMI}
      reset_command:=false;
    end;
end;


procedure TDebugController.SetSourceDirs;
  const
{$ifdef GDBMI}
    AddSourceDirCommand = '-environment-directory';
{$else GDBMI}
    AddSourceDirCommand = 'dir';
{$endif GDBMI}
  var f,s: ansistring;
      i : longint;
      Dir : SearchRec;
begin
  f:=GetSourceDirectories+';'+OrigPwd;
  repeat
    i:=pos(';',f);
    if i=0 then
        s:=f
    else
      begin
        s:=copy(f,1,i-1);
        system.delete(f,1,i);
      end;
    DefaultReplacements(s);
    if (pos('*',s)=0) and ExistsDir(s) then
      Command(AddSourceDirCommand+' '+GDBFileName(GetShortName(s)))
    { we should also handle the /* cases of -Fu option }
    else if pos('*',s)>0 then
      begin
        Dos.FindFirst(s,Directory,Dir);
        { the '*' can only be in the last dir level }
        s:=DirOf(s);
        while Dos.DosError=0 do
          begin
            if ((Dir.attr and Directory) <> 0) and ExistsDir(s+Dir.Name) then
              Command(AddSourceDirCommand+' '+GDBFileName(GetShortName(s+Dir.Name)));
            Dos.FindNext(Dir);
          end;
        Dos.FindClose(Dir);
      end;
  until i=0;
end;

procedure TDebugController.InsertBreakpoints;
  procedure DoInsert(PB : PBreakpoint);
  begin
    PB.Insert;
  end;

begin
  BreakpointsCollection.ForEach(TNestedActionProc(@DoInsert));
  Disableallinvalidbreakpoints:=false;
end;

procedure TDebugController.ReadWatches;

  procedure DoRead(PB : PWatch);
  begin
    PB.Get_new_value;
  end;

begin
  WatchesCollection.ForEach(TNestedActionProc(@DoRead));
  If Assigned(WatchesWindow) then
    WatchesWindow.Update;
end;

procedure TDebugController.RereadWatches;

  procedure DoRead(PB : PWatch);
  begin
    PB.Force_new_value;
  end;

begin
  WatchesCollection.ForEach(TNestedActionProc(@DoRead));
  If Assigned(WatchesWindow) then
    WatchesWindow.Update;
end;


procedure TDebugController.RemoveBreakpoints;
  procedure DoDelete(PB : PBreakpoint);
    begin
      PB.Remove;
    end;
begin
   BreakpointsCollection.ForEach(TNestedActionProc(@DoDelete));
end;

procedure TDebugController.ResetBreakpointsValues;
  procedure DoResetVal(PB : PBreakpoint);
    begin
      PB.ResetValues;
    end;
begin
   BreakpointsCollection.ForEach(TNestedActionProc(@DoResetVal));
end;

destructor TDebugController.Destroy;
begin
  { kill the program if running }
  Reset;
  RemoveBreakpoints;
  inherited Destroy;
end;


procedure TDebugController.Run;
const
{$ifdef GDBMI}
  SetTTYCommand = '-inferior-tty-set';
{$else GDBMI}
  SetTTYCommand = 'tty';
{$endif GDBMI}
{$ifdef Unix}
var
  Debuggeefile : text;
  ResetOK, TTYUsed  : boolean;
  PtyName : string;
{$endif Unix}
{$ifdef PALMOSGDB}
const
  TargetProtocol = 'palmos';
{$else}
const
  TargetProtocol = 'extended-remote';
{$endif PALMOSGDB}

{$ifdef SUPPORT_REMOTE}
var
  S,ErrorStr : string;
  ErrorVal : longint;
{$endif SUPPORT_REMOTE}
begin
  ResetBreakpointsValues;
{$ifdef SUPPORT_REMOTE}
  NoSwitch:=true;
  isRemoteDebugging:=false;
  if TargetProtocol<>'extended-remote' then
    isConnectedToRemote:=false;
  usessh:=true;
{$ifndef CROSSGDB}
  If (RemoteMachine<>'') and (RemotePort<>'') then
{$else CROSSGDB}
  if true then
{$endif CROSSGDB}
    begin
      isRemoteDebugging:=true;
      if UseSsh and not isConnectedToRemote then
        begin
          s:=TransformRemoteString(RemoteSshExecCommand);
          PushStatus(S);
{$ifdef Unix}
          ErrorVal:=0;
          { return without waiting for the function to end }
          s:= s+' &';
          If fpsystem(s)=-1 Then
           ErrorVal:=fpgeterrno;
{$else}
          IDEApp.DoExecute(GetEnv('COMSPEC'),'/C '+s,'','ssh__.out','ssh___.err',exNormal);
          ErrorVal:=DosError;
{$endif}
          PopStatus;
          // if errorval <> 0 then
          // AdvMessageBoxRect(var R: TRect; const Msg: String; Params: Pointer; AOptions: longint): Word;
          AddToolMessage('',#3'Start'#13#3+s+#13#3'returned '+
            IntToStr(Errorval),0,0);

        end
      else if not UseSsh then
        begin
          s:=TransformRemoteString(RemoteExecCommand);
          MessageBox(#3'Start in remote'#13#3+s,mfOKbutton);
        end;
      if usessh then
        { we use ssh port redirection }
        S:='localhost'
        //S:=TransformRemoteString('$REMOTEMACHINE')
      else
        S:=RemoteMachine;
      If pos('@',S)>0 then
        S:=copy(S,pos('@',S)+1,High(S));
      If RemotePort<>'' then
        S:=S+':'+RemotePort;
{$ifdef PALMOSGDB}
      { set the default value for PalmOS }
      If S='' then
        S:='localhost:2000';
{$endif PALMOSGDB}
      PushStatus(msg_connectingto+S);
      AddToolMessage('',msg_connectingto+S,0,0);
      UpdateToolMessages;
      if not isConnectedToRemote then
        Command('target '+TargetProtocol+' '+S);
      if Error then
        begin
           ErrorStr:=strpas(GetError);
           ErrorBox(#3'Error in "target '+TargetProtocol+'"'#13#3+ErrorStr,nil);
           PopStatus;
           exit;
        end
      else
        isConnectedToRemote:=true;
      PopStatus;
    end
  else
    begin
{$endif SUPPORT_REMOTE}
{$ifdef Windows}
  { Run the debugge in another console }
  if DebuggeeTTY<>'' then
    SetCommand('new-console on')
  else
    SetCommand('new-console off');
  NoSwitch:=DebuggeeTTY<>'';
{$endif Windows}
{$ifdef Unix}
  { Run the debuggee in another tty }
  if DebuggeeTTY <> '' then
    begin
{$I-}
      Assign(Debuggeefile,DebuggeeTTY);
      system.Reset(Debuggeefile);
      ResetOK:=IOResult=0;
      If ResetOK and (IsATTY(textrec(Debuggeefile).handle)<>-1) then
        begin
          Command(SetTTYCommand+' '+DebuggeeTTY);
          TTYUsed:=true;
        end
      else
        begin
          Command(SetTTYCommand+' ');
          TTYUsed:=false;
        end;
      if ResetOK then
        close(Debuggeefile);
      if TTYUsed and (DebuggeeTTY<>TTYName(stdout)) then
        NoSwitch:= true
      else
        NoSwitch:=false;
    end
  else
    begin
      { the debuggee gets a terminal of its own (gdb cannot take over the one of the IDE); the IDE relays it }
      PtyName:=PtyOpen;
      if PtyName<>'' then
        Command(SetTTYCommand+' '+PtyName)
      else if TTYName(input)<>'' then
        Command(SetTTYCommand+' '+TTYName(input));
      NoSwitch := false;
    end;
{$endif Unix}
{$ifdef SUPPORT_REMOTE}
    end;
{$endif SUPPORT_REMOTE}
  { Switch to user screen to get correct handles }
  UserScreen;
{$ifdef SUPPORT_REMOTE}
  if isRemoteDebugging then
    begin
      inc(init_count);
      { pass the stop in start code }
      if isFirstRemote then
        Command('continue')
      else
        Command ('start');
      isFirstRemote:=false;
    end
  else
{$endif SUPPORT_REMOTE}
    begin
      { Set cwd for debuggee }
      SetDir(GetRunDir);
      { the breakpoints of the list (changed while nothing ran) go to gdb now }
      RemoveBreakpoints;
      InsertBreakpoints;
      inherited Run;
      { Restore cwd for IDE }
      SetDir(StartupDir);
    end;
  DebuggerScreen;
  TView.SetCmdState([cmResetDebugger,cmUntilReturn],true);
  IDEApp.UpdateRunMenu(true);
  UpdateDebugViews;
end;


function TDebugController.IsRunning : boolean;
begin
  IsRunning:=debuggee_started;
end;

procedure TDebugController.Continue;
begin
{$ifdef NODEBUG}
  NoDebugger;
{$else}
  if not debuggee_started then
    Run
  else
    inherited Continue;
  UpdateDebugViews;
{$endif NODEBUG}
end;

procedure TDebugController.UntilReturn;
begin
  inherited UntilReturn;
  UpdateDebugViews;
  { We could try to get the return value !
    Not done yet }
end;


procedure TDebugController.CommandBegin(const s:string);
begin
  if assigned(GDBWindow) and (in_command>1) then
    begin
      { We should do something special for errors !! }
      If StrLen(GetError)>0 then
        GDBWindow.WriteErrorText(GetError);
      GDBWindow.WriteOutputText(GetOutput);
    end;
  if assigned(GDBWindow) then
    GDBWindow.WriteString(S);
end;

function TDebugController.Query(question : pchar; args : pchar) : longint;
var
  c : char;
  WasModal : boolean;
  ModalView : PView;
  res : longint;
begin
  if not assigned(TProgram.Application) then
    begin
      system.Write(question);
      repeat
        system.write('(y or n)');
        system.read(c);
        system.writeln(c);
      until (lowercase(c)='y') or (lowercase(c)='n');
      if lowercase(c)='y' then
        query:=1
      else
        query:=0;
      exit;
    end;
  if assigned(TProgram.Application.Current) and
     ((TProgram.Application.Current.State and sfModal)<>0) then
    begin
      WasModal:=true;
      ModalView:=TProgram.Application.Current;
      ModalView.SetState(sfModal, false);
      ModalView.Hide;
    end
  else
    WasModal:=false;
  PushStatus(Question);
  res:=MessageBox(Question,mfyesbutton+mfnobutton);
  PopStatus;
  if res=cmYes then
    Query:=1
  else
    Query:=0;
  if WasModal then
    begin
      ModalView.Show;
      ModalView.SetState(sfModal, true);
      ModalView.Draw;
    end;
end;

procedure TDebugController.FlushAll;
begin
  if assigned(GDBWindow) then
    begin
      If StrLen(GetError)>0 then
        begin
          GDBWindow.WriteErrorText(GetError);
          if in_command=0 then
            gdberrorbuf.reset;
        end;

{$ifdef GDB_RAW_OUTPUT}
      If StrLen(GetRaw)>0 then
        begin
          GDBWindow.WriteOutputText(GetRaw);
          if in_command=0 then
            gdbrawbuf.reset;
        end;
{$endif GDB_RAW_OUTPUT}
      If StrLen(GetOutput)>0 then
        begin
          GDBWindow.WriteOutputText(GetOutput);
          { Keep output for command results }
          if in_command=0 then
            gdboutputbuf.reset;
        end;
    end
  else
    Inherited FlushAll;
end;


procedure TDebugController.CommandEnd(const s:string);
begin
  if assigned(GDBWindow) and (in_command<=1) then
    begin
      { We should do something special for errors !! }
      If StrLen(GetError)>0 then
        GDBWindow.WriteErrorText(GetError);
{$ifdef GDB_RAW_OUTPUT}
      If StrLen(GetRaw)>0 then
        GDBWindow.WriteOutputText(GetRaw);
{$endif GDB_RAW_OUTPUT}
      GDBWindow.WriteOutputText(GetOutput);
      GDBWindow.Editor.TextEnd;
    end;
end;

function  TDebugController.AllowQuit : boolean;
begin
  if IsRunning then
    begin
      if ConfirmBox('Really quit GDB window'#13+
         'and kill running program?',nil,true)=cmYes then
        begin
           Reset;
           DoneGDBWindow;
           {AllowQuit:=true;}
           AllowQuit:=false;
        end
      else
        AllowQuit:=false;
    end
  else if ConfirmBox('Really quit GDB window?',nil,true)=cmYes then
    begin
      DoneGDBWindow;
      {AllowQuit:=true;}
      AllowQuit:=false;
    end
  else
    AllowQuit:=false;
end;

procedure TDebugController.ResetDebuggerRows;
  procedure ResetDebuggerRow(P: PView);
  begin
    if assigned(P) and
       ((P is TSourceWindow)) then
       PSourceWindow(P).Editor.SetLineFlagExclusive(lfDebuggerRow,-1);
  end;

begin
  TProgram.DeskTop.ForEach(@ResetDebuggerRow);
end;

procedure TDebugController.Reset;
var
  old_reset : boolean;
begin
{$ifdef SUPPORT_REMOTE}
  if isConnectedToRemote then
    begin
      Command('monitor exit');
      Command('disconnect');
      isConnectedToRemote:=false;
      isFirstRemote:=true;
    end;
{$endif SUPPORT_REMOTE}
  inherited Reset;
  { we need to free the executable
    if we want to recompile it }
  old_reset:=reset_command;
  reset_command:=true;
  SetExe('');
  reset_command:=old_reset;
  NoSwitch:=false;
  { In case we have something that the compiler touched }
  If IDEApp.IsRunning then
    begin
      TView.SetCmdState([cmResetDebugger,cmUntilReturn],false);
      IDEApp.UpdateRunMenu(false);
      AskToReloadAllModifiedFiles;
      ResetDebuggerRows;
    end;
end;

procedure TDebugController.AnnotateError;
var errornb : longint;
begin
  if error then
    begin
       errornb:=error_num;
       UpdateDebugViews;
       ErrorBox(#3'Error within GDB'#13#3'Error code = %d',@errornb);
    end;
end;

function TDebugController.GetValue(Const expr : string) : pchar;
begin
  GetValue:=StrNew(PChar(PrintCommand(expr)));
end;

function TDebugController.GetFramePointer : CORE_ADDR;
var
  st : string;
  p : longint;
begin
{$ifdef FrameNameKnown}
  st:=PrintFormattedCommand(FrameName,pfdecimal);
  p:=pos('=',st);
  while (p<length(st)) and (st[p+1] in [' ',#9]) do
    inc(p);
  Delete(st,1,p);
  p:=1;
  while (st[p] in ['0'..'9']) do
    inc(p);
  Delete(st,p,High(st));
  GetFramePointer:=StrToCard(st);
{$else not FrameNameKnown}
  GetFramePointer:=0;
{$endif not FrameNameKnown}
end;

function TDebugController.GetLongintAt(addr : CORE_ADDR) : longint;
var
  st : string;
  p : longint;
begin
  Command('x /wd 0x'+hexstr(longint(addr),sizeof(CORE_ADDR)*2));
  st:=strpas(GetOutput);
  p:=pos(':',st);
  while (p<length(st)) and (st[p+1] in [' ',#9]) do
    inc(p);
  Delete(st,1,p);
  p:=1;
  while (st[p] in ['0'..'9']) do
    inc(p);
  Delete(st,p,High(st));
  GetLongintAt:=StrToInt(st);
end;

function TDebugController.GetPointerAt(addr : CORE_ADDR) : CORE_ADDR;
var
  st : string;
  p : longint;
  code : integer;
begin
  Command('x /wx 0x'+hexstr(PtrInt(addr),sizeof(CORE_ADDR)*2));
  st:=strpas(GetOutput);
  p:=pos(':',st);
  while (p<length(st)) and (st[p+1] in [' ',#9]) do
    inc(p);
  if (p<length(st)) and (st[p+1]='$') then
    inc(p);
  Delete(st,1,p);
  p:=1;
  while (st[p] in ['0'..'9','A'..'F','a'..'f']) do
    inc(p);
  Delete(st,p,High(st));
  Val('$'+st,GetPointerAt,code);
end;

function TDebugController.GetFPCBreakErrorParameters(var ExitCode: LongInt; var ExitAddr, ExitFrame: CORE_ADDR): Boolean;
const
  { try to find the parameters }
  FirstArgOffset = -sizeof(CORE_ADDR);
  SecondArgOffset = 2*-sizeof(CORE_ADDR);
  ThirdArgOffset = 3*-sizeof(CORE_ADDR);
begin
  // Procedure HandleErrorAddrFrame (Errno : longint;addr : CodePointer; frame : Pointer);
  //  [public,alias:'FPC_BREAK_ERROR']; {$ifdef cpui386} register; {$endif}
{$if defined(i386)}
  GetFPCBreakErrorParameters :=
    GetIntRegister('eax', ExitCode) and
    GetIntRegister('edx', ExitAddr) and
    GetIntRegister('ecx', ExitFrame);
{$elseif defined(x86_64)}
  {$ifdef Win64}
    GetFPCBreakErrorParameters :=
      GetIntRegister('rcx', ExitCode) and
      GetIntRegister('rdx', ExitAddr) and
      GetIntRegister('r8', ExitFrame);
  {$else Win64}
    GetFPCBreakErrorParameters :=
      GetIntRegister('rdi', ExitCode) and
      GetIntRegister('rsi', ExitAddr) and
      GetIntRegister('rdx', ExitFrame);
 {$endif Win64}
{$elseif defined(FrameNameKnown)}
  ExitCode:=GetLongintAt(GetFramePointer+FirstArgOffset);
  ExitAddr:=GetPointerAt(GetFramePointer+SecondArgOffset);
  ExitFrame:=GetPointerAt(GetFramePointer+ThirdArgOffset);
  GetFPCBreakErrorParameters := True;
{$else}
  ExitCode := 0;
  ExitAddr := 0;
  ExitFrame := 0;
  GetFPCBreakErrorParameters := False;
{$endif}
end;

function TDebugController.DoSelectSourceLine(const fn:string;line,BreakIndex:longint): Boolean;
var
  W: PSourceWindow;
  Found : boolean;
  PB : PBreakpoint;
  S : String;
  stop_addr : CORE_ADDR;
  i,ExitCode : longint;
  ExitAddr,ExitFrame : CORE_ADDR;
begin
  TProgram.DeskTop.Lock;
  { 0 based line count in Editor }
  if Line>0 then
    dec(Line);

  S:=fn;
  stop_addr:=current_pc;

  if (BreakIndex=FPCBreakErrorNumber) then
    begin
      if GetFPCBreakErrorParameters(ExitCode, ExitAddr, ExitFrame) then
      begin
        Backtrace;
        for i:=0 to frame_count-1 do
          begin
            with frames[i] do
              begin
                if ExitAddr=address then
                  begin
                    if SelectFrameCommand(i) and
                       assigned(file_name) then
                      begin
                        s:=strpas(file_name);
                        line:=line_number;
                        stop_addr:=address;
                      end;
                    break;
                  end;
              end;
          end;
      end
      else
      begin
        TProgram.DeskTop.Unlock;
        DoSelectSourceLine := False;
        exit;
      end;
    end;
  { Update Disassembly position }
  if Assigned(DisassemblyWindow) then
    DisassemblyWindow.SetCurAddress(stop_addr);

  if (fn=LastFileName) then
    begin
      W:=PSourceWindow(LastSource);
      if assigned(W) then
        begin
          W.Editor.SetCurPtr(0,Line);
          W.Editor.TrackCursor(CenterDebuggerRow);
          W.Editor.SetLineFlagExclusive(lfDebuggerRow,Line);
          UpdateDebugViews;

          {if Not assigned(GDBWindow) or not GDBWindow.GetState(sfActive) then
            handled by SelectInDebugSession}
          W.SelectInDebugSession;
          InvalidSourceLine:=false;
        end
      else
        InvalidSourceLine:=true;
    end
  else
    begin
      if s='' then
        W:=nil
      else
        W:=TryToOpenFile(nil,s,0,Line,false);
      if assigned(W) then
        begin
          W.Editor.SetLineFlagExclusive(lfDebuggerRow,Line);
          W.Editor.TrackCursor(CenterDebuggerRow);
          UpdateDebugViews;
          {if Not assigned(GDBWindow) or not GDBWindow.GetState(sfActive) then
            handled by SelectInDebugSession}
          W.SelectInDebugSession;
          LastSource:=W;
          InvalidSourceLine:=false;
        end
        { only search a file once }
      else
       begin
         TProgram.DeskTop.UnLock;
         if s='' then
           Found:=false
         else
         { it is easier to handle with a * at the end }
           Found:=IDEApp.OpenSearch(s+'*');
         TProgram.DeskTop.Lock;
         if not Found then
           begin
             InvalidSourceLine:=true;
             LastSource:=Nil;
             { Show the stack in that case }
             InitStackWindow;
             UpdateDebugViews;
             StackWindow.MakeFirst;
           end
         else
           begin
             { should now be open }
              W:=TryToOpenFile(nil,s,0,Line,true);
              W.Editor.SetLineFlagExclusive(lfDebuggerRow,Line);
              W.Editor.TrackCursor(CenterDebuggerRow);
              UpdateDebugViews;
              {if Not assigned(GDBWindow) or not GDBWindow.GetState(sfActive) then
                handled by SelectInDebugSession}
              W.SelectInDebugSession;
              LastSource:=W;
              InvalidSourceLine:=false;
           end;
       end;
    end;
  LastFileName:=s;
  TProgram.DeskTop.UnLock;
  if BreakIndex>0 then
    begin
      PB:=BreakpointsCollection.GetGDB(BreakIndex);
      if (BreakIndex=FPCBreakErrorNumber) then
       begin
          if (ExitCode<>0) or (ExitAddr<>0) then
            WarningBox(#3'Run Time Error '+IntToStr(ExitCode)+#13+
                     #3'Error address $'+HexStr(ExitAddr,8),nil)
          else
            WarningBox(#3'Run Time Error',nil);
       end
      else if not assigned(PB) then
        begin
          if (BreakIndex<>start_break_number) and
             (BreakIndex<>TbreakNumber) then
            WarningBox(#3'Stopped by breakpoint '+IntToStr(BreakIndex),nil);
          if BreakIndex=start_break_number then
            start_break_number:=0;
          if BreakIndex=TbreakNumber then
            TbreakNumber:=0;
        end
      { For watch we should get old and new value !! }
      else if (Not assigned(GDBWindow) or not GDBWindow.GetState(sfActive)) and
         (PB.typ<>bt_file_line) and (PB.typ<>bt_function) and
         (PB.typ<>bt_address) then
        begin
           S:=PrintCommand(GetStr(PB.Name));
           got_error:=false;
           if Assigned(PB.OldValue) then
             DisposeStr(PB.OldValue);
           PB.OldValue:=PB.CurrentValue;
           PB.CurrentValue:=NewStr(S);
           If PB.typ=bt_function then
             WarningBox(#3'GDB stopped due to'#13+
               #3+BreakpointTypeStr[PB.typ]+' '+GetStr(PB.Name),nil)
           else if (GetStr(PB.OldValue)<>S) then
             WarningBox(#3'GDB stopped due to'#13+
               #3+BreakpointTypeStr[PB.typ]+' '+GetStr(PB.Name)+#13+
               #3+'Old value = '+GetStr(PB.OldValue)+#13+
               #3+'New value = '+GetStr(PB.CurrentValue),nil)
           else
             WarningBox(#3'GDB stopped due to'#13+
               #3+BreakpointTypeStr[PB.typ]+' '+GetStr(PB.Name)+#13+
               #3+' value = '+GetStr(PB.CurrentValue),nil);
        end;
    end;
  DoSelectSourceLine := True;
end;

procedure TDebugController.DoUserSignal;
var P :Array[1..2] of pstring;
    S1, S2 : string;
begin
  S1:=strpas(signal_name);
  S2:=strpas(signal_string);
  P[1]:=@S1;
  P[2]:=@S2;
  WarningBox(msg_programsignal,@P);
end;

procedure TDebugController.DoEndSession(code:longint);
var P :Array[1..2] of longint;
begin
   TView.SetCmdState([cmUntilReturn,cmResetDebugger],false);
   IDEApp.UpdateRunMenu(false);
   ResetDebuggerRows;
   LastExitCode:=Code;
   If HiddenStepsCount=0 then
     InformationBox(msg_programexitedwithexitcode,@code)
   else
     begin
        P[1]:=code;
        P[2]:=HiddenStepsCount;
        WarningBox(msg_programexitedwithcodeandsteps,@P);
     end;
  { In case we have something that the compiler touched }
  AskToReloadAllModifiedFiles;
{$ifdef Windows}
  main_pid_valid:=false;
{$endif Windows}
end;


procedure TDebugController.DoDebuggerScreen;
{$ifdef Windows}
  var
   IdeMode : DWord;
{$endif Windows}
begin
  if NoSwitch then
    begin
      PopStatus;
    end
  else
    begin
      IDEApp.ShowIDEScreen;
      Message(TProgram.Application,evBroadcast,cmDebuggerStopped,pointer(ptrint(RunCount)));
      PopStatus;
    end;
{$ifdef Windows}
   if NoSwitch then
     begin
       { Ctrl-C as normal char }
       GetConsoleMode(GetStdHandle(cardinal(Std_Input_Handle)), @IdeMode);
       IdeMode:=(IdeMode or ENABLE_MOUSE_INPUT or ENABLE_WINDOW_INPUT) and not ENABLE_PROCESSED_INPUT;
       SetConsoleMode(GetStdHandle(cardinal(Std_Input_Handle)), IdeMode);
     end;
   ChangeDebuggeeWindowTitleTo(Stopped_State);
{$endif Windows}
  If assigned(GDBWindow) then
    GDBWindow.Editor.UnLock;
end;


procedure TDebugController.DoUserScreen;

{$ifdef Windows}
  var
   IdeMode : DWord;
{$endif Windows}
begin
  Inc(RunCount);
  if NoSwitch then
    begin
{$ifdef SUPPORT_REMOTE}
      if isRemoteDebugging then
        PushStatus(msg_runningremotely+RemoteMachine)
      else
{$endif SUPPORT_REMOTE}
{$ifdef Unix}
      PushStatus(msg_runninginanotherwindow+DebuggeeTTY);
{$else not Unix}
      PushStatus(msg_runninginanotherwindow);
{$endif Unix}
    end
  else
    begin
      PushStatus(msg_runningprogram);
      IDEApp.ShowUserScreen;
    end;
{$ifdef Windows}
   if NoSwitch then
     begin
       { Ctrl-C as interrupt }
       GetConsoleMode(GetStdHandle(cardinal(Std_Input_Handle)), @IdeMode);
       IdeMode:=(IdeMode or ENABLE_MOUSE_INPUT or ENABLE_PROCESSED_INPUT or ENABLE_WINDOW_INPUT);
       SetConsoleMode(GetStdHandle(cardinal(Std_Input_Handle)), IdeMode);
     end;
   ChangeDebuggeeWindowTitleTo(Running_State);
{$endif Windows}
  { Don't try to print GDB messages while in User Screen mode }
  If assigned(GDBWindow) then
    GDBWindow.Editor.Lock;
end;

{$endif NODEBUG}


{****************************************************************************
                                 TBreakpoint
****************************************************************************}

function  ActiveBreakpoints : boolean;
  var
    IsActive : boolean;

  procedure TestActive(PB : PBreakpoint);
    begin
        If PB.state=bs_enabled then
          IsActive:=true;
    end;
begin
   IsActive:=false;
   If assigned(BreakpointsCollection) then
     BreakpointsCollection.ForEach(TNestedActionProc(@TestActive));
   ActiveBreakpoints:=IsActive;
end;


constructor TBreakpoint.Init_function(Const AFunc : String);
begin
  typ:=bt_function;
  state:=bs_enabled;
  GDBState:=bs_deleted;
  Name:=NewStr(AFunc);
  FileName:=nil;
  Line:=0;
  IgnoreCount:=0;
  Commands:=nil;
  Conditions:=nil;
  OldValue:=nil;
  CurrentValue:=nil;
end;

constructor TBreakpoint.Init_Address(Const AAddress : String);
begin
  typ:=bt_address;
  state:=bs_enabled;
  GDBState:=bs_deleted;
  Name:=NewStr(AAddress);
  FileName:=nil;
  Line:=0;
  IgnoreCount:=0;
  Commands:=nil;
  Conditions:=nil;
  OldValue:=nil;
  CurrentValue:=nil;
end;

constructor TBreakpoint.Init_Empty;
begin
  typ:=bt_function;
  state:=bs_enabled;
  GDBState:=bs_deleted;
  Name:=Nil;
  FileName:=nil;
  Line:=0;
  IgnoreCount:=0;
  Commands:=nil;
  Conditions:=nil;
  OldValue:=nil;
  CurrentValue:=nil;
end;

constructor TBreakpoint.Init_type(atyp : BreakpointType;Const AnExpr : String);
begin
  typ:=atyp;
  state:=bs_enabled;
  GDBState:=bs_deleted;
  Name:=NewStr(AnExpr);
  IgnoreCount:=0;
  Commands:=nil;
  Conditions:=nil;
  OldValue:=nil;
  CurrentValue:=nil;
end;

constructor TBreakpoint.Init_file_line(AFile : String; ALine : longint);
var
  CurDir : String;
begin
  typ:=bt_file_line;
  state:=bs_enabled;
  GDBState:=bs_deleted;
  AFile:=ExpandPath(AFile);
(*
  { d:test.pas:12 does not work !! }
  { I do not know how to solve this if
  if (Length(AFile)>1) and (AFile[2]=':') then
    AFile:=Copy(AFile,3,255);        }
{$ifdef Unix}
  CurDir:=GetCurDir;
{$else}
  CurDir:=LowerCaseStr(GetCurDir);
{$endif Unix}
  if Pos(CurDir,OSFileName(AFile))=1 then
    FileName:=NewStr(Copy(OSFileName(AFile),length(CurDir)+1,255))
  else
*)
    FileName:=NewStr(OSFileName(AFile));
  Name:=nil;
  Line:=ALine;
  IgnoreCount:=0;
  Commands:=nil;
  Conditions:=nil;
  OldValue:=nil;
  CurrentValue:=nil;
end;

constructor TBreakpoint.Load(S: TStream);
var
  FName : PString;
begin
  S.Read(typ,SizeOf(BreakpointType));
  S.Read(state,SizeOf(BreakpointState));
  GDBState:=bs_deleted;
  case typ of
    bt_file_line :
      begin
        { convert to current target }
        FName:=S.ReadStr;
        FileName:=NewStr(OSFileName(GetStr(FName)));
        If Assigned(FName) then
          DisposeStr(FName);
        S.Read(Line,SizeOf(Line));
        Name:=nil;
      end;
  else
    begin
        Name:=S.ReadStr;
        Line:=0;
        FileName:=nil;
    end;
  end;
  S.Read(IgnoreCount,SizeOf(IgnoreCount));
  Commands:=S.StrRead;
  Conditions:=S.ReadStr;
  OldValue:=nil;
  CurrentValue:=nil;
end;

procedure TBreakpoint.Store(S: TStream);
var
  St : String;
begin
  S.Write(typ,SizeOf(BreakpointType));
  S.Write(state,SizeOf(BreakpointState));
  case typ of
    bt_file_line :
      begin
        st:=OSFileName(GetStr(FileName));
        S.WriteStr(@St);
        S.Write(Line,SizeOf(Line));
      end;
  else
    begin
        S.WriteStr(Name);
    end;
  end;
  S.Write(IgnoreCount,SizeOf(IgnoreCount));
  S.StrWrite(Commands);
  S.WriteStr(Conditions);
end;

procedure TBreakpoint.Insert;
  var
    p,p2 : pchar;
    st : string;
    bkpt_no: LongInt = 0;
begin
{$ifndef NODEBUG}
  If not assigned(Debugger) then Exit;
  Remove;
  if (GDBState=bs_deleted) and (state=bs_enabled) then
    begin
      if (typ=bt_file_line) and assigned(FileName) then
        bkpt_no := Debugger.BreakpointInsert(GDBFileName(NameAndExtOf(GetStr(FileName)))+':'+IntToStr(Line), [])
      else if (typ=bt_function) and assigned(name) then
        bkpt_no := Debugger.BreakpointInsert(name^, [])
      else if (typ=bt_address) and assigned(name) then
        bkpt_no := Debugger.BreakpointInsert('*0x'+name^, [])
      else if (typ=bt_watch) and assigned(name) then
        bkpt_no := Debugger.WatchpointInsert(name^, wtWrite)
      else if (typ=bt_awatch) and assigned(name) then
        bkpt_no := Debugger.WatchpointInsert(name^, wtReadWrite)
      else if (typ=bt_rwatch) and assigned(name) then
        bkpt_no := Debugger.WatchpointInsert(name^, wtRead);
      if bkpt_no<>0 then
        begin
          GDBIndex:=bkpt_no;
          GDBState:=bs_enabled;
          Debugger.BreakpointCondition(GDBIndex, GetStr(Conditions));
          If IgnoreCount>0 then
            Debugger.BreakpointSetIgnoreCount(GDBIndex, IgnoreCount);
          If Assigned(Commands) then
            begin
              {Commands are not handled yet }
              Debugger.Command('command '+IntToStr(GDBIndex));
              p:=commands;
              while assigned(p) do
                begin
                  p2:=strscan(p,#10);
                  if assigned(p2) then
                      p2^:=#0;
                  st:=strpas(p);
                  Debugger.command(st);
                  if assigned(p2) then
                      p2^:=#10;
                  p:=p2;
                  if assigned(p) then
                    inc(p);
                end;
              Debugger.Command('end');
            end;
        end
      else
      { Here there was a problem !! }
        begin
          GDBIndex:=0;
          if not Debugger.Disableallinvalidbreakpoints then
            begin
              if (typ=bt_file_line) and assigned(FileName) then
                begin
                  ClearFormatParams;
                  AddFormatParamStr(NameAndExtOf(FileName^));
                  AddFormatParamInt(Line);
                  if ChoiceBox(msg_couldnotsetbreakpointat,@FormatParams,[btn_ok,button_DisableAllBreakpoints],false)=cmUserBtn2 then
                    Debugger.Disableallinvalidbreakpoints:=true;
                end
              else
                begin
                  ClearFormatParams;
                  AddFormatParamStr(BreakpointTypeStr[typ]);
                  AddFormatParamStr(GetStr(Name));
                  if ChoiceBox(msg_couldnotsetbreakpointtype,@FormatParams,[btn_ok,button_DisableAllBreakpoints],false)=cmUserBtn2 then
                    Debugger.Disableallinvalidbreakpoints:=true;
                end;
            end;
          state:=bs_disabled;
          UpdateSource;
        end;
    end
  else if (GDBState=bs_disabled) and (state=bs_enabled) then
    Enable
  else if (GDBState=bs_enabled) and (state=bs_disabled) then
    Disable;
{$endif NODEBUG}
end;

procedure TBreakpoint.Remove;
begin
{$ifndef NODEBUG}
  If not assigned(Debugger) then Exit;
  if GDBIndex>0 then
    Debugger.BreakpointDelete(GDBIndex);
  GDBIndex:=0;
  GDBState:=bs_deleted;
{$endif NODEBUG}
end;

procedure TBreakpoint.Enable;
begin
{$ifndef NODEBUG}
  If not assigned(Debugger) then Exit;
  if GDBIndex>0 then
    Debugger.BreakpointEnable(GDBIndex)
  else
    Insert;
  GDBState:=bs_disabled;
{$endif NODEBUG}
end;

procedure TBreakpoint.Disable;
begin
{$ifndef NODEBUG}
  If not assigned(Debugger) then Exit;
  if GDBIndex>0 then
    Debugger.BreakpointDisable(GDBIndex);
  GDBState:=bs_disabled;
{$endif NODEBUG}
end;

procedure TBreakpoint.ResetValues;
begin
  if assigned(OldValue) then
    DisposeStr(OldValue);
  OldValue:=nil;
  if assigned(CurrentValue) then
    DisposeStr(CurrentValue);
  CurrentValue:=nil;
end;

procedure  TBreakpoint.UpdateSource;
var W: PSourceWindow;
    b : boolean;
begin
  if typ=bt_file_line then
    begin
      W:=SearchOnDesktop(OSFileName(GetStr(FileName)),false);
      If assigned(W) then
        begin
          if state=bs_enabled then
            b:=true
          else
            b:=false;
          W.Editor.SetLineFlagState(Line-1,lfBreakpoint,b);
        end;
    end;
end;

destructor TBreakpoint.Destroy;
begin
  Remove;
  ResetValues;
  if assigned(Name) then
    DisposeStr(Name);
  if assigned(FileName) then
    DisposeStr(FileName);
  if assigned(Conditions) then
    DisposeStr(Conditions);
  if assigned(Commands) then
    StrDispose(Commands);
  inherited Destroy;
end;

{****************************************************************************
                        TBreakpointCollection
****************************************************************************}

function TBreakpointCollection.At(Index: Integer): PBreakpoint;
begin
  At := PBreakpoint(inherited At(Index));
end;


procedure TBreakpointCollection.Update;
begin
{$ifndef NODEBUG}
  { gdb gets the changes at once only while the program runs; otherwise at the next Run (the exe that is loaded
    may be that of another program: its symbols know nothing of the new breakpoint) }
  if assigned(Debugger) and Debugger.IsRunning then
    begin
      Debugger.RemoveBreakpoints;
      Debugger.InsertBreakpoints;
    end;
{$endif NODEBUG}
  if assigned(BreakpointsWindow) then
    BreakpointsWindow.Update;
end;

function  TBreakpointCollection.GetGDB(index : longint) : PBreakpoint;

  function IsNum(P : PBreakpoint) : boolean;
  begin
    IsNum:=P.GDBIndex=index;
  end;

begin
  if index=0 then
    GetGDB:=nil
  else
    GetGDB:=TBreakpoint(FirstThat(TNestedTestProc(@IsNum)));
end;

procedure TBreakpointCollection.ShowBreakpoints(W : PFPWindow);

  procedure SetInSource(P : PBreakpoint);
  begin
    If assigned(P.FileName) and
      (OSFileName(P.FileName^)=OSFileName(ExpandPath(PSourceWindow(W).Editor.FileName))) then
      PSourceWindow(W).Editor.SetLineFlagState(P.Line-1,lfBreakpoint,P.state=bs_enabled);
  end;

  procedure SetInDisassembly(P : PBreakpoint);
    var
      PDL : PDisasLine;
      S : string;
      ps,qs,i : longint;
      HAddr : PtrInt;
      code : integer;
  begin
    for i:=0 to PDisassemblyWindow(W).Editor.GetLineCount-1 do
      begin
        PDL:=PDisasLine(PDisassemblyWindow(W).Editor.GetLine(i));
        if PDL.Address=0 then
          begin
            if (P.typ=bt_file_line) then
              begin
                S:=PDisassemblyWindow(W).Editor.GetDisplayText(i);
                ps:=pos(':',S);
                qs:=pos(' ',copy(S,ps+1,High(S)));
                if (GDBFileName(P.FileName^)=GDBFileName(ExpandPath(Copy(S,1,ps-1)))) and
                   (StrToInt(copy(S,ps+1,qs-1))=P.line) then
                  PDisassemblyWindow(W).Editor.SetLineFlagState(i,lfBreakpoint,P.state=bs_enabled);
              end;
          end
        else
          begin
            if assigned(P.Name) then
              begin
                Val('$'+P.Name^,HAddr,code);
                If (P.typ=bt_address) and (PDL.Address=HAddr) then
                  PDisassemblyWindow(W).Editor.SetLineFlagState(i,lfBreakpoint,P.state=bs_enabled);
              end;
          end;
      end;
  end;

begin
  if W=PFPWindow(DisassemblyWindow) then
    ForEach(TNestedActionProc(@SetInDisassembly))
  else
    ForEach(TNestedActionProc(@SetInSource));
end;


procedure TBreakpointCollection.AdaptBreakpoints(Editor : PSourceEditor; Pos, Change : longint);

  procedure AdaptInSource(P : PBreakpoint);
  begin
    If assigned(P.FileName) and
       (P.FileName^=OSFileName(ExpandPath(Editor.FileName))) then
        begin
          if P.state=bs_enabled then
            Editor.SetLineFlagState(P.Line-1,lfBreakpoint,false);
          if P.Line-1>=Pos then
            begin
              if (Change>0) or (P.Line-1>=Pos-Change) then
                P.line:=P.Line+Change
              else
                begin
                  { removing inside a ForEach call leads to problems }
                  { so we do that after PM }
                  P.state:=bs_delete_after;
                end;
            end;
          if P.state=bs_enabled then
            Editor.SetLineFlagState(P.Line-1,lfBreakpoint,true);
        end;
  end;

  var
    I : longint;
begin
  ForEach(TNestedActionProc(@AdaptInSource));
  I:=Count-1;
  While (I>=0) do
    begin
      if At(I).state=bs_delete_after then
        AtFree(I);
      Dec(I);
    end;
end;

function TBreakpointCollection.FindBreakpointAt(Editor : PSourceEditor; Line : longint) : PBreakpoint;

  function IsAtLine(P : PBreakpoint) : boolean;
  begin
    If assigned(P.FileName) and
       (P.FileName^=OSFileName(ExpandPath(Editor.FileName))) and
       (Line=P.Line) then
      IsAtLine:=true
    else
      IsAtLine:=false;
  end;

begin
  FindBreakpointAt:=TBreakpoint(FirstThat(TNestedTestProc(@IsAtLine)));
end;

procedure TBreakpointCollection.ShowAllBreakpoints;

  procedure SetInSource(P : PBreakpoint);
    var
      W : PSourceWindow;
  begin
    If assigned(P.FileName) then
      begin
        W:=SearchOnDesktop(P.FileName^,false);
        if assigned(W) then
          W.Editor.SetLineFlagState(P.Line-1,lfBreakpoint,P.state=bs_enabled);
      end;
  end;

begin
  ForEach(TNestedActionProc(@SetInSource));
end;

function TBreakpointCollection.GetType(typ : BreakpointType;Const s : String) : PBreakpoint;

  function IsThis(P : PBreakpoint) : boolean;
  begin
    IsThis:=(P.typ=typ) and (GetStr(P.Name)=S);
  end;

begin
  GetType:=TBreakpoint(FirstThat(TNestedTestProc(@IsThis)));
end;


function TBreakpointCollection.ToggleFileLine(FileName: String;LineNr : Longint) : boolean;

  function IsThere(P : PBreakpoint) : boolean;
  begin
    IsThere:=(P.typ=bt_file_line) and assigned(P.FileName) and
      (OSFileName(P.FileName^)=FileName) and (P.Line=LineNr);
  end;

var
  PB : PBreakpoint;
begin
    ToggleFileLine:=false;
    FileName:=OSFileName(ExpandPath(FileName));
    PB:=TBreakpoint(FirstThat(TNestedTestProc(@IsThere)));
    If Assigned(PB) then
      begin
        { delete it form source window }
        PB.state:=bs_disabled;
        PB.UpdateSource;
        { remove from collection }
        BreakpointsCollection.free(PB);
      end
    else
      begin
        PB:= TBreakpoint.Init_file_line(FileName,LineNr);
        if assigned(PB) then
          Begin
            Insert(PB);
            PB.UpdateSource;
            ToggleFileLine:=true;
          End;
      end;
    Update;
end;



{****************************************************************************
                         TBreakpointItem
****************************************************************************}

constructor TBreakpointItem.Create(ABreakpoint : PBreakpoint);
begin
  inherited Create;
  Breakpoint:=ABreakpoint;
end;

function TBreakpointItem.GetText(MaxLen: Sw_integer): string;
var S: string;
begin
 with Breakpoint do
   begin
     S:=BreakpointTypeStr[typ];
     While Length(S)<10 do
       S:=S+' ';
     S:=S+'|';
     S:=S+BreakpointStateStr[state]+' ';
     While Length(S)<20 do
       S:=S+' ';
     S:=S+'|';
     if (typ=bt_file_line) then
       begin
         S:=S+NameAndExtOf(GetStr(FileName))+':'+IntToStr(Line);
         While Length(S)<40 do
           S:=S+' ';
         S:=S+'|';
         S:=S+copy(DirOf(GetStr(FileName)),1,min(length(DirOf(GetStr(FileName))),29));
       end
     else
       S:=S+GetStr(name);
     While Length(S)<70 do
       S:=S+' ';
     S:=S+'|';
     if IgnoreCount>0 then
       S:=S+IntToStr(IgnoreCount);
     While Length(S)<79 do
       S:=S+' ';
     S:=S+'|';
     if assigned(Conditions) then
       S:=S+' '+GetStr(Conditions);
     if length(S)>MaxLen then S:=copy(S,1,MaxLen-2)+'..';
     GetText:=S;
   end;
end;

procedure TBreakpointItem.Selected;
begin
end;

function TBreakpointItem.GetModuleName: string;
begin
  if breakpoint.typ=bt_file_line then
    GetModuleName:=GetStr(breakpoint.FileName)
  else
    GetModuleName:='';
end;

{****************************************************************************
                         TBreakpointsListBox
****************************************************************************}

constructor TBreakpointsListBox.Create(var Bounds: TRect; AHScrollBar, AVScrollBar: PScrollBar);
begin
  inherited Create(Bounds,1,AHScrollBar, AVScrollBar);
  GrowMode:=gfGrowLoX+gfGrowHiX+gfGrowHiY;
  NoSelection:=true;
end;

function TBreakpointsListBox.GetLocalMenu: PMenu;
var M: PMenu;
begin
  if (Owner<>nil) and (Owner.GetState(sfModal)) then M:=nil else
  M:=NewMenu(
    NewItem(menu_bplocal_gotosource,'',kbNoKey,cmMsgGotoSource,hcMsgGotoSource,
    NewItem(menu_bplocal_editbreakpoint,'',kbNoKey,cmEditBreakpoint,hcEditBreakpoint,
    NewItem(menu_bplocal_newbreakpoint,'',kbNoKey,cmNewBreakpoint,hcNewBreakpoint,
    NewItem(menu_bplocal_deletebreakpoint,'',kbNoKey,cmDeleteBreakpoint,hcDeleteBreakpoint,
    NewItem(menu_bplocal_togglestate,'',kbNoKey,cmToggleBreakpoint,hcToggleBreakpoint,
    nil))))));
  GetLocalMenu:=M;
end;

procedure TBreakpointsListBox.HandleEvent(var Event: TEvent);
var DontClear: boolean;
begin
  case Event.What of
    evKeyDown :
      begin
        DontClear:=false;
        case Event.KeyDown.KeyCode of
          kbEnd :
            FocusItem(List.Count-1);
          kbHome :
            FocusItem(0);
          kbEnter :
            Message(Self,evCommand,cmMsgGotoSource,nil);
          kbIns :
            Message(Self,evCommand,cmNewBreakpoint,nil);
          kbDel :
            Message(Self,evCommand,cmDeleteBreakpoint,nil);
        else
          DontClear:=true;
        end;
        if not DontClear then
          ClearEvent(Event);
      end;
    evBroadcast :
      case Event.Message.Command of
        cmListItemSelected :
          if Event.Message.InfoPtr=Pointer(Self) then
            Message(Self,evCommand,cmEditBreakpoint,nil);
      end;
    evCommand :
      begin
        DontClear:=false;
        case Event.Message.Command of
          cmMsgTrackSource :
            if Range>0 then
              TrackSource;
          cmEditBreakpoint :
              EditCurrent;
          cmToggleBreakpoint :
              ToggleCurrent;
          cmDeleteBreakpoint :
              DeleteCurrent;
          cmNewBreakpoint :
              EditNew;
          cmMsgClear :
            Clear;
          else
            DontClear:=true;
        end;
        if not DontClear then
          ClearEvent(Event);
      end;
  end;
  inherited HandleEvent(Event);
end;

procedure TBreakpointsListBox.AddBreakpoint(P: PBreakpointItem);
var W : integer;
begin
  if List=nil then Items := TCollection.Create(20,20);
  W:=length(P.GetText(255));
  if W>MaxWidth then
  begin
    MaxWidth:=W;
    if HScrollBar<>nil then
       HScrollBar.SetRange(0,MaxWidth);
  end;
  List.Insert(P);
  SetRange(List.Count);
  if Focused=List.Count-1-1 then
     FocusItem(List.Count-1);
  P.Breakpoint.UpdateSource;
  DrawView;
end;

function TBreakpointsListBox.GetText(Item,MaxLen: Sw_Integer): String;
var P: PBreakpointItem;
    S: string;
begin
  P:=TBreakpointItem(List.At(Item));
  S:=P.GetText(MaxLen);
  GetText:=copy(S,1,MaxLen);
end;

procedure TBreakpointsListBox.Clear;
begin
  if assigned(List) then
    List.Free;
  Items:=nil;
  MaxWidth:=0;
  SetRange(0); DrawView;
  Message(TProgram.Application,evBroadcast,cmClearLineHighlights,Self);
end;

procedure TBreakpointsListBox.TrackSource;
var W: PSourceWindow;
    P: PBreakpointItem;
    R: TRect;
begin
  (*Message(Application,evBroadcast,cmClearLineHighlights,Self);
  if Range=0 then Exit;*)
  P:=TBreakpointItem(List.At(Focused));
  if P.GetModuleName='' then Exit;
  TProgram.DeskTop.Lock;
  GetNextEditorBounds(R);
  R.B.Y:=Owner.Origin.Y;
  W:=EditorWindowFile(P.GetModuleName);
  if assigned(W) then
    begin
      R := W.GetExtent;
      R.B.Y:=Owner.Origin.Y;
      W.ChangeBounds(R);
      W.Editor.SetCurPtr(1,P.Breakpoint.Line);
    end
  else
    W:=TryToOpenFile(@R,P.GetModuleName,1,P.Breakpoint.Line,true);
  if W<>nil then
    begin
      W.Select;
      W.Editor.TrackCursor(do_centre);
      W.Editor.SetLineFlagExclusive(lfHighlightRow,P.Breakpoint.Line);
    end;
  if Assigned(Owner) then
    Owner.Select;
  TProgram.DeskTop.UnLock;
end;

procedure TBreakpointsListBox.ToggleCurrent;
var
  P: PBreakpointItem;
begin
  if Range=0 then Exit;
  P:=TBreakpointItem(List.At(Focused));
  if P=nil then Exit;
  if P.Breakpoint.state=bs_enabled then
    P.Breakpoint.state:=bs_disabled
  else if P.Breakpoint.state=bs_disabled then
    P.Breakpoint.state:=bs_enabled;
  P.Breakpoint.UpdateSource;
  BreakpointsCollection.Update;
end;

procedure TBreakpointsListBox.EditCurrent;
var
  P: PBreakpointItem;
begin
  if Range=0 then Exit;
  P:=TBreakpointItem(List.At(Focused));
  if P=nil then Exit;
  TProgram.Application.ExecuteDialog(TBreakpointItemDialog.Create(P.Breakpoint),nil);
  P.Breakpoint.UpdateSource;
  BreakpointsCollection.Update;
end;

procedure TBreakpointsListBox.DeleteCurrent;
var
  P: PBreakpointItem;
begin
  if Range=0 then Exit;
  P:=TBreakpointItem(List.At(Focused));
  if P=nil then Exit;
  { delete it form source window }
  P.Breakpoint.state:=bs_disabled;
  P.Breakpoint.UpdateSource;
  BreakpointsCollection.free(P.Breakpoint);
  List.free(P);
  BreakpointsCollection.Update;
end;

procedure TBreakpointsListBox.EditNew;
var
  P: PBreakpoint;
begin
  P:=TBreakpoint.Init_Empty;
  if TProgram.Application.ExecuteDialog(TBreakpointItemDialog.Create(P),nil)<>cmCancel then
    begin
      P.UpdateSource;
      BreakpointsCollection.Insert(P);
      BreakpointsCollection.Update;
    end
  else
    P.Free;
end;

procedure TBreakpointsListBox.Draw;
var
  I, J, Item: Sw_Integer;
  NormalColor, SelectedColor, FocusedColor, Color: Word;
  ColWidth, CurCol, Indent: Integer;
  B: TFVDrawBuffer;
  Text: String;
  SCOff: Byte;
  TC: byte;
procedure MT(var C: word); begin if TC<>0 then C:=(C and $ff0f) or (TC and $f0); end;
begin
  if (Owner<>nil) then TC:=ord(Owner.GetColorW(6)) else TC:=0;
  if State and (sfSelected + sfActive) = (sfSelected + sfActive) then
  begin
    NormalColor := GetColorW(1);
    FocusedColor := GetColorW(3);
    SelectedColor := GetColorW(4);
  end else
  begin
    NormalColor := GetColorW(2);
    SelectedColor := GetColorW(4);
  end;
  if Transparent then
    begin MT(NormalColor); MT(SelectedColor); end;
  if NoSelection then
     SelectedColor:=NormalColor;
  if HScrollBar <> nil then Indent := HScrollBar.Value
  else Indent := 0;
  ColWidth := Size.X div NumCols + 1;
  for I := 0 to Size.Y - 1 do
  begin
    for J := 0 to NumCols-1 do
    begin
      Item := J*Size.Y + I + TopItem;
      CurCol := J*ColWidth;
      if (State and (sfSelected + sfActive) = (sfSelected + sfActive)) and
        (Focused = Item) and (Range > 0) then
      begin
        Color := FocusedColor;
        SetCursor(CurCol+1,I);
        SCOff := 0;
      end
      else if (Item < Range) and IsSelected(Item) then
      begin
        Color := SelectedColor;
        SCOff := 2;
      end
      else
      begin
        Color := NormalColor;
        SCOff := 4;
      end;
      MoveChar(B[CurCol], ' ', Color, ColWidth);
      if Item < Range then
      begin
        Text := GetText(Item, ColWidth + Indent);
        Text := Copy(Text,Indent,ColWidth);
        MoveStr(B[CurCol+1], Text, Color);
        if ShowMarkers then
        begin
          SetCellChar(B[CurCol], Char(SpecialChars[SCOff]));
          SetCellChar(B[CurCol+ColWidth-2], Char(SpecialChars[SCOff+1]));
        end;
      end;
      MoveFill(B[CurCol+ColWidth-1], '│', GetColorW(5), 1);
    end;
    WriteLineC(0, I, Size.X, 1, B);
  end;
end;

constructor TBreakpointsListBox.Load(S: TStream);
begin
  inherited Load(S);
end;

procedure TBreakpointsListBox.Store(S: TStream);
var OL: PCollection;
    OldR : integer;
begin
  OL:=List;
  OldR:=Range;
  Range:=0;
  Items := TCollection.Create(1,1);

  inherited Store(S);

  List.Free;
  Range:=OldR;
  Items:=OL;
  { ^^^ nasty trick - has anyone a better idea how to avoid storing the
    collection? Pasting here a modified version of TListBox.Store+
    TAdvancedListBox.Store isn't a better solution, since by eventually
    changing the obj-hierarchy you'll always have to modify this, too - BG }
end;

destructor TBreakpointsListBox.Destroy;
begin
  inherited Destroy;
  if List<>nil then List.Free;
end;

{****************************************************************************
                         TBreakpointsWindow
****************************************************************************}

constructor TBreakpointsWindow.Create;
var R,R2: TRect;
    HSB,VSB: PScrollBar;
    ST: PStaticText;
    S: String;
    X,X1 : Sw_integer;
    Btn: PButton;
const
  NumButtons = 5;
begin
  R := TProgram.DeskTop.GetExtent; R.A.Y:=R.B.Y-18;
  inherited Create(R, dialog_breakpointlist, wnNoNumber);

  HelpCtx:=hcBreakpointListWindow;

  R := GetExtent; R.Grow(-1,-1); R.B.Y:=R.A.Y+1;
  S:=label_breakpointpropheader;
  ST := TStaticText.Create(R,S);
  ST.GrowMode:=gfGrowHiX;
  Insert(ST);
  R := GetExtent; R.Grow(-1,-1); Inc(R.A.Y,1); R.B.Y:=R.A.Y+1;
  ST := TStaticText.Create(R, CharStr('─', MaxViewWidth));
  ST.GrowMode:=gfGrowHiX;
  Insert(ST);
  R := GetExtent; R.Grow(-1,-1); Inc(R.A.Y,2);Dec(R.B.Y,5);
  R2 := R; Inc(R2.B.Y); R2.A.Y:=R2.B.Y-1;
  HSB := TScrollBar.Create(R2); HSB.GrowMode:=gfGrowLoY+gfGrowHiY+gfGrowHiX; Insert(HSB);
  HSB.SetStep(R.B.X-R.A.X-2,1);
  R2 := R; Inc(R2.B.X); R2.A.X:=R2.B.X-1;
  VSB := TScrollBar.Create(R2); VSB.GrowMode:=gfGrowLoX+gfGrowHiX+gfGrowHiY; Insert(VSB);
  VSB.SetStep(R.B.Y-R.A.Y-2,1);
  BreakLB := TBreakpointsListBox.Create(R,HSB,VSB);
  BreakLB.GrowMode:=gfGrowHiX+gfGrowHiY;
  BreakLB.Transparent:=true;
  Insert(BreakLB);
  R := GetExtent;R.Grow(-1,-1);
  Dec(R.B.Y);
  R.A.Y:=R.B.Y-2;
  X:=(R.B.X-R.A.X) div NumButtons;
  X1:=R.A.X+(X div 2);
  R.A.X:=X1-3;R.B.X:=X1+7;
  Btn := TButton.Create(R, button_Close, cmClose, bfDefault);
  Btn.GrowMode:=gfGrowLoY+gfGrowHiY;
  Insert(Btn);
  X1:=X1+X;
  R.A.X:=X1-3;R.B.X:=X1+7;
  Btn := TButton.Create(R, button_New, cmNewBreakpoint, bfNormal);
  Btn.GrowMode:=gfGrowLoY+gfGrowHiY;
  Insert(Btn);
  X1:=X1+X;
  R.A.X:=X1-3;R.B.X:=X1+7;
  Btn := TButton.Create(R, button_Edit, cmEditBreakpoint, bfNormal);
  Btn.GrowMode:=gfGrowLoY+gfGrowHiY;
  Insert(Btn);
  X1:=X1+X;
  R.A.X:=X1-3;R.B.X:=X1+7;
  Btn := TButton.Create(R, button_ToggleButton, cmToggleBreakInList, bfNormal);
  Btn.GrowMode:=gfGrowLoY+gfGrowHiY;
  Insert(Btn);
  X1:=X1+X;
  R.A.X:=X1-3;R.B.X:=X1+7;
  Btn := TButton.Create(R, button_Delete, cmDeleteBreakpoint, bfNormal);
  Btn.GrowMode:=gfGrowLoY+gfGrowHiY;
  Insert(Btn);
  BreakLB.Select;
  Update;
  BreakpointsWindow:=Self;
end;

constructor TBreakpointsWindow.Load(S: TStream);
begin
  inherited Load(S);
  GetSubViewPtr(S,BreakLB);
end;

procedure TBreakpointsWindow.Store(S: TStream);
begin
  inherited Store(S);
  PutSubViewPtr(S,BreakLB);
end;

procedure TBreakpointsWindow.AddBreakpoint(ABreakpoint : PBreakpoint);
begin
  BreakLB.AddBreakpoint(TBreakpointItem.Create(ABreakpoint));
end;

procedure TBreakpointsWindow.ClearBreakpoints;
begin
  BreakLB.Clear;
  ReDraw;
end;

procedure TBreakpointsWindow.ReloadBreakpoints;
  procedure InsertInBreakLB(P : PBreakpoint);
  begin
    BreakLB.AddBreakpoint(TBreakpointItem.Create(P));
  end;
begin
  If not assigned(BreakpointsCollection) then
    exit;
  BreakpointsCollection.ForEach(TNestedActionProc(@InsertInBreakLB));
  ReDraw;
end;

procedure TBreakpointsWindow.SizeLimits(out Min, Max: TPoint);
begin
  inherited SizeLimits(Min,Max);
  Min.X:=40; Min.Y:=18;
end;

procedure TBreakpointsWindow.Close;
begin
  Hide;
end;

procedure TBreakpointsWindow.HandleEvent(var Event: TEvent);
var DontClear : boolean;
begin
  case Event.What of
    evKeyDown :
      begin
        if (Event.KeyDown.KeyCode=kbEnter) or (Event.KeyDown.KeyCode=kbEsc) then
          begin
            ClearEvent(Event);
            Hide;
          end;
      end;
    evCommand :
      begin
       DontClear:=False;
       case Event.Message.Command of
         cmNewBreakpoint :
           BreakLB.EditNew;
         cmEditBreakpoint :
           BreakLB.EditCurrent;
         cmDeleteBreakpoint :
           BreakLB.DeleteCurrent;
         cmToggleBreakInList :
           BreakLB.ToggleCurrent;
         cmClose :
           Hide;
          else
            DontClear:=true;
        end;
        if not DontClear then
          ClearEvent(Event);
      end;
    evBroadcast :
      case Event.Message.Command of
        cmUpdate :
          Update;
      end;
  end;
  inherited HandleEvent(Event);
end;

procedure TBreakpointsWindow.Update;
var
  StoreFocus : longint;
begin
  StoreFocus:=BreakLB.Focused;
  ClearBreakpoints;
  ReloadBreakpoints;
  If StoreFocus<BreakLB.Range then
    BreakLB.FocusItem(StoreFocus);
end;

destructor TBreakpointsWindow.Destroy;
begin
  inherited Destroy;
  BreakpointsWindow:=nil;
end;

{****************************************************************************
                         TBreakpointItemDialog
****************************************************************************}

constructor TBreakpointItemDialog.Create(ABreakpoint: PBreakpoint);
var R,R2,R3: TRect;
    Items: PSItem;
    I : BreakpointType;
    KeyCount: sw_integer;
begin
  KeyCount:=longint(high(BreakpointType));

  R := TRect.Create(0, 0, 60, Max(9+KeyCount,18));
  inherited Create(R,dialog_modifynewbreakpoint);
  Breakpoint:=ABreakpoint;

  R := GetExtent; R.Grow(-3,-2); R3 := R;
  Inc(R.A.Y); R.B.Y:=R.A.Y+1; R.B.X:=R.B.X-3;
  NameIL := TEditorInputLine.Create(R, 255); Insert(NameIL);
  R2 := R; R2.A.X:=R2.B.X; R2.B.X:=R2.A.X+3;
  Insert(THistory.Create(R2, NameIL, hidBreakPointDialogName));
  R := R3; Inc(R.A.Y); R.B.Y:=R.A.Y+1;
  R2 := R; R2.Move(-1,-1);
  Insert(TLabel.Create(R2, label_breakpoint_name, NameIL));
  R.Move(0,3);
  R.B.X:=R.B.X-3;
  ConditionsIL := TEditorInputLine.Create(R, 255); Insert(ConditionsIL);
  R2 := R; R2.A.X:=R2.B.X; R2.B.X:=R2.A.X+3;
  Insert(THistory.Create(R2, ConditionsIL, hidBreakPointDialogCond));
  R2 := R; R2.Move(-1,-1); Insert(TLabel.Create(R2, label_breakpoint_conditions, ConditionsIL));
  R.Move(0,3); R.B.X:=R.A.X+36;
  LineIL := TEditorInputLine.Create(R, 128); Insert(LineIL);
  LineIL.SetValidator(TRangeValidator.Create(0,MaxInt));
  R2 := R; R2.Move(-1,-1); Insert(TLabel.Create(R2, label_breakpoint_line, LineIL));
  R.Move(0,3);
  IgnoreIL := TEditorInputLine.Create(R, 128); Insert(IgnoreIL);
  IgnoreIL.SetValidator(TRangeValidator.Create(0,MaxInt));
  R2 := R; R2.Move(-1,-1); Insert(TLabel.Create(R2, label_breakpoint_ignorecount, IgnoreIL));

  R := R3; Inc(R.A.X,38); Inc(R.A.Y,7); R.B.Y:=R.A.Y+KeyCount;
  Items:=nil;
  { don't use invalid type }
  for I:=pred(high(BreakpointType)) downto low(BreakpointType) do
    Items:=NewSItem(BreakpointTypeStr[I], Items);
  TypeRB := TRadioButtons.Create(R, Items);

  R2 := R; R2.Move(-1,-1); R2.B.Y:=R2.A.Y+1;
  Insert(TLabel.Create(R2, label_breakpoint_type, TypeRB));

  Insert(TypeRB);

  InsertButtons(Self);

  NameIL.Select;
end;

function TBreakpointItemDialog.Execute: Word;
var R: sw_word;
    S1: string;
    err: word;
    L: longint;
begin
  R:=sw_word(Breakpoint.typ);
  TypeRB.SetData(R);

  If Breakpoint.typ=bt_file_line then
    S1:=GetStr(Breakpoint.FileName)
  else
    S1:=GetStr(Breakpoint.name);
  NameIL.SetData(S1);

  If Breakpoint.typ=bt_file_line then
    S1:=IntToStr(Breakpoint.Line)
  else
    S1:='0';
  LineIL.SetData(S1);

  S1:=IntToStr(Breakpoint.IgnoreCount);
  IgnoreIL.SetData(S1);
  S1:=GetStr(Breakpoint.Conditions);
  ConditionsIL.SetData(S1);

  if assigned(FirstEditorWindow) then
    FindReplaceEditor:=FirstEditorWindow.Editor;

  R:=inherited Execute;

  FindReplaceEditor:=nil;
  if R=cmOK then
  begin
    TypeRB.GetData(R);
    L:=R;
    Breakpoint.typ:=BreakpointType(L);

    NameIL.GetData(S1);
    If Breakpoint.typ=bt_file_line then
      begin
        If assigned(Breakpoint.FileName) then
          DisposeStr(Breakpoint.FileName);
        Breakpoint.FileName:=NewStr(S1);
      end
    else
      begin
        If assigned(Breakpoint.Name) then
          DisposeStr(Breakpoint.Name);
        Breakpoint.name:=NewStr(S1);
      end;
    If Breakpoint.typ=bt_file_line then
      begin
        LineIL.GetData(S1);
        Val(S1,L,err);
        Breakpoint.Line:=L;
      end;
    IgnoreIL.GetData(S1);
    Val(S1,L,err);
    Breakpoint.IgnoreCount:=L;

    ConditionsIL.GetData(S1);
    If assigned(Breakpoint.Conditions) then
      DisposeStr(Breakpoint.Conditions);
    Breakpoint.Conditions:=NewStr(S1);
  end;
  Execute:=R;
end;

{****************************************************************************
                         TWatch
****************************************************************************}

constructor TWatch.Create(s : string);
  begin
    expr:=NewStr(s);
    last_value:=nil;
    current_value:=nil;
    Get_new_value;
    GDBRunCount:=-1;
  end;

constructor TWatch.Load(S: TStream);
  begin
    expr:=S.ReadStr;
    last_value:=nil;
    current_value:=nil;
    Get_new_value;
    GDBRunCount:=-1;
  end;

procedure TWatch.Store(S: TStream);
  begin
    S.WriteStr(expr);
  end;

procedure TWatch.rename(s : string);
  begin
    if assigned(expr) then
      begin
        if GetStr(expr)=S then
          exit;
        DisposeStr(expr);
      end;
    expr:=NewStr(s);
    if assigned(last_value) then
      StrDispose(last_value);
    last_value:=nil;
    if assigned(current_value) then
      StrDispose(current_value);
    current_value:=nil;
    GDBRunCount:=-1;
    Get_new_value;
  end;

procedure TWatch.Get_new_value;
{$ifndef NODEBUG}
  var i, curframe, startframe : longint;
      s,s2,orig_s_result : AnsiString;
      loop_higher, found : boolean;
      fv : ShortString;

    function GetValue(var s : AnsiString) : boolean;
      begin
        s:=Debugger.PrintCommand(s);
        GetValue := not Debugger.Error;
        { do not open a messagebox for such errors }
        Debugger.got_error:=false;
      end;

  begin
    if Assigned(ForeignEval) then
      begin
        { a session of the debugger of Go is open: Delve evaluates }
        if GDBRunCount=ForeignRunCount then
          exit;
        GDBRunCount:=ForeignRunCount;
        if assigned(last_value) then
          strdispose(last_value);
        last_value:=current_value;
        if ForeignEval(GetStr(expr),fv) then
          current_value:=StrNew(PChar(AnsiString('= ' + fv)))
        else
          current_value:=StrNew(PChar(AnsiString(fv)));
        exit;
      end;
    If not assigned(Debugger) or Not Debugger.HasExe or
       (GDBRunCount=Debugger.RunCount) then
      exit;
    GDBRunCount:=Debugger.RunCount;
    if assigned(last_value) then
      strdispose(last_value);
    last_value:=current_value;
    s:=GetStr(expr);
    { Fix 2d array indexing, change [x,x] to [x][x] }
    i:=pos('[',s);
    if i>0 then
      begin
        while i<length(s) do
          begin
            if s[i]=',' then
              begin
                s[i]:='[';
                insert(']',s,i);
                inc(i);
              end;
            inc(i);
          end;
      end;
    found:=GetValue(s);
    orig_s_result:=s;
    Debugger.got_error:=false;
    loop_higher:=not found;
    if not found then
      begin
        curframe:=Debugger.get_current_frame;
        startframe:=curframe;
      end
    else
      begin
        curframe:=0;
        startframe:=0;
      end;
    while loop_higher do
      begin
         s:='parentfp';
         if GetValue(s) then
           begin
             repeat
               inc(curframe);
               if not Debugger.set_current_frame(curframe) then
                 loop_higher:=false;
{$ifdef FrameNameKnown}
               s2:=FrameName;
{$else not  FrameNameKnown}
               s2:='$ebp';
{$endif FrameNameKnown}
               if not getValue(s2) then
                 loop_higher:=false;
               if pos(s2,s)>0 then
                 loop_higher :=false;
             until not loop_higher;
             { try again at that level }
             s:=GetStr(expr);
             found:=GetValue(s);
             loop_higher:=not found;
           end
         else
           loop_higher:=false;
      end;
    if found then
      current_value:=StrNew(PChar('= ' + s))
    else
      current_value:=StrNew(PChar(orig_s_result));
    Debugger.got_error:=false;
    { We should try here to find the expr in parent
      procedure if there are
      I will implement this as I added a
      parent_ebp pseudo local var to local procedure
      in stabs debug info PM }
    { But there are some pitfalls like
      locals redefined in other sublocals that call the function }
    if curframe<>startframe then
      Debugger.set_current_frame(startframe);

    GDBRunCount:=Debugger.RunCount;
  end;
{$else NODEBUG}
  begin
  end;
{$endif NODEBUG}

procedure TWatch.Force_new_value;
  begin
    GDBRunCount:=-1;
    Get_new_value;
  end;

destructor TWatch.Destroy;
  begin
    if assigned(expr) then
      disposestr(expr);
    if assigned(last_value) then
      strdispose(last_value);
    if assigned(current_value) then
      strdispose(current_value);
    inherited Destroy;
  end;

{****************************************************************************
                         TWatchesCollection
****************************************************************************}

      constructor TWatchesCollection.Create;
        begin
          inherited Create(10,10);
        end;

      procedure TWatchesCollection.Insert(Item: Pointer);
       begin
         PWatch(Item).Get_new_value;
         Inherited Insert(Item);
         Update;
       end;

      procedure TWatchesCollection.Update;
        var
         W,W1 : integer;

         procedure GetMax(P : PWatch);
           begin
              if assigned(P.Current_value) then
                W1:=StrLen(P.Current_value)+3+Length(GetStr(P.expr))
              else
                W1:=2+Length(GetStr(P.expr));
              if W1>W then
                W:=W1;
           end;

         begin
          W:=0;
          ForEach(TNestedActionProc(@GetMax));
          MaxW:=W;
          If assigned(WatchesWindow) then
            WatchesWindow.WLB.Update(MaxW);
        end;

      function  TWatchesCollection.At(Index: Integer): PWatch;
        begin
          At:=TWatch(Inherited At(Index));
        end;

{****************************************************************************
                         TWatchesListBox
****************************************************************************}

constructor TWatchesListBox.Create(var Bounds: TRect; AHScrollBar, AVScrollBar: PScrollBar);
  begin
    inherited Create(Bounds,1,AHScrollBar,AVScrollBar);
    If assigned(List) then
      list.Free;
    Items:=WatchesCollection;
  end;

procedure TWatchesListBox.Update(AMaxWidth : integer);
var R : TRect;
begin
  R := GetExtent;
  MaxWidth:=AMaxWidth;
  if (HScrollBar<>nil) and (R.B.X-R.A.X<MaxWidth) then
    HScrollBar.SetRange(0,MaxWidth-(R.B.X-R.A.X))
  else
    HScrollBar.SetRange(0,0);
  if R.B.X-R.A.X>MaxWidth then
    HScrollBar.Hide
  else
    HScrollBar.Show;
  SetRange(List.Count+1);
  if R.B.Y-R.A.Y>Range then
    VScrollBar.Hide
  else
    VScrollBar.Show;

  {if Focused=List.Count-1-1 then
     FocusItem(List.Count-1);
     What was that for ?? PM }
  DrawView;
end;

function    TWatchesListBox.GetIndentedText(Item,Indent,MaxLen: Sw_Integer;var Modified : boolean): String;
var
  PW : PWatch;
  ValOffset : Sw_integer;
  S : String;
begin
  Modified:=false;
  if Item>=WatchesCollection.Count then
    begin
      GetIndentedText:='';
      exit;
    end;

  PW:=WatchesCollection.At(Item);
  ValOffset:=Length(GetStr(PW.Expr))+2;
  if not assigned(PW.expr) then
    GetIndentedText:=''
  else if Indent<ValOffset then
    begin
      S:=GetStr(PW.Expr);
      if Indent=0 then
        S:=' '+S
      else
        S:=Copy(S,Indent,High(S));
      if not assigned(PW.current_value) then
        S:=S+' <Unknown value>'
      else
        S:=S+' '+GetPChar(PW.Current_value);
      GetIndentedText:=Copy(S,1,MaxLen);
    end
  else
   begin
      if not assigned(PW.Current_value) or
         (StrLen(PW.Current_value)<Indent-Valoffset) then
        S:=''
      else
        S:=GetPchar(@(PW.Current_Value[Indent-Valoffset]));
      GetIndentedText:=Copy(S,1,MaxLen);
   end;
   if assigned(PW.current_value) and
      assigned(PW.last_value) and
      (strcomp(PW.Last_value,PW.Current_value)<>0) then
     Modified:=true;
end;

procedure TWatchesListBox.EditCurrent;
var
  P: PWatch;
begin
  if Range=0 then Exit;
  if Focused<WatchesCollection.Count then
    P:=WatchesCollection.At(Focused)
  else
    P := TWatch.Create('');
  TProgram.Application.ExecuteDialog(TWatchItemDialog.Create(P),nil);
  WatchesCollection.Update;
end;

function    TWatchesListBox.GetText (Item: Sw_Integer; MaxLen: Sw_Integer): String;
var
  Dummy_Modified : boolean;
begin
  GetText:=GetIndentedText(Item, 0, MaxLen, Dummy_Modified);
end;

procedure TWatchesListBox.DeleteCurrent;
var
  P: PWatch;
begin
  if (Range=0) or
     (Focused>=WatchesCollection.Count) then
    exit;
  P:=WatchesCollection.At(Focused);
  WatchesCollection.free(P);
  WatchesCollection.Update;
end;

procedure TWatchesListBox.EditNew;
var
  P: PWatch;
  S : string;
begin
  if Focused<WatchesCollection.Count then
    begin
      P:=WatchesCollection.At(Focused);
      S:=GetStr(P.expr);
    end
  else
    S:='';
  P := TWatch.Create(S);
  if TProgram.Application.ExecuteDialog(TWatchItemDialog.Create(P),nil)<>cmCancel then
    begin
      WatchesCollection.AtInsert(Focused,P);
      WatchesCollection.Update;
    end
  else
    P.Free;
end;

procedure   TWatchesListBox.Draw;
var
  I, J, Item: Sw_Integer;
  NormalColor, SelectedColor, FocusedColor, Color: Word;
  ColWidth, CurCol, Indent: Integer;
  B: TFVDrawBuffer;
  Modified : boolean;
  Text: String;
  SCOff: Byte;
  TC: byte;
  procedure MT(var C: word);
    begin
      if TC<>0 then C:=(C and $ff0f) or (TC and $f0);
    end;
begin
  if (Owner<>nil) then TC:=ord(Owner.GetColorW(6)) else TC:=0;
  if State and (sfSelected + sfActive) = (sfSelected + sfActive) then
  begin
    NormalColor := GetColorW(1);
    FocusedColor := GetColorW(3);
    SelectedColor := GetColorW(4);
  end else
  begin
    NormalColor := GetColorW(2);
    SelectedColor := GetColorW(4);
  end;
  if Transparent then
    begin MT(NormalColor); MT(SelectedColor); end;
  (* if NoSelection then
     SelectedColor:=NormalColor;*)
  if HScrollBar <> nil then Indent := HScrollBar.Value
  else Indent := 0;
  ColWidth := Size.X div NumCols + 1;
  for I := 0 to Size.Y - 1 do
  begin
    for J := 0 to NumCols-1 do
    begin
      Item := J*Size.Y + I + TopItem;
      CurCol := J*ColWidth;
      if (State and (sfSelected + sfActive) = (sfSelected + sfActive)) and
        (Focused = Item) and (Range > 0) then
      begin
        Color := FocusedColor;
        SetCursor(CurCol+1,I);
        SCOff := 0;
      end
      else if (Item < Range) and IsSelected(Item) then
      begin
        Color := SelectedColor;
        SCOff := 2;
      end
      else
      begin
        Color := NormalColor;
        SCOff := 4;
      end;
      MoveChar(B[CurCol], ' ', Color, ColWidth);
      if Item < Range then
      begin
        (* Text := GetText(Item, ColWidth + Indent);
        Text := Copy(Text,Indent,ColWidth); *)
        Text:=GetIndentedText(Item,Indent,ColWidth,Modified);
        if modified then
          begin
            SCOff:=0;
            Color:=(Color and $fff0) or Red;
          end;
        MoveStr(B[CurCol], Text, Color);
        if {ShowMarkers or } Modified then
        begin
          SetCellChar(B[CurCol], Char(SpecialChars[SCOff]));
          SetCellChar(B[CurCol+ColWidth-2], Char(SpecialChars[SCOff+1]));
          SetCellBios(B[CurCol+ColWidth-2], Color and $ff);
        end;
      end;
      MoveFill(B[CurCol+ColWidth-1], '│', GetColorW(5), 1);
    end;
    WriteLineC(0, I, Size.X, 1, B);
  end;
end;

function TWatchesListBox.GetLocalMenu: PMenu;
var M: PMenu;
begin
  if (Owner<>nil) and (Owner.GetState(sfModal)) then M:=nil else
  M:=NewMenu(
    NewItem(menu_watchlocal_edit,'',kbNoKey,cmEdit,hcNoContext,
    NewItem(menu_watchlocal_new,'',kbNoKey,cmNew,hcNoContext,
    NewItem(menu_watchlocal_delete,'',kbNoKey,cmDelete,hcNoContext,
    NewLine(
    NewItem(menu_msglocal_saveas,'',kbNoKey,cmSaveAs,hcSaveAs,
    nil))))));
  GetLocalMenu:=M;
end;

procedure   TWatchesListBox.HandleEvent(var Event: TEvent);
var DontClear: boolean;
begin
  case Event.What of
    evMouseDown : begin
                   if ((Event.Mouse.EventFlags and meDoubleClick) <> 0) then
                      Message(Self,evCommand,cmEdit,nil)
                   else
                     ClearEvent(Event);
                  end;
    evKeyDown :
      begin
        DontClear:=false;
        case Event.KeyDown.KeyCode of
          kbEnter :
            Message(Self,evCommand,cmEdit,nil);
          kbIns :
            Message(Self,evCommand,cmNew,nil);
          kbDel :
            Message(Self,evCommand,cmDelete,nil);
        else
          DontClear:=true;
        end;
        if not DontClear then
          ClearEvent(Event);
      end;
    evBroadcast :
      case Event.Message.Command of
        cmListItemSelected :
          if Event.Message.InfoPtr=Pointer(Self) then
            Message(Self,evCommand,cmEdit,nil);
      end;
    evCommand :
      begin
        DontClear:=false;
        case Event.Message.Command of
          cmEdit :
              EditCurrent;
          cmDelete :
              DeleteCurrent;
          cmNew :
              EditNew;
          else
            DontClear:=true;
        end;
        if not DontClear then
          ClearEvent(Event);
      end;
  end;
  inherited HandleEvent(Event);
end;

      constructor TWatchesListBox.Load(S: TStream);
        begin
          inherited Load(S);
          If assigned(List) then
            list.Free;
          Items:=WatchesCollection;
          { we must set Range PM }
          SetRange(List.count+1);
        end;

      procedure   TWatchesListBox.Store(S: TStream);
        var OL: PCollection;
            OldRange : Sw_integer;
        begin
          OL:=List;
          OldRange:=Range;
          Range:=0;
          Items := TCollection.Create(1,1);
          inherited Store(S);
          List.Free;
          Items:=OL;
          { ^^^ nasty trick - has anyone a better idea how to avoid storing the
            collection? Pasting here a modified version of TListBox.Store+
            TAdvancedListBox.Store isn't a better solution, since by eventually
            changing the obj-hierarchy you'll always have to modify this, too - BG }
          SetRange(OldRange);
        end;

      destructor  TWatchesListBox.Destroy;
        begin
          Items:=nil;
          inherited Destroy;
        end;

{****************************************************************************
                         TWatchesWindow
****************************************************************************}

  Constructor TWatchesWindow.Create;
    var
      HSB,VSB: PScrollBar;
      R,R2 : trect;
    begin
      R := TProgram.DeskTop.GetExtent;
      R.A.Y:=R.B.Y-7;
      inherited Create(R, dialog_watches,SearchFreeWindowNo);
      Palette:=wpCyanWindow;
      R := GetExtent;
      HelpCtx:=hcWatchesWindow;
      R.Grow(-1,-1);
      R2 := R;
      Inc(R2.B.Y);
      R2.A.Y:=R2.B.Y-1;
      HSB := TScrollBar.Create(R2);
      HSB.GrowMode:=gfGrowLoY+gfGrowHiY+gfGrowHiX;
      HSB.SetStep(R.B.X-R.A.X,1);
      Insert(HSB);
      R2 := R;
      Inc(R2.B.X);
      R2.A.X:=R2.B.X-1;
      VSB := TScrollBar.Create(R2);
      VSB.GrowMode:=gfGrowLoX+gfGrowHiX+gfGrowHiY;
      Insert(VSB);
      WLB := TWatchesListBox.Create(R,HSB,VSB);
      WLB.GrowMode:=gfGrowHiX+gfGrowHiY;
      WLB.Transparent:=true;
      Insert(WLB);
      If assigned(WatchesWindow) then
        WatchesWindow.Free;
      WatchesWindow:=Self;
      Update;
    end;

  procedure TWatchesWindow.Update;
    begin
      WatchesCollection.Update;
      Draw;
    end;

  constructor TWatchesWindow.Load(S: TStream);
    begin
      inherited Load(S);
      GetSubViewPtr(S,WLB);
      If assigned(WatchesWindow) then
        WatchesWindow.Free;
      WatchesWindow:=Self;
    end;

  procedure TWatchesWindow.Store(S: TStream);
    begin
      inherited Store(S);
      PutSubViewPtr(S,WLB);
    end;

  Destructor TWatchesWindow.Destroy;
    begin
      WatchesWindow:=nil;
      WLB.Free;
      inherited Destroy;
    end;


{****************************************************************************
                         TWatchItemDialog
****************************************************************************}

constructor TWatchItemDialog.Create(AWatch: PWatch);
var R,R2: TRect;
begin
  R := TRect.Create(0, 0, 50, 10);
  inherited Create(R,'Edit Watch');
  Watch:=AWatch;

  R := GetExtent; R.Grow(-3,-2);
  Inc(R.A.Y); R.B.Y:=R.A.Y+1; R.B.X:=R.A.X+36;
  NameIL := TEditorInputLine.Create(R, 255); Insert(NameIL);
  R2 := R; R2.A.X:=R2.B.X; R2.B.X:=R2.A.X+3;
  Insert(THistory.Create(R2, NameIL, hidWatchDialog));
  R2 := R; R2.Move(-1,-1);
  Insert(TLabel.Create(R2, label_watch_expressiontowatch, NameIL));
  R := GetExtent;
  R.Grow(-3,-1);
  R.A.Y:=R.A.Y+3;
  TextST := TAdvancedStaticText.Create(R, label_watch_values);
  Insert(TextST);

  InsertButtons(Self);

  NameIL.Select;
end;

function TWatchItemDialog.Execute: Word;
var R: word;
    S1,S2: string;
begin
  S1:=GetStr(Watch.expr);
  NameIL.SetData(S1);

  S1:=GetPChar(Watch.Current_value);
  S2:=GetPChar(Watch.Last_value);

  ClearFormatParams;
  AddFormatParamStr(S1);
  AddFormatParamStr(S2);
  if assigned(Watch.Last_value) and
     assigned(Watch.Current_value) and
     (strcomp(Watch.Last_value,Watch.Current_value)=0) then
    S1:=FormatStrF(msg_watch_currentvalue,FormatParams)
  else
    S1:=FormatStrF(msg_watch_currentandpreviousvalue,FormatParams);

  TextST.SetText(S1);

  if assigned(FirstEditorWindow) then
    FindReplaceEditor:=FirstEditorWindow.Editor;

  R:=inherited Execute;

  FindReplaceEditor:=nil;

  if R=cmOK then
  begin
    NameIL.GetData(S1);
    Watch.Rename(S1);
{$ifndef NODEBUG}
    If assigned(Debugger) then
       Debugger.ReadWatches;
{$endif NODEBUG}
  end;
  Execute:=R;
end;

{****************************************************************************
                         TStackWindow
****************************************************************************}

  constructor TFramesListBox.Create(var Bounds: TRect; AHScrollBar, AVScrollBar: PScrollBar);
    begin
      inherited Create(Bounds,AHScrollBar,AVScrollBar);
    end;

  procedure TFramesListBox.Update;

    var i : longint;
        W : PSourceWindow;
        fname,fsrc : string;
        fline : longint;

    begin
{$ifndef NODEBUG}
      if Assigned(ForeignFrameCount) then
        begin
          TProgram.DeskTop.Lock;
          Clear;
          for i:=0 to ForeignFrameCount()-1 do
            begin
              ForeignFrame(i,fname,fsrc,fline);
              AddItem(TMessageItem.Create(0,fname,AddModuleName(fsrc),fline,1));
            end;
          if Assigned(list) and (List.Count > 0) then
            FocusItem(0);
          TProgram.DeskTop.Unlock;
          exit;
        end;
      { call backtrace command }
      If not assigned(Debugger) then
        exit;
      TProgram.DeskTop.Lock;
      Clear;

      Debugger.Backtrace;
      { generate list }
      { all is in tframeentry }
      for i:=0 to Debugger.frame_count-1 do
        begin
          with Debugger.frames[i] do
            begin
              if assigned(file_name) then
                AddItem(TMessageItem.Create(0,GetPChar(function_name)+GetPChar(args),
                  AddModuleName(GetPChar(file_name)),line_number,1))
              else
                AddItem(TMessageItem.Create(0,HexStr(address,SizeOf(address)*2)+' '+GetPChar(function_name)+GetPChar(args),
                  AddModuleName(''),line_number,1));
              W:=SearchOnDesktop(GetPChar(file_name),false);
              { First reset all Debugger rows }
              If assigned(W) then
                begin
                  W.Editor.SetLineFlagExclusive(lfDebuggerRow,-1);
                  W.Editor.DebuggerRow:=-1;
                end;
            end;
        end;
      { Now set all Debugger rows }
      for i:=0 to Debugger.frame_count-1 do
        begin
          with Debugger.frames[i] do
            begin
              W:=SearchOnDesktop(GetPChar(file_name),false);
              If assigned(W) then
                begin
                  If W.Editor.DebuggerRow=-1 then
                    begin
                      W.Editor.SetLineFlagState(line_number-1,lfDebuggerRow,true);
                      W.Editor.DebuggerRow:=line_number-1;
                    end;
                end;
            end;
        end;
      if Assigned(list) and (List.Count > 0) then
        FocusItem(0);
      TProgram.DeskTop.Unlock;
{$endif NODEBUG}
    end;

  function TFramesListBox.GetLocalMenu: PMenu;
    begin
      GetLocalMenu:=Inherited GetLocalMenu;
    end;

  procedure TFramesListBox.GotoSource;
    begin
      if Assigned(ForeignSelectFrame) then
        begin
          { the frame that expressions are evaluated in; the watches are read again }
          ForeignSelectFrame(Focused);
          ForeignRereadWatches;
          inherited GotoSource;
          exit;
        end;
{$ifndef NODEBUG}
      { select frame for watches }
      If not assigned(Debugger) then
        exit;
      Debugger.SelectFrameCommand(Focused);
      { for local vars }
      Debugger.RereadWatches;
{$endif NODEBUG}
      { goto source }
      inherited GotoSource;
    end;

  procedure   TFramesListBox.GotoAssembly;
    begin
{$ifndef NODEBUG}
      { select frame for watches }
      If not assigned(Debugger) then
        exit;
      Debugger.SelectFrameCommand(Focused);
      { for local vars }
      Debugger.RereadWatches;
{$endif}
      { goto source/assembly mixture }
      InitDisassemblyWindow;
      DisassemblyWindow.LoadFunction('');
{$ifndef NODEBUG}
      DisassemblyWindow.SetCurAddress(Debugger.frames[Focused].address);
      DisassemblyWindow.SelectInDebugSession;
{$endif NODEBUG}
    end;


  procedure   TFramesListBox.HandleEvent(var Event: TEvent);
    begin
      if ((Event.What=EvKeyDown) and (Event.KeyDown.CharScan.CharCode=Ord('i'))) or
         ((Event.What=EvCommand) and (Event.Message.Command=cmDisassemble)) then
        GotoAssembly;
      inherited HandleEvent(Event);
    end;

  destructor  TFramesListBox.Destroy;
    begin
      inherited Destroy;
    end;

  Constructor TStackWindow.Create;
    var
      HSB,VSB: PScrollBar;
      R,R2 : trect;
    begin
      R := TProgram.DeskTop.GetExtent;
      R.A.Y:=R.B.Y-5;
      inherited Create(R, dialog_callstack, wnNoNumber);
      Palette:=wpCyanWindow;
      R := GetExtent;
      HelpCtx:=hcStackWindow;
      R.Grow(-1,-1);
      R2 := R;
      Inc(R2.B.Y);
      R2.A.Y:=R2.B.Y-1;
      HSB := TScrollBar.Create(R2);
      HSB.GrowMode:=gfGrowLoY+gfGrowHiY+gfGrowHiX;
      Insert(HSB);
      R2 := R;
      Inc(R2.B.X);
      R2.A.X:=R2.B.X-1;
      VSB := TScrollBar.Create(R2);
      VSB.GrowMode:=gfGrowLoX+gfGrowHiX+gfGrowHiY;
      Insert(VSB);
      FLB := TFramesListBox.Create(R,HSB,VSB);
      FLB.GrowMode:=gfGrowHiX+gfGrowHiY;
      Insert(FLB);
      If assigned(StackWindow) then
        StackWindow.Free;
      StackWindow:=Self;
      Update;
    end;

  procedure TStackWindow.Update;
    begin
      FLB.Update;
      DrawView;
    end;

  constructor TStackWindow.Load(S: TStream);
    begin
      inherited Load(S);
      GetSubViewPtr(S,FLB);
      If assigned(StackWindow) then
        StackWindow.Free;
      StackWindow:=Self;
    end;

  procedure TStackWindow.Store(S: TStream);
    begin
      inherited Store(S);
      PutSubViewPtr(S,FLB);
    end;

  Destructor TStackWindow.Destroy;
    begin
      StackWindow:=nil;
      FLB.Free;
      inherited Destroy;
    end;



{$ifdef SUPPORT_REMOTE}
{****************************************************************************
                         TransformRemoteString
****************************************************************************}
function TransformRemoteString(st : string) : string;
begin
  If RemoteConfig<>'' then
    ReplaceStrI(St,'$CONFIG','-F '+RemoteConfig)
  else
    ReplaceStrI(St,'$CONFIG','');
  If RemoteIdent<>'' then
    ReplaceStrI(St,'$IDENT','-i '+RemoteIdent)
  else
    ReplaceStrI(St,'$IDENT','');
  If RemotePuttySession<>'' then
    ReplaceStrI(St,'$PUTTYSESSION','-load '+RemotePuttySession)
  else
    ReplaceStrI(St,'$PUTTYSESSION','');
  ReplaceStrI(St,'$LOCALFILENAME',NameAndExtOf(ExeFile));
  ReplaceStrI(St,'$LOCALFILE',ExeFile);
  ReplaceStrI(St,'$REMOTEDIR',RemoteDir);
  ReplaceStrI(St,'$REMOTEPORT',RemotePort);
  ReplaceStrI(St,'$REMOTEMACHINE',RemoteMachine);
  ReplaceStrI(St,'$REMOTEGDBSERVER',maybequoted(remotegdbserver));
  ReplaceStrI(St,'$REMOTECOPY',maybequoted(RemoteCopy));
  ReplaceStrI(St,'$REMOTESHELL',maybequoted(RemoteShell));
  { avoid infinite recursion here !!! }
  if Pos('$REMOTEEXECCOMMAND',UpcaseSTr(St))>0 then
    ReplaceStrI(St,'$REMOTEEXECCOMMAND',TransformRemoteString(RemoteExecCommand));
{$ifdef WINDOWS}
  ReplaceStrI(St,'$START','start "Shell to remote"');
  ReplaceStrI(St,'$DOITINBACKGROUND','');
{$else}
  ReplaceStrI(St,'$START','');
  ReplaceStrI(St,'$DOITINBACKGROUND',' &');
{$endif}
  TransformRemoteString:=st;
end;
{$endif SUPPORT_REMOTE}

{****************************************************************************
                         Init/Final
****************************************************************************}


function GetGDBTargetShortName : string;
begin
{$ifndef CROSSGDB}
GetGDBTargetShortName:=source_info.shortname;
{$else CROSSGDB}
{$ifdef SUPPORT_REMOTE}
{$ifdef PALMOSGDB}
GetGDBTargetShortName:='palmos';
{$else}
GetGDBTargetShortName:='linux';
{$endif PALMOSGDB}
{$endif not SUPPORT_REMOTE}
{$endif CROSSGDB}
end;

procedure InitDebugger;
{$ifdef DEBUG}
var s : string;
    i,p : longint;
{$endif DEBUG}
var
   NeedRecompileExe : boolean;
   cm : longint;
begin
{$ifdef DEBUG}
  if not use_gdb_file then
    begin
      Assign(gdb_file,GDBOutFileName);
      {$I-}
      Rewrite(gdb_file);
      if InOutRes<>0 then
        begin
          s:=GDBOutFileName;
          p:=pos('.',s);
          if p>1 then
           for i:=0 to 9 do
             begin
               s:=copy(s,1,p-2)+chr(i+ord('0'))+copy(s,p,length(s));
               InOutRes:=0;
               Assign(gdb_file,s);
               rewrite(gdb_file);
               if InOutRes=0 then
                 break;
             end;
        end;
      if IOResult=0 then
        Use_gdb_file:=true;
    end;
  {$I+}
{$endif}

  NeedRecompileExe:=false;
{$ifndef SUPPORT_REMOTE}
  if UpCaseStr(TargetSwitches.GetCurrSelParam)<>UpCaseStr(GetGDBTargetShortName) then
    begin
     ClearFormatParams;
     AddFormatParamStr(TargetSwitches.GetCurrSelParam);
     AddFormatParamStr(GetGDBTargetShortName);
     cm:=ConfirmBox(msg_cantdebugchangetargetto,@FormatParams,true);
     if cm=cmCancel then
       Exit;
     if cm=cmYes then
       begin
         { force recompilation }
         PrevMainFile:='';
         NeedRecompileExe:=true;
         TargetSwitches.SetCurrSelParam(GetGDBTargetShortName);
         If DebugInfoSwitches.GetCurrSelParam='-' then
           DebugInfoSwitches.SetCurrSelParam('l');
         IDEApp.UpdateTarget;
       end;
    end;
{$endif ndef SUPPORT_REMOTE}
  if not NeedRecompileExe then
    NeedRecompileExe:=(not ExistsFile(ExeFile)) or (CompilationPhase<>cpDone) or
     (PrevMainFile<>MainFile) or NeedRecompile(cRun,false);
  if Not NeedRecompileExe and Not MainHasDebugInfo then
    begin
     ClearFormatParams;
     cm:=ConfirmBox(msg_compiledwithoutdebuginforecompile,nil,true);
     if cm=cmCancel then
       Exit;
     if cm=cmYes then
       begin
         { force recompilation }
         PrevMainFile:='';
         NeedRecompileExe:=true;
         DebugInfoSwitches.SetCurrSelParam('l');
       end;
    end;
  if NeedRecompileExe then
    begin
      { a program that is about to be built for the debugger needs symbols }
      if DebugInfoSwitches.GetCurrSelParam='-' then
        DebugInfoSwitches.SetCurrSelParam('');
      DoCompile(cRun);
    end;
  if CompilationPhase<>cpDone then
    Exit;
  if (EXEFile='') then
   begin
     ErrorBox(msg_nothingtodebug,nil);
     Exit;
   end;
{ init debugcontroller }
{$ifndef NODEBUG}
  if not assigned(Debugger) then
    begin
      PushStatus(msg_startingdebugger);
      Debugger := TDebugController.Create;
      PopStatus;
    end;
  Debugger.SetExe(ExeFile);
{$endif NODEBUG}
{$ifdef GDBWINDOW}
  InitGDBWindow;
{$endif def GDBWINDOW}
end;

const
  Invalid_gdb_file_handle: boolean = false;


procedure DoneDebugger;
begin
{$ifdef DEBUG}
  If IDEApp.IsRunning then
    PushStatus('Closing debugger');
{$endif}
{$ifndef NODEBUG}
  if assigned(Debugger) then
   Debugger.Free;
  Debugger:=nil;
{$endif NODEBUG}
{$ifdef DOS}
  If assigned(UserScreen) then
    PDosScreen(UserScreen).FreeGraphBuffer;
{$endif DOS}
{$ifdef DEBUG}
  If Use_gdb_file then
    begin
      Use_gdb_file:=false;
{$IFOPT I+}
  {$I-}
  {$DEFINE REENABLE_I}
{$ENDIF}
      Close(GDB_file);
      if ioresult<>0 then
        begin
          { This handle seems to get lost for DJGPP
            don't bother too much about this. }
          Invalid_gdb_file_handle:=true;
        end;
{$IFDEF REENABLE_I}
  {$I+}
{$ENDIF}
    end;
  If IDEApp.IsRunning then
    PopStatus;
{$endif DEBUG}
end;

procedure InitGDBWindow;
var
  R : TRect;
begin
  if GDBWindow=nil then
    begin
      R := TProgram.DeskTop.GetExtent;
      GDBWindow := TGDBWindow.Create(R);
      TProgram.DeskTop.Insert(GDBWindow);
    end;
end;

procedure DoneGDBWindow;
begin
  If IDEApp.IsRunning and
     assigned(GDBWindow) then
    begin
      TProgram.DeskTop.Delete(GDBWindow);
    end;
  GDBWindow:=nil;
end;

procedure InitDisassemblyWindow;
var
  R : TRect;
begin
  if DisassemblyWindow=nil then
    begin
      R := TProgram.DeskTop.GetExtent;
      DisassemblyWindow := TDisassemblyWindow.Create(R);
      TProgram.DeskTop.Insert(DisassemblyWindow);
    end;
end;

procedure DoneDisassemblyWindow;
begin
  if assigned(DisassemblyWindow) then
    begin
      TProgram.DeskTop.Delete(DisassemblyWindow);
      DisassemblyWindow.Free;
      DisassemblyWindow:=nil;
    end;
end;

procedure InitStackWindow;
begin
  if StackWindow=nil then
    begin
      StackWindow := TStackWindow.Create;
      TProgram.DeskTop.Insert(StackWindow);
    end;
end;

procedure DoneStackWindow;
begin
  if assigned(StackWindow) then
    begin
      TProgram.DeskTop.Delete(StackWindow);
      StackWindow:=nil;
    end;
end;

procedure InitBreakpoints;
begin
  BreakpointsCollection := TBreakpointCollection.Create(10,10);
end;

procedure DoneBreakpoints;
begin
  BreakpointsCollection.Free;
  BreakpointsCollection:=nil;
end;

procedure InitWatches;
begin
  WatchesCollection := TwatchesCollection.Create;
end;

procedure DoneWatches;
begin
  WatchesCollection.Free;
  WatchesCollection:=nil;
end;

{$ifndef NOOBJREG}
{ tv3 stream registration: factories + run-time record fill (see tools/fpide-streamrec-migrate.py) }
function Build_RBreakpointsWindow(S: TStream): TStreamable;
begin
  Result := TStreamable(Pointer(TBreakpointsWindow.Load(S)));
end;

procedure Store_RBreakpointsWindow(P: TStreamable; S: TStream);
begin
  TBreakpointsWindow(Pointer(P)).Store(S);
end;

function Build_RBreakpointsListBox(S: TStream): TStreamable;
begin
  Result := TStreamable(Pointer(TBreakpointsListBox.Load(S)));
end;

procedure Store_RBreakpointsListBox(P: TStreamable; S: TStream);
begin
  TBreakpointsListBox(Pointer(P)).Store(S);
end;

function Build_RWatchesWindow(S: TStream): TStreamable;
begin
  Result := TStreamable(Pointer(TWatchesWindow.Load(S)));
end;

procedure Store_RWatchesWindow(P: TStreamable; S: TStream);
begin
  TWatchesWindow(Pointer(P)).Store(S);
end;

function Build_RWatchesListBox(S: TStream): TStreamable;
begin
  Result := TStreamable(Pointer(TWatchesListBox.Load(S)));
end;

procedure Store_RWatchesListBox(P: TStreamable; S: TStream);
begin
  TWatchesListBox(Pointer(P)).Store(S);
end;

function Build_RStackWindow(S: TStream): TStreamable;
begin
  Result := TStreamable(Pointer(TStackWindow.Load(S)));
end;

procedure Store_RStackWindow(P: TStreamable; S: TStream);
begin
  TStackWindow(Pointer(P)).Store(S);
end;

function Build_RFramesListBox(S: TStream): TStreamable;
begin
  Result := TStreamable(Pointer(TFramesListBox.Load(S)));
end;

procedure Store_RFramesListBox(P: TStreamable; S: TStream);
begin
  TFramesListBox(Pointer(P)).Store(S);
end;

function Build_RBreakpoint(S: TStream): TStreamable;
begin
  Result := TStreamable(Pointer(TBreakpoint.Load(S)));
end;

procedure Store_RBreakpoint(P: TStreamable; S: TStream);
begin
  TBreakpoint(Pointer(P)).Store(S);
end;

function Build_RWatch(S: TStream): TStreamable;
begin
  Result := TStreamable(Pointer(TWatch.Load(S)));
end;

procedure Store_RWatch(P: TStreamable; S: TStream);
begin
  TWatch(Pointer(P)).Store(S);
end;

function Build_RBreakpointCollection(S: TStream): TStreamable;
begin
  Result := TStreamable(Pointer(TBreakpointCollection.Load(S)));
end;

procedure Store_RBreakpointCollection(P: TStreamable; S: TStream);
begin
  TBreakpointCollection(Pointer(P)).Store(S);
end;

function Build_RWatchesCollection(S: TStream): TStreamable;
begin
  Result := TStreamable(Pointer(TWatchesCollection.Load(S)));
end;

procedure Store_RWatchesCollection(P: TStreamable; S: TStream);
begin
  TWatchesCollection(Pointer(P)).Store(S);
end;

procedure FillStreamRecs_fpdebug;
begin
  RBreakpointsWindow.ObjType := 1701;
  RBreakpointsWindow.VmtLink := PtrUInt(System.TClass(TBreakpointsWindow));
  RBreakpointsWindow.Load := @Build_RBreakpointsWindow;
  RBreakpointsWindow.Store := @Store_RBreakpointsWindow;
  RBreakpointsWindow.Next := nil;
  RBreakpointsListBox.ObjType := 1702;
  RBreakpointsListBox.VmtLink := PtrUInt(System.TClass(TBreakpointsListBox));
  RBreakpointsListBox.Load := @Build_RBreakpointsListBox;
  RBreakpointsListBox.Store := @Store_RBreakpointsListBox;
  RBreakpointsListBox.Next := nil;
  RWatchesWindow.ObjType := 1703;
  RWatchesWindow.VmtLink := PtrUInt(System.TClass(TWatchesWindow));
  RWatchesWindow.Load := @Build_RWatchesWindow;
  RWatchesWindow.Store := @Store_RWatchesWindow;
  RWatchesWindow.Next := nil;
  RWatchesListBox.ObjType := 1704;
  RWatchesListBox.VmtLink := PtrUInt(System.TClass(TWatchesListBox));
  RWatchesListBox.Load := @Build_RWatchesListBox;
  RWatchesListBox.Store := @Store_RWatchesListBox;
  RWatchesListBox.Next := nil;
  RStackWindow.ObjType := 1705;
  RStackWindow.VmtLink := PtrUInt(System.TClass(TStackWindow));
  RStackWindow.Load := @Build_RStackWindow;
  RStackWindow.Store := @Store_RStackWindow;
  RStackWindow.Next := nil;
  RFramesListBox.ObjType := 1706;
  RFramesListBox.VmtLink := PtrUInt(System.TClass(TFramesListBox));
  RFramesListBox.Load := @Build_RFramesListBox;
  RFramesListBox.Store := @Store_RFramesListBox;
  RFramesListBox.Next := nil;
  RBreakpoint.ObjType := 1707;
  RBreakpoint.VmtLink := PtrUInt(System.TClass(TBreakpoint));
  RBreakpoint.Load := @Build_RBreakpoint;
  RBreakpoint.Store := @Store_RBreakpoint;
  RBreakpoint.Next := nil;
  RWatch.ObjType := 1708;
  RWatch.VmtLink := PtrUInt(System.TClass(TWatch));
  RWatch.Load := @Build_RWatch;
  RWatch.Store := @Store_RWatch;
  RWatch.Next := nil;
  RBreakpointCollection.ObjType := 1709;
  RBreakpointCollection.VmtLink := PtrUInt(System.TClass(TBreakpointCollection));
  RBreakpointCollection.Load := @Build_RBreakpointCollection;
  RBreakpointCollection.Store := @Store_RBreakpointCollection;
  RBreakpointCollection.Next := nil;
  RWatchesCollection.ObjType := 1710;
  RWatchesCollection.VmtLink := PtrUInt(System.TClass(TWatchesCollection));
  RWatchesCollection.Load := @Build_RWatchesCollection;
  RWatchesCollection.Store := @Store_RWatchesCollection;
  RWatchesCollection.Next := nil;
end;

{$endif}

procedure RegisterFPDebugViews;
begin
  FillStreamRecs_fpdebug;
  RegisterType(RWatchesWindow);
  RegisterType(RBreakpointsWindow);
  RegisterType(RWatchesListBox);
  RegisterType(RBreakpointsListBox);
  RegisterType(RStackWindow);
  RegisterType(RFramesListBox);
  RegisterType(RBreakpoint);
  RegisterType(RWatch);
  RegisterType(RBreakpointCollection);
  RegisterType(RWatchesCollection);
end;

end.
{$endif NODEBUG}
