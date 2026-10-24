# secp256k1-internal: the C stubs and the bundled libsecp256k1, built with
# dune -x.  config/discover.ml enables the x86-64 assembly when the machine
# running it (a host program) is x86-64, not the C compiler's target: off.

SOURCE=opam:secp256k1-internal

build() {
  apply_patches "$BASE_RECIPE_DIR/patches"
  dune_stubs secp256k1-internal
}
