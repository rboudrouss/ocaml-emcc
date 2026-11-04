# codex: the C stubs, built with dune -x once their 32-bit branches compile
# (patches/: wasm32).

SOURCE=opam:codex

build() {
  apply_patches "$BASE_RECIPE_DIR/patches"
  dune_stubs codex
}
