{ Names Free Vision exposed via Views; PFoo aliases for tv3 classes. }
type
  TPalette = TvViews.TPalette;
  TCommandSet = TvViews.TCommandSet;
  TTitleStr   = ShortString;
  PView       = TView;
  PGroup      = TGroup;
  PFrame      = TFrame;
  PScrollBar  = TScrollBar;
  PScroller   = TScroller;
  PWindow     = TWindow;

{ Free Vision phases of the focus chain (TGroup.Phase). }
type
  TPhaseType = TvViews.TPhaseType;
const
  phFocused     = TvViews.phFocused;
  phPreProcess  = TvViews.phPreProcess;
  phPostProcess = TvViews.phPostProcess;
