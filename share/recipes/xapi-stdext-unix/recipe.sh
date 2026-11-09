# xapi-stdext-unix: the C stubs, built with dune -x once they know
# emscripten (patches/): no block device files (their size fails with
# ENOTSUP), and TCP's socket options at the level IPPROTO_TCP.

SOURCE=opam:xapi-stdext-unix

build() {
  apply_patches "$BASE_RECIPE_DIR/patches"
  dune_stubs xapi-stdext-unix
}
