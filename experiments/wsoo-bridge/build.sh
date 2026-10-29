#!/usr/bin/env bash
# build.sh PROG.bc OUTDIR [C inputs...]
#
# PROG.bc compiled by wasm_of_ocaml, its primitives that wasm_of_ocaml
# lacks bridged to C compiled by emscripten (the C inputs: .c files,
# objects and archives compiled with `ocaml-emcc env --cflags`, -l/-L
# flags), with the wasm runtime of ocaml-emcc's sysroot.
#   node OUTDIR/main.js OUTDIR/PROG.js args...
#
# Needs: wasm_of_ocaml and binaryen in PATH, emcc, an ocaml-emcc sysroot
# (`ocaml-emcc setup`, wasm32) for the switch's OCaml 5.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
BC=$(realpath "$1"); OUT=$2; shift 2
OE=${OCAML_EMCC:-$ROOT/_build/default/bin/main.exe}
mkdir -p "$OUT"; OUT=$(realpath "$OUT")
NAME=$(basename "${BC%.*}")
SYSROOT=$("$OE" env --sysroot)
CFLAGS="$("$OE" env --cflags) -w"
cd "$OUT"

# the primitives of PROG.bc (and how many arguments each one gets), and
# those that wasm_of_ocaml reports missing
cp "$ROOT"/src/{compat,str_util,bytecode}.ml "$HERE/arity/arity.ml" .
ocamlfind ocamlopt -package unix -linkpkg compat.ml str_util.ml bytecode.ml arity.ml -o arity.exe
./arity.exe "$BC" > arities.txt
wasm_of_ocaml compile "$BC" -o probe.js > probe.log 2>&1 || { cat probe.log; exit 1; }
python3 "$HERE/missing.py" arities.txt probe.log > prims.txt
echo "bridged primitives: $(wc -l < prims.txt)"

# C inputs
objs=()
for f in "$@"; do
  case $f in
    *.c) emcc $CFLAGS -c "$f" -o "$(basename "${f%.c}").o"; objs+=("$(basename "${f%.c}").o") ;;
    *) objs+=("$f") ;;
  esac
done

# the GC side: one export per bridged primitive, and the names of
# Callback.register that the C code may look up (strings of the C inputs)
cstrings=()
for f in "$@"; do [ -f "$f" ] && cstrings+=("$f"); done
python3 "$HERE/gen.py" "$HERE/bridge.wat" prims.txt oe.wat dispatch.c named.js "${cstrings[@]}"
wasm_of_ocaml compile named.js oe.wat "$BC" -o "$NAME.js"
# the C module's exports, as the "c" imports of the wasm_of_ocaml module
sed -i 's/env:{}}/env:{},c:globalThis.__oe_c}/' "$NAME.js"
grep -q 'c:globalThis.__oe_c' "$NAME.js"

# the C side: libcamlrun, initialized by an empty program
rm -f oeinit.c; echo "let () = ()" > empty.ml; ocamlc -output-obj empty.ml -o oeinit.c
emcc $CFLAGS -c "$HERE/bridge.c" -o bridge.o
emcc $CFLAGS -c oeinit.c -o oeinit.o
link() {
  emcc $CFLAGS -c dispatch.c -o dispatch.o
  emcc $CFLAGS bridge.o dispatch.o oeinit.o "${objs[@]}" "$SYSROOT/lib/libcamlrun.a" -L"$SYSROOT/lib" -lm \
    -o oec.js -sMODULARIZE=1 -sEXPORT_NAME=createC -sENVIRONMENT=node \
    -sALLOW_MEMORY_GROWTH=1 -sMAXIMUM_MEMORY=4GB -sSTACK_SIZE=8MB \
    -sEXPORTED_RUNTIME_METHODS=wasmExports -sEXPORTED_FUNCTIONS=_oe_init -sINVOKE_RUN=0 \
    -sINCOMING_MODULE_JS_API=[] -Wl,--wrap=caml_named_value --js-library "$HERE/oe-lib.js" 2> link.err
}
link
# a C definition with another arity than the call (wasm-ld made it a trap):
# called with its own arity
if grep -q "signature mismatch" link.err; then
  python3 "$HERE/mismatch.py" prims.txt link.err > prims2.txt
  python3 "$HERE/gen.py" "$HERE/bridge.wat" prims2.txt oe2.wat dispatch.c named2.js
  link
fi
grep -v "signature mismatch\|^>>> defined as" link.err >&2 || true
cp "$HERE/main.js" .
echo "node $OUT/main.js $OUT/$NAME.js"
