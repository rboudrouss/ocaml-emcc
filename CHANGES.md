## 0.1.0

First release.

- `ocaml-emcc build OUT.js`: a dune executable and the C stubs of its
  dependencies, compiled to WebAssembly with emscripten (wasm32 or wasm64).
- wasm OCaml runtime rebuilt from the sources of the switch's compiler,
  OCaml 4.08 to 5.4.
- Step-by-step commands (`setup`, `dune`, `deps`, `link`, `doctor`...) for
  projects without dune.
- Recipes for C libraries: gmp, mpfr, zlib, sqlite3, libffi, libbz2,
  libpcre2-8, zstd, gsl, camlidl, mlgmpidl, apron, clang; project recipes in
  `emcc-recipes/`.
- ctypes and ctypes-foreign support.
