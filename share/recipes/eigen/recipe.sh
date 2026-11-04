# eigen: the C++ stubs, built with dune -x once the vendored Eigen compiles
# with emscripten's clang (patches/: Eigen 3.4.1's fix).

SOURCE=opam:eigen

build() {
  apply_patches "$BASE_RECIPE_DIR/patches"
  dune_stubs eigen
}
