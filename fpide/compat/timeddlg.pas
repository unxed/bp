{ Timed dialogs for fpide on tv3 classes. Ported from FPC FV timeddlg. }
{$mode objfpc}{$H-}
{$modeswitch nestedprocvars}
unit timeddlg;

interface

uses
  Objects, Dialogs, FVConsts, Drivers, Views, MsgBox, App, Dos;

type
  TTimedDialog = class;
  PTimedDialog = TTimedDialog;
  TTimedDialog = class(TDialog)
    Secs: LongInt;
    constructor Create(var Bounds: TRect; ATitle: TTitleStr; ASecs: Word); reintroduce;
    function Read(Ip: ipstream): Pointer; override;
    procedure GetEvent(var Event: TEvent); override;
    procedure Write(Os: opstream); override;
  private
    Secs0: LongInt;
    Secs2: LongInt;
    DayWrap: Boolean;
  end;

  TTimedDialogText = class;
  PTimedDialogText = TTimedDialogText;
  TTimedDialogText = class(TStaticText)
    constructor Create(var Bounds: TRect); reintroduce;
    procedure GetText(var S: string); override;
  end;

function TimedMessageBox(const Msg: string; Params: Pointer;
  AOptions: Word; ASecs: Word): Word;
function TimedMessageBoxRect(var R: TRect; const Msg: string; Params: Pointer;
  AOptions: Word; ASecs: Word): Word;

implementation

constructor TTimedDialogText.Create(var Bounds: TRect);
begin
  inherited Create(Bounds, '');
end;

procedure TTimedDialogText.GetText(var S: string);
begin
  if Owner <> nil then
  begin
    Str(PTimedDialog(Owner).Secs, S);
    S := #3 + S;
  end
  else
    S := '';
end;

constructor TTimedDialog.Create(var Bounds: TRect; ATitle: TTitleStr; ASecs: Word);
var
  H, M, S, S100: Word;
begin
  inherited Create(Bounds, ATitle);
  GetTime(H, M, S, S100);
  Secs0 := H * 3600 + M * 60 + S;
  Secs2 := Secs0 + ASecs;
  Secs := ASecs;
  DayWrap := Secs2 > 24 * 3600;
end;

procedure TTimedDialog.GetEvent(var Event: TEvent);
var
  H, M, S, S100: Word;
  Secs1: LongInt;
begin
  inherited GetEvent(Event);
  GetTime(H, M, S, S100);
  Secs1 := H * 3600 + M * 60 + S;
  if DayWrap then
    Inc(Secs1, 24 * 3600);
  if Secs2 - Secs1 <> Secs then
  begin
    Secs := Secs2 - Secs1;
    if Secs < 0 then
      Secs := 0;
    Redraw;
  end;
  with Event do
    if (Secs = 0) and (What = evNothing) then
    begin
      What := evCommand;
      Message.Command := cmCancel;
    end;
end;

function TTimedDialog.Read(Ip: ipstream): Pointer;
begin
  Result := Self;
  inherited Read(Ip);
  Ip.ReadBytes(Secs, SizeOf(Secs));
  Ip.ReadBytes(Secs0, SizeOf(Secs0));
  Ip.ReadBytes(Secs2, SizeOf(Secs2));
  Ip.ReadBytes(DayWrap, SizeOf(DayWrap));
end;

procedure TTimedDialog.Write(Os: opstream);
begin
  inherited Write(Os);
  Os.WriteBytes(Secs, SizeOf(Secs));
  Os.WriteBytes(Secs0, SizeOf(Secs0));
  Os.WriteBytes(Secs2, SizeOf(Secs2));
  Os.WriteBytes(DayWrap, SizeOf(DayWrap));
end;

function BoxTitle(AOptions: Word): ShortString;
begin
  case AOptions and 3 of
    mfError: BoxTitle := MsgBoxText.ErrorText;
    mfInformation: BoxTitle := MsgBoxText.InformationText;
    mfConfirmation: BoxTitle := MsgBoxText.ConfirmText;
  else
    BoxTitle := MsgBoxText.WarningText;
  end;
end;

function TimedMessageBox(const Msg: string; Params: Pointer;
  AOptions: Word; ASecs: Word): Word;
var
  R: TRect;
begin
  R := TRect.Create(0, 0, 40, 10);
  if (AOptions and mfInsertInApp) = 0 then
    R.Move((TProgram.DeskTop.Size.X - R.B.X) div 2, (TProgram.DeskTop.Size.Y - R.B.Y) div 2)
  else
    R.Move((TProgram.Application.Size.X - R.B.X) div 2, (TProgram.Application.Size.Y - R.B.Y) div 2);
  TimedMessageBox := TimedMessageBoxRect(R, Msg, Params, AOptions, ASecs);
end;

function TimedMessageBoxRect(var R: TRect; const Msg: string; Params: Pointer;
  AOptions: Word; ASecs: Word): Word;
const
  Commands: array[0..3] of Word = (cmYes, cmNo, cmOK, cmCancel);
var
  Dlg: PTimedDialog;
  TimedText: PTimedDialogText;
  R2: TRect;
  I, X, ButtonCount: Integer;
  ButtonList: array[0..4] of TView;
  Names: array[0..3] of PShortString;
  Btn: TButton;
begin
  Names[0] := @MsgBoxText.YesText;
  Names[1] := @MsgBoxText.NoText;
  Names[2] := @MsgBoxText.OkText;
  Names[3] := @MsgBoxText.CancelText;
  Dlg := TTimedDialog.Create(R, BoxTitle(AOptions), ASecs);
  R2 := TRect.Create(3, Dlg.Size.Y - 5, Dlg.Size.X - 2, Dlg.Size.Y - 4);
  TimedText := TTimedDialogText.Create(R2);
  Dlg.Insert(TimedText);
  R2 := TRect.Create(3, 2, Dlg.Size.X - 2, Dlg.Size.Y - 5);
  Dlg.Insert(TStaticText.Create(R2, Msg));
  X := -2;
  ButtonCount := 0;
  for I := 0 to 3 do
    if (AOptions and ($0100 shl I)) <> 0 then
    begin
      R2 := TRect.Create(0, 0, 10, 2);
      Btn := TButton.Create(R2, Names[I]^, Commands[I], bfNormal);
      ButtonList[ButtonCount] := Btn;
      Inc(X, Btn.Size.X + 2);
      Inc(ButtonCount);
    end;
  X := (Dlg.Size.X - X) div 2;
  for I := 0 to ButtonCount - 1 do
  begin
    Dlg.Insert(ButtonList[I]);
    ButtonList[I].MoveTo(X, Dlg.Size.Y - 3);
    Inc(X, ButtonList[I].Size.X + 2);
  end;
  Dlg.SelectNext(False);
  TimedMessageBoxRect := TProgram.Application.ExecView(Dlg);
  Dlg.Free;
end;

end.
