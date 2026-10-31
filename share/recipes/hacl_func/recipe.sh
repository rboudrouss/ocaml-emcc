# hacl_func: the C stubs (HACL*'s C, vendored), built with dune -x once
# they know emscripten (patches/): memzero is explicit_bzero, which
# emscripten has; its fallback has a #warning, an error with the package's
# -Werror.

SOURCE=opam:hacl_func

build() {
  apply_patches "$BASE_RECIPE_DIR/patches"
  dune_stubs hacl_func
}
