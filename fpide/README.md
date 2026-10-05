# fpide: Text Mode IDE на tv3

Перенос **Free Pascal Text Mode IDE** с **Free Vision** (`packages/fv`) на **[unxed/tv3](https://github.com/unxed/tv3)**:
UTF-8 внутри, модель **классов** вместо `object`/`New`/`Dispose`, те же цели сборки, что у DN (Linux x86_64 в первую очередь).

Образец процесса: репозиторий [`unxed/dn`](https://github.com/unxed/dn) (submodule `tv/` → tv3, shims, CI, приёмка «прокликиванием»).

| Каталог | Назначение |
|---|---|
| [`fpide/src/`](src/) | исходники IDE (база — FPC `packages/ide` @ 3.2.2) |
| [`fpide/bootstrap/`](bootstrap/) | pin FPC + fetch; **compiler/** не в git — в `build/…/staging-compiler` |
| [`fpide/compat/shims/`](compat/shims/) | карта имён Free Vision → tv3 (`tools/gen-shim.py`) |
| [`tv/`](../tv/) | git submodule tv3 (отдельная лицензия; код не смешивается с `fpide/`) |
| [`tools/build-fpide.sh`](../tools/build-fpide.sh) | сборка (локально можно не гонять тяжёлое — см. CI) |

План и вехи: [`PLAN.md`](PLAN.md). Текущий статус: [`MIGRATION-STATUS.md`](MIGRATION-STATUS.md).

## Локальный preflight (перед push)

Тяжёлую сборку IDE гоняем в CI только по `workflow_dispatch`. Перед push в `main`:

```sh
git submodule update --init tv
tools/fpide-preflight.sh              # layout + shims + smoke-link; fp — информационно
```

## Сборка (когда порт дойдёт до линковки)

```sh
git submodule update --init tv
tools/build-fpide.sh linux64          # результат: out/fpide/linux64/fp
```

Переменные: `FPIDE_TV=/path/to/tv3`, `FPIDE_GDBMI=1` (по умолчанию, как апстрим на Linux), `FPIDE_NOGDB=1` — только явный отказ от отладчика, `FPIDE_EXTRA` — доп. флаги FPC.

## Приёмка

Полное совпадение с ванильной IDE после тех же действий: **текст, цвет, фон** (и прочие атрибуты экрана) — побитово, с поправкой только на различие кодировок (ванilla CP866/OEM vs наш UTF-8). Автоматизация — по аналогии с `tools/dn-linux-accept.py` в dn; workflow `.github/workflows/fpide-accept.yml` (ещё в работе).
