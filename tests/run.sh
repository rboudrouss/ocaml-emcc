#!/usr/bin/env bash
# Build every test project natively and with ocaml-emcc, run both, compare.
#   tests/run.sh [--target wasm32|wasm64] [test...]   (default: wasm32)
#   tests/run.sh --wasi [test...]      OUT.wasm --wasi, run by wasmtime (or node's WASI)
#   SWITCH=bench tests/run.sh          (another opam switch)
set -u
cd "$(dirname "$0")"; TESTS_DIR=$PWD
. ./env.sh
TARGET=wasm32 WASI=no
while [ $# -gt 0 ]; do
  case $1 in
    --target) TARGET=$2; shift 2 ;;
    --wasi) WASI=yes; shift ;;
    *) break ;;
  esac
done
export OCAML_EMCC_TARGET=$TARGET
# --wasi: a "wasi" entry in the targets column of the test
TARGET_COL=$TARGET; [ $WASI = yes ] && TARGET=wasm32 TARGET_COL=wasi
# the WASI host: $WASMTIME, wasmtime in PATH, else node:wasi
WASMTIME=${WASMTIME:-$(command -v wasmtime || true)}
wasi_run() {
  if [ -n "$WASMTIME" ]; then "$WASMTIME" run -W exceptions=y --dir . --dir /tmp -S inherit-env=y "$@"
  else "$NODE" --no-warnings "$TESTS_DIR/wasi-run.mjs" "$@"; fi
}

# name | dune target (no ext.) | args | required packages | targets (wasm32, wasm64, wasi) | lines allowed to differ
# A test with an expected.txt is compared to it instead of a native run.
# A test with a Makefile and no dune-project is built with make (no dune).
TESTS='
hello     | hello    | a b        |                             | wasm64             |
stubs     | bin/main |            |                             | wasm32 wasm64 wasi |
zarith    | zt       |            | zarith                      | wasm32 wasm64 wasi |
mixed     | mixed    | --name w 7 | digestif yojson re cmdliner | wasm32 wasm64 wasi |
ocaml5    | o5       |            | ocaml>=5                    | wasm32 wasm64 wasi | ^Domain\.
gitrecipe | bin/main |            |                             | wasm32 wasm64 wasi |
nodune    | prog     |            | zarith                      | wasm32 wasm64 wasi |
syslibs   | bin/main |            | mlmpfr zlib                 | wasm32 wasm64 wasi |
apron     | ap       |            | apron                       | wasm32 wasm64 wasi | could not set fpu|cannot change the FPU
sqlite    | sq       |            | sqlite3                     | wasm32 wasm64 wasi |
bz2       | bz       |            | bz2                         | wasm32 wasm64 wasi |
pcre2     | re       |            | pcre2                       | wasm32 wasm64 wasi |
zstd      | zs       |            | zstd                        | wasm32 wasm64 wasi |
gsl       | gs       |            | gsl                         | wasm32 wasm64 wasi |
camlzip   | cz       |            | camlzip                     | wasm32 wasm64 wasi |
ctypes    | cf       |            | ctypes-foreign              | wasm32 wasm64      |
yaml      | ym       |            | yaml                        | wasm32 wasm64      |
clibs     | sm       |            | sha checkseum bigstringaf mtime ptime eqaf | wasm32 wasm64      |
mcrypto   | mc       |            | mirage-crypto-ec mirage-crypto-pk mirage-crypto-rng | wasm32 wasm64      |
lwt       | lw       |            | lwt                         | wasm32 wasm64      |
cryptokit | ck       |            | cryptokit                   | wasm32 wasm64      |
minisat   | ms       |            | minisat                     | wasm32 wasm64      |
lua       | lu       |            | ocaml-lua                   | wasm32 wasm64      |
stb       | sb       |            | stb_image                   | wasm32 wasm64      |
extunix   | eu       |            | extunix                     | wasm32 wasm64      |
lz4       | lz       |            | lz4                         | wasm32 wasm64      |
snappy    | sn       |            | snappy                      | wasm32 wasm64      |
argon2    | ar       |            | argon2                      | wasm32 wasm64      |
expat     | ex       |            | expat                       | wasm32 wasm64      |
lmdb      | lm       |            | lmdb                        | wasm32 wasm64      |
glpk      | gl       |            | glpk                        | wasm32 wasm64      |
fftw3     | ff       |            | fftw3                       | wasm32 wasm64      |
secp      | sc       |            | secp256k1-internal          | wasm32 wasm64      |
sdl       | sd       |            | tsdl                        | wasm64             |
binio     | bi       |            |                             | wasm32 wasm64 wasi |
depgraph  | bin/main |            | depgraph                    | wasm32 wasm64      |
'
# wasi (tests/run.sh --wasi): OUT.wasm --wasi, the tests checked that way.
# ctypes needs libffi's JavaScript functions, no WASI host has them.
# hello is wasm64 only on purpose: 63-bit literals and arithmetic.  sdl
# too, for now: its ctypes structs, laid out with the sizes of the host
# before ctypes was rebuilt for wasm32 (as yaml's are), were not tried since.
# depgraph needs its package installed: opam install ./tests/depgraph/pkg

has_pkg() {
  case $1 in
    ocaml\>=5) [ "$(ocamlc -vnum | cut -d. -f1)" -ge 5 ] ;;
    *) ocamlfind query "$1" >/dev/null 2>&1 || [ -d "$OPAM_SWITCH_PREFIX/lib/$1" ] ;;
  esac
}

trim() { sed -e 's/^ *//' -e 's/ *$//'; }
pass=0; fail=0; skip=0
while IFS='|' read -r name target args pkgs targets differ; do
  name=$(echo "$name" | trim); [ -n "$name" ] || continue
  if [ $# -gt 0 ] && [[ " $* " != *" $name "* ]]; then continue; fi
  target=$(echo "$target" | trim); args=$(echo "$args" | trim)
  pkgs=$(echo "$pkgs" | trim); differ=$(echo "$differ" | trim)
  if [[ " $targets " != *" $TARGET_COL "* ]]; then echo "SKIP $name (not for $TARGET_COL)"; skip=$((skip+1)); continue; fi
  missing=
  for p in $pkgs; do has_pkg "$p" || missing="$missing $p"; done
  if [ -n "$missing" ]; then echo "SKIP $name (missing:$missing)"; skip=$((skip+1)); continue; fi
  (
    set -e
    cd "$name"; rm -rf out; mkdir -p out
    js="out/$(basename "$target").js" flags=
    if [ $WASI = yes ]; then js="out/$(basename "$target").wasm" flags=--wasi; fi
    if [ -f Makefile ] && [ ! -f dune-project ]; then
      make clean >/dev/null; make OCAML_EMCC="$OE_ROOT/_build/default/bin/main.exe" LINK_FLAGS="$flags" "$js" 2>&1
    else
      if [ ! -f expected.txt ]; then dune build --root . "./$target.exe" 2>&1; fi
      # the all-in-one command: runtime, bytecode, stubs, link
      ocaml-emcc build "$js" --exe "$target" $flags 2>&1
    fi
    if [ -f expected.txt ]; then cp expected.txt out/native.txt
    else "./_build/default/$target.exe" $args > out/native.txt || echo "exit=$?" >> out/native.txt; fi
    if [ $WASI = yes ]; then run() { wasi_run "$@"; }; else run() { "$NODE" "$@"; }; fi
    run "$js" $args > out/wasm.txt 2> out/wasm.err || echo "exit=$?" >> out/wasm.txt
  ) > "$name/out.log" 2>&1
  if [ -n "$differ" ]; then filt() { grep -Ev "$differ" "$1"; }; else filt() { cat "$1"; }; fi
  if [ -f "$name/out/wasm.txt" ] && diff <(filt "$name/out/native.txt") <(filt "$name/out/wasm.txt") > "$name/out/diff.txt"; then
    echo "PASS $name ($(wc -l < "$name/out/native.txt") lines, $(du -k "$name/out/$(basename "$target").wasm" | cut -f1) KB wasm)"
    pass=$((pass+1))
  else
    echo "FAIL $name (see tests/$name/out.log, out/diff.txt, out/wasm.err)"; fail=$((fail+1))
  fi
done <<< "$TESTS"
echo "switch $(basename "$OPAM_SWITCH_PREFIX") (OCaml $(ocamlc -vnum)), target $TARGET_COL: $pass passed, $fail failed, $skip skipped"
[ $fail -eq 0 ]
