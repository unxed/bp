# fpide: Text Mode IDE на tv3

Перенос **Free Pascal Text Mode IDE** с **Free Vision** (`packages/fv`) на **[unxed/tv3](https://github.com/unxed/tv3)**:
UTF-8 внутри, модель **классов** вместо `object`/`New`/`Dispose`, те же цели сборки, что у DN (Linux x86_64 в первую очередь).

Образец процесса: репозиторий [`unxed/dn`](https://github.com/unxed/dn) (submodule `fpide/tv/` → tv3, shims, CI, приёмка «прокликиванием»).

| Каталог | Назначение |
|---|---|
| [`fpide/src/`](src/) | исходники IDE (база — FPC `packages/ide` @ 3.2.2) |
| [`fpide/bootstrap/`](bootstrap/) | pin FPC + fetch исходников `compiler/` — только для `FPIDE_EMBED=1` |
| [`fpide/compat/fpc/`](compat/fpc/) | несколько модулей компилятора FPC 3.2.2 (`globtype`, `systems`, `tokens`, …) — IDE нужны и без встроенного компилятора |
| [`compat/shims/`](compat/shims/) | карта имён Free Vision → tv3 (`tools/gen-shim.py`) |
| [`tv/`](tv/) | git submodule tv3 (отдельная лицензия; код не смешивается с `fpide/`) |
| [`tools/build-fpide.sh`](tools/build-fpide.sh) | сборка (локально можно не гонять тяжёлое — см. CI) |

План и вехи: [`PLAN.md`](PLAN.md). Текущий статус: [`MIGRATION-STATUS.md`](MIGRATION-STATUS.md).

## Локальный preflight (перед push)

Перед push: `fpide/tools/fpide-setup-build.sh test` (сборка ~15 с, тесты ~5 мин: `test_accept.py`, `test_functions.py` — прокликивание основных функций, включая отладчик, `test_menu_sweep.py`).
В логе сборки не должно быть предупреждений `An inherited method is hidden by ...` (потерянный `override`).

## Сборка

Нужны только Ubuntu/Debian с `apt` и git. Одной командой (ставит пакеты, берёт `fpide/tv/`, собирает, `test` — ещё и гоняет тесты):

```sh
git clone --recurse-submodules https://github.com/unxed/sp && cd sp
fpide/tools/fpide-setup-build.sh [test]     # результат: fpide/out/linux64/fp
```

Или вручную, если `fpc` (3.2.x), `gdb` и `tmux` уже стоят: `git submodule update --init fpide/tv && fpide/tools/build-fpide.sh`.
Цель определяется по текущей системе (сейчас — `linux64`); используется `fpc` из PATH (`FPC=/путь/к/fpc` — другой).

**Компилятор и отладчик внешние.** IDE запускает `fpc` и `gdb` из системы (как и остальные инструменты); компилятор ищется в PATH
автоматически. Другой — переменной `FP_COMPILER=/путь/к/fpc` или строкой `Compiler=` в секции `[Compile]` файла `fp.ini`
(`auto` — по умолчанию, путь, либо `builtin` для сборки с встроенным компилятором). Нескольких модулей компилятора, которые IDE
нужно знать сама (`globtype`, `systems`, `tokens`, `comphook`, …), хватает в `fpide/compat/fpc/` — из репозитория, ничего не скачивается.
Информации для браузера символов (Search > Objects/Modules/Globals/Symbol) внешний компилятор не даёт, поэтому браузер строится по исходникам: программа (или модуль) и найденные рядом используемые модули разбираются парсером FCL (`fcl-passrc`, `fpide/src/fpsrcbrw.pas`) — объявления, классы с предками, члены, процедуры с параметрами. Исходники читаются с диска при каждом открытии браузера.

`FPIDE_EMBED=1 fpide/tools/build-fpide.sh` — как в оригинале, со встроенным компилятором FPC (качает исходники `compiler/` FPC 3.2.2, ~400 МБ;
результат — `fpide/out/linux64-embed/fp`).

Переменные: `FPIDE_TV=/path/to/tv3`, `FPIDE_GDBMI=1` (по умолчанию), `FPIDE_NOGDB=1` — без отладчика, `FPIDE_EXTRA` — доп. флаги FPC.

## Приёмка

Полное совпадение с ванильной IDE после тех же действий: **текст, цвет, фон** (и прочие атрибуты экрана) — побитово, с поправкой только на различие кодировок (ванilla CP866/OEM vs наш UTF-8). Автоматизация — по аналогии с `tools/dn-linux-accept.py` в dn; workflow `.github/workflows/fpide-accept.yml` (ещё в работе).
