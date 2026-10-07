# Better Pascal (bp)

Free Pascal, каким его хотелось бы получить по умолчанию: безопасная память, UTF-8 везде, горутины.
Без форка FPC и без опций компилятора: один юнит `BP`.

```pascal
program Hello;
uses BP, SysUtils;   // BP — ПЕРВЫМ в основной программе (он ставит менеджер потоков до SysUtils)
begin
  WriteLn('Привет, мир 😀', CPLength('aё😀'));
end.
```

В остальных юнитах `BP` пишется **последним** в `uses`: так он затеняет опасные примитивы (`GetMem(...)` не скомпилируется,
`System.GetMem` — явный unsafe). Компилятору нужен путь к каталогу с `bp.pas`: `fpc -Fu<путь> -Fu<путь>/safe -Fu<путь>/ext`.

## Три части репозитория

| Каталог | Часть | Зависит от |
|---|---|---|
| [`safe/`](safe/README.md) | **Safe Pascal**: memory safety (владение, срезы, арена, defer, FFI, отравление опасного) | ничего |
| [`ext/`](ext/README.md) | **Надстройки над FPC**: UTF-8 по умолчанию, горутины и каналы, менеджер потоков | `safe/` (ядро) |
| [`fpide/`](fpide/README.md) | **fpide**: Free Pascal IDE на [tv3](https://github.com/unxed/tv3) | только `tv/` и внешний `fpc` |

| Файл | Что это |
|---|---|
| `bp.pas` | `unit BP`: собирает `safe/*.inc` и `ext/*.inc` в один юнит (safe + UTF-8 + горутины) |
| `safe/safe.pas` | `unit Safe`: только слой safe, если остальное не нужно |
| `tests/` | `tests/safe/` и `tests/ext/`; `tests/run.sh [safe\|ext\|all]` |
| `.github/workflows/` | `ci` (safe + ext, кросс-сборки), `fpide`, `fpide-accept` |

Лицензия: MIT (`LICENSE`). Код `fpide/` — производный от FPC IDE (GPL, см. `fpide/README.md`), в `safe/` и `ext/` его нет.

Репозиторий пока называется `sp`; переименование в `bp` — за владельцем.
