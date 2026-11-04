# unix-errno: the C stubs, built with dune -x once emscripten has Linux's
# errno codes (patches/: its libc is musl).

SOURCE=opam:unix-errno

build() {
  apply_patches "$BASE_RECIPE_DIR/patches"
  dune_stubs unix-errno
}
