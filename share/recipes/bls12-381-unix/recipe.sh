# bls12-381-unix: the C stubs, built with dune -x once they know emscripten
# (patches/): blst is built by its build.sh for emscripten (CROSS_COMPILE=em:
# no assembly), and size_t may be 32 bits (wasm32), as in ctypes.  The
# script runs through sh: in a cross context, dune looks for ./build_blst.sh
# in the host's.

SOURCE=opam:bls12-381-unix

build() {
  apply_patches "$BASE_RECIPE_DIR/patches"
  dune_stubs bls12-381-unix
}
