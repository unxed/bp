function NewMenu(Items: PMenuItem): PMenu;
begin
  Result := TMenu.Create(Items);
end;

function NewSubMenu(const Name: ShortString; AHelpCtx: Word; SubMenu: PMenu; Next: PMenuItem): PMenuItem;
begin
  Result := TMenuItem.Create(Name, kbNoKey, SubMenu, AHelpCtx, Next);
end;

function NewItem(const Name, Param: ShortString; AKeyCode, ACommand, AHelpCtx: Word; Next: PMenuItem): PMenuItem;
begin
  Result := TMenuItem.Create(Name, ACommand, AKeyCode, AHelpCtx, Param, Next);
end;

function NewLine(Next: PMenuItem): PMenuItem;
begin
  Result := TMenuItem.Create('', 0, kbNoKey, hcNoContext, '', Next);
end;

procedure DisposeMenu(Menu: PMenu);
begin
  Menu.Free;
end;

function NewStatusKey(const AText: ShortString; AKeyCode, ACommand: Word; ANext: PStatusItem): PStatusItem;
begin
  Result := TStatusItem.Create(AText, AKeyCode, ACommand, ANext);
end;

function NewStatusDef(AMin, AMax: Word; AItems: PStatusItem; ANext: PStatusDef): PStatusDef;
begin
  Result := TStatusDef.Create(AMin, AMax, AItems, ANext);
end;


function StdStatusKeys(ANext: PStatusItem): PStatusItem;
begin
  StdStatusKeys :=
    NewStatusKey('', kbAltX, cmQuit,
    NewStatusKey('', kbF10, cmMenu,
    NewStatusKey('', kbAltF3, cmClose,
    NewStatusKey('', kbF5, cmZoom,
    NewStatusKey('', kbCtrlF5, cmResize,
    NewStatusKey('', kbF6, cmNext,
    NewStatusKey('', kbShiftF6, cmPrev, ANext)))))));
end;
