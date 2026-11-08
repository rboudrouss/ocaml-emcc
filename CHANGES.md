## Unreleased

- Compiled mode is the default: `build` and `link` compile the bytecode
  to C with c_of_ocaml (in `PATH`, or `$OCAML_EMCC_C_OF_OCAML`). The
  interpreter stays available with `--interpreted` (or `interpreted: yes`
  in `ocaml-emcc.conf`), less tested, and is used with OCaml before 4.14;
  `--compiled` is still accepted. `tests/run.sh --interpreted` runs the
  tests interpreted.
- The dune patched for the (ctypes) stanza is built again once dune is
  upgraded (the copy of the previous one, read-only, made it fail:
  bls12-381, lilv).
- `--jspi` (`jspi: yes` in `ocaml-emcc.conf`) links with JSPI (emcc's
  `-sJSPI`): `main` is asynchronous, and the compiled code recurses
  deeper than the stack of a browser (6 000 to 15 000 nested calls) on new
  stacks of the engine (c_of_ocaml's segmented stack), in Chrome and Edge
  137 or later, or node 24 with `--experimental-wasm-jspi`. Without JSPI,
  the program says so instead of failing to instantiate. Under `--wasi`,
  the compiled code has no new stacks (it imported emscripten's JavaScript
  for them, which a WASI host lacks). It also replaces `-sASYNCIFY` for C
  that suspends (`emscripten_sleep`, raylib's loop), keeping the tail
  calls, for a smaller program which may suspend under the code of
  plugins.
- `--cps-stack` (`cps-stack: yes`), compiled: the recursive functions get
  a version in continuation-passing style (c_of_ocaml's `--cps-stack`),
  in which a recursion deeper than the stack of a browser goes on, on the
  heap, in every browser and with a synchronous `main`, for a program
  about 1.5 times bigger. With `--dynlink`, the plugins have it too
  (`plugin --main` follows the program, or `plugin --cps-stack`), and all
  have double translation. Not with `--effects` other than
  `double-translation`. A C stack under 1 MB (`--stack-size`) gets a
  warning, with `--jspi` too. It works with `-sASYNCIFY` (no wasm tail
  calls), C suspending under a deep recursion, with a c_of_ocaml whose
  returns to the continuations bounce on the trampoline.
- Compiled with `-sASYNCIFY`: asyncify saves the stack in 1 MB
  (`-sASYNCIFY_STACK_SIZE=1048576`, unless given) rather than 4 KB, which
  suspending under some hundred frames exceeded. Only `-sASYNCIFY` itself
  turns off the tail calls, not its other settings (`-sASYNCIFY_IMPORTS`).
- `--no-tail-calls` (`tail-calls: no`), compiled: without wasm tail
  calls (emcc's `-mtail-call`), for the browsers that lack them (Safari
  before 18.2, Firefox before 121, Chrome before 112), usually with
  `--cps-stack`. `-sASYNCIFY` implies it. Its plugins follow (`plugin
  --main`, or `plugin --no-tail-calls`).
- Compiled mode compiles the parts of the C in parallel, the biggest
  first, `$OCAML_EMCC_JOBS` at a time (default: the number of
  processors).
- The dune commands of several ocaml-emcc running at the same time take
  turns (a lock in the temporary directory) instead of failing ("Another
  Dune instance is currently running"): the links of a project can run in
  parallel.
- Compiled mode leaves to c_of_ocaml what is about the code, and keeps
  here what is about emscripten; it needs a c_of_ocaml with a manifest
  (`--manifest`) and `camlc_main`. The primitives the code calls and the
  effects it was compiled with come from c_of_ocaml's manifest instead of
  its C (the marker that `plugin --main` reads followed `--effects`, not
  c_of_ocaml's choice). Backtraces follow the debug events of the
  bytecode on c_of_ocaml's side, which warns of integer literals beyond 31
  bits itself (`link` only does for the interpreter). The program starts
  from `main.c`, and JSPI's new stacks for the segmented stack come from
  `share/runtime/jspi.c`, linked with `--jspi` only. The C functions the
  code of plugins calls are linked in the program by c_of_ocaml
  (`asin` and `acos` were missing from those `link --dynlink` exported).
- Effect handlers with `--dynlink`: a program whose own code performs
  effects is compiled with them (double translation) without `--effects`,
  instead of raising `Effect.Unhandled` (c_of_ocaml 3456533a), and
  `plugin` refuses a plugin performing effects for a program without
  them, or without `--main`, unless `--effects disabled`.
- `--dynlink` is implied when a compiled program (not a standalone
  `.wasm`) links `Emcc_dynlink`.
- The C of an executable's own `(foreign_stubs ...)` is linked (its
  primitives raised `Failure "... not implemented"`).
- A program with plugins exports the usual C functions of libc
  (`snprintf`, `strchr`, `qsort`...) even when it does not call them, as
  the C of its plugins may (which C the program links depends on its
  primitives).
- Interpreted, `--dynlink` loads the C stubs of bytecode plugins (OCaml's
  `Dynlink`, of a `.cma` naming a `dllX.so`), which `plugin --interpreted
  LIB.cma -o DIR` builds as wasm side modules (`--main` naming an
  interpreted program implies it). A host `dllX.so` that `Dynlink` finds
  first gives way to the wasm one of `$OCAML_EMCC_STUBLIBS` or the current
  directory. `link` notes that Dynlink's plugins with C need
  `--dynlink`.
- Plugins of a program linked with `--threads` load: `plugin --main`
  links them with `-pthread`, for the program's shared memory, as does
  `plugin --threads` (they failed with "could not load dynamic lib").
  The callback of `Emcc_dynlink.load_url` runs after `main` in such a
  program (`main` running in a pthread, the program exited first).
  With `--jspi`, the threads other than the main one load the plugins
  synchronously (a thread started after a plugin is loaded failed:
  `SuspendError`, emscripten's loads suspending outside of JSPI). A
  plugin's entry is read as data, its address in the plugin's
  part of the table: looked up as a function, it got a slot in the
  table of one thread only, and on wasm64 the next loads aborted
  ("table index is out of bounds").
- Domains, interpreted: the interpreter's state for its re-entries (see
  the `ocaml` recipe) is per thread. Shared, two domains entering the
  interpreter at the same time could take the other's, a rare crash
  (memory access out of bounds, a few runs in a thousand of
  `tests/domains`). (Sysroots built before note the change: `ocaml-emcc
  install --force ocaml`.)
- `--threads`: the memory of a thread that ends (its stack, its TLS) is
  freed once the thread no longer uses it. With `--wasi`, a detached
  thread (OCaml's threads and domains) freed it itself while still
  running on it; with emscripten's glue, the main thread could free it
  while the thread was still asking it to. A thread whose memory is above
  2 GB (wasm32) is given back too: its address, read as negative, was
  that of no thread ("Cannot read properties of undefined (reading
  'pthread_ptr')", then memory corruption, in programs starting and ending
  many domains).
- js_of_ocaml with `--threads`: a thread other than the main one calling
  JavaScript raises `Failure` (the program crashed: JavaScript values
  belong to the main thread), the GC of another thread releases
  JavaScript values on the main thread, and once `main` returned, the
  other threads go on between the callbacks (they waited forever, `main`
  kept the runtime).
- `--wasi`: files can be mapped (`Unix.map_file`, `mmap`), as with
  emscripten's glue: a copy, written back by `msync` and `munmap` when
  shared and writable (it failed with ENOSYS).
- `--wasi`, compiled: c_of_ocaml's small functions padding the module,
  which only V8's inlining heuristic needs, are left out (`--disable
  small-functions`, when c_of_ocaml has it): a smaller module.
- js_of_ocaml, compiled: the property and method names of the program
  (its literals) are decoded once, which halves the cost of a property
  access (120 to 65 ns) or a method call (280 to 140 ns).
- The sqlite3 and openblas recipes are thread-safe (`SQLITE_THREADSAFE=1`,
  sqlite's default, and openblas's `USE_LOCKING`): with `--threads`,
  threads using them at the same time no longer share their state
  unprotected. (Sysroots built before note the change: `ocaml-emcc
  install --force sqlite3 openblas`.)
- `--node-fs`, compiled: `Sys.chdir` changes the current directory, which
  relative paths then follow (node's worker thread running the program
  cannot change the process's: chdir did nothing, Rocq found none of its
  libraries).
- x86's SIMD and floating-point flags (`-msse2`, `-mfpmath=sse`...), which
  a configure run on the host may add (rocq-runtime on wasm64), are dropped
  from C compilations unless they ask for wasm SIMD (`-msimd128`).
- `build`: the libraries compiled against a package rebuilt for the
  target are rebuilt however many rounds it takes (at most 5 before:
  netsnmp's async libraries, over core, failed with "inconsistent
  assumptions").
- Packages building C with their own build (make, CMake, configure, run
  by a dune rule) get emcc in the wasm context under the host's names:
  `cc`, `gcc`, `g++`, `c++`, `clang`, `clang++`, `ar` and `ranlib`. They
  were the host's, which refused emcc's flags (qbf, re2, cudd,
  hdr_histogram, cucumber, bls12-381). CMake looks for their libraries in
  the sysroot first (hdr_histogram's zlib; the wrappers skip directories
  named like the tool, emscripten's cmake/). In the host context, those
  compilers drop emscripten's flags, which a build script may take from
  `CFLAGS` (bls12-381's build_blst.sh).
- As with gcc, C++ stubs may use `register` (clang refuses it in C++17:
  gbddml), and C functions declared without a prototype are no error with
  `-Werror` (cucumber's gherkin-c).
- A `dll<x>.so` that a package's own build makes with emcc (stem's
  snowball) is replaced by a placeholder when ocamlc links an executable
  of the package for the target ("Unrecognized magic").
- Stub libraries a package enables for some architectures only (curve448:
  amd64, arm64...) are compiled from the C files of its native build: the
  wasm context's architecture is `none`, so dune skipped them.
- `ocamlc -config` of the wasm32 toolchain says `word_size: 32` and
  `int_size: 31`, the program's, and packages choosing their OCaml code by
  them in their dune files are built for wasm32 when they are rebuilt for
  the target.
- Recipes: `HOST_TOOLS=1` (with `PATCH_OCAML=1`) builds the executables
  that a package's build runs for the host, in a host context, when its
  OCaml libraries are rebuilt for the target (rocq-runtime's
  configure.exe, with C stubs).
- The C files behind the members of a native stub archive built by CMake
  (`x.c.o`, out of the source tree) are found.
- Stubs without dune or a recipe: the C files reaching the OCaml headers
  through several local headers are found (orsetto).
- ctypes-foreign: the functions emscripten only has as failing stubs
  (`getpwnam`...) are found by `dlsym` (opasswd stopped at startup with
  "undefined symbol"), and emscripten's libraries are looked for in
  `$EM_CACHE` when it is set. The rest of the users database, which it
  lacks, finds no one and writes nothing (`putpwent`, the shadow
  passwords' `getspnam`..., `lckpwdf`).
- The stubs of packages whose dune package is named otherwise
  (ocaml-systemd: `-p systemd`) are built.
- The OCaml libraries rebuilt for the target are built again once dune is
  downgraded: an older dune cannot read the newer one's `dune-package`
  files ("Version 3.24 of the dune language is not supported": re2,
  async, shell...).
- The OCaml libraries rebuilt for the target whose C alone failed to build
  (re2's vendored C++ library, janestreet_cpuid's x86 stubs) are kept,
  their stubs being built apart (with an empty archive where their
  `dune-package` names one); a library that needed rebuilding and
  failed is reported as such, not as one the target does not need.
- Added recipes: bls12-381 and bls12-381-signature (a 32-bit size_t),
  codex (its 32-bit branches), eigen (Eigen 3.4.1's fix for recent clang),
  gdbm (dbm), hdr_histogram (musl's <endian.h>), janestreet_cpuid (its
  CPUID primitives fail, as in JavaScript; its flags shifted in 63 bits),
  libcurl (curl), libpcre (pcre), mariadb (mysql, mariadb),
  ocaml_intrinsics (CRC-32C in software), readline, rocq-runtime (no perf
  counter; its OCaml rebuilt for 31-bit integers on wasm32),
  shared-memory-ring (memory barriers for wasm), shell (no disk quotas:
  ENOSYS), tuntap (no devices: ENOSYS), unionFind (identifiers for 31-bit
  integers: frama-c on wasm32), unix-errno (Linux's errno codes), zmq
  (libzmq).

## 0.5.1

- macOS: the symbol table of archives made by its `ar` (`__.SYMDEF
  SORTED`, a BSD long name) is no longer taken for an object (the tests
  failed).
- OCaml 4.08 to 4.11: the commands whose output ocaml-emcc reads (`opam
  var prefix`, `nm`, `dune describe`...) are found in `PATH` (they were
  not, so the tests failed).
- The stubs a recipe built before `-pthread -fPIC` (zarith, lwt,
  mirage-crypto...) are built again when a program links them, as 0.5.0
  said: with OCaml 5 they crashed at startup (memory access out of bounds)
  or failed to link with `--threads`.

## 0.5.0

- Threads: with `--threads` (or `threads: yes` in `ocaml-emcc.conf`),
  `Thread.create` starts a real thread and, with OCaml 5.3 or later,
  `Domain.spawn` a domain running in parallel, in node, browsers
  (cross-origin isolated pages) and WASI hosts with wasi-threads (wasmer,
  wasmtime up to 46), interpreted or compiled (with c_of_ocaml's support).
  lwt then runs its jobs in its threads, and `Lwt_preemptive` works, as
  does Async's `In_thread.run` (core_unix's `prctl` names threads). The C code of the runtime, recipes
  and stubs is now compiled with `-pthread` (programs without `--threads`
  stay single-threaded) and `-fPIC` (for plugins, at no measured cost):
  existing runtimes and recipes are built again.
  The mpfr, libssl, libevent, pixman and fontconfig recipes are
  thread-safe, liblo has its server thread.
- Sockets with WASI: `--wasix` (or `wasix: yes` in `ocaml-emcc.conf` for
  `--wasi`) makes a module for wasmer (`wasmer run --net`) with WASIX's
  sockets: `Unix.socket`, `connect`, `bind`, `listen`, `accept`, options,
  addresses, UDP, `getaddrinfo` and `gethostbyname`, and lwt's sockets,
  with or without threads. With `--wasi` alone, the program accepts
  connections on the sockets its host preopens (wasmtime 46:
  `-S preview2=n -S tcplisten=ADDR`), the descriptors after the standard
  streams.
- The local time zone has its file, `/etc/localtime`, also under its name
  in `/usr/share/zoneinfo`, which core's `Timezone.local` reads: under node
  the host's (and that of `$TZ`), in browsers one made from the browser's
  time zone (its offsets from 1970 to 2037). It was missing, outside
  `--node-fs`.
- `--wasi`: an absolute symbolic link is followed through the preopened
  directories (`/etc/localtime`), which WASI hosts refuse to do.
- `--wasi`: lwt works (`Lwt_unix`, `Lwt_io`): `poll` with no timeout
  failed (emscripten's new probe, `ENOSYS`), as did `fdatasync`
  (imported from JavaScript) and, with node's WASI, waiting for a file.
- js_of_ocaml's JavaScript primitives: programs using the libraries
  js_of_ocaml (`Js`, `Dom_html`, its ppx, js_of_ocaml-lwt, Brr...) run in
  browsers and node, interpreted or compiled, on both targets, with the
  conventions of wasm_of_ocaml for JavaScript values. Callbacks keep
  running after the main program, JavaScript exceptions are
  `Js_error.Exn` (or `Failure`), `Js.export` gives functions to the
  page, and `Sys_js` redirects channels to functions and mounts files
  given on demand. Their stubs, which only abort, are no longer linked.
- `--js-file FILE` (and `js-files:` in `ocaml-emcc.conf`): primitives of
  the program implemented in JavaScript, called with JavaScript values.
- Plugins, in compiled mode: `ocaml-emcc plugin LIB.cma -o LIB.wasm`
  compiles a library to a wasm side module, which a program linked with
  `--dynlink` loads with the new library `ocaml-emcc.dynlink`
  (`Emcc_dynlink.loadfile`, or `load_url` to fetch it in a web page),
  checking their interfaces as `Dynlink` does. A plugin links the C
  stubs of its library. Effect handlers with
  `--effects double-translation`, which plugins built with `--main`
  follow.
- Added recipes: async_ssl, async_unix, bls12-381-unix, bytesrw, cairo,
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
  `fchdir` works, `sendmsg` and `recvmsg` are no longer imported from
  JavaScript, and a standard stream the host reports as a socket is a FIFO
  (node's piped standard streams).
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
