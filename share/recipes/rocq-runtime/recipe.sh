# rocq-runtime: the C stubs, built with dune -x without Linux's perf
# counter (patches/: it fails to initialize, as without perf events).
# Its OCaml libraries are built for the target too: their 63-bit integers
# and floats are uint63_%{ocaml-config:int_size}.ml..., the 31-bit
# versions on wasm32.  Its configure.exe, run by the build, has C stubs:
# built for the host (HOST_TOOLS).

SOURCE=opam:rocq-runtime
PATCH_OCAML=1
HOST_TOOLS=1

build() {
  apply_patches "$BASE_RECIPE_DIR/patches"
  dune_stubs rocq-runtime
}
