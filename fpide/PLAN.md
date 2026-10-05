# fpide: Text Mode IDE на Free Pascal + tv3

Цель: **Text Mode IDE** из дистрибутива FPC (`packages/ide`), собранный на **[unxed/tv3](https://github.com/unxed/tv3)** вместо **Free Vision**, с **UTF-8** и переходом **`object` → `class`**, с поведением, неотличимым от ванильной IDE на экране (после учёта кодировок).

**Приоритет:** полностью перенести, **не сломав никакой функционал**. Цель «быстрее собрать / зелёный CI пораньше» **не стоит**. Нельзя ради линковки отключать компилятор, отладчик, редактор, справку и т.п., заглушать их или сужать продукт до «сначала только UI». Неполный порт с падающей сборкой допустим; урезанный «успешный» порт — нет.

Как работаем (как в `unxed/dn`): коммиты в **`main`**, тяжёлая сборка и тесты — **GitHub Actions**, submodule `tv/` указывает на tv3. Перед push — локальный `tools/fpide-preflight.sh`.

## Источники

| Что | Где |
|---|---|
| IDE | FPC `packages/ide`, тег `release_3_2_2` — [`fpide/bootstrap/upstream.env`](bootstrap/upstream.env) |
| Компилятор (обязательно) | тот же тег FPC, дерево `compiler/` (`FInput`, `Compiler`, `systems`, `globtype`, …) — то, ради чего IDE существует |
| UI (замена FV) | [unxed/tv3](https://github.com/unxed/tv3), submodule `tv/` |
| Эталон поведения | бинарник IDE из того же FPC 3.2.x (`fp` / `fpide`) на Linux, сравнение дампов экрана |
| Образец переноса | [unxed/dn](https://github.com/unxed/dn): shims, `tools/build.sh`, `dn-accept`, class migration |

Free Vision в репозиторий **не** копируем: имена юнитов FV (`Views`, `App`, …) закрываются **shim-юнитами**, генерируемыми из tv3 (`tools/gen-shim.py`, карта `fpide/compat/shims/shims.map`).

Юниты **компилятора не заглушаем и не выкидываем** ради «сначала только UI». Порт без встроенного компилятора — не этот продукт. Их подключаем из официального `compiler/` того же `FPC_COMMIT`, что и `packages/ide` (bootstrap расширяется; provenance как у IDE).

## Решения

1. **Два независимых дерева:** `tv/` не знает о `fpide/`; `fpide/` использует tv3 только как пакет. Проверяет `tools/check-fpide-layout.sh`.
2. **База IDE — публичный FPC 3.2.2**, воспроизводимая через `fpide/bootstrap/run.sh`; дальше — обычные коммиты в `fpide/src`.
3. **Компилятор — настоящий `compiler/` FPC**, тот же тег/коммит. Заглушки запрещены. **В git не кладём** — только pin в `upstream.env` и `fpide/bootstrap/ensure-compiler.sh` → `build/…/staging-compiler`.
4. **UTF-8** — как в tv3/DN: строки и ресурсы IDE переводим на UTF-8; на экране сравниваем с ванилью через нормализацию кодировок в тестах приёмки.
5. **Классы** — по тому же плану, что DN (`CLASS-MIGRATION.md` в dn): alias-ы, поля, `New`/`Done`, затем ресурсы и редакторские юниты.
6. **Отладчик** — как у апстрима FPC IDE на Linux: по умолчанию **GDB/MI** (`-dGDBMI`). `FPIDE_NOGDB=1` только как явный override, не цель порта.
7. **CI** — полная сборка `linux64` на `ubuntu-24.04`; локально — `tools/fpide-preflight.sh` перед push.

## Вехи

| # | Содержание | Критерий готовности |
|---|---|---|
| 0 | Каркас репо, bootstrap, submodule tv3, CI «попытка сборки» | зелёный bootstrap-check; submodule и layout |
| 1 | Shims FV→tv3 + **реальный `compiler/`** в unit path; `fp.pas` линкуется (linux64, GDB/MI) | `fp` в CI; компилятор и отладчик — настоящие, не stubs |
| 2 | Минимальный запуск: меню, статусная строка, выход | pty-скриншот совпадает с ванилью |
| 3 | Редактор, диалоги открытия/сохранения | сценарии приёмки |
| 4 | Компиляция из IDE (уже на настоящем компиляторе), сообщения, справка | сценарии приёмки |
| 5 | Class migration завершена | без `object`-иерархии TV в fpide |
| 6 | Полная приёмка (все пункты меню, горячие клавиши) | `fpide-accept` побитово vs vanilla |

## Открыто

- Точная карта shim для юнитов IDE (`WEditor`, `Tabs`, …) — часть FV, часть только IDE.
- Ресурсы `.tdf`/`.term` и кодировки строк в `fp*.pas`.
- Параллель с Safe Pascal (`safe.pas` в корне sp) — **не** блокирует fpide; возможная интеграция позже.
