{
    This file is part of the Free Pascal Integrated Development Environment
    Copyright (c) 1998 by Berczi Gabor

    Calculator object for the IDE

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}
{$I globdir.inc}
unit FPCalc;
{$modeswitch nestedprocvars}{$modeswitch autoderef}

interface

uses
  Drivers,Objects,Views,Dialogs,App,
  FVConsts,
  WViews,
  FPViews;

const
      MaxDecimals = 10;
      MaxDigits   = 30;

type

  TCalcState = (csFirst, csValid, csError);

  TCalcButton = class;
  PCalcButton = TCalcButton;
  TCalcButton = class(TButton)
    procedure HandleEvent(var Event: TEvent); override;
  end;

  TCalcDisplay = class;
  PCalcDisplay = TCalcDisplay;
  TCalcDisplay = class(TView)
    Status: TCalcState;
    Number: string[MaxDigits];
    Sign: Char;
    LastOperator,
    _Operator: Char;
    LastR,
    Operand: extended;
    Memory: extended;
    DispNumber: extended;
    HexShown : boolean;
    constructor Create(var Bounds: TRect);
    constructor Load(S: TStream);
    function  CalcKey(Key: string): boolean;
    procedure Clear;
    procedure Draw; override;
    function  GetPalette: TPalette; override;
    procedure HandleEvent(var Event: TEvent); override;
    procedure Store(S: TStream); override;
  private
    procedure GetDisplay(var R: extended);
    procedure SetDisplay(R: extended;ShouldKeepZeroes : boolean);
    procedure Error;
  end;

  TCalculator = class;
  PCalculator = TCalculator;
  TCalculator = class(TCenterDialog)
    CD : PCalcDisplay;
    constructor Create;
    procedure   HandleEvent(var Event: TEvent); override;
    procedure   Show; {override;}
    procedure   Close; override;
    constructor Load(S: TStream);
    procedure   Store(S: TStream); override;
  end;

{$ifndef NOOBJREG}
{$ifndef NOOBJREG}
{$ifndef NOOBJREG}
var RCalcButton: TStreamRec;
var RCalcDisplay: TStreamRec;
var RCalculator: TStreamRec;

{$endif}
{$endif}
{$endif}

procedure RegisterFPCalc;

implementation

uses
{$ifdef Unix}
  baseunix,
  unix,
{$endif}
{$ifdef go32v2}
  dpmiexcp,
{$endif}
{$ifdef windows}
 {$ifdef HasSignal}
    signals,
  {$endif}
{$endif windows}
  FPUtils,FPConst,WUtils;

const
  cmCalcButton  = 100;
  cmPressButton = 101;

{$ifdef useresstrings}
resourcestring
{$else}
const
{$endif}
      dialog_calculator       = 'Calculator';


procedure TCalcButton.HandleEvent(var Event: TEvent);
var
  Call : boolean;
  i : Sw_Word;
begin
  Call:=true;
  case Event.What of
    evKeyDown :
     case Event.KeyDown.KeyCode of
       kbEnter   : Call:=false;
     end;
    evBroadcast :
     case Event.Message.Command of
       cmDefault     : Call:=false;
       cmPressButton :
         begin
           if (PString(Event.Message.InfoPtr)^=Title^) or
              ((PString(Event.Message.InfoPtr)^='^') and (Title^='x^y')) then
              begin
                Select;
                DrawState(true);
                i:=GetDosTicks+2;
                repeat
                until GetDosTicks>i;
                DrawState(false);
                ClearEvent(Event);
              end;
         end;
     end;
  end;
  if Call then
  inherited HandleEvent(Event);
end;

constructor TCalcDisplay.Create(var Bounds: TRect);
begin
  inherited Create(Bounds);
  Options := Options or ofSelectable;
  EventMask := evKeyDown + evBroadcast;
  Clear;
  HelpCtx:={hcCalculatorLine}0;
  HexShown:=false;
end;

constructor TCalcDisplay.Load(S: TStream);
begin
  inherited Load(S);
  S.Read(Status, SizeOf(Status) + SizeOf(Number) + SizeOf(Sign) +
    SizeOf(_Operator) + SizeOf(Operand));
  HexShown:=false;
end;

procedure TCalcDisplay.GetDisplay(var R: extended);
begin
{  Val(Sign + Number, R, E);}
  R:=DispNumber;
end;

procedure TCalcDisplay.SetDisplay(R: extended;ShouldKeepZeroes : boolean);
var
  S: string[MaxDigits];
  i,KeepZeroes : byte;
begin
  DispNumber:=R;
  KeepZeroes:=0;
  if ShouldKeepZeroes and (pos('.',Number)>0) then
    for i:=length(Number) downto pos('.',Number)+1 do
      if Number[i]='0' then
        inc(KeepZeroes)
      else
        break;

  Str(R: 0: MaxDecimals, S);
  if Pos('.',S)<>0 then
     while (length(S)>1) and (S[length(S)]='0') do Dec(S[0]);
  if KeepZeroes>0 then
    for i:=1 to KeepZeroes do
      S:=S+'0';
  if S[1] <> '-' then Sign := ' ' else
  begin
    Delete(S, 1, 1);
    Sign := '-';
  end;
  if Length(S) > MaxDigits + 1 + MaxDecimals then Error
  else
  begin
    if S[Length(S)] = '.' then Dec(S[0]);
    Number := S;
  end;
end;

procedure TCalcDisplay.Error;
begin
  Status := csError;
  Number := 'Error';
  Sign := ' ';
  DrawView;
end;

{$ifdef HasSignal}
var
{$ifndef go32v2}
  CalcSigJmp : Jmp_Buf;
{$else : go32v2}
  CalcSigJmp : dpmi_jmp_buf;
{$endif go32v2}
const
  fpucw : word = $1332;
{$ifdef Unix}
Procedure CalcSigFPE(sig : longint);cdecl;
{$else}
function CalcSigFPE(sig : longint) : longint;cdecl;
{$endif}
{$ifdef CPUI386}
  var
    { Use a local variable to avoid problems with PIC code }
    local_fpucw : word;
{$endif CPUI386}
begin
{$ifdef CPUI386}
  asm
    fninit
    fldcw local_fpucw
  end;
  fpucw := local_fpucw;
{$endif}
  { ErrorBox('Error while computing math expression',nil);
    was only there for debugging PM }
{$ifdef go32v2}
  Dpmi_LongJmp(CalcSigJmp,1);
{$else : not go32v2}
  LongJmp(CalcSigJmp,1);
{$endif go32v2}
{$ifndef Unix}
  { Just here to avoid compiler warnings PM }
  CalcSigFPE:=0;
{$endif}
end;
{$endif HasSignal}

function TCalcDisplay.CalcKey(Key: string): boolean;
var
  R,D: extended;
  X : cardinal;
procedure CheckFirst;
begin
  if Status = csFirst then
  begin
    Status := csValid;
    SetDisplay(0,false);
  end;
end;
{$ifdef HasSignal}
var
  StoreSigFPE : SignalHandler;
{$endif HasSignal}
{$ifdef CPUI386}
var
  { Use a local variable to avoid problems with PIC code }
  local_fpucw : word;
{$endif CPUI386}
begin
  CalcKey:=true;
  Key := UpCaseStr(Key);
{$ifdef HasSignal}
{$ifdef CPUI386}
  local_fpucw:=fpucw;
  asm
    fstcw local_fpucw
  end;
{$endif}
{$ifdef go32v2}
  if Dpmi_SetJmp(CalcSigJmp)=0 then
{$else : not go32v2}
  if SetJmp(CalcSigJmp)=0 then
{$endif go32v2}
{$endif HasSignal}
    begin
{$ifdef HasSignal}
      StoreSigFPE:={$ifdef unix}fpSignal{$else}Signal{$endif}(SIGFPE,@CalcSigFPE);
{$endif HasSignal}
      if (Status = csError) and (Key <> 'C') then Key := ' ';
      if HexShown then
        begin
          GetDisplay(R);
          SetDisplay(R,false);
          HexShown := false;
          if Key = 'H' then
            Key := ' ';
        end;
      if Key='X^Y' then Key:='^';
      if length(Key)>1 then
         begin
    {        if Status = csFirst then}
            begin
    {          Status := csValid;}
              GetDisplay(R);
              if Key='1/X' then begin if R=0 then Error else SetDisplay(1/R,false) end else
              if Key='SQRT' then begin if R<0 then Error else SetDisplay(sqrt(R),false) end else
              if Key='LOG' then begin if R<=0 then Error else SetDisplay(ln(R),false) end else
              if Key='X^2' then SetDisplay(R*R,false) else
              if Key='±' then begin if Sign = ' ' then Sign := '-' else Sign := ' '; SetDisplay(-R,true) end else
              if Key='M+' then Memory:=Memory+R else
              if Key='M-' then Memory:=Memory-R else
              if Key='M'#26 then SetDisplay(Memory,false) else
              if Key='M'#27 then Memory:=R else
              if Key='M'#29 then begin D:=Memory; Memory:=R; SetDisplay(D,false); end;
            end;
         end
      else
      case Key[1] of
        '0'..'9':
        if Length(Number)<MaxDigits then
          begin
            CheckFirst;
            if Number = '0' then Number := '';
            Number := Number + Key;
            SetDisplay(StrToExtended(Number),true);
          end;
        '.':
          begin
            CheckFirst;
            if Pos('.', Number) = 0 then Number := Number + '.';
          end;
        #8, #27:
          begin
            CheckFirst;
            if Length(Number) = 1 then Number := '0' else Dec(Number[0]);
            SetDisplay(StrToExtended(Number),true); { !!! }
          end;
        'H':
          begin
            GetDisplay(R);
            X:=trunc(abs(R));
            Number:=HexStr(longint(X),8);
            HexShown:=true;
          end;
        '_', #241:
          begin
            if Sign = ' ' then Sign := '-' else Sign := ' ';
            GetDisplay(R);
            SetDisplay(-R,true);
          end;
        '+', '-', '*', '/', '=', '%', #13, '^':
          begin
            if (Key[1]='=') and (Status=csFirst) then
              begin
                Status:=csValid;
                R:=LastR;
                _Operator:=LastOperator;
              end
            else
              GetDisplay(R);
            if (Status = csValid)  then
            begin
              Status := csFirst;
              LastR:=R;
              LastOperator:=_Operator;
              if Key = '%' then
                case _Operator of
                  '+', '-': R := Operand * R / 100;
                  '*', '/': R := R / 100;
                end;
              case _Operator of
                '^': if (Operand = 0)and(R <= 0) then Error else SetDisplay(Power(Operand,R),false);
                '+': SetDisplay(Operand + R,false);
                '-': SetDisplay(Operand - R,false);
                '*': SetDisplay(Operand * R,false);
                '/': if R = 0 then Error else SetDisplay(Operand / R,false);
              end;
            end;
            _Operator := Key[1];
            GetDisplay(Operand);
          end;
        'C':
          Clear;
        else CalcKey:=false;
      end;
{$ifdef HasSignal}
      {$ifdef unix}fpSignal{$else}Signal{$endif}(SIGFPE,StoreSigFPE);
{$endif HasSignal}
      DrawView;
{$ifdef HasSignal}
    end
  else { LongJmp called }
    begin
      ErrorBox('Error while computing '+Key,nil);
      CalcKey:=true;
{$endif HasSignal}
    end;
end;

procedure TCalcDisplay.Clear;
begin
  Status := csFirst;
  Number := '0';
  Sign := ' ';
  _Operator := '=';
end;

procedure TCalcDisplay.Draw;
var
  Color: Byte;
  I: Integer;
  B: TFVDrawBuffer;
begin
  Color := GetColorW(1);
  I := Size.X - Length(Number) - 2;
  MoveChar(B, ' ', Color, Size.X);
  MoveChar(B[I], Sign, Color, 1);
  MoveStr(B[I + 1], Number, Color);
  WriteBufC(0, 0, Size.X, 1, B);
end;

function TCalcDisplay.GetPalette: TPalette;
const
  P: string[1] = #19;
begin
  Result := MakePalette(P);
end;

procedure TCalcDisplay.HandleEvent(var Event: TEvent);
var S: string[3];
begin
  inherited HandleEvent(Event);
  case Event.What of
    evKeyDown:
      if Owner<>nil then
      if (Owner.State and sfSelected)<>0 then
      begin
        S:=Chr(Event.KeyDown.CharScan.CharCode);
        Message(Owner,evBroadcast,cmPressButton,@S);
        if CalcKey(Chr(Event.KeyDown.CharScan.CharCode)) then
        ClearEvent(Event);
      end;
    evBroadcast:
      if Event.Message.Command = cmCalcButton then
      begin
        CalcKey(PButton(Event.Message.InfoPtr).Title^);
        ClearEvent(Event);
      end;
  end;
end;

procedure TCalcDisplay.Store(S: TStream);
begin
  inherited Store(S);
  S.Write(Status, SizeOf(Status) + SizeOf(Number) + SizeOf(Sign) +
    SizeOf(_Operator) + SizeOf(Operand));
end;

{ TCalculator }

constructor TCalculator.Create;
const
  Keys: array[0..29] of string[4] =
   ('M+',  'x^y','C'  ,#27  ,'%'  ,'±'  ,
    'M-',  'x^2','7'  ,'8'  ,'9'  ,'/'  ,
    'M'#26,'1/x','4'  ,'5'  ,'6'  ,'*'  ,
    'M'#27,'sqrt','1'  ,'2'  ,'3'  ,'-'  ,
    'M'#29,'log','0'  ,'.'  ,'='  ,'+'  );
var
  I: Integer;
  P: PView;
  R: TRect;
begin
  R := TRect.Create(5, 3, 43, 18);
  inherited Create(R, dialog_Calculator);
  Options := Options or ofFirstClick or ofTopSelect;
  HelpCtx:=hcCalcWindow;

  for I := 0 to 29 do
  begin
    R.A.X := (I mod 6) * 5 + 2;
    R.A.Y := (I div 6) * 2 + 4;
    R.B.X := R.A.X + 5;
    R.B.Y := R.A.Y + 2;
    if (I mod 6)=0 then Inc(R.B.X,1) else
    if (I mod 6)=1 then begin R.Move(1,0); Inc(R.B.X,2) end else
    R.Move(3,0);
    P := TCalcButton.Create(R, Keys[I], cmCalcButton,
      bfNormal + bfBroadcast+bfGrabFocus);
    P.Options := P.Options {and not ofSelectable};
    Insert(P);
  end;
  R := TRect.Create(3, 2, 35, 3);
  CD := TCalcDisplay.Create(R);
  CD.Options:=CD.Options or ofSelectable;
  Insert(CD);
end;

procedure TCalculator.HandleEvent(var Event: TEvent);
var R: extended;
    CDEvent: TEvent;
{    Re: real;}
begin
  if (State and sfSelected)<>0 then
  case Event.What of
    evCommand :
     case Event.Message.Command of
       cmCalculatorPaste :
         begin
           MakeKeyEvent(CDEvent,kbCtrlEnter,0);
           HandleEvent(CDEvent);
         end;
     end;
    evKeyDown :
     case Event.KeyDown.KeyCode of
       kbEnter :
         begin
           Event.KeyDown.KeyCode:=0;
           Event.KeyDown.CharScan.CharCode:=Ord('=');
         end;
       kbCtrlEnter :
         begin
           ClearEvent(Event);
           CD.GetDisplay(R); {Re:=R;}
           Close;
           CalcClipboard:=R;
           Message(TProgram.Application,evBroadcast,cmCalculatorPaste,nil);
         end;
       kbEsc :
         begin
           CD.GetDisplay(R);
           if R<>0 then begin
                          CD.SetDisplay(0,false);
                          CD.DrawView;
                        end
                   else Close;
           ClearEvent(Event);
         end;
     end;
  end;
  { lets CD try to handle this }
  if Event.What=evKeyDown then
    begin
      { tv3: Message() fills Command, which is not the KeyCode of a key event: hand over a copy }
      CDEvent:=Event;
      CD.HandleEvent(CDEvent);
    end;
  inherited HandleEvent(Event);
end;

procedure TCalculator.Show;
begin
{  if GetState(sfVisible)=false then CD.Clear;}
  inherited Show;
end;

procedure TCalculator.Close;
begin
  Hide;
end;

constructor TCalculator.Load(S: TStream);
begin
  inherited Load(S);
  GetSubViewPtr(S,CD);
end;

procedure TCalculator.Store(S: TStream);
begin
  inherited Store(S);
  PutSubViewPtr(S,CD);
end;


{$ifndef NOOBJREG}
{ tv3 stream registration: factories + run-time record fill (see tools/fpide-streamrec-migrate.py) }
function Build_RCalcButton(S: TStream): TStreamable;
begin
  Result := TStreamable(Pointer(TCalcButton.Load(S)));
end;

procedure Store_RCalcButton(P: TStreamable; S: TStream);
begin
  TCalcButton(Pointer(P)).Store(S);
end;

function Build_RCalcDisplay(S: TStream): TStreamable;
begin
  Result := TStreamable(Pointer(TCalcDisplay.Load(S)));
end;

procedure Store_RCalcDisplay(P: TStreamable; S: TStream);
begin
  TCalcDisplay(Pointer(P)).Store(S);
end;

function Build_RCalculator(S: TStream): TStreamable;
begin
  Result := TStreamable(Pointer(TCalculator.Load(S)));
end;

procedure Store_RCalculator(P: TStreamable; S: TStream);
begin
  TCalculator(Pointer(P)).Store(S);
end;

procedure FillStreamRecs_fpcalc;
begin
  RCalcButton.ObjType := 10139;
  RCalcButton.VmtLink := PtrUInt(System.TClass(TCalcButton));
  RCalcButton.Load := @Build_RCalcButton;
  RCalcButton.Store := @Store_RCalcButton;
  RCalcButton.Next := nil;
  RCalcDisplay.ObjType := 10140;
  RCalcDisplay.VmtLink := PtrUInt(System.TClass(TCalcDisplay));
  RCalcDisplay.Load := @Build_RCalcDisplay;
  RCalcDisplay.Store := @Store_RCalcDisplay;
  RCalcDisplay.Next := nil;
  RCalculator.ObjType := 10141;
  RCalculator.VmtLink := PtrUInt(System.TClass(TCalculator));
  RCalculator.Load := @Build_RCalculator;
  RCalculator.Store := @Store_RCalculator;
  RCalculator.Next := nil;
end;

{$endif}

procedure RegisterFPCalc;
begin
{$ifndef NOOBJREG}
  FillStreamRecs_fpcalc;
  RegisterType(RCalcButton);
  RegisterType(RCalcDisplay);
  RegisterType(RCalculator);
{$endif}
end;

end.
