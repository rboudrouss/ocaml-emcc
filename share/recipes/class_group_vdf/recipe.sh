# class_group_vdf: the C++ stubs, built with dune -x once size_t may be 32
# bits (wasm32), as in ctypes (patches/).  gmpxx: the gmp recipe.

SOURCE=opam:class_group_vdf

build() {
  apply_patches "$BASE_RECIPE_DIR/patches"
  dune_stubs class_group_vdf
}
