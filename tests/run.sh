#!/usr/bin/env bash
# Build every test project natively and with ocaml-emcc, run both, compare.
#   tests/run.sh [--target wasm32|wasm64] [test...]   (default: wasm32)
#   tests/run.sh --wasi [test...]      OUT.wasm --wasi, run by wasmtime (or node's WASI)
#   tests/run.sh --interpreted [test...]  the bytecode interpreted, not compiled
#                                      to C by c_of_ocaml (always before OCaml 4.14)
#   SWITCH=bench tests/run.sh          (another opam switch)
set -u
cd "$(dirname "$0")"; TESTS_DIR=$PWD
. ./env.sh
TARGET=wasm32 WASI=no INTERPRETED=
while [ $# -gt 0 ]; do
  case $1 in
    --target) TARGET=$2; shift 2 ;;
    --wasi) WASI=yes; shift ;;
    --interpreted) INTERPRETED=--interpreted; shift ;;
    --compiled) shift ;;   # the default
    *) break ;;
  esac
done
export OCAML_EMCC_TARGET=$TARGET
# the compiled mode needs OCaml 4.14 (ocaml-emcc interprets before)
if [ "$(printf '%s\n' 4.14 "$(ocamlc -vnum)" | sort -V | head -1)" != 4.14 ]; then INTERPRETED=--interpreted; fi
# --wasi: a "wasi" entry in the targets column of the test
TARGET_COL=$TARGET; [ $WASI = yes ] && TARGET=wasm32 TARGET_COL=wasi
# the WASI host: $WASMTIME, wasmtime in PATH, else node:wasi.  Programs
# with threads (threads: yes in their ocaml-emcc.conf) need wasi-threads:
# $WASMTIME_THREADS, a wasmtime <= 46 (47 removed it).  The program's
# temporary files go to /tmp, which is preopened (not $TMPDIR), as are /etc
# and /usr/share/zoneinfo (the local time zone).  Programs
# with sockets (wasix: yes) run in $WASMER (wasmer in PATH), with network
# (and the tail calls of the compiled code).
WASMTIME=${WASMTIME:-$(command -v wasmtime || true)}
WASMTIME_THREADS=${WASMTIME_THREADS:-$WASMTIME}
WASMER=${WASMER:-$(command -v wasmer || true)}
# a program running longer than $TEST_TIMEOUT seconds (default 900) is
# stopped: the test fails (exit=124) instead of blocking the others
TO="timeout -k 10 ${TEST_TIMEOUT:-900}"
ZONES=; [ -d /usr/share/zoneinfo ] && ZONES="--dir /usr/share/zoneinfo"
wasi_run() {
  local -x TMPDIR=/tmp
  if grep -qs '^wasix: *yes' ocaml-emcc.conf; then
    $TO "$WASMER" run --net --enable-tail-call "$1" -- "${@:2}"
  elif grep -qs '^threads: *yes' ocaml-emcc.conf; then
    $TO "$WASMTIME_THREADS" run -W exceptions=y,threads=y,shared-memory=y -S threads=y --dir . --dir /tmp --dir /etc $ZONES -S inherit-env=y "$@" 2> >(grep -v '^WARNING: the `-Sthreads` flag' >&2)
  elif [ -n "$WASMTIME" ]; then $TO "$WASMTIME" run -W exceptions=y --dir . --dir /tmp --dir /etc $ZONES -S inherit-env=y "$@"
  else $TO "$NODE" --no-warnings "$TESTS_DIR/wasi-run.mjs" "$@"; fi
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
compress  | cm       |            | ocaml>=5.1                  | wasm32 wasm64 wasi |
gitrecipe | bin/main |            |                             | wasm32 wasm64 wasi |
nodune    | prog     |            | zarith                      | wasm32 wasm64 wasi |
syslibs   | bin/main |            | mlmpfr zlib                 | wasm32 wasm64 wasi |
apron     | ap       |            | apron                       | wasm32 wasm64 wasi | could not set fpu|cannot change the FPU
sqlite    | sq       |            | sqlite3                     | wasm32 wasm64 wasi |
bz2       | bz       |            | bz2                         | wasm32 wasm64 wasi |
zstd      | zs       |            | zstd                        | wasm32 wasm64 wasi |
gsl       | gs       |            | gsl                         | wasm32 wasm64 wasi |
camlzip   | cz       |            | camlzip                     | wasm32 wasm64 wasi |
ctypes    | cf       |            | ctypes-foreign              | wasm32 wasm64      |
yaml      | ym       |            | yaml                        | wasm32 wasm64      |
cstanza   | bin/main |            | ctypes                      | wasm32 wasm64 wasi |
clibs     | sm       |            | checkseum bigstringaf       | wasm32 wasm64      |
mcrypto   | mc       |            | mirage-crypto-ec mirage-crypto-pk mirage-crypto-rng | wasm32 wasm64      |
lwt       | lw       |            | lwt                         | wasm32 wasm64 wasi |
cryptokit | ck       |            | cryptokit                   | wasm32 wasm64      |
minisat   | ms       |            | minisat                     | wasm32 wasm64      |
lua       | lu       |            | ocaml-lua                   | wasm32 wasm64      |
stb       | sb       |            | stb_image                   | wasm32 wasm64      |
extunix   | eu       |            | extunix                     | wasm32 wasm64      |
snappy    | sn       |            | snappy                      | wasm32 wasm64      |
jspi      | jp       |            |                             | wasm32 wasm64      |
cpsstack  | cs       |            | cps-stack                   | wasm32 wasm64      |
cpsasync  | ca       |            | cps-stack-asyncify          | wasm32 wasm64      |
notailcalls | nt     |            | cps-stack-asyncify          | wasm32 wasm64      |
argon2    | ar       |            | argon2                      | wasm32 wasm64      |
expat     | ex       |            | expat                       | wasm32 wasm64      |
lmdb      | lm       |            | lmdb                        | wasm32 wasm64      |
mapfile   | mf       |            | interpreted                 | wasm32 wasm64 wasi |
glpk      | gl       |            | glpk                        | wasm32 wasm64      |
fftw3     | ff       |            | fftw3                       | wasm32 wasm64      |
secp      | sc       |            | secp256k1-internal          | wasm32 wasm64      |
sdl       | sd       |            | tsdl                        | wasm64             |
raylib    | rl       |            | raylib                      | wasm32 wasm64      |
binio     | bi       |            |                             | wasm32 wasm64 wasi |
nodefs    | prog     |            |                             | wasm32 wasm64      |
depgraph  | bin/main |            | depgraph                    | wasm32 wasm64      |
cudd      | cu       |            | cudd                        | wasm32 wasm64      |
hacl      | hc       |            | hacl-star                   | wasm32 wasm64      |
posix     | px       |            | posix-time2 posix-socket posix-stat | wasm32 wasm64      |
mccs      | mc       |            | mccs                        | wasm32 wasm64      |
dynlink   | main     |            | compiled                    | wasm32 wasm64      |
dyneffects | main    |            | compiled ocaml>=5           | wasm32 wasm64      |
dyncps    | main     |            | compiled cps-stack-dynlink  | wasm32 wasm64      |
dynbyte   | main     |            | interpreted                 | wasm32 wasm64      |
dynthreads | main    |            | compiled                    | wasm32 wasm64      |
dynjspi   | main     |            | compiled                    | wasm32 wasm64      |
dynweb    | main     |            | compiled playwright         | wasm32 wasm64      |
jsoo      | js       |            | js_of_ocaml-ppx             | wasm32 wasm64      |
jsprims   | jp       |            | js_of_ocaml                 | wasm32 wasm64      |
jsdom     | page     |            | js_of_ocaml-ppx playwright  | wasm32 wasm64      |
sysjs     | sj       |            | js_of_ocaml                 | wasm32 wasm64      |
jsthreads | jt       |            | js_of_ocaml                 | wasm32 wasm64      |
jsthreadsweb | jt     |            | js_of_ocaml playwright      | wasm32 wasm64      |
localtime | tz       |            |                             | wasm32 wasm64      |
core      | cr       |            | core                        | wasm32 wasm64 wasi |
async     | as       |            | async core_unix             | wasm32 wasm64 wasi |
asyncthreads | at    |            | async core_unix wasi-threads | wasm32 wasm64 wasi |
asyncssl  | sl       |            | async_ssl                   | wasm32 wasm64      |
threads   | th       |            | wasi-threads                | wasm32 wasm64 wasi |
domains   | dm       |            | ocaml>=5.3 wasi-threads     | wasm32 wasm64 wasi |
threadsweb | th      |            | playwright                  | wasm32 wasm64      |
lwtthreads | lt      |            | lwt                         | wasm32 wasm64      |
sockets   | sk       |            | wasmer                      | wasi               |
lwtsockets | ls      |            | lwt wasmer                  | wasi               |
threadsockets | ts   |            | wasmer                      | wasi               |
'
# wasi (tests/run.sh --wasi): OUT.wasm --wasi, the tests checked that way.
# ctypes needs libffi's JavaScript functions, no WASI host has them.
# hello is wasm64 only on purpose: 63-bit literals and arithmetic.  sdl
# too, for now: its ctypes structs, laid out with the sizes of the host
# before ctypes was rebuilt for wasm32 (as yaml's are), were not tried since.
# depgraph needs its package installed: opam install ./tests/depgraph/pkg
# dynlink, dyneffects, dyncps, dynthreads and dynweb (plugins) are for the
# compiled mode only, dynbyte (Dynlink's) for the interpreted one.
# threads and domains (--threads) under --wasi need a wasmtime with
# wasi-threads ($WASMTIME_THREADS, <= 46); threadsweb runs threads in
# Chromium, as jsdom.  Compiled: c_of_ocaml 69880cea or later.
# sockets, lwtsockets and threadsockets (WASIX's, wasix: yes) are for
# --wasi only: they run in wasmer ($WASMER), a TCP server and its clients,
# UDP, names, with Lwt, with threads.
# jsdom runs in headless Chromium (its check.mjs): it needs playwright,
# PLAYWRIGHT_DIR (the directory of its node_modules) and
# PLAYWRIGHT_BROWSERS_PATH.

has_pkg() {
  case $1 in
    compiled) [ -z "$INTERPRETED" ] ;;
    interpreted) [ -n "$INTERPRETED" ] ;;
    wasmer) [ -n "$WASMER" ] ;;
    wasi-threads) [ $WASI = no ] || { [ -n "$WASMTIME_THREADS" ] && [ "$("$WASMTIME_THREADS" --version | sed 's/^wasmtime \([0-9]*\).*/\1/')" -le 46 ]; } ;;
    playwright) [ -n "${PLAYWRIGHT_DIR:-}" ] && [ -d "$PLAYWRIGHT_DIR/node_modules/playwright" ] ;;
    cps-stack) "${OCAML_EMCC_C_OF_OCAML:-c_of_ocaml}" --help 2>/dev/null | grep -q -- --cps-stack ;;
    # (the c_of_ocaml before camlc_cps_bounce_direct overflows the stack
    # without tail calls)
    cps-stack-asyncify) has_pkg cps-stack && grep -qs camlc_cps_bounce_direct "$(command -v "${OCAML_EMCC_C_OF_OCAML:-c_of_ocaml}")" ;;
    # (the c_of_ocaml before 45c785ea refuses --cps-stack with --dynlink)
    cps-stack-dynlink) has_pkg cps-stack && ! grep -qs 'not supported with --dynlink and for plugins' "$(command -v "${OCAML_EMCC_C_OF_OCAML:-c_of_ocaml}")" ;;
    ocaml\>=*) [ "$(printf '%s\n' "${1#ocaml>=}" "$(ocamlc -vnum)" | sort -V | head -1)" = "${1#ocaml>=}" ] ;;
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
    js="out/$(basename "$target").js" flags=$INTERPRETED
    if [ $WASI = yes ]; then js="out/$(basename "$target").wasm" flags="--wasi $INTERPRETED"; fi
    if [ -f Makefile ] && [ ! -f dune-project ]; then
      make clean >/dev/null; make OCAML_EMCC="$OE_ROOT/_build/default/bin/main.exe" LINK_FLAGS="$flags" "$js" 2>&1
    else
      if [ ! -f expected.txt ]; then dune build --root . "./$target.exe" 2>&1; fi
      # the all-in-one command: runtime, bytecode, stubs, link
      ocaml-emcc build "$js" --exe "$target" $flags 2>&1
    fi
    if [ -f expected.txt ]; then cp expected.txt out/native.txt
    else "./_build/default/$target.exe" $args > out/native.txt || echo "exit=$?" >> out/native.txt; fi
    if [ $WASI = yes ]; then run() { wasi_run "$@"; }
    elif grep -qs '^jspi: *yes' ocaml-emcc.conf; then
      # on node's main thread, whose stack (984 KB) is that of browsers: the
      # deep recursions of the compiled code go on JSPI's new stacks
      run() { OCAML_EMCC_STACK_MB=0 $TO "$NODE" --experimental-wasm-jspi "$@"; }
    elif grep -qs '^cps-stack: *yes' ocaml-emcc.conf; then
      # the same, the deep recursions going on in CPS on the heap
      run() { OCAML_EMCC_STACK_MB=0 $TO "$NODE" "$@"; }
    else run() { $TO "$NODE" "$@"; }; fi
    if [ -f check.mjs ]; then
      # a web page: index.html, the program, and check.mjs driving a browser
      cp index.html out/
      $TO "$NODE" check.mjs out > out/wasm.txt 2> out/wasm.err || echo "exit=$?" >> out/wasm.txt
    else
      run "$js" $args > out/wasm.txt 2> out/wasm.err || echo "exit=$?" >> out/wasm.txt
    fi
    # without wasm tail calls (tail-calls: no): none left in the module
    # (binaryen's wasm-dis, from emsdk)
    if grep -qs '^tail-calls: *no' ocaml-emcc.conf; then
      n=$("$(dirname "$(command -v emcc)")/../bin/wasm-dis" "${js%.*}.wasm" | grep -c return_call)
      [ "$n" = 0 ] || echo "$n return_call" >> out/wasm.txt
    fi
  ) > "$name/out.log" 2>&1
  if [ -n "$differ" ]; then filt() { grep -Ev "$differ" "$1"; }; else filt() { cat "$1"; }; fi
  if [ -f "$name/out/wasm.txt" ] && diff <(filt "$name/out/native.txt") <(filt "$name/out/wasm.txt") > "$name/out/diff.txt"; then
    echo "PASS $name ($(wc -l < "$name/out/native.txt") lines, $(du -k "$name/out/$(basename "$target").wasm" | cut -f1) KB wasm)"
    pass=$((pass+1))
  else
    echo "FAIL $name (see tests/$name/out.log, out/diff.txt, out/wasm.err)"; fail=$((fail+1))
  fi
done <<< "$TESTS"
echo "switch $(basename "$OPAM_SWITCH_PREFIX") (OCaml $(ocamlc -vnum)), target $TARGET_COL${INTERPRETED:+ (interpreted)}: $pass passed, $fail failed, $skip skipped"
[ $fail -eq 0 ]
