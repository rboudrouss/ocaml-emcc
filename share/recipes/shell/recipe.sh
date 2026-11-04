# shell: the C stubs, built with dune -x without disk quotas (patches/:
# they fail with ENOSYS, emscripten has no quotactl).

SOURCE=opam:shell

build() {
  apply_patches "$BASE_RECIPE_DIR/patches"
  dune_stubs shell
}
