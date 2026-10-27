#!/usr/bin/env bash
# Run tests against several versions of the package they are about: each
# version is installed in the switch with opam (its dependents with it),
# the tests are run (tests/run.sh), and the packages of the switch are
# installed back at the end of each line.
#   tests/versions.sh [--target wasm32|wasm64|--wasi] [test...]
#   SWITCH=emcc-4.14 OPAMFLAGS=--assume-depexts tests/versions.sh zarith lwt
# Prints a line per version, then a summary line per package.
set -u
cd "$(dirname "$0")"; TESTS_DIR=$PWD
. ./env.sh
RUN_ARGS=()
while [ $# -gt 0 ]; do
  case $1 in
    --target) RUN_ARGS=(--target "$2"); shift 2 ;;
    --wasi) RUN_ARGS=(--wasi); shift ;;
    *) break ;;
  esac
done

# tests | package whose versions change | versions, oldest first
VERSIONS='
zarith                | zarith             | 1.11 1.12 1.13 1.14
mixed                 | digestif           | 1.1.2 1.3.0 1.4.1
sqlite                | sqlite3            | 5.0.3 5.2.0 5.4.2
zstd                  | zstd               | 0.3 0.4
gsl                   | gsl                | 1.22.0 1.24.3 1.25.1
camlzip               | camlzip            | 1.11 1.13 1.14
ctypes cstanza posix  | ctypes-foreign     | 0.21.1 0.22.0 0.23.0 0.24.0
yaml                  | yaml               | 3.0.1 3.1.0 3.2.0
mcrypto               | mirage-crypto      | 2.0.2 2.2.0 2.4.1
lwt                   | lwt                | 5.6.1 5.9.2 6.1.2
cryptokit             | cryptokit          | 1.20 1.21.1
secp                  | secp256k1-internal | 0.3.1 0.4.0
apron                 | apron              | v0.9.13 v0.9.14 v0.9.15
extunix               | extunix            | 0.3.2 0.4.1 0.4.4
stb                   | stb_image          | 0.4 0.5
minisat               | minisat            | 0.4 0.6
cudd                  | mlcuddidl          | 3.0.6 3.0.7 3.0.8
hacl                  | hacl-star          | 0.5.0 0.6.2 0.7.2
posix                 | posix-socket       | 2.2.0 3.0.0 4.0.2
mccs                  | mccs               | 1.1+13 1.1+17 1.1+19
'

trim() { sed -e 's/^ *//' -e 's/ *$//'; }
opam_install() {
  # shellcheck disable=SC2086
  opam install --switch "${SWITCH:-emcc-4.14}" -y ${OPAMFLAGS:-} "$@" > "$TESTS_DIR/versions-opam.log" 2>&1
}
while IFS='|' read -r name pkg versions; do
  name=$(echo "$name" | trim); [ -n "$name" ] || continue
  if [ $# -gt 0 ] && [[ " $* " != *" ${name%% *} "* ]]; then continue; fi
  pkg=$(echo "$pkg" | trim); versions=$(echo "$versions" | trim)
  # the packages of the switch, put back afterwards: a version may take
  # others along (zstd 0.3 downgrades ctypes, ctypes 0.21 removes posix-*)
  before=$(opam list --switch "${SWITCH:-emcc-4.14}" -i -s --columns=name,version 2>/dev/null | awk '{ print $1 "." $2 }')
  summary=
  for v in $versions; do
    if ! opam_install "$pkg.$v"; then
      cp "$TESTS_DIR/versions-opam.log" "$TESTS_DIR/versions-opam-$pkg.$v.log"
      echo "$pkg.$v: not installable (tests/versions-opam-$pkg.$v.log)"; summary="$summary $v:opam"; continue
    fi
    # shellcheck disable=SC2086
    out=$(./run.sh "${RUN_ARGS[@]}" $name 2>&1 | grep -E '^(PASS|FAIL|SKIP) ' | cut -d' ' -f1,2 | tr '\n' ' ')
    echo "$pkg.$v: $out"
    summary="$summary $v:[${out% }]"
  done
  # shellcheck disable=SC2086
  opam_install $before || echo "$name: could not install the packages of the switch back"
  echo "== $pkg:$summary"
done <<< "$VERSIONS"
