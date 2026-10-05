# Environment for building fpide (after need-tv.sh).
# Full IDE: real FPC compiler/ + GDB/MI by default (upstream Linux IDE).
FPIDE_STAGE=${FPIDE_STAGE:-$here/fpide/src}
FPIDE_OBJ=${FPIDE_OBJ:-$out/obj}
FPIDE_GEN=${FPIDE_GEN:-$out/gen}
FPIDE_COMPAT=${FPIDE_COMPAT:-$here/fpide/compat}
FPIDE_COMPILER=${FPIDE_COMPILER:-$here/fpide/fpc-compiler}
FPIDE_CPU=${FPIDE_CPU:-x86_64}
mkdir -p "$FPIDE_OBJ" "$FPIDE_GEN"
: "${FPIDE_NOGDB:=0}"
: "${FPIDE_GDBMI:=1}"

if [ ! -f "$FPIDE_COMPILER/finput.pas" ]; then
    echo "fpide-env: missing $FPIDE_COMPILER/finput.pas — run fpide/bootstrap/run.sh and materialize fpc-compiler" >&2
    exit 1
fi

# Matches packages/ide/fpmake.pp for a native linux64 IDE with GDB/MI.
FPIDE_OPTS="-Mobjfpc -Sh- -Se1 -Sg -Ur"
FPIDE_OPTS="$FPIDE_OPTS -dNOCATCH -dBrowserCol -dGDB -d$FPIDE_CPU"
FPIDE_OPTS="$FPIDE_OPTS -Fu$FPIDE_STAGE -Fu$FPIDE_STAGE/compiler -Fu$FPIDE_COMPAT"
FPIDE_OPTS="$FPIDE_OPTS -Fu$FPIDE_COMPILER -Fu$FPIDE_COMPILER/$FPIDE_CPU -Fu$FPIDE_COMPILER/targets"
FPIDE_OPTS="$FPIDE_OPTS -Fu$FPIDE_COMPILER/systems -Fu$FPIDE_COMPILER/x86"
FPIDE_OPTS="$FPIDE_OPTS -Fu$here/tv/src -Fu$FPIDE_GEN"
FPIDE_OPTS="$FPIDE_OPTS -Fi$FPIDE_STAGE -Fi$FPIDE_COMPAT -Fi$here/fpide/compat/shims"
FPIDE_OPTS="$FPIDE_OPTS -Fi$FPIDE_COMPILER -Fi$FPIDE_COMPILER/$FPIDE_CPU"
FPIDE_OPTS="$FPIDE_OPTS -FU$FPIDE_OBJ -FE$out"

if [ "$FPIDE_NOGDB" != 0 ]; then
  FPIDE_OPTS="$FPIDE_OPTS -dNOGDB -dNODEBUG"
elif [ "$FPIDE_GDBMI" != 0 ]; then
  FPIDE_OPTS="$FPIDE_OPTS -dGDBMI"
fi
FPIDE_OPTS="$FPIDE_OPTS ${FPIDE_EXTRA:-}"

fpide_gen_shims() {
    python3 "$here/tools/gen-shim.py" "$here/fpide/compat/shims/shims.map" "$FPIDE_GEN" "$here/tv/src" >/dev/null
}

fpide_compile() {
    prog=$1
    # shellcheck disable=SC2086
    fpc $FPIDE_OPTS "$FPIDE_STAGE/$prog" > "$FPIDE_OBJ/${prog%.pas}.log" 2>&1 || true
}
