# miou: the C stubs, built with dune -x once its epoll backend knows
# emscripten (patches/).  The OCaml side configured on a Linux host uses
# epoll (miou_epoll_*), which emscripten emulates with epoll_wait only (no
# epoll_pwait2): conf/select.ml then chooses epoll for the target too.

SOURCE=opam:miou

build() {
  apply_patches "$BASE_RECIPE_DIR/patches"
  dune_stubs miou
}
