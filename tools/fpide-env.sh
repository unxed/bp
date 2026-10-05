# Environment for building fpide (after need-tv.sh).
# Compiler sources are NOT in git: bootstrap stages them under build/bootstrap-fpide/staging-compiler.
FPIDE_STAGE=${FPIDE_STAGE:-$here/fpide/src}
FPIDE_OBJ=${FPIDE_OBJ:-$out/obj}
FPIDE_GEN=${FPIDE_GEN:-$out/gen}
FPIDE_COMPAT=${FPIDE_COMPAT:-$here/fpide/compat}
FPIDE_BOOTSTRAP=${FPIDE_BOOTSTRAP:-$here/build/bootstrap-fpide}
FPIDE_COMPILER=${FPIDE_COMPILER:-$FPIDE_BOOTSTRAP/staging-compiler}
FPIDE_CPU=${FPIDE_CPU:-x86_64}
mkdir -p "$FPIDE_OBJ" "$FPIDE_GEN"
: "${FPIDE_NOGDB:=0}"
: "${FPIDE_GDBMI:=1}"

if [ ! -f "$FPIDE_COMPILER/finput.pas" ]; then
    echo "fpide-env: fetching FPC compiler/ via bootstrap…" >&2
    "$here/fpide/bootstrap/ensure-compiler.sh"
fi
if [ ! -f "$FPIDE_COMPILER/finput.pas" ]; then
    echo "fpide-env: missing $FPIDE_COMPILER/finput.pas" >&2
    exit 1
fi

# Matches packages/ide/fpmake.pp for a native linux64 IDE with GDB/MI.
# GEN + tv/src must be first: FPC's default path has rtl-extra/Objects and fv/Drivers.
FPIDE_OPTS="-Mobjfpc -Sh- -Se1 -Sg -Ur"
FPIDE_OPTS="$FPIDE_OPTS -dNOCATCH -dBrowserCol -dGDB -d$FPIDE_CPU"
FPIDE_OPTS="$FPIDE_OPTS -Fu$FPIDE_GEN -Fu$here/tv/src -Fu$FPIDE_COMPAT"
FPIDE_OPTS="$FPIDE_OPTS -Fu$FPIDE_STAGE -Fu$FPIDE_STAGE/compiler"
FPIDE_OPTS="$FPIDE_OPTS -Fu$FPIDE_COMPILER -Fu$FPIDE_COMPILER/$FPIDE_CPU -Fu$FPIDE_COMPILER/targets"
FPIDE_OPTS="$FPIDE_OPTS -Fu$FPIDE_COMPILER/systems -Fu$FPIDE_COMPILER/x86"
FPIDE_OPTS="$FPIDE_OPTS -Fi$FPIDE_GEN -Fi$FPIDE_STAGE -Fi$FPIDE_COMPAT -Fi$here/fpide/compat/shims"
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
    rm -rf "$FPIDE_GEN/manual"
    cp -a "$here/fpide/compat/shims/manual" "$FPIDE_GEN/manual"
    # Linux FS is case-sensitive; FPC looks up the uses-clause spelling.
    # Provide lowercase aliases for generated units (objects vs Objects).
    for f in "$FPIDE_GEN"/*.pas; do
        base=$(basename "$f")
        lower=$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')
        if [ "$base" != "$lower" ] && [ ! -e "$FPIDE_GEN/$lower" ]; then
            ln -s "$base" "$FPIDE_GEN/$lower"
        fi
    done
}

fpide_compile() {
    prog=$1
    # shellcheck disable=SC2086
    fpc $FPIDE_OPTS "$FPIDE_STAGE/$prog" > "$FPIDE_OBJ/${prog%.pas}.log" 2>&1 || true
}
