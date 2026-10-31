# eio_posix: the C stubs, built with dune -x once they know emscripten
# (patches/): the OS entropy comes from getentropy (crypto.getRandomValues)
# instead of the BSDs' arc4random_buf, which emscripten's libc lacks.

SOURCE=opam:eio_posix

build() {
  apply_patches "$BASE_RECIPE_DIR/patches"
  dune_stubs eio_posix
}
