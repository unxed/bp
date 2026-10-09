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
  TPhaseType = TvViews.TView.PhaseType;
const
  phFocused     = TvViews.TView.PhaseType.phFocused;
  phPreProcess  = TvViews.TView.PhaseType.phPreProcess;
  phPostProcess = TvViews.TView.PhaseType.phPostProcess;
