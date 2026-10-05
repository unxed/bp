# bootstrap/: IDE in git; compiler fetched on demand (not committed)

| Что | В git? | Где |
|---|---|---|
| IDE (`packages/ide`) | да | `fpide/src` |
| Компилятор (`compiler/`) | **нет** | `build/bootstrap-fpide/staging-compiler` после `ensure-compiler.sh` |
| Pin | да | `upstream.env` (`FPC_COMMIT`) |

```sh
fpide/bootstrap/run.sh build/bootstrap-fpide          # stage both trees
diff -rq build/bootstrap-fpide/staging-ide fpide/src  # IDE must match pin
fpide/bootstrap/ensure-compiler.sh                    # compiler only (cached by commit)
```

Компилятор настоящий (тот же тег, что IDE); в репозиторий его не кладём — только pin и скрипты.
