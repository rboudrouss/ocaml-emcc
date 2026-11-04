# hdr_histogram: the C stubs and the vendored HdrHistogram_c (CMake, with
# the zlib recipe), built with dune -x once its endianness header knows
# emscripten (patches/: musl's <endian.h>, as on Linux).

SOURCE=opam:hdr_histogram

build() {
  apply_patches "$BASE_RECIPE_DIR/patches"
  dune_stubs hdr_histogram
}
