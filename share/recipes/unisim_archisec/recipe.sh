# unisim_archisec: the C++ stubs, built with dune -x once the floating-point
# exceptions are defined (patches/): wasm has no exception flags, and
# emscripten's fenv.h defines none.  They get distinct bits, never raised
# (feraiseexcept ignores them, fetestexcept returns none).

SOURCE=opam:unisim_archisec

build() {
  apply_patches "$BASE_RECIPE_DIR/patches"
  dune_stubs unisim_archisec
}
