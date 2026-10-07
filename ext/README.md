# ext/ — надстройки над Free Pascal

Слой 2 из трёх в Better Pascal. Не про безопасность памяти, а про удобство: то, чего не хватает FPC «из коробки».

| Часть | Файлы | Что даёт |
|---|---|---|
| UTF-8 по умолчанию | `utf8.intf.inc`, `utf8.impl.inc`, `utf8.init.inc` | `String` = UTF-8, имена файлов и консоль в UTF-8, `CodePoints`, `CPLength`; выключается `-dSAFE_NO_UTF8` |
| Горутины | `go.intf.inc`, `go.impl.inc` | `TGroup`/`TTask` (структурная конкурентность), `TChan<T>`, `Select` (SPEC §14) |
| Потоки | `bpthreads.pas` | менеджер потоков без libc для Linux (clone/futex/mmap), `cthreads` на остальных Unix; DOS: пусто |
| UTF-8 для чужого кода | `fpc-utf8/` | отдельный вариант «только UTF-8» через `-Fa` и конфиг, без `BP` (перенесён из `unxed/sandbox`) |

Слой использует ядро `safe/` (`ESafety`, счётчики отказов), но `safe/` о нём ничего не знает.
В код программы он попадает через `unit BP` (`../bp.pas`), который включает эти `.inc` вместе с `safe/*.inc`.

Тесты — `tests/ext/` (`test_utf8`, `test_go`, `test_threads`, `compile/mf_*`).
