# fpide: Text Mode IDE на Free Pascal + tv3

Цель: **Text Mode IDE** из дистрибутива FPC (`packages/ide`), собранный на **[unxed/tv3](https://github.com/unxed/tv3)** вместо **Free Vision**, с **UTF-8** и переходом **`object` → `class`**, с поведением, неотличимым от ванильной IDE на экране (после учёта кодировок).

**Приоритет:** полностью перенести, **не сломав никакой функционал**. Нельзя ради линковки заглушать компилятор, отладчик, редактор, справку или сужать продукт до «только UI». **Решение владельца (2026-10-06):** компилятор и отладчик — **внешние программы** системы (`fpc`, `gdb`), IDE запускает их сама; встроенный компилятор FPC остаётся опцией (`FPIDE_EMBED=1`). Сборка — одной командой на Ubuntu (`tools/fpide-setup-build.sh`), без скачивания исходников FPC.

Как работаем (как в `unxed/dn`): коммиты в **`main`**, тяжёлая сборка и тесты — **GitHub Actions**, submodule `tv/` указывает на tv3. Перед push — локальный `tools/fpide-preflight.sh`.

## Источники

| Что | Где |
|---|---|
| IDE | FPC `packages/ide`, тег `release_3_2_2` — [`fpide/bootstrap/upstream.env`](bootstrap/upstream.env) |
| Компилятор | системный `fpc` (внешний); несколько модулей компилятора, которые нужны самой IDE, лежат в [`compat/fpc`](compat/fpc). Встроенный вариант (`FPIDE_EMBED=1`): дерево `compiler/` того же тега FPC |
| UI (замена FV) | [unxed/tv3](https://github.com/unxed/tv3), submodule `tv/` |
| Эталон поведения | бинарник IDE из того же FPC 3.2.x (`fp` / `fpide`) на Linux, сравнение дампов экрана |
| Образец переноса | [unxed/dn](https://github.com/unxed/dn): shims, `tools/build.sh`, `dn-accept`, class migration |

Free Vision в репозиторий **не** копируем: имена юнитов FV (`Views`, `App`, …) закрываются **shim-юнитами**, генерируемыми из tv3 (`tools/gen-shim.py`, карта `fpide/compat/shims/shims.map`).

Компиляция из IDE идёт через внешний `fpc` (разбор вывода, переход к ошибкам, сообщения); отладка — через `gdb` (GDB/MI), у отлаживаемой программы свой pty. Браузер символов строится по исходникам парсером FCL (`fpsrcbrw.pas`).

## Решения

1. **Два независимых дерева:** `tv/` не знает о `fpide/`; `fpide/` использует tv3 только как пакет. Проверяет `tools/check-fpide-layout.sh`.
2. **База IDE — публичный FPC 3.2.2**, воспроизводимая через `fpide/bootstrap/run.sh`; дальше — обычные коммиты в `fpide/src`.
3. **Компилятор — внешний `fpc`** (автоопределение; `FP_COMPILER`/`fp.ini` для другого). Встроенный `compiler/` FPC — только для `FPIDE_EMBED=1`; в git не кладём (pin в `upstream.env`, `fpide/bootstrap/ensure-compiler.sh`).
4. **UTF-8** — как в tv3/DN: исходники, строки и ресурсы IDE в UTF-8; редактор открывает, правит и сохраняет UTF-8 (столбец = символ, широкие символы в две ячейки); однобайтовый режим только для DOS.
5. **Классы** — по тому же плану, что DN (`CLASS-MIGRATION.md` в dn): alias-ы, поля, `New`/`Done`, затем ресурсы и редакторские юниты.
6. **Отладчик** — как у апстрима FPC IDE на Linux: по умолчанию **GDB/MI** (`-dGDBMI`). `FPIDE_NOGDB=1` только как явный override, не цель порта.
7. **CI** — `ubuntu-24.04`: сборка и приёмка (`fpide-accept.yml`: `test_accept.py`, `test_functions.py`, `test_menu_sweep.py`); локально — `tools/fpide-setup-build.sh test`.

## Вехи

| # | Содержание | Критерий готовности |
|---|---|---|
| 0 | Каркас репо, submodule tv3, CI | сделано |
| 1 | Shims FV→tv3; `fp.pas` линкуется (linux64, GDB/MI, внешний fpc/gdb) | сделано |
| 2 | Запуск: меню, статусная строка, выход | сделано (`test_accept.py`, `test_functions.py`) |
| 3 | Редактор (UTF-8), диалоги открытия/сохранения, буфер обмена, мышь | сделано |
| 4 | Компиляция из IDE (внешний fpc), сообщения, запуск, отладчик (gdb), браузер символов | сделано; справка — файлы CHM не поставляются (как в оригинале) |
| 5 | Class migration | сделано для fpide |
| 6 | Полная приёмка (все пункты меню, горячие клавиши) | пункты меню проходят `test_menu_sweep.py`, функции — `test_functions.py`; сравнение с ванильной IDE побитово — открыто |

## Открыто

- Точная карта shim для юнитов IDE (`WEditor`, `Tabs`, …) — часть FV, часть только IDE.
- Справка IDE (CHM) и просмотр справки (`whlpview`, счёт по байтам).
- Параллель с Better Pascal (`bp.pas`, `safe/`, `ext/` в корне репозитория) — **не** блокирует fpide; возможная интеграция позже.

## Другие языки (этап 7)

Сделано: `src/fplang.pas` — класс-бэкенд языка (инструмент, аргументы, разбор вывода, отладчик); первым идёт **Go**: Compile (go vet),
Make/Build (`go build`, в модуле собирается пакет файла), Run (запуск собранного), Compile > Test (`go test`); ошибки с позицией
попадают в окно Compiler Messages, Enter переходит на строку. Юнит-тест `tests/unit/t_fplang.pas`, приёмка `test_functions.py <fp> golang`.
Подсветка `.go` — грамматика `lang-go.hl` из tve.

Готово: шаблон нового файла Go (File > Open несуществующего `.go` — `NewFileText`), Tools > Format Go file (`gofmt -w`, тихая перезагрузка `ReloadSilently`).
Готово (первый срез): отладчик Go — Delve. `src/fpdlv.pas` — клиент DAP к `dlv dap` (TCP на localhost, mode `debug`: dlv сам собирает программу с `-N -l`),
`src/fpgodbg.pas` — связка с меню Run: Run при точке останова в `.go` (или F7/F8 без сессии — остановка в `main.main`), F8 step over, F7 trace into,
Alt+F4 step out, F4 run to cursor, Continue, Program reset; точки останова из списка IDE (Ctrl+F8) передаются dlv перед каждым запуском; строка остановки
подсвечивается как debugger row; в конце — окно с кодом выхода и последними строками вывода программы. Юнит-тест `tests/unit/t_fpdlv.pas`
(настоящий dlv, пропускается без dlv/go), приёмка `test_functions.py <fp> debuggo`.
Не сделано для Go: окна Watches/Call stack/Registers/Evaluate (только gdb), условия и ignore-счётчики точек останова, ввод с клавиатуры в отлаживаемую
программу (stdin закрыт), вывод программы показывается по завершении, а не вживую; Delve проверен версией 1.25.2 с Go 1.24 (dlv 1.27 требует более новый Go); ошибки сборки программы попадают в окно Compiler Messages.
Другие языки в задание не входили: класс `TLangBackend` готов, но новых языков не добавляем без отдельного запроса.
