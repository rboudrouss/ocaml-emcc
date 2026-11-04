# ocaml_intrinsics: the C stubs, built with dune -x once crc_stubs.c has
# CRC-32C for wasm (patches/: in software, as the crc32 instructions of
# x86 and arm64 compute it).

SOURCE=opam:ocaml_intrinsics

build() {
  apply_patches "$BASE_RECIPE_DIR/patches"
  dune_stubs ocaml_intrinsics
}
