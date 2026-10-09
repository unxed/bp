{ Class types in tv3: PFoo aliases that Free Vision kept as ^TFoo. }
type
  PMenuView   = TMenuView;
  PMenuBar    = TMenuBar;
  PMenuBox    = TMenuBox;
  PMenuPopup  = TMenuPopup;
  PStatusLine = TStatusLine;
  PMenu       = TMenu;
  PMenuItem   = TMenuItem;
  PStatusItem = TStatusItem;
  PStatusDef  = TStatusDef;

{ The menus and the status line of the Pascal API, built by functions (the classes of tv/ with their constructors). }
function NewMenu(Items: PMenuItem): PMenu;
function NewSubMenu(const Name: ShortString; AHelpCtx: Word; SubMenu: PMenu; Next: PMenuItem): PMenuItem;
function NewItem(const Name, Param: ShortString; AKeyCode, ACommand, AHelpCtx: Word; Next: PMenuItem): PMenuItem;
function NewLine(Next: PMenuItem): PMenuItem;
procedure DisposeMenu(Menu: PMenu);
function NewStatusKey(const AText: ShortString; AKeyCode, ACommand: Word; ANext: PStatusItem): PStatusItem;
function NewStatusDef(AMin, AMax: Word; AItems: PStatusItem; ANext: PStatusDef): PStatusDef;

{ FV standard status line keys: Alt-X, F10, Alt-F3, F5, Ctrl-F5, F6, Shift-F6 (no text, so they are only keys). }
function StdStatusKeys(ANext: PStatusItem): PStatusItem;
