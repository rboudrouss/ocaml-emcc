## unreleased

- Installed packages configured against a host library: in the wasm context
  of `dune -x`, `llvm-config` is the `clang` recipe's (as `pkg-config`
  already was the sysroot's), and `-lclang-cpp`, `-lclangX`,
  `-lLLVM-<major>` build the `clang` recipe, which links the LLVM libraries
  with `-lclang-cpp`. A package binding clang's C++ API, installed with
  opam against the host's LLVM, builds without configuration; its stubs
  used to be compiled against the host's LLVM headers. Recipes declare such names with `LIB_PATTERNS=`. A `clang`
  recipe built before needs `ocaml-emcc install --force clang`.
- The `mpfr` recipe installs `mpfr.pc`: `pkg-config mpfr` failed in the
  wasm context, and packages asking it fell back to compiling their C files
  without their own flags.

## 0.2.0

Tried on FFI-heavy packages (mirage-crypto, lwt, cryptokit, minisat,
ocaml-lua, stb_image, extunix, lz4, snappy, argon2, ocaml-expat, lmdb, glpk,
fftw3, secp256k1-internal, tsdl...); fixes for what broke.

- wasm32: integer literals beyond 31 bits in the bytecode's DATA section
  are wrapped to 31 bits instead of aborting the program at startup (optint,
  hence checkseum and decompress, holds such literals in its 32-bit code).
- Node: the standard streams are the process's, as bytes (binary output and
  input were decoded as UTF-8, NUL bytes dropped).
- C++ stubs and libraries with exceptions (`-fwasm-exceptions`).
- `-pthread` dropped from the flags of stubs (lwt): `caml_state` became a
  thread-local variable there.
- wasm64: `caml_ba_alloc_dims` gets its dimensions as `intnat` (stubs
  passing `int`s corrupted the heap); libffi writes widened return values
  at their address (ctypes-foreign calls returning `int` read 0).
- `link` shows the C functions whose calls wasm-ld turned into traps
  (signature mismatches between C files), it used to hide them.
- `dune -x`: the tools of the host next to the toolchain's `ocamlc`
  (`%{ocaml}`...); `pkg-config` only shows the sysroot's libraries to the
  wasm context; C tests see the sysroot's headers and libraries; archives
  holding host objects (a vendored library built by `make`) are rebuilt from
  the native build's C files; a kept `_build` of another tool is left
  alone; a package that produced no archive is not marked as built.
- Packages without dune: the C files behind the native build's archive.
- `link` builds the libraries named by `-lX` in `.cma` files (custom-only
  libraries such as stb_image, C libraries bound with ctypes-foreign).
- System recipes are also found from the `-lX` of a package's `.cma` files.
- New recipes: liblz4, snappy, expat, fftw3, glpk, libargon2, liblmdb, sdl2;
  mirage-crypto (-ec, -rng), lwt, cryptokit, secp256k1-internal, lmdb.

## 0.1.0

First release.

- `ocaml-emcc build OUT.js`: a dune executable and the C stubs of its
  dependencies, compiled to WebAssembly with emscripten (wasm32 or wasm64).
- wasm OCaml runtime rebuilt from the sources of the switch's compiler,
  OCaml 4.08 to 5.5.
- Step-by-step commands (`setup`, `dune`, `deps`, `link`, `doctor`...) for
  projects without dune.
- Recipes for C libraries: gmp, mpfr, zlib, sqlite3, libffi, libbz2,
  libpcre2-8, zstd, gsl, camlidl, mlgmpidl, apron, clang; project recipes in
  `emcc-recipes/`.
- ctypes and ctypes-foreign support.
