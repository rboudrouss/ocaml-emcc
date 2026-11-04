# janestreet_cpuid: the C stubs, built with dune -x without the x86 CPUID
# instruction (patches/: its primitives fail, as in JavaScript).

SOURCE=opam:janestreet_cpuid

build() {
  apply_patches "$BASE_RECIPE_DIR/patches"
  dune_stubs janestreet_cpuid
}
