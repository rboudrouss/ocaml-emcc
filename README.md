# ocaml-emcc

Compile OCaml programs **together with their C stubs** to WebAssembly, for
node, browsers and WASI hosts.

Your program and its dependencies (zarith/gmp, unix, str, digestif, your own
`foreign_stubs`, a C library cloned from GitHub...) end up in one
emscripten module. Unlike js_of_ocaml / wasm_of_ocaml, no C stub has to be
rewritten in JavaScript, so FFI-heavy code works as is.

But the program runs as bytecode, interpreted by an
`ocamlrun` compiled to wasm, so it is much slower than the same program
compiled by js_of_ocaml or wasm_of_ocaml, which compile OCaml itself. If your
project is pure OCaml, or its C stubs already have JavaScript
implementations, use those instead. ocaml-emcc is for code whose C you
cannot or do not want to rewrite

ocaml-emcc is a prototype (see [Status](#status)).

## Quick start

```sh
opam install ocaml-emcc             # or opam pin add ocaml-emcc git+https://github.com/rboudrouss/ocaml-emcc.git
source /path/to/emsdk/emsdk_env.sh  # emcc in PATH

ocaml-emcc build main.js            # in your dune project
node main.js                        # or load main.js in a web page
```

`ocaml-emcc build main.js` finds the dune executable named `main`, builds a
wasm OCaml runtime from the sources of your switch's compiler (the first
time only), compiles the C stubs of the program and of its dependencies
with emcc, and writes `main.js` and `main.wasm`.

## Requirements

- An opam switch with **OCaml 4.08 or later** (4.x or 5.x).
- The sources of the compiler and of the packages with C stubs, which
  ocaml-emcc rebuilds. opam deletes them after a build, so ocaml-emcc
  fetches them again with `opam source` (once, they are cached in the
  sysroot): this needs network access and a version still in the opam
  repository. To skip the download, keep them when building the switch,
  with `--keep-build-dir` on `opam switch create` and `opam install`, or
  `OPAMKEEPBUILDDIR=true` (there is no persistent setting).
- The emscripten SDK, with `emcc` in `PATH` (tested with emsdk 6.0.11).
  Standalone `.wasm` outputs need emsdk 4.0 or later (clang 19, for
  `#embed`).
- dune 3.11 or later, except for projects built without dune (see
  [Without dune](#without-dune)).

Everything ocaml-emcc builds (the runtime, C libraries, rebuilt packages)
lives in `$OPAM_SWITCH_PREFIX/emcc-sysroot/` and goes away with the switch.

## Building

```sh
ocaml-emcc build main.js                      # the executable `main`, wherever it is
ocaml-emcc build bin/main.js                  # the executable bin/main
ocaml-emcc build dist/app.js --exe bin/main   # any other output path
```

The executable built is the one at the same path as the output, else the
only executable of the project with that name. `--exe DIR/NAME` names it
explicitly. Any `(modes ...)` works, `byte` is not needed.

The extension of the output decides what is written:

| output | what it is | runs in |
|--------|------------|---------|
| `main.js` (+ `main.wasm`) | the module and emscripten's JavaScript glue | node, browsers |
| `main.html` (+ `.js`, `.wasm`) | the same, plus a minimal emscripten page | browsers |
| `main.wasm` | a standalone module, without JavaScript | hosts providing emscripten's imports |
| `main.wasm` with `--wasi` | a module importing only WASI functions | wasmtime, node's WASI, other WASI hosts (see [WASI](#wasi)) |

A standalone `.wasm` without `--wasi` still imports emscripten functions
(file operations other than read and write, `getcwd`, sockets...), which
its host has to provide. See [standalone WebAssembly](https://v8.dev/blog/emscripten-standalone-wasm).

Note that `--wasi` uses emscripten's **experimental flag** `-sPURE_WASI`.

The most common options are `--target wasm64` (see
[wasm32 or wasm64](#wasm32-or-wasm64)), `-O -Oz` (default `-O2`),
`--stack-size 16MB` (default 8MB), `-l LIB` and `-L DIR` for extra
libraries, and `--emcc-flag F`. Arguments after `--` are passed to emcc.
All options are in the [command reference](#command-reference), and
project defaults go in [`ocaml-emcc.conf`](#configuration).

## Running

### In node

```sh
node main.js arg1 arg2
```

The bytecode is embedded in the `.wasm`, and the program behaves like a
native executable: it gets the arguments, the exit code, and the standard
streams of the node process as bytes (`node main.js < in.bin > out.bin`
works). Its files are in emscripten's in-memory file system, unless it is
built with `--node-fs`, the build then only runs in node, sees the real
file system and the environment variables (`Sys.getenv`), and the bytecode
is written next to `main.js` instead of being embedded.

### In a browser

The same `main.js` and `main.wasm` work in a web page. The `Module` object
gives the arguments and receives the output:

```html
<script>
  var Module = {
    arguments: ["arg1"],
    print: s => console.log(s),       // stdout
    printErr: s => console.error(s),  // stderr
  };
</script>
<script src="main.js"></script>
```

- Don't declare global `out` or `err` variables in the page because emscripten's
  script declares them.
- `Module.print`, `Module.printErr` and `Module.stdin` handle lines of
  text rather than bytes. They take precedence over node's streams too.
- `-- -sMODULARIZE=1 -sEXPORT_NAME=createMain` gives a module to
  instantiate yourself.
- `--preload` moves the bytecode to a separate `main.data`, loaded next to
  the page (under node, relative to the current directory).

### WASI

```sh
ocaml-emcc build main.wasm --wasi
wasmtime run -W exceptions=y --dir . main.wasm arg1 arg2
```

A `--wasi` module imports only WASI (preview1) functions, and the program sees the arguments, environment, standard
streams, clocks and the directories its host grants it. It is wasm32 only,
as no host runs wasm64 WASI modules.

**Hosts.** The host must implement the standard exception handling
instructions (exnref), which wasmtime 50 and node 22 do: OCaml raises
exceptions from C with `longjmp`, which uses them. wasmtime needs
`-W exceptions=y`, and `--dir DIR` for each directory the program may use.
With node, use `node:wasi` with `version: 'preview1'` and `preopens` (see
`tests/wasi-run.mjs`).

**What works:**

- Files: paths are resolved against the preopened directories, as
  wasi-libc does: `/tmp/x` is `x` in the directory preopened as `/tmp`, and
  a directory preopened as `.` holds every other path. Opening, reading,
  writing, `stat`, directories, renaming, removing, truncating, links and
  times work. `Sys.chdir` and `Sys.getcwd` use a current directory kept by
  the program, `/` at first.
- Waiting: `Unix.sleep` and `Unix.select` wait for the host instead of
  spinning. `Sys.time` is the CPU time of the process, or the time since it
  started when the host has no CPU clock.
- `Unix.dup` and `dup2` of a file the program opened open it again at the
  same position, giving a copy with its own position. This is enough for a
  C library doing `fdopen(dup(fd))`, or to redirect `stdout` to a file. The
  standard streams cannot be duplicated.

**What does not:** sockets, `getaddrinfo`, pipes, processes and
`Sys.command` fail with `ENOSYS`. There are no users: everything is owned
by root, and `chmod` and `chown` do nothing. File locks (`fcntl`, `lockf`)
always succeed, as there is a single process. `Unix.localtime` is UTC.

C libraries that call functions emscripten implements in JavaScript (SDL,
the `dlsym` of ctypes-foreign) keep importing them. `link` lists the
imports that are not WASI, and such a module only runs where they are
defined (`wasmtime -W unknown-imports-trap=y` runs it until one is called).

## wasm32 or wasm64

The bytecode is always the one of your switch, compiled for 64 bits. The
target is what the runtime and the C code are compiled for:

- **wasm32** (default): smaller, faster, supported everywhere, but OCaml
  ints are 31 bits at run time (see below).
- **wasm64** (`--target wasm64`): memory64, exactly the semantics of the
  native 64-bit program. Needs node 24 or later (the one shipped with emsdk
  works), Chrome 133 or Firefox 134, and has no WASI.

On wasm32, as with a 32-bit OCaml:

- Integer literals beyond 31 bits (`0x40000000`, `123456789012`) are
  wrapped when the program starts: `0x40000000` becomes `min_int`. This is
  right for code that picks 32-bit variants with `Sys.word_size` (optint,
  used by checkseum and decompress), wrong otherwise. `build`, `link` and
  `doctor` **warn** when there are any (the check is exact). Marshalled
  data holding such integers fails to load
  (`input_value: integer too large`).
- Arithmetic beyond 31 bits wraps silently (`1 lsl 40` is 256).

## Differences from native

Besides 31-bit integers on wasm32:

- **No threads.** `Thread.create` and `Domain.spawn` fail, while `Mutex`
  and `Condition` work. lwt runs its blocking jobs (`Lwt_unix` file
  operations...) synchronously, and `Lwt_preemptive` fails.
- **ctypes structs**: ctypes and the packages using it are rebuilt for the
  target, so that their structs have its layouts (see
  [ctypes layouts](docs/internals.md#ctypes-layouts)). Those that cannot be
  (packages built without dune) keep the layouts of the 64-bit host, wrong
  on wasm32 for `long`, `size_t` and pointers, and on both targets for the
  structs of the libc (`struct stat`). `build`, `link` and `doctor` **warn**.
- **ctypes-foreign** only finds the C symbols named by string literals of
  the program, not names computed at run time. `dlopen` accepts any file
  name, since everything is linked in.
- **C type mismatches.** A C function declared by a stub with other types
  than its definition (`int` for `long`) becomes a trap on wasm64. `link`
  warns about each one.
- **Floating-point rounding modes** do not exist in wasm: only
  round-to-nearest is available, so code that switches to directed rounding
  (`fesetround`) loses that guarantee.
- **LMDB** opens databases lock-free and writes through the map
  (`MDB_NOLOCK | MDB_WRITEMAP`): emscripten has no process-shared mutexes,
  and its file mappings are copies.
- **SDL2** under node only initializes the timer and events subsystems.
  Video and audio need a web page.

## C dependencies

### What is built automatically

Most programs need no configuration. `build` and `link` find the C a
program needs from its bytecode and its opam packages:

- **Stub libraries of opam packages** are
  rebuilt with emcc from the package that installed them: with the builtin
  recipe of that package if there is one, else with the package's own dune
  rules, else from the C files of its native build.
- **System C libraries**: when a package depends on `conf-gmp`,
  `conf-zlib`..., the recipe of the same name is built and linked. So is
  any recipe providing a `libX.a` for a `-lX` that the package's `.cma`
  files record.
- **`c_library_flags`**: the `-lX` that libraries record for their stubs
  (`(c_library_flags (-lfoo))`, `-cclib -lfoo`) are linked when a wasm
  `libX.a` exists or can be built. Host flags (`-L/usr/lib`, `-Wl,-rpath`)
  and the libraries emcc provides (`-lm`, `-lpthread`...) are dropped, and
  `-lstdc++` links the program as C++.
- **Packages configured on the host**: dune rules that run `pkg-config` or
  `llvm-config` get the answers of the sysroot, and the recipes of the
  libraries a package names are built before its stubs. A package whose
  stubs use mpfr through `pkg-config` (`tests/depgraph`), or a C parser
  built against the host's LLVM (rebuilt against the `clang` recipe), work
  this way.
- **ctypes**: bindings using stub generation (`Cstubs`, dune's `(ctypes)`
  stanza) and ctypes-foreign work on both targets.

A recipe is built once per switch and target, and is not rebuilt when it changes
(ocaml-emcc says so): `ocaml-emcc install --force NAME` rebuilds it.

### Builtin recipes

| recipe | for (opam) | notes |
|--------|------------|-------|
| `gmp`, `mpfr` | zarith, mlmpfr, mlgmpidl, apron... | |
| `zlib` | camlzip, zlib | |
| `sqlite3` | sqlite3 | amalgamation, single-threaded, FTS3/4/5, R-tree, math functions (`SQLITE_CFLAGS`) |
| `libffi` | ctypes-foreign | |
| `libbz2` | bz2 | |
| `libpcre2-8` | pcre2 | no JIT |
| `zstd` | zstd | single-threaded |
| `gsl` | gsl | with its CBLAS |
| `liblz4` | lz4 | |
| `snappy` | snappy | C++ |
| `expat` | ocaml-expat | |
| `fftw3` | fftw3 | double and single precision, no threads or SIMD |
| `glpk` | glpk | |
| `libargon2` | argon2 | reference implementation, no threads |
| `liblmdb` | lmdb | lock-free, see [differences](#differences-from-native) |
| `sdl2` | tsdl | emscripten's port (`-sUSE_SDL=2`) |
| `clang` | programs embedding clang's frontend | see [docs/recipes.md](docs/recipes.md#the-clang-recipe) |

These recipes take the sources of the opam package
that vendors the library if the switch has it, else
the newest upstream release compatible with the host's library (see
[system recipes](docs/recipes.md#system-recipes)).

OCaml packages, built from the sources of the installed package:

- `zarith`, `camlidl`, `mlgmpidl`
- `apron`: the C libraries and the stubs of every domain (box, oct, polka,
  t1p, avo) in each numeric variant
- `mlcuddidl`: the CUDD it bundles, configured for the target, and the
  stubs camlidl generates from its `.idl` files (with m4 and sed)
- `hacl-star-raw`: HACL*'s portable C (cmake), and the ctypes stubs its
  generators print, run on the host; the vectorized and Vale (x86
  assembly) variants are not built, and trap if called
- packages whose sources need a change for wasm:
  - `mirage-crypto` (and `-ec`, `-rng`): wasm32 takes the 32-bit code, the
    cycle counter reads the high-resolution clock, entropy comes from
    `getentropy`, no AES-NI
  - `lwt`: blocking calls run synchronously instead of in a thread pool
  - `cryptokit`: a runtime function declared with the wrong integer type traps on wasm64
  - `secp256k1-internal`: x86-64 assembly disabled
  - `lmdb`: its bundled LMDB is changed as in `liblmdb`
  - `mccs`: its solver silences GLPK with `glp_term_out` instead of closing
    `stdout`, whose output musl keeps and writes later
  - `ocaml-lua`: the Lua it bundles is unpacked and patched as its opam
    file does before dune runs

### Project recipes

A project recipe lives in `emcc-recipes/<name>/recipe.sh` next to
`dune-project`, is listed in `requires:` and linked with `link-flags:` in
[`ocaml-emcc.conf`](#configuration). This one clones cJSON
(`tests/gitrecipe`):

```sh
# emcc-recipes/cjson/recipe.sh
SOURCE=git:https://github.com/DaveGamble/cJSON.git
REF=v1.7.18                       # tag, branch or commit

build() {                         # runs in a fresh copy of the sources
  "$EMCC" $CFLAGS -c cJSON.c -o cJSON.o
  mklib cjson cJSON.o             # -> libcjson.a
  install_lib libcjson.a
  install_headers cjson cJSON.h   # -> #include <cjson/cJSON.h>
}
```

Project recipes take precedence over the builtin ones (`share/recipes/`).
More directories can be added with `--recipes DIR` or
`$OCAML_EMCC_RECIPES_PATH`.

A project recipe can also **refine** a builtin one: `include_recipe NAME`
reads the next recipe of that name, after the project's variables are set,
and an optional `pre_build` function runs before its `build`, to patch the
sources. [MOPSA](https://gitlab.com/rboudrouss/mopsa-analyzer-32-bit/-/tree/ocaml-emcc?ref_type=heads) pins clang 9 and patches apron this way:

```sh
# emcc-recipes/clang/recipe.sh
LLVM_VERSION=9.0.1
include_recipe clang

# emcc-recipes/apron/recipe.sh
include_recipe apron
pre_build() { sed -i '...' apron/ap_manager.c; }
```

Recipes for system C libraries, the variables, functions and helpers
recipes can use, and how their patches are applied are described in
[docs/recipes.md](docs/recipes.md).

## Configuration

A project can have an `ocaml-emcc.conf`, looked up from the current
directory upwards. Every field is optional:

```
target: wasm32                  # default target of the project
requires: cjson                 # recipes built before building/linking
link-flags: -lcjson -sINITIAL_MEMORY=64MB
cflags: -DNDEBUG
recipes: emcc-recipes           # recipe directories (default: ./emcc-recipes)
```

Emscripten link flags come from, in increasing precedence (emcc keeps the
last `-s` setting): `link-flags:`, `$OCAML_EMCC_LDFLAGS`, `--emcc-flag F`,
then the arguments after `--`:

```sh
ocaml-emcc build app.js -- --preload-file assets@/assets \
  -sINITIAL_MEMORY=128MB -sENVIRONMENT=web
```

C flags for stubs and recipes come from `cflags:` and
`$OCAML_EMCC_EXTRA_CFLAGS`.

## Without dune

`build` chains the following commands, which can also be run on their own
from scripts and Makefiles:

```sh
ocaml-emcc setup                         # wasm runtime of the switch (once per target)
ocaml-emcc install gmp zarith cjson      # build recipes
ocaml-emcc dune ./bin/main.bc            # dune build -x wasm32: C stubs compiled with emcc
ocaml-emcc doctor prog.bc                # how stubs and primitives resolve, 31-bit literals
ocaml-emcc deps prog.bc                  # build the missing stub libraries of prog.bc
ocaml-emcc link prog.bc -o prog.js       # the final link
ocaml-emcc env --cflags                  # flags to compile C stubs yourself
```

Without dune, build the bytecode however you like, compile your stubs with
`emcc $(ocaml-emcc env --cflags)` and give their archive to `link`. The
stub libraries of your dependencies are found from the bytecode itself
(`tests/nodune/Makefile`):

```make
out/prog.js: prog.bc libstub.a
	ocaml-emcc link prog.bc -o $@ -l ./libstub.a

libstub.a: stub.c
	emcc $$(ocaml-emcc env --cflags) -c stub.c -o stub.o
	emar rcs $@ stub.o

prog.bc: prog.ml      # -no-check-prims: our primitives only exist in libstub.a
	ocamlfind ocamlc -package zarith,unix -linkpkg -no-check-prims prog.ml -o $@
```

A bytecode that uses ctypes should be compiled against the packages
rebuilt for the target (`link` warns otherwise):
`OCAMLFIND_CONF=<sysroot>/findlib.conf ocamlfind -toolchain wasm32 ocamlc ...`
(or `-toolchain wasm64`).

## Command reference

```
ocaml-emcc [--target wasm32|wasm64] [--switch SW] [--sysroot DIR] [--recipes DIR] [-v] COMMAND
  build OUT.js [--exe DIR/NAME] [LINK OPTIONS] [-- EMCC-ARGS]
                                   everything (dune projects)
  setup [--force]                  wasm runtime of the switch's compiler
  install [--force] RECIPE...      build recipes
  dune [DUNE-BUILD-ARGS]           dune build -x <target> + static stub archives
  deps PROG.bc [-L DIR]            build the missing stub libraries
  doctor PROG.bc [-L DIR]          stub libraries, primitives, 31-bit literals
  link PROG.bc -o OUT.js [LINK OPTIONS] [-- EMCC-ARGS]
  env [--cflags|--sysroot]         configuration / flags for C stubs

link options (build and link):
  -L DIR          search lib<x>.a in DIR
  -l LIB          extra library or archive to link (repeatable)
  --preload       bytecode in a separate .data file instead of embedded
  --node-fs       node only: real file system access, .bc next to OUT.js
  -O FLAG         emcc optimisation flag (default -O2)
  --stack-size S  C stack size (default 8MB)
  --no-deps       do not build missing stub libraries automatically
  --wasi          OUT.wasm for a WASI host (wasm32)
  --emcc-flag F   extra emcc link flag (repeatable)
```

`ocaml-emcc help` prints the same with more detail.

## How it works

The bytecode is compiled by the switch's own `ocamlc`, and runs on an
`ocamlrun` that emcc builds from the sources of the switch's compiler. The
C stubs of the program and of its dependencies are rebuilt with emcc and
linked with the runtime and the bytecode into one module.
[docs/internals.md](docs/internals.md) details each step, standalone and
WASI modules, ctypes, the flags used for all C code and the workarounds
for each OCaml version.

## Status

The test suite ([tests/README.md](tests/README.md)) builds about 40
programs with C stubs (zarith, apron, sqlite3, ctypes, lwt, mirage-crypto,
hacl-star, mccs, sdl...) and compares their output under node with that
of the native executable. It passes on both targets, except `ctypes` on
wasm64 (libffi's calls stop on "Unexpected type 0" with emsdk 6.0.11). For
0.3.0 it passed on every OCaml version from 4.08 to 5.5, and its WASI
part with wasmtime 50. CI runs it on OCaml 4.14 and 5.5.

`tests/versions.sh` also runs the tests against several versions of each
package. The only failures due to ocaml-emcc's targets are ctypes 0.20.2,
whose struct layouts stay the host's (`link` warns), and extunix before
0.4.4 on wasm32, whose `splice.c` is wrong on 32-bit targets.

## Next steps

- Domains: a `--threads` variant (runtime, stubs and link with `-pthread`)
  could enable `Domain.spawn`. It needs SharedArrayBuffer (COOP/COEP
  headers on the web).
- Propose the patch of dune's `(ctypes)` stanza upstream
  ([ocaml/dune#13650](https://github.com/ocaml/dune/issues/13650)), so that
  the switch's dune can build it.
- More recipes: ppl (C++, apron's `ppl` and `polkaGrid` domains), flint,
  openssl, libtidy, and newer LLVM versions for `clang`.
- WASI: sockets the host preopens (preview1's `sock_accept`, `sock_recv`,
  `sock_send`), and a `dlsym` that needs no JavaScript (a table of the
  exported functions generated by `link`), though ctypes-foreign would
  still need a libffi without JavaScript. WASI preview 2 (components) is not
  targeted.

## Development

```
bin/main.ml           CLI
src/                  bytecode reading, linking, dependency resolution, project config
share/driver.sh       recipe driver
share/recipes/        ocaml (runtime + patches), C libraries (gmp, mpfr, zlib...),
                      OCaml packages needing changes (zarith, apron, lwt...)
share/tools/          ocamlc / ocamlmklib wrappers for dune -x, dune's (ctypes) patch
share/runtime/        main.c, compat.c, dlsym.c, wasi.c, node_stdio.js
tests/run.sh          test suite (SWITCH=<opam switch> tests/run.sh --target wasm64, --wasi)
```
