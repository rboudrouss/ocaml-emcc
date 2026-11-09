# optiml-transport: the C++ stubs, built with dune -x once their floating
# constant with GCC's suffix d (0.0d), which clang refuses, is a plain one
# (patches/).

SOURCE=opam:optiml-transport

build() {
  apply_patches "$BASE_RECIPE_DIR/patches"
  dune_stubs optiml-transport
}
