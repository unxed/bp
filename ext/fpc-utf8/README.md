# fpc-utf8: UTF-8 Everywhere для Free Pascal

Идея: `string` всегда UTF-8, и всё работает из коробки, без правки исходников.

FPC 3.x уже умеет строки с кодовой страницей (`AnsiString(CP_UTF8)`), мешают только умолчания:
`string` = `ShortString` в режиме по умолчанию, кодировка строк берётся из локали,
на Unix нужен `cwstring`, на Windows консоль в OEM. Всё это чинится в одном месте:

- `utf8everywhere.pas`: модуль, который прячет `cwstring` внутрь себя, в `initialization`
  ставит `DefaultSystemCodePage`, `DefaultFileSystemCodePage`, `DefaultRTLFileSystemCodePage`
  и кодировку `Input/Output/StdErr` в `CP_UTF8` (на Windows ещё `SetConsoleOutputCP`).
  Плюс `for Ch in CodePoints(S)` (символ тоже `string`) и `CPLength(S)`.
- `utf8.cfg`: `-Mobjfpc -Sh -FaUTF8Everywhere`. Главный трюк: ключ `-Fa`
  заставляет компилятор вставить модуль первым в `uses` каждой программы.
  Строки из `utf8.cfg` можно дописать в системный `fpc.cfg`, и UTF-8 станет умолчанием вообще.

Сборка: `fpc @fpc-utf8/utf8.cfg -Fufpc-utf8 program.pas`.

Принцип: `Length(S)` и `S[i]` в байтах (как в Go и Rust). `Pos/Copy/Delete` на байтовых индексах
корректны, потому что UTF-8 самосинхронизируется. Символы нужны редко, для них `CodePoints`.

## Тесты

`test_utf8.pas` (модуль в нём не подключён, его вставляет `-Fa`): длины, `Pos/Copy`, конверсия в
`UnicodeString` и обратно, `AnsiUpperCase/AnsiLowerCase` кириллицы, `Format`, обход по символам
(включая эмодзи и обрезанный символ), файл с UTF-8 именем и UTF-8 содержимым, вывод в консоль.
Код возврата 0 = всё прошло. CI: `.github/workflows/ci.yml`, job `fpc-utf8` (Ubuntu, `fp-compiler` из apt).

## Статус и сомнительные места

- Итерация 1: код написан, локально не собирался; первая проверка в CI.
- Регистр букв (`AnsiUpperCase`) на Unix идёт через `towupper` из libc и зависит от локали:
  при `LANG=C` кириллица не поднимется. Тест гоняется под `C.UTF-8`. Вариант на будущее:
  настройка (define) для чистого паскалевского менеджера `fpwidestring` из rtl-unicode, без libc.
- Windows не проверен в CI. Известно, что `ParamStr` на Windows в FPC 3.2 может отдавать строки
  в ANSI-кодировке (в Lazarus для этого есть `ParamStrUTF8`), это следующая итерация.
- `-Fa` действует только на программы (не на модули и библиотеки). Для программы этого достаточно:
  `initialization` модуля отрабатывает до основного кода.

## Почему нет `-FcUTF8` (исправлено 2026-10-03)

Первая версия `utf8.cfg` содержала `-FcUTF8`. С ним строковые литералы становятся `UnicodeString` (кодовая страница 1200),
и `Pos('ве', S)` возвращает 0, а `Copy(S, Pos(...), MaxInt)` возвращает всю строку: тест падал в CI. Без ключа литералы
хранятся как байты с кодировкой `CP_ACP`, а она в рантайме равна `DefaultSystemCodePage` = UTF-8, и всё работает (так делает Lazarus).
