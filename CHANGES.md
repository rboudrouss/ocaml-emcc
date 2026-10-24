## Unreleased

- ctypes on wasm32: ctypes and the packages of the program depending on it
  are rebuilt for wasm32 (`driver.sh shadow`) into the sysroot's findlib
  directory, which the toolchain searches first, and `build` builds the
  bytecode against them: struct layouts, `sizeof` and arrays now have the
  sizes of wasm32, for the structs laid out at run time and for the type
  descriptions generated when the package is built (yaml now works on
  wasm32). `link` and `doctor` warn when a bytecode was compiled against
  the host's builds, or uses a package that could not be rebuilt (packages
  without dune).
- dune's `(ctypes)` stanza (a project's, or a package's): dune links its
  generators natively only (ocaml/dune#13650), which the wasm context
  cannot. A project or package using it is built by a dune patched to link
  them as custom bytecode without `ocamlopt`
  (`share/tools/dune/ctypes-linkage.patch`), built once per version from
  the sources of the switch's dune: its structs have the layouts of the
  target. The `build` of a project with the stanza used to fail, and the
  stubs of such packages came from their native build.
- The C compiler of the wasm context makes node scripts of the executables
  it links (`-sEXECUTABLE`), for build rules to run, with the node of
  emscripten's configuration (memory64 for wasm64).
- The `ocamlc` wrapper of the toolchains no longer writes placeholder
  `dllX.so` files in the host's switch, next to its installed libraries.
  On OCaml 4.x, those of `unix` and `str` in `lib/ocaml` (in `ld.conf`)
  hid the real ones: the host's `ocaml unix.cma` and `ocamlc unix.cma`
  failed (`The external function unix_waitpid is not available`). A
  switch where `build` ran before keeps them: delete the empty `dll*.so`
  of `lib/` outside the `stublibs` directories.

- `--wasi` (`link`, `build`): `OUT.wasm` is a WASI module, importing only
  WASI functions, for wasmtime, node's WASI and other WASI hosts (wasm32).
  emscripten's standalone libc fails to open or `stat` a file and imports
  the rest of the file system from JavaScript: `share/runtime/wasi.c`
  implements these system calls with WASI (preopened directories, a
  current directory), sleeping, `select` and `getrusage` with
  `poll_oneoff` and the WASI clocks, `dup`/`dup2` of an opened file by
  opening it again, file locks and owners as no-ops. Linked with
  `-sPURE_WASI`, the module is translated to the standard exception
  handling instructions (exnref) that WASI hosts implement.
  `tests/run.sh --wasi` runs the suite this way (wasmtime or node's WASI),
  and CI does on 4.14 and 5.5.
- A standalone `OUT.wasm` (with or without `--wasi`) has its bytecode as C
  arrays started by `caml_startup_code`, instead of a file of emscripten's
  JavaScript file system, which it does not have. `link` lists the imports
  that are not WASI.
- The functions of `share/runtime/*.c` (`compat.c`, `dlsym.c`, `wasi.c`)
  that the program's libraries define as well are left out: the program's
  are linked.
- `ocaml` recipe: on wasm32, the integer literals beyond 31 bits are
  wrapped by `caml_startup_code` as well; the debug events of a program
  started by `caml_startup_code` can come from memory (backtraces of
  standalone modules have their locations). A runtime built before needs
  `ocaml-emcc setup --force` (`link` says so).
- Recipes change the sources they build with patches (`patches/` next to
  `recipe.sh`) instead of `sed` and `perl`: ocaml, libffi, liblmdb, lmdb,
  lwt, mirage-crypto, cryptokit, secp256k1-internal. The `ocaml` ones apply
  to the sources of every version from 4.08 to 5.5 (on 5.0 to 5.3, still
  untested, the wasm32 build used to stop on the DATA literals). A recipe's checksum covers its patches:
  the "recipe changed" note shows when they change.

## 0.2.1

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
- `tests/depgraph`: an installed package (mpfr through `pkg-config`, zarith)
  whose whole dependency graph is built from the program.

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
