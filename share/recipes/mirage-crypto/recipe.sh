# mirage-crypto, and mirage-crypto-ec / mirage-crypto-rng (same sources,
# their recipes include this one): the C stubs, built with dune -x once the
# sources know wasm (patches/):
# - src/native/mirage_crypto.h picks the 32- or 64-bit C code (fiat,
#   tables) from the architecture macros and stops on unknown ones; the
#   OCaml side chooses with Sys.word_size, which is 32 on wasm32;
# - the cycle counter (an entropy source of the RNG) reads the CPU's; on
#   wasm, the high resolution clock (performance.now, in ns);
# - the OS entropy of mirage-crypto-rng.unix (getrandom) comes from
#   getentropy, as on the BSDs (emscripten: crypto.getRandomValues).
# The CPU acceleration (AES-NI...) stays off: config/cfg.ml sees no x86.

SOURCE=opam:$RECIPE_NAME

build() {
  apply_patches "$BASE_RECIPE_DIR/patches"
  dune_stubs "$RECIPE_NAME"
}
