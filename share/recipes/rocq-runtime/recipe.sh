# rocq-runtime: the C stubs, built with dune -x without Linux's perf
# counter (patches/: it fails to initialize, as without perf events).
# Its OCaml side assumes 63-bit integers (uint63_63.ml, chosen by the
# host's int_size): wasm64.

SOURCE=opam:rocq-runtime

build() {
  apply_patches "$BASE_RECIPE_DIR/patches"
  dune_stubs rocq-runtime
}
