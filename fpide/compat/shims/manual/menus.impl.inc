
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
