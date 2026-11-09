# owl: the C stubs, built with dune -x once they leave x86's cpuid out and
# read the dimensions of an ndarray as intnat, 32-bit on wasm32 (patches/).

SOURCE=opam:owl

build() {
  apply_patches "$BASE_RECIPE_DIR/patches"
  dune_stubs owl
}
