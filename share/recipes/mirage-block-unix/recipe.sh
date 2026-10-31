# mirage-block-unix: the C stubs, built with dune -x once the size of block
# devices is known for emscripten (patches/): as on Windows, there are no
# block device files.

SOURCE=opam:mirage-block-unix

build() {
  apply_patches "$BASE_RECIPE_DIR/patches"
  dune_stubs mirage-block-unix
}
