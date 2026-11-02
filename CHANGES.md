## Unreleased

- js_of_ocaml's JavaScript primitives: programs using the libraries
  js_of_ocaml (`Js`, `Dom_html`, its ppx, js_of_ocaml-lwt, Brr...) run in
  browsers and node, interpreted or compiled, on both targets, with the
  conventions of wasm_of_ocaml for JavaScript values. Callbacks keep
  running after the main program, JavaScript exceptions are
  `Js_error.Exn` (or `Failure`), and `Js.export` gives functions to the
  page. Their stubs, which only abort, are no longer linked.
- `--js-file FILE` (and `js-files:` in `ocaml-emcc.conf`): primitives of
  the program implemented in JavaScript, called with JavaScript values.
- Plugins, in compiled mode: `ocaml-emcc plugin LIB.cma -o LIB.wasm`
  compiles a library to a wasm side module, which a program linked with
  `--dynlink` loads with the new library `ocaml-emcc.dynlink`
  (`Emcc_dynlink.loadfile`, or `load_url` to fetch it in a web page).
- Added recipes: async_unix, bls12-381-unix, bytesrw, cairo,
  class_group_vdf, core_unix, cpu, eio_posix, faad, ffmpeg, freetype,
  frei0r, gd, glfw3, hacl_func, lacaml, lame, libev, libevent,
  libfontconfig, libjpeg, liblo, liblzo2, libogg, libopus, libpng, libssl,
  mad, memcpy, miou, mirage-block-unix, ncurses, nlopt, num, oniguruma,
  openblas, osdp, pixman, poll, rowex, scrypt, secp256k1, setcore, shine.
  zlib installs its pkg-config file and comes from its GitHub releases
  (zlib.net fails at times), gmp installs its C++ interface (gmpxx).
- Jane Street's libraries on wasm32: jst-config, the libraries reading its
  configuration (time_now, core, core_unix) and those compiled against an
  interface that differs there (the async stack) are rebuilt for the
  target, as ctypes users are. Their 64-bit code treated an `Int63` as an
  `int`, where Base has an `int64` on wasm32 (a crash in `caml_int64_div`
  in async). The configuration is the host's but for the word size and
  endianness. core and async run on wasm32, interpreted or compiled, in
  node and with `--wasi`. Without threads, Async's thread pool runs its
  jobs synchronously (async_unix recipe), as lwt does.
- dune-configurator's C tests in the wasm context read the runtime's
  `caml/config.h`, not the host's (its `-I` of the host's standard library
  is replaced).
- OCaml 5.1 and later: the runtime is built with zstd when the switch's
  compiler is, and can read compressed marshalled data: the `.cmi` and
  `.cmt` files (`ocamlc.byte`, merlin, odoc, toplevels failed with
  "Corrupted compiled interface") and compiler-libs' `Compression`.
  Existing runtimes: `ocaml-emcc setup --force`.
- wasm32: the minor heap is 1M words (4 MB) by default instead of 256k
  (1 MB, half a 64-bit native program's): programs allocating much spent
  their time in minor collections (binary_trees compiled: 1.26 s, now
  1.01 s; a list pipeline: 0.80 s, now 0.44 s), for 3 ms and 3 MB more at
  startup. `OCAMLRUNPARAM=s=...` still sets it; wasm64 is unchanged.
  Existing runtimes: `ocaml-emcc setup --force`.
- `--wasi`: pipes are buffers in memory (Async's and lwt's wake-up pipes),
  `fchdir` works, `sendmsg` and `recvmsg` fail with `ENOSYS` instead of
  being imported from JavaScript, and a descriptor the host reports as a
  socket is a FIFO (node's piped standard streams).
- Recipes: `PATCH_OCAML=1` rebuilds the OCaml libraries of the package of an
  `opam:` recipe for the target with its patches. These patches are also
  applied to the builds for the target of ctypes users and Jane Street's
  libraries (core_unix's C stubs), whose stamps record them.
- A primitive that no linked library defines (a stub written for one OS
  only: epoll, Windows...) becomes a stub raising `Failure "NAME not
  implemented"` when called, as with js_of_ocaml: `link` warns, and a
  program that never calls it runs. `--no-missing-primitives` makes it a
  link error, as before.
- Compiled mode: the generated C is split in parts (`c_of_ocaml --split`),
  compiled separately, and a part left unchanged is not compiled again.
- The heap is sized with `-sINITIAL_HEAP` (emscripten 3.1.55 and later)
  unless the user's flags size the memory: with `MAXIMUM_MEMORY`, the
  initial memory was fixed at 16 MB, which the static data alone can exceed
  (72 MB of embedded bytecode for core with `-linkall`).
- The C compiler wrapper drops `-march`, `-mtune`, `-mcpu`, `-fopenmp`
  (emscripten's OpenMP needs threads: the code runs serially) and the
  host's `-I/usr/include...`; `-Ofast` becomes `-O3 -ffast-math`.
- `ocamlc -config` in the wasm context reports `architecture: none`: stubs
  choosing their C code with `%{architecture}` take the portable one (num's
  bng, without amd64 assembly).
- A package that does not lay C types out is rebuilt for the target only if
  an interface it was compiled against differs there: otherwise its build
  was inconsistent with the packages depending on it (frama-c's plugins).
  One already built is only built again if one of its dependencies was
  rebuilt, and one depending on no root (ctypes, jst-config) is checked
  without fetching its sources.
- The stubs of a dune package are built with what its opam build selects:
  `--release` instead of `-p PKG` when it builds the whole tree (frama-c's
  plugins, which are other packages).
- Stubs found without a recipe nor dune: a C file including the OCaml
  headers through a local header counts (b0's `b0_stubs.h`), those of the
  library are preferred when the package has several (bytesrw), and
  without the native archive the files that do not compile are left out.
- Recipes: `meson_setup` configures a meson project for the target (cross
  file, static libraries, the sysroot's pkg-config files).
- OCaml 5: the runtime has a single domain (`Domain.spawn` already
  failed). It reserved at startup the minor heaps of 16 domains in wasm32
  and 128 in wasm64, which emscripten's `mmap` allocates and clears: a
  hello world now starts with 16 MB of wasm memory instead of 29 MB
  (wasm32) and 317 MB (wasm64), and ~10 ms (wasm32) and ~130 ms (wasm64)
  sooner. `OCAMLRUNPARAM=d=N` still sets it (5.3 and later). Existing
  runtimes: `ocaml-emcc setup --force`.
- The stubs built with dune or from a package's native build, and the
  packages rebuilt for ctypes, record the version of the toolchain's
  wrappers in their stamps: a fix of the wrappers builds them again.
  Those built before the pkg-config fix below had the host's C flags
  (ctypes-foreign's wasm64 stubs: the host's `ffi_cif`, 8 bytes too
  small, and calls failing with "Unexpected type 0").
- The stubs whose C signature differs from their OCaml arity are found by
  reading the wasm objects of the libraries (`linking` section, function
  types), no longer by parsing wasm-ld's warnings, whose wording could
  change with emsdk. `link` now links once instead of twice when stubs
  need adapters.
- What the recipe driver decided moved from bash to OCaml: which recipes
  to build (stamps, `DEPENDS`), their sources (opam, tarballs, git, system
  libraries), the C stubs of opam packages (dune, native build, blind),
  the builds for the target of ctypes users, the patched dune and the
  toolchain's wrappers. `share/driver.sh` (1084 lines, now 339) reads
  recipes and runs their `build` function; the recipe format and helpers
  are unchanged. Unit tests (`dune test`) cover the logic that moved.
- dune-configurator runs `pkg-config` from a temporary
  directory, where the sysroot's wrapper took it for the host context: the
  wasm stubs got the host's C flags (`gsl` read its headers from
  `/usr/include`). The wrapper now goes by `INSIDE_DUNE`.
- Compiled mode (experimental): with `--compiled`, `build` and `link`
  compile the bytecode to C with c_of_ocaml instead of interpreting it.
  Programs run 2 to 5 times faster in node, and their `.wasm` is 2 to 8
  times smaller. It works with OCaml 4.14 and 5, on wasm32 and wasm64,
  effect handlers included. The stubs get the same signature adapters as
  with the interpreter. `tests/run.sh --compiled` runs the tests in this
  mode.
- The bytecode interpreter runs about twice as fast in node and browsers
  (fib: 52.7 s before, 23.9 s after, 15.8 s for the native `ocamlrun`).
  V8 optimizes a wasm function for its next calls only, so the
  interpreter, called once for the whole program, stayed in the baseline
  tier: it now returns to its caller every 2^20 polls and is called again.
  Its `setjmp`, which wrapped each of its calls in an exception handler,
  moved to that caller (`patches/4.x/` and `patches/5.x/`).
- New recipe: `raylib` (raylib-ocaml). The raylib it vendors is built for
  raylib's `PLATFORM_WEB` (emscripten's GLFW, WebGL), linked with
  `-sASYNCIFY` so that the usual `while not (window_should_close ())`
  loop runs in a browser (`-- -sJSPI` replaces it). Test: `raylib`.
  raylib-ocaml's master after 2.3.0 builds it for the web itself: the
  recipe's patch for it only applies to the releases before, and now
  builds from fresh sources too (it ran host helpers it did not depend on).
- The placeholder `dll<name>.so` of a wasm stub archive defines its C
  functions (aborting if called): a (ctypes) generator linked against a
  library of its package with stubs could not start ("unknown C
  primitive").
- The shadow build of a package installing many `.cmi` files (raylib) was
  reported as failed: `find | grep -q`, under `pipefail`, failed when
  `find` was killed by SIGPIPE. The same in the check for wasm archives.
- `-cclib "-l X"` is read as `-lX`.

## 0.4.0

- Recipe patches are placed by their text, not their line numbers
  (`share/tools/patch.awk`): the old text of each hunk must occur once in
  the file, `@@` lines need no numbers, and the context only has to tell
  the place apart. A hunk matching no place, or several, stops the build
  (GNU patch applied some of ours with fuzz, at the place it guessed). The
  `ocaml` patches lost their spare context, and `patches/5.1/` and
  `patches/5.2+/` became `patches/5.1+/`.
- New recipes for packages that the default paths cannot build:
  `mlcuddidl` (CUDD configured for the target, stubs generated by camlidl
  from its `.idl` files), `hacl-star-raw` (HACL*'s portable C with cmake,
  ctypes stubs printed by generators run on the host, the vectorized and
  Vale variants trapping) and `mccs` (GLPK silenced with `glp_term_out`:
  musl writes what was written to a closed `stdout` once fd 1 is back).
  An `ocaml-lua` recipe unpacks and patches the Lua it bundles, as its opam
  file does before dune runs (it only built from a kept build directory).
  Tests: `cudd`, `hacl`, `mccs`, and `posix` (posix-time2, -socket, -stat).
- ctypes bindings are rebuilt for wasm64 too: emscripten's musl does not
  lay the libc's structs out as glibc (`struct stat`'s `st_size` was
  glibc's `st_mtime`). When a package rebuilt for the target is rebuilt
  again (another version), the packages depending on it are too; the
  builds of versions no longer installed, or made against other versions
  of their dependencies, are dropped first (ctypes 0.24's next to
  ctypes-foreign 0.22: "inconsistent assumptions"); a package depending on
  one that cannot be rebuilt (ctypes 0.20, built by make) keeps the host's
  build, and `link` warns. A package that dune builds no library of
  (hacl-star-raw, built by make next to hacl-star) keeps the host's build.
- A recipe built from an opam package (`SOURCE=opam:`) is built again for
  another version of it, as dune-built stub libraries already were
  (recipes built before: `install --force`).
- opam commands of the driver act on the switch being built for, not on
  opam's current one; the sources of a package come from its build
  directory or `opam source`, which applies the `patches:` of its opam
  file (not from the archive in `.opam-switch/sources`, which has none).
- wasm64: `getaddrinfo` is resolved in C (`compat.c`): emscripten's
  JavaScript one throws on memory64 (`BigInt(null)`), so did
  `Unix.getaddrinfo`.
- Stubs compiled blindly get the include directories of the package's
  opam dependencies (ctypes before 0.21: `ocaml_integers.h`). The native
  build behind the archives that `dune -x` builds with host objects is made
  when `_build/default` lacks them (`dune -x` leaves only what the target
  needs there). A recipe asked for a library it did not build is built
  again.
- `mlgmpidl`: its stubs regenerated with camlidl get `MPFR_VERSION_MAJOR`
  (apron's test failed without a kept build directory). `zarith`: the
  defines of its configure, and an empty `z_features.h` before 1.12.
- Tests: `pcre2` and `lz4` dropped, `clibs` keeps checkseum and
  bigstringaf (the others needed nothing other tests do not cover).
  `tests/versions.sh` runs tests against several versions of their
  package.

## 0.3.0

- OCaml 5.0 to 5.3: the `ocaml` recipe builds their runtime. They commit
  the minor heap with `mmap(MAP_FIXED)`, which emscripten lacks ("Failed
  to create main domain"): `patches/5.0/` and `patches/5.1/` commit it
  with `mprotect` as 5.2 and later do (`patches/5.4+/` becomes
  `patches/5.2+/`). 5.0 calls `pthread_getaffinity_np`, which its
  configure only compiles (`patches/5.0/`), and names the otherlibs stub
  archives without the `byt` suffix.
- OCaml 5: `-pthread` is kept out of the runtime by giving
  `PTHREAD_CFLAGS=-D_REENTRANT` to configure, instead of editing
  `Makefile.config` (5.0 put it in `OC_CFLAGS`, which the edit missed: "no
  domain lock held").
- The C compiler of the wasm context drops `CPATH`, `C_INCLUDE_PATH`,
  `CPLUS_INCLUDE_PATH` and `LIBRARY_PATH`: their host headers came before
  those of the sysroot (ctypes-foreign's stubs were compiled with the
  host's `ffi.h`: "Unexpected type 0" at the first call).
- ctypes on wasm32, OCaml 5.2 and later: a library compiled against the
  host's ctypes (ctypes-foreign, once zstd had rebuilt ctypes) is rebuilt
  for wasm32 again. ocamlc quotes the files of "make inconsistent
  assumptions", which hid them.
- A stub library of the sysroot built from an opam package (with dune, or
  blindly) for another version than the installed one, after an `opam
  upgrade`, is built again: the old one was linked (digestif 1.4's blake3
  primitives undefined).
- A library of the compiler missing from the runtime of the sysroot
  (`libthreads.a`, built since) has the runtime built again, instead of
  failing ("libthreads.a (wasm) not found").
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
  to the sources of every version from 4.08 to 5.5 (on 5.0 to 5.3, the
  wasm32 build used to stop on the DATA literals). A recipe's checksum
  covers its patches: the "recipe changed" note shows when they change.

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
