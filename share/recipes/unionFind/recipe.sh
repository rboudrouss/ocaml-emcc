# unionFind: its OCaml libraries rebuilt for the target with patches/: on
# wasm32 (31-bit integers), the concurrent version's identifiers are its
# counter alone, without a random salt in their high bits.  No C stubs.

SOURCE=opam:unionFind
PATCH_OCAML=1

build() {
  apply_patches "$BASE_RECIPE_DIR/patches"
}
