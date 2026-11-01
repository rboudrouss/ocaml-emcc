# async_unix: its C stubs (dune), and its OCaml side rebuilt for the target
# with patches/: without threads (emscripten cannot create any), the jobs
# of In_thread run synchronously in the async thread, as lwt's do.

SOURCE=opam:async_unix
PATCH_OCAML=1

build() {
  apply_patches "$BASE_RECIPE_DIR/patches"
  dune_stubs async_unix
}
