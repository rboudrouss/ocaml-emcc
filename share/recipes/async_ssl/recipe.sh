# async_ssl: its C stubs (dune), and its OCaml side rebuilt for the target
# with patches/: its configuration program looks the functions of OpenSSL
# up with dlopen(NULL), which a program without dynamic linking does not
# have: the headers tell instead.

SOURCE=opam:async_ssl
PATCH_OCAML=1

build() {
  apply_patches "$BASE_RECIPE_DIR/patches"
  dune_stubs async_ssl
}
