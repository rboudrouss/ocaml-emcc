# janestreet_cpuid: the C stubs, built with dune -x without the x86 CPUID
# instruction (patches/: its primitives fail, as in JavaScript), and its
# OCaml libraries rebuilt for the target with its flags shifted in 63 bits
# (31-bit integers on wasm32).

SOURCE=opam:janestreet_cpuid
PATCH_OCAML=1

build() {
  apply_patches "$BASE_RECIPE_DIR/patches"
  dune_stubs janestreet_cpuid
}
