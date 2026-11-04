# shared-memory-ring: the C stubs, built with dune -x once barrier.h has
# memory barriers for wasm (patches/: a sequentially consistent fence).

SOURCE=opam:shared-memory-ring

build() {
  apply_patches "$BASE_RECIPE_DIR/patches"
  dune_stubs shared-memory-ring
}
