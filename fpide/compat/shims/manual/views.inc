{ Names Free Vision exposed via Views; PFoo aliases for tv3 classes. }
type
  { the command set of the Pascal API: a set of the commands 0..255 (CommandSetOf gives the TCommandSet of tv/) }
  TCommandBytes = set of Byte;
  TTitleStr   = ShortString;
  PView       = TView;
  PGroup      = TGroup;
  PFrame      = TFrame;
  PScrollBar  = TScrollBar;
  PScroller   = TScroller;
  PWindow     = TWindow;

{ Free Vision phases of the focus chain (TGroup.Phase). }
type
  TPhaseType = TvViews.TView.PhaseType;
const
  phFocused     = TvViews.TView.PhaseType.phFocused;
  phPreProcess  = TvViews.TView.PhaseType.phPreProcess;
  phPostProcess = TvViews.TView.PhaseType.phPostProcess;

function CommandSetOf(const Commands: TCommandBytes): TCommandSet;

{ the palette of the Pascal API: a string of color indices (TPalette.Create of tv/), and the number of its entries }
function MakePalette(const S: ShortString): TPalette;
function PaletteSize(const P: TPalette): Integer;
