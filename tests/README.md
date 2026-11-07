# Tests

`tests/run.sh [--target wasm32|wasm64] [--wasi] [--interpreted]` builds
each test with `ocaml-emcc build` (or make), runs it with node and
compares the output with that of the native executable (or with
`expected.txt`), in the opam switch `$SWITCH` (a name or a prefix, default
`emcc-4.14`). The tests are compiled (c_of_ocaml), or interpreted with
`--interpreted` (always before OCaml 4.14). CI
(`.github/workflows/ci.yml`) runs the suite compiled on OCaml 4.14 and
5.5, on both targets and WASI, and the threads and sockets tests
interpreted. A program still running after `$TEST_TIMEOUT` seconds (900) is
stopped, and its test fails.

| test        | what it covers |
|-------------|----------------|
| `hello`     | stdlib, 63-bit ints and literals, Marshal, GC, files, exit code (wasm64 only, on purpose) |
| `stubs`     | dune `foreign_stubs`: int64, floats, callbacks, C exceptions, custom blocks; unix, str |
| `ocaml5`    | effects, Atomic, Mutex, Dynarray (5.2+; `Domain.spawn` raises) |
| `gitrecipe` | a project recipe cloning cJSON from GitHub |
| `nodune`    | a Makefile, ocamlfind, a hand-compiled stub and `ocaml-emcc link` |
| `binio`     | binary data on stdout and stderr under node |
| `nodefs`    | `--node-fs`: real files, `Sys.chdir` and relative paths in the worker thread of compiled code |
| `depgraph`  | an installed package (`opam install ./tests/depgraph/pkg`): stubs on mpfr with flags from `pkg-config`, zarith; gmp, mpfr and both stub libraries built from the program |
| `zarith`    | zarith + gmp (recipe: configure's defines) |
| `mixed`     | digestif (stubs rebuilt by its own dune rules), yojson, re, cmdliner |
| `clibs`     | checkseum (optint's 32-bit code on wasm32), bigstringaf (bigarrays) |
| `syslibs`   | mlmpfr + zlib through `conf-mpfr`/`conf-zlib`, no configuration (OCaml 4) |
| `apron`     | apron (box, octagons, polyhedra) + mlgmpidl + camlidl: generated stubs, custom blocks |
| `cudd`      | mlcuddidl: CUDD's BDDs as custom blocks finalized by the GC, OCaml closures called back by CUDD's recursive apply while `Gc.compact` runs |
| `sqlite`    | sqlite3: SQL, JSON, math functions, a database file |
| `bz2`       | bz2 + libbz2 (`fdopen(dup(fd))` under WASI) |
| `zstd`      | zstd: ctypes stub generation |
| `gsl`       | gsl: special functions, integration, LU, RNG, stats (bigarrays, callbacks) |
| `camlzip`   | camlzip (no dune) + zlib: gzip, zip archives |
| `ctypes`    | ctypes-foreign + libffi: libc functions, callbacks (qsort), structs by value |
| `yaml`      | yaml: ctypes stubs, vendored libyaml, structs laid out by a C program |
| `cstanza`   | the project's own `(ctypes)` stanza, with a struct (patched dune) |
| `posix`     | posix-time2, -socket, -stat: ctypes layouts of libc structs (`timespec`, `tm`, `sockaddr_in`, `struct stat`), `getaddrinfo` |
| `hacl`      | hacl-star: HACL*'s C built by cmake, ctypes stubs printed by host generators; hashes, AEAD, X25519, Ed25519, P-256, K-256, NaCl |
| `mcrypto`   | mirage-crypto, -rng, -ec (X25519, Ed25519, P-256/384/521), -pk (RSA, DSA, DH) |
| `cryptokit` | ciphers, hashes, MACs, RSA, zlib |
| `secp`      | secp256k1-internal (vendored libsecp256k1, gmp) |
| `lwt`       | lwt.unix: timers, files, pipes, timeouts (jobs run synchronously, without `--threads`) |
| `minisat`   | minisat: vendored C++, exceptions |
| `mccs`      | mccs: opam's solver, C++ and its bundled GLPK, CUDF universes converted to C++ and back |
| `lua`       | ocaml-lua: vendored Lua built by `make`, callbacks both ways |
| `stb`       | stb_image (no dune, `ocamlmklib -custom`) |
| `extunix`   | extunix: feature tests with dune-configurator |
| `snappy`, `expat`, `glpk`, `fftw3` | each binding + its library's recipe (C++ for snappy, SAX callbacks for expat, no dune for glpk, both precisions for fftw3) |
| `argon2`    | argon2 (ctypes-foreign, `-largon2`) + libargon2 |
| `lmdb`      | lmdb + liblmdb: a database file, cursors, transactions |
| `sdl`       | tsdl + sdl2: timer, events, surfaces, RWops (wasm64) |
| `raylib`    | raylib (raylib-ocaml): its vendored raylib built for the web, ctypes structs holding pointers; images, colors, collisions, text, without a window |
| `dynlink`   | plugins (`ocaml-emcc plugin`, `--dynlink` implied by `Emcc_dynlink`, `Emcc_dynlink.loadfile`): a `.cmo` using the program, the standard library and str's stubs; a `.cma`; a plugin using another; a `.cma` with C stubs of its own (static data, calls to the runtime); errors (module missing, already loaded, compiled against another interface, exception, no file); `load_url` after the main program (compiled mode only) |
| `dyneffects` | plugins and effects (`--effects double-translation`, OCaml 5): effects performed by a plugin under the program's handler, through `List.fold_left`, and under its own; a plugin built without effects refused |
| `dyncps`    | plugins with `--cps-stack` (`cps-stack: yes`) on node's main thread: a plugin following the program (`plugin --main`) recursing 200 000 calls deep on its own, through a function of the program, in one of the program's, in `List.fold_right`, an exception crossing them; a plugin with double translation without `--cps-stack`; a plugin without effects refused (skipped when c_of_ocaml refuses `--cps-stack` with `--dynlink`) |
| `dynthreads` | plugins of a program with threads (`threads: yes`): a plugin linked for its shared memory (`plugin --main`) starting threads while it loads, the program's threads running the plugins' code, a second plugin loaded by `load_url`, whose callback runs after `main` |
| `dynbyte`   | interpreted: OCaml's `Dynlink` loading bytecode plugins (a `.cmo`, a `.cma`, errors), with C stubs of their own as wasm `dllX.so` (`plugin --interpreted`), a host `dllX.so` on Dynlink's path, `str.cma` in a program without `Str`, a plugin whose wasm stubs are missing |
| `dynweb`    | the plugins of `dynlink` fetched by a web page in headless Chromium (`load_url`) |
| `jsoo`      | js_of_ocaml's library and ppx under node: properties, methods, strings, numbers, arrays, callbacks, OCaml values and exceptions through JavaScript, JavaScript errors, typed arrays, timers and promises after the main program |
| `jsprims`   | primitives implemented in a JavaScript file (`js-files:` in `ocaml-emcc.conf`) |
| `jsdom`     | a web page in headless Chromium (`check.mjs`, playwright): DOM, an event handler, `Js.export` |
| `dynjspi`   | `dynthreads` with `--jspi` (`jspi: yes`): threads started after a plugin is loaded, a plugin loaded by `load_url` |
| `jspi`      | `--jspi` (`jspi: yes`): recursions 200 000 calls deep (plain, allocating, `List.fold_right`, an exception crossing them) on node's main thread, whose 984 KB stack is that of browsers: compiled, they go on JSPI's new stacks (node 24 with `--experimental-wasm-jspi`). And `emscripten_sleep` without asyncify, in a loop, in C calling OCaml back, under such a recursion (the executable's own `foreign_stubs`) |
| `cpsstack`  | the recursions of `jspi` with `--cps-stack` (`cps-stack: yes`), without JSPI: compiled, they go on in CPS, on the heap (skipped when c_of_ocaml has no `--cps-stack`) |
| `mapfile`   | `Unix.map_file`: a shared writable mapping written back to the file once collected, a longer one growing the file, a read-only one (interpreted, where collections are timely; also under `--wasi`) |
| `localtime` | the local time zone's file (`/etc/localtime`, or that of `$TZ`) gives the offsets of `Unix.localtime` |
| `core`      | core: `Int63` (an `int64` on wasm32), times, maps, bin_prot, sexps, dates, the local time zone |
| `async`     | async: the scheduler, a timer, deferreds, a pipe, writers |
| `asyncthreads` | async with `--threads`: `In_thread.run` jobs in threads, at once |
| `asyncssl`  | async_ssl: a TLS 1.3 handshake between a server and its client over pipes, a self-signed certificate, data both ways (not under `--wasi`, interpreted: ctypes-foreign's libffi calls JavaScript) |
| `sysjs`     | `Sys_js`: `stderr` and `stdin` redirected to functions, `create_file`, a mounted path giving files on demand (its `expected.txt` is js_of_ocaml's output) |
| `jsthreads` | js_of_ocaml with `--threads`: a thread calling JavaScript gets `Failure`, the GC of another thread finalizes JavaScript values, a thread going on once main returned, with a timer's callbacks |
| `jsthreadsweb` | `jsthreads` in headless Chromium, on a cross-origin isolated page |
| `threads`   | `--threads`: Thread, Mutex, Condition, Event, `Thread.delay`, exceptions and `Thread.exit` in threads (node, WASI) |
| `domains`   | `Domain.spawn` in parallel (OCaml 5.3+): Atomic, a mutex shared by domains, collections while they allocate, `Domain.DLS`, a thread in a domain |
| `threadsweb` | `threads` in headless Chromium, on a cross-origin isolated page |
| `lwtthreads` | lwt with `--threads`: jobs in its pool of threads (several at once), `Lwt_preemptive.detach` while timers run |
| `sockets`   | WASIX's sockets (`wasix: yes`, `--wasi` only): a TCP server and its client in one program, options, `select`, channels, UDP, `getaddrinfo`, `gethostbyname` |
| `lwtsockets` | lwt's sockets with WASIX: a server and three clients at once, a read timing out, a refused connection |
| `threadsockets` | WASIX's sockets with `--threads`: a server thread accepting, a thread per connection, client threads |

Under `--wasi`, `threads` and `domains` need a wasmtime with wasi-threads
(46 or older, removed in 47): `$WASMTIME_THREADS`; they are skipped
otherwise. `core`, `async`, `asyncthreads` and `asyncssl` need core,
core_unix, async and async_ssl, whose libraries are rebuilt for the target
(12 to 20 minutes in the CI): the CI runs them in a workflow of their own
(`.github/workflows/janestreet.yml`, weekly and by hand). `sockets`,
`lwtsockets` and `threadsockets` run in wasmer (`$WASMER`, or in `PATH`),
skipped without it.

`jsdom`, `dynweb`, `threadsweb` and `jsthreadsweb` need playwright and its Chromium (`npm i playwright`,
`npx playwright install chromium-headless-shell`), found through
`PLAYWRIGHT_DIR` (the directory of its `node_modules`) and
`PLAYWRIGHT_BROWSERS_PATH`; it is skipped otherwise.

They pass on both targets, except `hello` (it checks 63-bit ints on
purpose) and `sdl` (not tried on wasm32 yet), which are wasm64 only, and
`ctypes` on wasm64: libffi's calls stop on "Unexpected type 0" with emsdk
6.0.11 (libffi 3.5.2 and 3.8.0 alike, and with ocaml-emcc 0.3.0 too, whose
run had passed). The last run was on OCaml 4.14.2, from an empty sysroot.
For 0.3.0, the suite passed on every OCaml version from 4.08 to 5.5 (the
latest patch release of each; `ocaml5` from 5.0, `syslibs` before 5.0, as
mlmpfr 4.2.1 does not build with OCaml 5), and CI runs it on 4.14 and 5.5.
The libraries of `snappy`, `expat`, `glpk`, `fftw3`, `argon2`, `lmdb` and
`sdl` have no `-dev` package on the machine of the last run: CI installs
them. The zarith test also ran unmodified in Chrome, on both targets.

## WASI

`tests/run.sh --wasi` builds the tests marked `wasi` in `run.sh` (from
`stubs` to `camlzip`, `cstanza`, `lwt`, `binio`, the threads tests and the
socket tests) with `--wasi`, and runs them with wasmtime (`$WASMTIME`, or
the one in `PATH`), else with node's WASI. They passed with wasmtime 50 on
every OCaml version for 0.3.0 (`ocaml5` from 5.0, `syslibs` before 5.0),
and with node 24's WASI on OCaml 4.14. `ctypes` cannot pass, as libffi's
emscripten port makes its calls in JavaScript, and the other tests from
`clibs` on were not tried.

## Versions of the dependencies

`tests/versions.sh` runs the tests against several versions of their
package, see
[versions of the dependencies](../README.md#versions-of-the-dependencies).
