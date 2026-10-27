# Tests

`tests/run.sh [--target wasm32|wasm64]` builds each test with
`ocaml-emcc build` (or make), runs it with node and compares the output
with that of the native executable (or with `expected.txt`), in the
current switch or in `$SWITCH`. CI
(`.github/workflows/ci.yml`) runs the suite on OCaml 4.14 and 5.5, on both
targets.

| test        | what it covers |
|-------------|----------------|
| `hello`     | stdlib, 63-bit ints and literals, Marshal, GC, files, exit code (wasm64 only, on purpose) |
| `stubs`     | dune `foreign_stubs`: int64, floats, callbacks, C exceptions, custom blocks; unix, str |
| `ocaml5`    | effects, Atomic, Mutex, Dynarray (5.2+; `Domain.spawn` raises) |
| `gitrecipe` | a project recipe cloning cJSON from GitHub |
| `nodune`    | a Makefile, ocamlfind, a hand-compiled stub and `ocaml-emcc link` |
| `binio`     | binary data on stdout and stderr under node |
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
| `lwt`       | lwt.unix: timers, files, pipes, timeouts (jobs run synchronously) |
| `minisat`   | minisat: vendored C++, exceptions |
| `mccs`      | mccs: opam's solver, C++ and its bundled GLPK, CUDF universes converted to C++ and back |
| `lua`       | ocaml-lua: vendored Lua built by `make`, callbacks both ways |
| `stb`       | stb_image (no dune, `ocamlmklib -custom`) |
| `extunix`   | extunix: feature tests with dune-configurator |
| `snappy`, `expat`, `glpk`, `fftw3` | each binding + its library's recipe (C++ for snappy, SAX callbacks for expat, no dune for glpk, both precisions for fftw3) |
| `argon2`    | argon2 (ctypes-foreign, `-largon2`) + libargon2 |
| `lmdb`      | lmdb + liblmdb: a database file, cursors, transactions |
| `sdl`       | tsdl + sdl2: timer, events, surfaces, RWops (wasm64) |

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
`stubs` to `camlzip`, `cstanza` and `binio`) with `--wasi`, and runs them with
wasmtime (`$WASMTIME`, or the one in `PATH`), else with node's WASI. They
passed with wasmtime 50 on every OCaml version for 0.3.0 (`ocaml5` from
5.0, `syslibs` before 5.0). `sqlite`, `stubs`, `camlzip` and `binio`
pass with node 24's WASI too. `ctypes` cannot pass, as libffi's emscripten
port makes its calls in JavaScript, and the tests from `clibs` on were not
tried.

## Versions of the dependencies

`tests/versions.sh` installs each version of a package in turn (opam takes
its dependents along), runs the tests about it, and puts the packages of
the switch back. On wasm32, OCaml 4.14.2:

| tests | package | versions that pass | others |
|-------|---------|--------------------|--------|
| `zarith` | zarith | 1.11, 1.12, 1.13, 1.14 | |
| `mixed` | digestif | 1.1.2, 1.3.0, 1.4.1 | |
| `sqlite` | sqlite3 | 5.0.3, 5.2.0, 5.4.2 | |
| `zstd` | zstd | 0.4 | 0.3: the test uses later functions |
| `gsl` | gsl | 1.24.3, 1.25.1 | 1.22.0: not installable on OCaml 4.14 |
| `camlzip` | camlzip | 1.11, 1.13, 1.14 | |
| `ctypes`, `cstanza` | ctypes, ctypes-foreign | 0.21.1, 0.22.0, 0.23.0, 0.24.0 | 0.20.2, built by make, cannot be rebuilt for wasm32: its layouts are the host's (`link` warns) |
| `yaml` | yaml | 3.0.1, 3.1.0, 3.2.0 | |
| `mcrypto` | mirage-crypto | 2.4.1 | 2.0.2, 2.2.0: the test uses later functions |
| `lwt` | lwt | 5.6.1, 5.9.2, 6.1.2 | |
| `cryptokit` | cryptokit | 1.21.1 | 1.20: the test uses later functions |
| `secp` | secp256k1-internal | 0.3.1, 0.4.0 | |
| `apron` | apron | v0.9.14, v0.9.15 | v0.9.13: does not build natively (GCC 14) |
| `extunix` | extunix | 0.4.4 | 0.3.2, 0.4.1: `splice.c` returns a `value *` as an `off_t *`, an error on 32-bit targets |
| `stb` | stb_image | 0.4, 0.5 | |
| `minisat` | minisat | 0.4, 0.6 | |
| `cudd` | mlcuddidl | 3.0.8 | 3.0.6, 3.0.7: do not build natively (GCC 14) |
| `hacl` | hacl-star | 0.7.2 | 0.5.0, 0.6.2: the test uses later modules (`K256`) |
| `posix` | posix-time2, -socket, -stat | 4.0.2 | 2.2.0, 3.0.0: no posix-stat |
| `mccs` | mccs | 1.1+13, 1.1+17, 1.1+19 | |

The recipes' patches (placed by their text, see [patches](../docs/recipes.md#patches)) were
also checked to apply, as GNU patch applied the previous ones, to the
sources of every OCaml version from 4.08 to 5.5 and of lwt 5.4 to 6.1,
mirage-crypto 0.11 to 2.4, cryptokit 1.16 to 1.21, secp256k1-internal 0.3
and 0.4, lmdb 1.1, dune 3.12 to 3.24 and mccs 1.1+13 to 1.1+19.
