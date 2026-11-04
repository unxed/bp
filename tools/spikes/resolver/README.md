# Spike 1: a typed `bpvet` on `PasResolver`

A throw-away probe for step 1 of unxed/bp#108. The verdict and its conditions are in `safe/SPEC.md` §20, "Spike 1 result".

- `rspike.pas` — one `TPasResolver` per module, a shared hub, units found by search paths; used units are read up to the
  end of their interface. It accepts casts and `PChar` → `String` that FPC accepts, and registers `WriteLn`, `SizeOf` and
  the like as built-in routines with any arguments.
- `stub/` — declaration stubs of the RTL units, written by hand for the spike; the real step generates them from the
  `.ppu` files with `ppudump -Fj`.
- `run.sh` — runs a built `rspike` over the modules of the repository.

Build: `fpc -Fu<dir of a fixed pasresolver.pp> -Fu<fcl-passrc src> -Fi<fcl-passrc src> rspike.pas`. Without the fix of
`TPasResolver.CheckUseAsType` described in SPEC §20 the resolver stops at `safe/core.impl.inc` (the bare name of a generic in
its own method). Not part of CI.
