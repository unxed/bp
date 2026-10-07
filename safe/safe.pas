{ SPDX-License-Identifier: MIT }
{ Safe Pascal v0.1 — безопасный по умолчанию Free Pascal (только слой «safe»).
  Спецификация: SPEC.md. Подключение: `uses ..., Safe;` ПОСЛЕДНИМ в каждом модуле.
  Опции компилятора не нужны.

  Что делает модуль (и только это):
  - TOwned/TShared/TWeak/TSlice/TArena, TDefer, FFI (TCResource), счётчик утечек (SPEC §4–5, §13);
  - "отравляет" опасные примитивы затенением имён (SPEC §6): GetMem(...) в модуле,
    где Safe последний в uses, не скомпилируется. Полное имя (System.GetMem) — явный unsafe.

  UTF-8 по умолчанию и горутины сюда не входят: они в ext/, а всё вместе — unit BP (bp.pas).
  Исходники слоя — include-файлы safe/*.inc: те же файлы собираются в unit BP. }
unit Safe;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}
{$define BP_LAYER_SAFE}

interface

uses
  SysUtils;

{$I core.intf.inc}
{$I poison.intf.inc}

implementation

{$I core.impl.inc}
{$I poison.impl.inc}

end.
