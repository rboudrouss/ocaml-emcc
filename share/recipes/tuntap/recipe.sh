# tuntap: the C stubs, built with dune -x without tun/tap devices
# (patches/: opening one fails with ENOSYS, as emscripten has none).

SOURCE=opam:tuntap

build() {
  apply_patches "$BASE_RECIPE_DIR/patches"
  dune_stubs tuntap
}
