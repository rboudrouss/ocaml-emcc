# secp256k1-internal: the C stubs and the bundled libsecp256k1, built with
# dune -x.  config/discover.ml enables the x86-64 assembly when the machine
# running it (a host program) is x86-64, not the C compiler's target: off.

SOURCE=opam:secp256k1-internal

build() {
  sed -i 's/^let is_x86_64 = Config.hw_is_x86_64 ()$/let is_x86_64 = false (* ocaml-emcc: wasm *)/' config/discover.ml
  grep -q 'ocaml-emcc: wasm' config/discover.ml || die "config/discover.ml: cannot disable the x86-64 assembly"
  dune_stubs secp256k1-internal
}
