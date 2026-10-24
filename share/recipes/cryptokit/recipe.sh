# cryptokit: the C stubs, built with dune -x.  src/stubs-md5.c declares the
# runtime's caml_MD5Update with an `unsigned` length where the runtime has
# `uintnat`: the same type on wasm32, not on wasm64, where wasm-ld turns the
# call into a trap (MD5 hashing then stops with "unreachable").

SOURCE=opam:cryptokit

build() {
  apply_patches "$BASE_RECIPE_DIR/patches"
  dune_stubs cryptokit
}
