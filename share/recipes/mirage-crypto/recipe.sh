# mirage-crypto, and mirage-crypto-ec / mirage-crypto-rng (same sources,
# their recipes include this one): the C stubs, built with dune -x once the
# sources know wasm:
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
  sed -i -e 's/^#if defined (__x86_64__)/#if defined (__wasm64__) || defined (__x86_64__)/' \
         -e 's/^#elif defined (__i386__)/#elif defined (__wasm32__) || defined (__i386__)/' \
         src/native/mirage_crypto.h
  grep -q __wasm32__ src/native/mirage_crypto.h || die "mirage_crypto.h: cannot add wasm"
  perl -0pi -e 's/\n#else\n(#error \("No known cycle-counting instruction."\))/\n#elif defined (__wasm__)\n  return Val_long ((intnat) (int64_t) (emscripten_get_now () * 1e6));\n#else\n$1/; s/^(CAMLprim value mc_cycle_counter)/#if defined (__wasm__)\n#include <emscripten\/emscripten.h>\n#endif\n\n$1/m' \
    src/native/entropy_cpu_stubs.c
  grep -q emscripten_get_now src/native/entropy_cpu_stubs.c || die "entropy_cpu_stubs.c: cannot add wasm"
  sed -i 's/ || defined(__NetBSD__)$/ || defined(__NetBSD__) || defined(__EMSCRIPTEN__)/' \
    rng/unix/mc_getrandom_stubs.c
  grep -q __EMSCRIPTEN__ rng/unix/mc_getrandom_stubs.c || die "mc_getrandom_stubs.c: cannot add emscripten"
  dune_stubs "$RECIPE_NAME"
}
