# bootstrap/: откуда взялись `fpide/src` и `fpide/fpc-compiler`

Запись о воспроизводимом пути от официальных исходников FPC.

| Что | Значение |
|---|---|
| IDE | Free Pascal `packages/ide` (Text Mode IDE) → `fpide/src` |
| Компилятор | Free Pascal `compiler/` → `fpide/fpc-compiler` (**обязательно**, не заглушки) |
| Репозиторий | `upstream.env` → GitLab `freepascal.org/fpc/source` |
| Версия | тег `release_3_2_2`, commit в `FPC_COMMIT` |
| Лицензия | LGPL/GPL как в дистрибутиве FPC (`COPYING` в дереве компилятора) |

Free Vision (`packages/fv`) **не** копируется: UI — submodule [`tv/`](../../tv/) ([unxed/tv3](https://github.com/unxed/tv3)).

## Короткий путь

```sh
fpide/bootstrap/run.sh build/bootstrap-fpide
diff -rq build/bootstrap-fpide/staging-ide fpide/src
diff -rq build/bootstrap-fpide/staging-compiler fpide/fpc-compiler
```

Или обновить деревья из staging:

```sh
fpide/bootstrap/materialize.sh
```

Нужны: `git`, `sh`.
