#!/usr/bin/env bash
# Build every test project natively and with ocaml-emcc, run both, compare.
#   tests/run.sh [--target wasm32|wasm64] [test...]   (default: wasm32)
#   SWITCH=bench tests/run.sh          (another opam switch)
set -u
cd "$(dirname "$0")"
. ./env.sh
TARGET=wasm32
if [ "${1:-}" = --target ]; then TARGET=$2; shift 2; fi
export OCAML_EMCC_TARGET=$TARGET

# name | dune target (no ext.) | args | required packages | targets | lines allowed to differ
# A test with an expected.txt is compared to it instead of a native run.
# A test with a Makefile and no dune-project is built with make (no dune).
TESTS='
hello     | hello    | a b        |                             | wasm64        |
stubs     | bin/main |            |                             | wasm32 wasm64 |
zarith    | zt       |            | zarith                      | wasm32 wasm64 |
mixed     | mixed    | --name w 7 | digestif yojson re cmdliner | wasm32 wasm64 |
ocaml5    | o5       |            | ocaml>=5                    | wasm32 wasm64 | ^Domain\.
gitrecipe | bin/main |            |                             | wasm32 wasm64 |
nodune    | prog     |            | zarith                      | wasm32 wasm64 |
syslibs   | bin/main |            | mlmpfr zlib                 | wasm32 wasm64 |
apron     | ap       |            | apron                       | wasm32 wasm64 | could not set fpu|cannot change the FPU
sqlite    | sq       |            | sqlite3                     | wasm32 wasm64 |
bz2       | bz       |            | bz2                         | wasm32 wasm64 |
pcre2     | re       |            | pcre2                       | wasm32 wasm64 |
zstd      | zs       |            | zstd                        | wasm32 wasm64 |
gsl       | gs       |            | gsl                         | wasm32 wasm64 |
'
# hello is wasm64 only on purpose: 63-bit literals and arithmetic.

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
  if [[ " $targets " != *" $TARGET "* ]]; then echo "SKIP $name (not for $TARGET)"; skip=$((skip+1)); continue; fi
  missing=
  for p in $pkgs; do has_pkg "$p" || missing="$missing $p"; done
  if [ -n "$missing" ]; then echo "SKIP $name (missing:$missing)"; skip=$((skip+1)); continue; fi
  (
    set -e
    cd "$name"; rm -rf out; mkdir -p out
    js="out/$(basename "$target").js"
    if [ -f Makefile ] && [ ! -f dune-project ]; then
      make clean >/dev/null; make OCAML_EMCC="$OE_ROOT/_build/default/bin/main.exe" "$js" 2>&1
    else
      if [ ! -f expected.txt ]; then dune build --root . "./$target.exe" 2>&1; fi
      # the all-in-one command: runtime, bytecode, stubs, link
      ocaml-emcc build "$js" --exe "$target" 2>&1
    fi
    if [ -f expected.txt ]; then cp expected.txt out/native.txt
    else "./_build/default/$target.exe" $args > out/native.txt || echo "exit=$?" >> out/native.txt; fi
    "$NODE" "$js" $args > out/wasm.txt 2> out/wasm.err || echo "exit=$?" >> out/wasm.txt
  ) > "$name/out.log" 2>&1
  if [ -n "$differ" ]; then filt() { grep -Ev "$differ" "$1"; }; else filt() { cat "$1"; }; fi
  if [ -f "$name/out/wasm.txt" ] && diff <(filt "$name/out/native.txt") <(filt "$name/out/wasm.txt") > "$name/out/diff.txt"; then
    echo "PASS $name ($(wc -l < "$name/out/native.txt") lines, $(du -k "$name/out/$(basename "$target").wasm" | cut -f1) KB wasm)"
    pass=$((pass+1))
  else
    echo "FAIL $name (see tests/$name/out.log, out/diff.txt, out/wasm.err)"; fail=$((fail+1))
  fi
done <<< "$TESTS"
echo "switch $(basename "$OPAM_SWITCH_PREFIX") (OCaml $(ocamlc -vnum)), target $TARGET: $pass passed, $fail failed, $skip skipped"
[ $fail -eq 0 ]
