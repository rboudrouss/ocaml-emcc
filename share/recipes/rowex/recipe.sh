# rowex: the C stubs, built with dune -x once they know emscripten
# (patches/): its radix tree uses SSE2 (or NEON) only, which emscripten
# emulates with wasm SIMD (-msimd128 -msse2).

SOURCE=opam:rowex

build() {
  apply_patches "$BASE_RECIPE_DIR/patches"
  dune_stubs rowex
}
