# Safe Pascal

Безопасный по умолчанию Free Pascal: один файл `safe.pas` + `uses Safe` последним в каждом модуле.
Без форка FPC и без опций компилятора. Спецификация (её можно прикладывать к промпту): [SPEC.md](SPEC.md).

| Файл | Что это |
|---|---|
| `SPEC.md` | спецификация; §0 — карточка правил, §13 FFI, §14 горутины, §15–16 план: зависимости как в Go, инструмент `sp`, что ещё взять у Go/Rust |
| `safe.pas` | вся библиотека: UTF-8, TOwned/TShared/TWeak/TSlice/TArena, TDefer, горутины (TGroup/TTask/TChan/Select), FFI (TCResource), отравление опасных примитивов |
| `tests/test_safe.pas` | рантайм-тесты владения, слайсов, арены, defer, UTF-8 |
| `safethreads.pas` | менеджер потоков без libc для Linux (clone/futex/mmap); первым в uses программы |
| `tests/test_threads.pas` | нагрузочный тест потоков |
| `tests/test_go.pas` | горутины, каналы, select, отмена, структурное ожидание |
| `tests/test_sumtype.pas` | образец типа-суммы из SPEC §16 |
| `tests/test_ffi.pas`, `tests/ffi_libc.pas` | FFI: образец модуля обвязки libc и тест |
| `tests/compile/mf_*.pas` | проверки компиляции: опасное не собирается/предупреждает, `System.X` собирается |
| `tests/run.sh` | прогон всего (копирует файлы в одну папку и вызывает голый `fpc`) |
| `DN-ADOPTION.md` | план перевода DOS Navigator (`unxed/dn`) на Safe Pascal: этапы S0–S10, замеры, сомнения |
| `fpc-utf8/` | отдельный вариант «только UTF-8» (`utf8everywhere.pas`, `utf8.cfg`, тест), см. `fpc-utf8/README.md` |
| [`fpide/`](fpide/README.md) | перенос **Text Mode IDE** FPC с Free Vision на [tv3](https://github.com/unxed/tv3) (UTF-8, classes); сборка в CI [`fpide.yml`](.github/workflows/fpide.yml) |
| `tv/` | submodule [unxed/tv3](https://github.com/unxed/tv3) для `fpide/` |
| `.github/workflows/ci.yml` | CI: Ubuntu, `fp-compiler` из apt; job `fpc-utf8` и задания Safe Pascal |

Связь с `fpc-utf8/` (лежит в этом же репозитории, перенесён из `unxed/sandbox` с историей): UTF-8-часть оттуда встроена в `safe.pas`,
но подключается не через `-Fa` и конфиг, а через `uses Safe`, который и так есть в каждом модуле.
`fpc-utf8` остаётся вариантом «только UTF-8» для кода, который не переходит на Safe Pascal.

## Статус

Итерация 1: код написан, первый прогон workflow `ci` зелёный (гипотезы затенения подтвердились).
Итерация 2 (v0.2, идеи из Zig, SPEC §12): `TDefer`, `SafeLiveCount`/`SafeCheckNoLeaks` (R5), раздел «уроки практики» по порту DOS Navigator (`object` против `class`). Проверка — тот же workflow.
Итерация 3 (v0.3): горутины (SPEC §14) и FFI (SPEC §13). Собрано и прогнано локально (FPC 3.2.2, Linux): все тесты зелёные, `test_go` 30 прогонов подряд без сбоев. Найдено: `cthreads` нельзя спрятать в `Safe` (должен инициализироваться раньше SysUtils), поэтому для горутин одна строка в файле программы (с v0.5 — `SafeThreads`, §18), иначе R8.
Итерация 4 (v0.3.1): проверка на целях `unxed/dn` (x86_64, i386 и aarch64 Linux статически, DOS go32v2, Windows): таблица в SPEC §2; на DOS `TGroup.Go` бросает R8 вместо зависания.
Итерация 5 (v0.5): Linux без libc по умолчанию (свои потоки на `clone`/`futex`, `fpwidestring`), `-dSAFE_LIBC` для FFI; `-dSAFE_NO_CWSTRING` больше не нужен для статических сборок. Что реализовано и что только план: SPEC, «Что реально есть, а что пока только план».

## Гипотезы первого прогона CI (исторический раздел, все подтверждены)

1. Тип-заглушка с именем `GetMem/New/Move/...` в модуле, стоящем последним в `uses`, закрывает
   процедуру/интринсик System, и вызов даёт ошибку компиляции с текстом `deprecated` (`SAFE-S1`).
   Особенно сомнительны интринсики `New/Dispose`.
2. `deprecated` допустим на объявлении синонима типа (`Pointer = System.Pointer deprecated '...'`).
3. Хелпер `TObject` с методом `Free(const X: <тип-заглушка>)` перекрывает `TObject.Free`: `Obj.Free` — ошибка компиляции (подтверждено, `tests/compile/mf_free.pas`).
4. Внутри обобщённой записи её имя без параметров (`TOwned`) обозначает текущую специализацию.
5. Тела обобщений, специализируемые в модуле пользователя, видят private-поля и интерфейсные
   символы `Safe` и не задевают отравленные имена.
6. `specialize TArray<T>` из System доступен в FPC 3.2.2.

Если что-то из этого не подтвердится — запасные варианты: (1) обычная процедура с `deprecated` и
`{$WARN SYMBOL_DEPRECATED ERROR}`; (2,3) только линтер; (4) вложенный синоним типа.

## Сомнительные решения (зафиксированы, к обсуждению)

- `TOwned` на счётчике ссылок, уникальность — контракт линтера (обоснование: SPEC §4).
- `Free` отравлен только предупреждением: ошибкой его сделать без опций нельзя.
- `Safe` меняет глобальные кодировки в `initialization`; выключается `-dSAFE_NO_UTF8`.
- Лицензия: **MIT** (файл `LICENSE`; решение владельца 2026-10-03). Она совместима с переносом в FPC/Lazarus: код можно взять в RTL под её modified LGPL, ничего не меняя у нас.

## Следующие итерации

Линтер на `fcl-passrc` (правила S3–S10), пакет Lazarus для OPM, Windows в CI, GC-куча (SPEC §11).
