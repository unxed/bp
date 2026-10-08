# bootstrap/: IDE in git; compiler fetched on demand (not committed)

| What | In git? | Where |
|---|---|---|
| IDE (`packages/ide`) | yes | `fpide/src` |
| Compiler (`compiler/`) | **no** | `build/bootstrap-fpide/staging-compiler` after `ensure-compiler.sh` |
| Pin | yes | `upstream.env` (`FPC_COMMIT`) |

```sh
fpide/bootstrap/run.sh build/bootstrap-fpide          # stage both trees
diff -rq build/bootstrap-fpide/staging-ide fpide/src  # IDE must match pin
fpide/bootstrap/ensure-compiler.sh                    # compiler only (cached by commit)
```

The compiler is the real one (the same tag as the IDE); it is not committed to the repository, only the pin and the scripts are.
