# lacaml: the C stubs, built with dune -x once its zdot convention is given
# for the target (patches/): it is found by running a program linked with
# BLAS, which cannot run on the host when built for wasm.

SOURCE=opam:lacaml

build() {
  apply_patches "$BASE_RECIPE_DIR/patches"
  dune_stubs lacaml
}
