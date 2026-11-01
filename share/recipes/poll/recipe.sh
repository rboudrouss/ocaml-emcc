# poll: the C stubs, built with dune -x once its epoll backend knows
# emscripten (patches/): the OCaml side configured on a Linux host uses epoll
# (poll_stub_epoll*), which emscripten emulates.

SOURCE=opam:poll

build() {
  apply_patches "$BASE_RECIPE_DIR/patches"
  dune_stubs poll
}
