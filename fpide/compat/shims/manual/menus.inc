{ Class types in tv3: PFoo aliases that Free Vision kept as ^TFoo. }
type
  PMenuView   = TMenuView;
  PMenuBar    = TMenuBar;
  PMenuBox    = TMenuBox;
  PMenuPopup  = TMenuPopup;
  PStatusLine = TStatusLine;

{ FV standard status line keys: Alt-X, F10, Alt-F3, F5, Ctrl-F5, F6, Shift-F6 (no text, so they are only keys). }
function StdStatusKeys(ANext: PStatusItem): PStatusItem;
