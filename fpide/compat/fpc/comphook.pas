{
    Copyright (c) 1998-2002 by Peter Vreman

    The compiler hooks of the Free Pascal compiler, reduced for the IDE that runs an external compiler:
    the levels and the status record only, no input file hooks, no message output.
    Taken from the compiler (release_3_2_2, compiler/comphook.pas); GPL-2 or later, see COPYING.FPC.
 ****************************************************************************
}
unit comphook;

{$i fpcdefs.inc}

interface

uses
  sysutils,
  globtype;


Const
  { Levels }
  V_None         = $0;
  V_Fatal        = $1;
  V_Error        = $2;
  V_Normal       = $4; { doesn't show a text like Error: }
  V_Warning      = $8;
  V_Note         = $10;
  V_Hint         = $20;
  V_LineInfoMask = $fff;
  { From here by default no line info }
  V_Info         = $1000;
  V_Status       = $2000;
  V_Used         = $4000;
  V_Tried        = $8000;
  V_Conditional  = $10000;
  V_Debug        = $20000;
  V_Executable   = $40000;
  V_TimeStamps   = $80000;
  V_LevelMask    = $fffffff;
  V_All          = V_LevelMask;
  V_Default      = V_Fatal + V_Error + V_Normal;
  { Flags }
  V_LineInfo     = $10000000;

const
  { RHIDE expect gcc like error output }
  fatalstr      : string[20] = 'Fatal:';
  errorstr      : string[20] = 'Error:';
  warningstr    : string[20] = 'Warning:';
  notestr       : string[20] = 'Note:';
  hintstr       : string[20] = 'Hint:';

type
  PCompilerStatus = ^TCompilerStatus;
  TCompilerStatus = record
  { Current status }
    currentmodule,
    currentsourceppufilename, { the name of the ppu where the source file
                                comes from where the error location is given }
    currentsourcepath,
    currentsource : string;   { filename }
    currentline,
    currentcolumn : longint;  { current line and column }
    currentmodulestate : string[20];
  { Total Status }
    compiledlines : longint;  { the number of lines which are compiled }
    errorcount,               { this field should never be increased directly,
                                use Verbose.GenerateError procedure to do this,
                                this allows easier error catching using GDB by
                                adding a single breakpoint at this procedure }
    countWarnings,
    countNotes,
    countHints    : longint;  { number of found errors/warnings/notes/hints }
    codesize,
    datasize      : qword;
  { program info }
    isexe,
    ispackage,
    islibrary     : boolean;
  { Settings for the output }
    showmsgnrs    : boolean;
    verbosity     : longint;
    maxerrorcount : longint;
    errorwarning,
    errornote,
    errorhint,
    skip_error,
    use_stderr,
    use_redir,
    use_bugreport,
    use_gccoutput,
    sources_avail,
    print_source_path : boolean;
  { Redirection support }
    redirfile : text;
  { Special file for bug report }
    reportbugfile : text;
  end;

type
  EControlCAbort=class(Exception)
    constructor Create;
  end;
  ECompilerAbort=class(Exception)
    constructor Create;
  end;
  ECompilerAbortSilent=class(Exception)
    constructor Create;
  end;

var
  status : tcompilerstatus;

{ Default Functions }

Function  def_status:boolean;
Function  def_comment(Level:Longint;const s:ansistring):boolean;
function  def_internalerror(i:longint):boolean;
function  def_CheckVerbosity(v:longint):boolean;
procedure def_initsymbolinfo;
procedure def_donesymbolinfo;
procedure def_extractsymbolinfo;
{ Function redirecting for IDE support }
type
  tstopprocedure         = procedure(err:longint);
  tstatusfunction        = function:boolean;
  tcommentfunction       = function(Level:Longint;const s:ansistring):boolean;
  tinternalerrorfunction = function(i:longint):boolean;
  tcheckverbosityfunction = function(i:longint):boolean;
  tinitsymbolinfoproc = procedure;
  tdonesymbolinfoproc = procedure;
  textractsymbolinfoproc = procedure;

const
  do_status        : tstatusfunction  = @def_status;
  do_comment       : tcommentfunction = @def_comment;
  do_internalerror : tinternalerrorfunction = @def_internalerror;
  do_checkverbosity : tcheckverbosityfunction = @def_checkverbosity;
  do_initsymbolinfo : tinitsymbolinfoproc = @def_initsymbolinfo;
  do_donesymbolinfo : tdonesymbolinfoproc = @def_donesymbolinfo;
  do_extractsymbolinfo : textractsymbolinfoproc = @def_extractsymbolinfo;
  needsymbolinfo : boolean =false;

implementation

constructor EControlCAbort.Create;
  begin
    inherited Create('Ctrl-C Signaled!');
  end;

constructor ECompilerAbort.Create;
  begin
    inherited Create('Compilation Aborted');
  end;

constructor ECompilerAbortSilent.Create;
  begin
    inherited Create('Compilation Aborted');
  end;

function def_status:boolean;
begin
  def_status:=false;
end;

function def_comment(Level:Longint;const s:ansistring):boolean;
begin
  def_comment:=false;
end;

function def_internalerror(i : longint) : boolean;
begin
  def_internalerror:=true;
end;

function def_CheckVerbosity(v:longint):boolean;
begin
  result:=status.use_bugreport or
          ((v<>V_None) and
           ((status.verbosity and (v and V_LevelMask))=(v and V_LevelMask)));
end;

procedure def_initsymbolinfo;
begin
end;

procedure def_donesymbolinfo;
begin
end;

procedure def_extractsymbolinfo;
begin
end;

end.
