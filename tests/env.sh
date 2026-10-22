# Source me: environment used by the tests (emsdk + an opam switch + dev CLI).
#   SWITCH=bench . tests/env.sh   to use another switch (default: emcc-4.14)
OE_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
. "${EMSDK:-$HOME/tools/emsdk}/emsdk_env.sh" >/dev/null 2>&1
export OPAM_SWITCH_PREFIX=$HOME/.opam/${SWITCH:-emcc-4.14}
export PATH=$OPAM_SWITCH_PREFIX/bin:$PATH
export CAML_LD_LIBRARY_PATH=$OPAM_SWITCH_PREFIX/lib/stublibs:$OPAM_SWITCH_PREFIX/lib/ocaml/stublibs
# host C libraries built locally (this machine has no -dev packages), for the native runs
if [ -d "$HOME/.local/gmp-host/lib" ]; then
  export LIBRARY_PATH=$HOME/.local/gmp-host/lib CPATH=$HOME/.local/gmp-host/include LD_LIBRARY_PATH=$HOME/.local/gmp-host/lib
  export PATH=$HOME/.local/gmp-host/bin:$PATH PKG_CONFIG_PATH=$HOME/.local/gmp-host/lib/pkgconfig:/usr/lib/x86_64-linux-gnu/pkgconfig
fi
# cmake/ninja for the clang recipe, if installed by hand in ~/tools
for d in "$HOME"/tools/cmake-*/bin "$HOME/tools/ninja"; do [ -d "$d" ] && PATH=$d:$PATH; done
ocaml-emcc() { "$OE_ROOT/_build/default/bin/main.exe" "$@"; }
# memory64 needs node >= 24 (emsdk ships one)
NODE=$(ls -d "${EMSDK:-$HOME/tools/emsdk}"/node/*/bin 2>/dev/null | tail -1)/node
