{
    This file is part of the Free Pascal Integrated Development Environment
    Copyright (c) 1998 by Berczi Gabor

    Compiler menu entries

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}

procedure TIDEApp.Target;
var R,R2: TRect;
    D: PCenterDialog;
    RB: PRadioButtons;
    TargetCount,I: integer;
    LastItem: TSItem;
    L: longint;
begin
  TargetCount:=TargetSwitches.ItemCount;
  R := TRect.Create(0, 0, 60, 4+TargetCount);
  D := TCenterDialog.Create(R, dialog_target);
  with D do
  begin
    HelpCtx:=hcTarget;
    R := GetExtent; R.Grow(-3,-1); Inc(R.A.Y);
    R2 := R; Inc(R2.A.Y); R2.B.Y:=R2.A.Y+TargetCount;
    LastItem:=nil;
    for I:=TargetCount-1 downto 0 do
      LastItem:=TSItem.Create(TargetSwitches.ItemName(I), LastItem);
    RB := TRadioButtons.Create(R2, LastItem);
    L:=ord(TargetSwitches.GetCurrSel);
    RB.SetData(L);
    Insert(RB);
    R2 := R;
    R2.B.Y:=R2.A.Y+1;
    Insert(TLabel.Create(R2, label_target_platform, RB));
  end;
  InsertButtons(D);
  RB.Select;
  if Desktop.ExecView(D)=cmOK then
    begin
       TargetSwitches.SetCurrSel(RB.Value);
       { we allways need to recompile if we change
         the target OS PM }
       if L<>RB.Value then
         PrevMainFile:='';
       UpdateTarget;
    end;
  D.Free;
end;

procedure TIDEApp.UpdateTarget;
var TargetMenu : PMenuItem;
begin
  TargetMenu:=PAdvancedMenuBar(MenuBar).GetMenuItem(cmTarget);
  if assigned(TargetMenu) then
    begin
      If assigned(TargetMenu.Param) then
        DisposeStr(TargetMenu.Param);
      TargetMenu.Param:=NewStr(StripTilde(TargetSwitches.ItemName(TargetSwitches.GetCurrSel)));
    end;
end;

procedure TIDEApp.UpdateMode;
var ModeMenu : PMenuItem;
begin
  ModeMenu:=PAdvancedMenuBar(MenuBar).GetMenuItem(cmSwitchesMode);
  if assigned(ModeMenu) then
    begin
      If assigned(ModeMenu.Param) then
        DisposeStr(ModeMenu.Param);
      ModeMenu.Param:=NewStr(StripTilde(SwitchesModeName[SwitchesMode]));
    end;
end;

procedure TIDEApp.DoPrimaryFile;
var
  D : PFileDialog;
  FileName : string;
begin
  D := TFileDialog.Create('*.pri;*.pas',label_primaryfile_primaryfile,'*.pri;*.pas',fdOpenButton,hidPrimaryFile);
  D.HelpCtx:=hcPrimaryFile;
  if Desktop.ExecView(D)<>cmCancel then
  begin
    FileName := D.GetFileName;
    SetPrimaryFile(FileName);
    UpdatePrimaryFile;
  end;
end;


procedure TIDEApp.DoClearPrimary;
begin
  PrimaryFile:='';
  PrimaryFileMain:='';
  PrimaryFileSwitches:='';
  PrimaryFilePara:='';
  UpdatePrimaryFile;
end;


procedure TIDEApp.DoCompilerMessages;
begin
  if not CompilerMessageWindow.GetState(sfVisible) then
   CompilerMessageWindow.Show;
  CompilerMessageWindow.MakeFirst;
end;

