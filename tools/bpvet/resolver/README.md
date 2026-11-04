# A patched resolver for the typed mode of `bpvet`

`bpvet` reads types with `PasResolver` of `fcl-passrc` (safe/SPEC.md §20, "Spike 1 result"). The resolver and the parser
of FPC 3.2.2 reject three constructs that FPC itself accepts and that Better Pascal uses; `pasresolver.patch` and
`pparser.patch` change them (each patch header says what and why). The repository keeps only the patches: `get.sh OUT`
takes the original files of FPC 3.2.2, checks their SHA-256, applies the patches and leaves the result in `OUT`, from
where `bpvet` is built (`-FuOUT -FiOUT`, `build.sh`).

Licence: the patch and the patched file are under the licence of `fcl-passrc`, the LGPL with the static linking exception
of Free Pascal (`COPYING.FPC` in the FPC sources). The exception allows linking them with the MIT code of `bpvet`; the
changed source is this patch applied to the published FPC file. The rest of `bpvet` stays MIT.

FPC main already has all three changes; the patches go when `bpvet` moves to the next FPC release.

`genstubs.py OUT SRC...` writes the declaration stubs of the RTL that the typed mode reads (`bpvet --typed --rtl OUT`),
from `ppudump -Fj` of the installed units (Debian, Ubuntu: fp-utils); its header says how.
