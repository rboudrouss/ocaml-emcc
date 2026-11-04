# bls12-381-signature: the C stubs, built with dune -x once they know a
# 32-bit size_t (patches/: wasm32).

SOURCE=opam:bls12-381-signature

build() {
  apply_patches "$BASE_RECIPE_DIR/patches"
  dune_stubs bls12-381-signature
}
