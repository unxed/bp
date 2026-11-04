# A patched `pasresolver.pp` for the typed mode of `bpvet`

`bpvet` reads types with `PasResolver` of `fcl-passrc` (safe/SPEC.md §20, "Spike 1 result"). The resolver of FPC 3.2.2
rejects two constructs that FPC itself accepts and that Better Pascal uses; `pasresolver.patch` changes them (the patch
header says what and why). The repository keeps only the patch: `get.sh OUT` takes the original file of FPC 3.2.2,
checks its SHA-256, applies the patch and leaves the result in `OUT`, from where `bpvet` is built (`-FuOUT`).

Licence: the patch and the patched file are under the licence of `fcl-passrc`, the LGPL with the static linking exception
of Free Pascal (`COPYING.FPC` in the FPC sources). The exception allows linking them with the MIT code of `bpvet`; the
changed source is this patch applied to the published FPC file. The rest of `bpvet` stays MIT.

The two changes are meant to be offered to FPC; until then they live here.
