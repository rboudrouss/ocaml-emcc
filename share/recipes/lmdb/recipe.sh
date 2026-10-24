# The lmdb bindings: their C stubs, built with dune -x, and the copy of LMDB
# they bundle (used when there is no system one, see the liblmdb recipe)
# opened lock-free and written through the map on emscripten, as there.

SOURCE=opam:lmdb

build() {
  ( cd liblmdb && apply_patches "$OCAML_EMCC_SHARE/recipes/liblmdb/patches" )
  dune_stubs lmdb
}
