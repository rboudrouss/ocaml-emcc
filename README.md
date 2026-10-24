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
opam switch create myswitch <version> --keep-build-dir # keep the sources ocaml-emcc rebuilds
opam install . --deps-only --keep-build-dir            # your project's dependencies
opam install ocaml-emcc                                # or opam pin add ocaml-emcc git+https://github.com/rboudrouss/ocaml-emcc.git
source /path/to/emsdk/emsdk_env.sh                     # emcc in PATH

ocaml-emcc build main.js                               # in your dune project
node main.js                                           # or load main.js in a web page
```

`ocaml-emcc build main.js` finds the dune executable named `main`, builds a
wasm OCaml runtime from the sources of your switch's compiler (the first
time only), compiles the C stubs of the program and of its dependencies
with emcc, and writes `main.js` and `main.wasm`.

## Requirements

- An opam switch with **OCaml 4.08 or later** (4.x or 5.x).
- The sources of the compiler and of the packages with C stubs, which
  ocaml-emcc rebuilds. opam deletes them after a build unless
  `--keep-build-dir` is passed to `opam switch create` and `opam install`,
  or `OPAMKEEPBUILDDIR=true` is set (there is no persistent setting).
  Missing sources are fetched again with `opam source`, which needs network
  access and a version still in the repository.
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
- ctypes and the packages using it are rebuilt for wasm32, so that their C
  structs have the layouts of wasm32. `build` and `link` warn about those
  that cannot be (see [Differences from native](#differences-from-native)).

## Differences from native

Besides 31-bit integers on wasm32:

- **No threads.** `Thread.create` and `Domain.spawn` fail, while `Mutex`
  and `Condition` work. lwt runs its blocking jobs (`Lwt_unix` file
  operations...) synchronously, and `Lwt_preemptive` fails.
- **ctypes structs on wasm32**, for the bindings that could not be rebuilt
  for wasm32 (dune's `(ctypes)` stanza with structs, packages built without
  dune): struct fields, `sizeof`, and arrays of `long`, `size_t` or
  pointers are those of the 64-bit host. `build`, `link` and `doctor`
  **warn**. Such bindings only work on wasm64, or with the experimental
  [`--docker`](#experimental---docker).
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
| `clang` | programs embedding clang's frontend | see [below](#the-clang-recipe) |

These recipes take the sources of the opam package
that vendors the library if the switch has it, else
the newest upstream release compatible with the host's library (see
[system recipes](#system-recipes)).

OCaml packages, built from the sources of the installed package:

- `zarith`, `camlidl`, `mlgmpidl`
- `apron`: the C libraries and the stubs of every domain (box, oct, polka,
  t1p, avo) in each numeric variant
- packages whose sources need a change for wasm:
  - `mirage-crypto` (and `-ec`, `-rng`): wasm32 takes the 32-bit code, the
    cycle counter reads the high-resolution clock, entropy comes from
    `getentropy`, no AES-NI
  - `lwt`: blocking calls run synchronously instead of in a thread pool
  - `cryptokit`: a runtime function declared with the wrong integer type traps on wasm64
  - `secp256k1-internal`: x86-64 assembly disabled
  - `lmdb`: its bundled LMDB is changed as in `liblmdb`

#### The clang recipe

`clang` builds the libraries of clang's frontend (`libclang*.a`,
`libclang-cpp.a` and the `libLLVM*.a` they need), their headers and
clang's resource headers. It is built for a `-lclang-cpp`,
`-lclangFrontend`... or `-lLLVM-<major>` in a `.cma`. It needs cmake and a
host C++ compiler (and uses ninja if available). LLVM 9.0.1, the only
version tested, takes about 15 minutes on 4 cores.

The LLVM version is `LLVM_VERSION` if a project recipe sets it (`9.0.1`, or
a major such as `9`), else the major version of the host's `llvm-config`,
else the newest release.

It also installs two tools in `$SYSROOT/bin`, which come first in `PATH`
during builds:

- `llvm-config`, describing this installation (`--cxxflags`, `--ldflags`,
  `--libs`...), so that configure scripts and dune rules compile against
  the wasm LLVM.
- `clang`, which compiles nothing but answers `-print-resource-dir` with
  where the program will find the resource headers at run time:
  `CLANG_RESOURCE_DIR` (default `/usr/lib/clang/<ver>`), overridden by
  `$OCAML_EMCC_CLANG_RESOURCE_DIR`. Preload the headers there.

Values that a package's `./configure` wrote into its sources stay the
host's, such as the output of the host's `clang -print-resource-dir`:
preload the resource headers at that path instead.

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

#### System recipes

A recipe with `SOURCE=system:NAME` describes a C library and lets
ocaml-emcc pick its sources:

1. the sources of the opam package that vendors the library, if the switch
   has it, since that is what the native build uses
2. otherwise the newest upstream release compatible with the host's
   library, whose version comes from pkg-config or from the version macros
   of its header. Compatible means the same major version by default
   (`COMPAT=major`, or `minor`, `exact`, `latest`). Without a host
   library, the newest release.

opam fetches the release and checks its checksum when its repository knows
that version. Otherwise the tarball is downloaded from `RELEASES` without a
checksum, and the log says so. To pin a version, write a project recipe of
the same name.

```sh
# share/recipes/mpfr/recipe.sh
SOURCE=system:mpfr
DEPENDS=gmp
HEADER=mpfr.h                     # host version: pkg-config mpfr, else these macros
VERSION_MACROS="MPFR_VERSION_MAJOR MPFR_VERSION_MINOR MPFR_VERSION_PATCHLEVEL"
RELEASES=https://ftp.gnu.org/gnu/mpfr/   # directory listing mpfr-X.Y.Z.tar.*

build() {
  emconfigure ./configure --host=none --enable-static --disable-shared \
    --with-gmp="$SYSROOT" --prefix="$SYSROOT" CFLAGS="$CFLAGS"
  emmake make -C src && make -C src install
}
```

Optional variables are `PKGCONFIG=`, `TARBALL=` (prefix of the tarball
names), `COMPAT=`, `OPAM_SOURCES=` (the vendoring opam package) and `LINK=`
(default `-lNAME`, followed by the flags of `DEPENDS`). For releases that
are not in a directory listing, define a `releases` function printing
`<version> <tarball url>` lines, oldest first, the `git_tag_releases` function helps:

```sh
releases() { git_tag_releases https://github.com/libffi/libffi.git v \
  'https://github.com/libffi/libffi/releases/download/v{v}/libffi-{v}.tar.gz'; }
```

The recipe should install a pkg-config file in `$SYSROOT/lib/pkgconfig`
(`install_pc`) when the library's build system does not: during builds,
`pkg-config` (and dune-configurator) only sees the sysroot's libraries.

#### Recipe reference

- `SOURCE=`: `git:URL` (+ `REF=`), `url:TARBALL` (+ `SHA256=`), `dir:PATH`
  (relative to the recipe), `opam:PACKAGE` (sources of an installed
  package), `system:NAME` (see above), `fetch` (the recipe defines a
  `fetch DEST` function), `none`
- `DEPENDS=`: other recipes to build first
- `LINK=`: makes the recipe a C library, built for the `-lX` it provides
  (implied by `SOURCE=system:`)
- `LIB_PATTERNS=`: globs of more library names the recipe is built for
  (`clang`: `'clang* LLVM*'`)
- `USE_CFLAGS=`: C flags its users' stubs need besides the sysroot's
  include directory (`sdl2`: `-I$SYSROOT/include/SDL2`)
- functions: `build` (required), `pre_build`, `releases`, `fetch`
- helpers: `stub_cc file.c [flags]` (emcc with the OCaml runtime headers),
  `mklib`, `install_lib`, `install_headers`, `install_pc NAME VERSION LIBS
  [CFLAGS]`, `link_flags LIB "-lfoo"` (flags needed whenever `libLIB.a` is
  linked), `apply_patches DIR`, `make_var DIR VAR` (value of a Makefile
  variable), `include_recipe NAME`, `dune_stubs PKG` (build and install the
  stub archives of a dune package from its sources, after changing them),
  `fetch_opam_version PKG VER DEST`, `host_version PCNAME HEADER MACRO...`,
  `git_tag_releases REPO TAG_PREFIX URL_TEMPLATE`, `log`, `die`
- variables: `$EMCC`, `$CFLAGS`, `$LDFLAGS`, `$SYSROOT`, `$OCAML_INC`,
  `$OCAML_VERSION`, `$TARGET`, `$RECIPE_DIR`, `$BASE_RECIPE_DIR` (that of
  the recipe read by `include_recipe`, where its patches are), `$NPROC`,
  `$SHARED` (target-independent: host tools, big source archives)

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
ocaml-emcc build app.js -- -sMODULARIZE=1 -sEXPORT_NAME=createApp \
  --preload-file assets@/assets -sINITIAL_MEMORY=128MB -sENVIRONMENT=web
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

On wasm32, a bytecode that uses ctypes should be compiled against the
packages rebuilt for wasm32 (`link` warns otherwise):
`OCAMLFIND_CONF=<sysroot>/findlib.conf ocamlfind -toolchain wasm32 ocamlc ...`.

## Command reference

```
ocaml-emcc [--target wasm32|wasm64] [--switch SW] [--sysroot DIR] [--recipes DIR] [-v] COMMAND
  build OUT.js [--exe DIR/NAME] [--docker] [--docker-platform P] [LINK OPTIONS] [-- EMCC-ARGS]
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

## Experimental: `--docker`

On wasm32, some packages compute C layouts when they are built: ctypes'
sizes and struct offsets, dune-configurator's answers. ocaml-emcc rebuilds
most of them for wasm32 itself, but not the bindings using dune's
`(ctypes)` stanza with structs. `build OUT.js --docker` (wasm32 only)
compiles the bytecode with a 32-bit OCaml in a container instead, so that
these values are those of a 32-bit platform. The C stubs are still the
host's, rebuilt for wasm32.

The image (`ocaml-emcc-docker:<arch>-<version>-emcc<version>`, based on
Debian) gets an opam switch with the OCaml version of the host's switch,
and the host's version of each package the program uses, installed on
demand. Pins and local packages are not reproduced. Two platforms are
available:

- `--docker-platform linux/386` (default): no emulation. The struct
  layouts are those of wasm32, except for the alignment of `long double`
  (16 bytes, 8 on wasm32).
- `--docker-platform linux/arm/v7`: the struct layouts of wasm32, except
  for the size of `long double` (8 bytes, 16 on wasm32). On an x86 machine
  it needs qemu-user in binfmt_misc
  (`docker run --privileged --rm tonistiigi/binfmt --install arm`), and is
  slow.

Tried on OCaml 5.5.1 with linux/386: ctypes (ctypes-foreign), zstd, yaml
and zarith pass. See [How it works](#--docker) for the details.

## How it works

### The build

1. **Runtime** (`setup`, the `ocaml` recipe): the sources of the switch's
   compiler are configured with `emconfigure`, then `libcamlrun.a` and the
   C parts of `unix`, `str` and `runtime_events` are built and installed in
   the sysroot with the wasm headers. A findlib toolchain (`wasm32` or
   `wasm64`) is written for dune.
2. **Bytecode**: the host's own `ocamlc`, ppx, menhir and installed `.cma`
   files are used unchanged.
3. **dune -x**: in the wasm context, an `ocamlc` wrapper rewrites
   `ocamlc -config`, so dune compiles stubs with emcc and the wasm headers.
   An `ocamlmklib` replacement builds the `lib*.a` with `emar`, and
   `(modes exe)` executables come out as plain bytecode
   (`-output-complete-exe` is intercepted). Package rules that call
   `ocamlmklib`, `pkg-config` or `llvm-config` themselves get the wasm
   versions, which come first in dune's `PATH`; the wasm `ocamlmklib`
   hands host objects to the host tool. The C compiler of this context
   turns the executables it links into node scripts, so that build rules
   can run them.
4. **Dependencies**: the bytecode's `DLLS` section names the stub libraries
   (`dllzarith`...), and each `dll<x>` maps to a wasm `lib<x>.a`. A missing
   one is built from the opam package that installed `dll<x>.so`, by the
   first of:
   1. a recipe with the package's name;
   2. the package's own dune rules (`dune -x`), as for digestif;
   3. the C files behind each stub archive of the package's native build,
      with its `-I` flags: for packages without dune (glpk), when `dune -x`
      fails (the `(ctypes)` stanza), or when an archive was built by a host
      tool (ocaml-lua runs `make` in its copy of Lua);
   4. every `.c` file of the package that includes `<caml/...>`.

   `c_library_flags` are only used by custom links, which a bytecode build
   does not do. So the toolchain's `ocamlc` records those of every linked
   `.cma` in the sysroot, and `link` builds the missing ones: the stub
   library of the opam package that installed `dllX.so` (libraries built
   with `ocamlmklib -custom`, such as stb_image, are only named there), or
   the recipe providing `libX.a`.
5. **Link**: a primitive table is generated with only the primitives the
   bytecode uses, so wasm-ld drops the rest. The bytecode, without its
   `DLLS`/`DLPT` sections, is embedded in the module and `argv[0]` points
   to it (the `ocamlc -custom` trick), so `Sys.argv` looks native.

### Standalone modules

A `.wasm` without JavaScript has no file system to embed the bytecode in.
Its sections become the C arrays of a generated `bytecode.c` (`#embed`),
and `main.c` starts the program with `caml_startup_code`, as the C file of
`ocamlc -output-obj` does: `CODE`, `DATA`, the section table of that
compiler for the toplevel and Dynlink (`SYMB`, `CRCS`, and `PRIM` before
5.0), and the debug events of `DBUG`, relocated and gathered by `link`
into what the runtime would build from the executable file (backtraces
keep their locations).

### WASI

emscripten's standalone libc already reads, writes and closes files, and
reads clocks, arguments and the environment, with WASI calls. But opening
and `stat`ing a file are stubs that fail (EPERM, ENOSYS) whatever the host,
and the rest of the file system (`unlink`, `rename`, `getcwd`,
`readdir`...), sockets and `system` are imports of emscripten's
JavaScript. `--wasi` adds `share/runtime/wasi.c`, which implements these
system calls with WASI as wasi-libc does, and links with `-sPURE_WASI`,
which removes emscripten's last import (memory growth notifications).

`setjmp`/`longjmp` (`-sSUPPORT_LONGJMP=wasm`) and C++ exceptions are
compiled into emscripten's default encoding of wasm exceptions, the legacy
one, which WASI hosts do not implement: binaryen translates the module to
the standard one (exnref) as emcc finishes it
(`-sBINARYEN_EXTRA_PASSES=--translate-to-exnref,--emit-exnref`).

When the program's own C (its stubs, `-l` archives, `c_library_flags`)
defines one of the functions of `wasi.c`, `compat.c` or `dlsym.c`
(`__syscall_getcwd` or `getaddrinfo` for instance), `link` leaves
ocaml-emcc's out and says so: the program's definition is the one linked.

### Signature adapters

A wasm indirect call traps on any signature mismatch, while native code
ignores extra arguments: OCaml calls zarith's `ml_z_init()` with one
argument, for instance. The arity of each call site is read from the
bytecode (`C_CALLn`), wasm-ld reports the definitions that differ, and an
adapter is generated for each of them.

### ctypes on wasm32

ctypes lays C types out (struct fields, `sizeof`, arrays) with sizes it
generated when it was built (`ctypes_primitives.ml`), and bindings that
generate their type descriptions (`Cstubs_structs`, yaml) print the
offsets of the structs from a C program. Built on the 64-bit host, both
are those of LP64: right for wasm64, wrong for wasm32, where `long`,
`size_t` and pointers have 4 bytes. A 32-bit host would not do either:
i386 aligns `double` and `int64_t` to 4 bytes in structs, wasm32 to 8.

So on wasm32, `build` and `link` rebuild ctypes and the packages of the
program that depend on it (found from the program's `CRCS` section and
the opam dependencies), once per switch and package version
(`driver.sh shadow`). Their OCaml libraries are installed in
`<sysroot>/lib/findlib`, which the toolchain searches before the switch.
`build` then builds the bytecode against them, and also rebuilds the
libraries of the switch that ocamlc finds compiled against the host's
build of one of them (ctypes-foreign imports `Ctypes_primitives`).

Each package is built with dune, in a single context on the wasm32
toolchain (without the host context of `dune -x`, whose executables dune
would run instead): its OCaml generators are bytecode run by the host's
`ocamlrun` with the host's stub DLLs, its C generators are compiled by
emcc into node scripts, and dune-configurator gets the answers of wasm32.

Packages built without dune cannot be rebuilt this way, nor those using
dune's `(ctypes)` stanza, whose generators dune only builds natively
([ocaml/dune#13650](https://github.com/ocaml/dune/issues/13650)). A
package whose generated types have no structs or unions (zstd: constants)
needs no rebuild.

### ctypes-foreign

A static wasm program has no `dlsym`, so `link` exports the C functions and
variables whose names appear as string literals in the program, and links
a `dlopen`/`dlsym` that looks them up among the module's exports.
ctypes-foreign also needs the `threads` library, which the `ocaml` recipe
builds single-threaded.

### `--docker`

The container's OCaml is built with glibc. Once it is, the container's C
compiler uses the headers of emscripten and of the sysroot instead of
glibc's, so that the constants a build reads from C headers are the
target's: errno values (`ENOENT` is 44 there, 2 on Linux), libffi's ABI
(ctypes-foreign). Its programs are still linked with glibc: right for the
generators that print constants, sizes and offsets, not for C code calling
the system through the structs of these headers. On i386, it compiles with
`-malign-double -m128bit-long-double`, for the struct layouts of wasm32.

OCaml 5 has no 32-bit native compiler, so the container's switch is
bytecode only. dune links the generators of its `(ctypes)` stanza natively
only ([ocaml/dune#13650](https://github.com/ocaml/dune/issues/13650)): an
opam repository ranked first in the container patches dune to link them as
custom bytecode when there is no `ocamlopt`, the linkage dune already uses
for ppx drivers (proposed upstream in
[ocaml/dune#7431](https://github.com/ocaml/dune/pull/7431), closed for
lack of a test). The same repository drops the conflict with
`ocaml-option-bytecode-only` of the packages that declare it for that
reason (zstd).

### Flags used for all C code

- `-fno-strict-overflow`: works around an LLVM bug on wasm64, which folds
  `p[-8]` (`Tag_val`) into an unsigned load offset that traps
- `-sSUPPORT_LONGJMP=wasm`: OCaml raises exceptions from C with longjmp,
  and the JS implementation would route every primitive call through JS
- `-fwasm-exceptions`: C++ exceptions with the same wasm instructions
  (emscripten's JS exceptions cannot be thrown alongside)
- no `-pthread` (lwt asks for it): the program is single-threaded, and
  with it `caml_state` would be a thread-local variable, unlike in the
  runtime

### OCaml versions

The `ocaml` recipe works around these issues:

| version | issue | fix |
|---------|-------|-----|
| 4.08    | `caml_debug_info` defined in two files (needs `-fcommon`, which wasm lacks) | `patches/4.08/`: made `extern` in `backtrace.c` |
| 4.x     | `Tag_val` indexes with an unsigned `-sizeof(value)`: out-of-bounds wasm32 load | `patches/4.x/` (fixed upstream in 5.0) |
| < 4.12  | `afl.c` needs `shmat`, missing from emscripten's libc | weak stub (`share/runtime/compat.c`) |
| ≥ 4.14  | `runtime/sak` is a build-time tool | built with the host `cc` |
| ≤ 4.11  | otherlibs ignore the configure `CFLAGS` | target flags passed in `CC` |
| 5.x     | no `sigaltstack` in emscripten ("Failed to allocate signal stack") | `ac_cv_func_sigaction=no` |
| 5.x     | configure adds `-pthread`: runtime and stubs disagree on `caml_state` ("no domain lock held") | `-pthread` removed |
| ≥ 5.4   | minor heap committed with `mmap(MAP_FIXED)` ("Failed to create main domain") | `patches/5.4+/` |
| ≥ 5.5   | `caml_byte_program_mode` and `caml_runtime_standard_library_default` come from the file ocamlc generates | weak definitions (`compat.c`) |
| ≥ 5.5   | DLL names in the bytecode start with `-` or `:` | prefix removed (`Bytecode.dlls`) |
| all     | `sigsuspend` missing (unix) | weak stub |
| all, wasm32 | `ARCH_ALIGN_DOUBLE` (`alignof(double)` is 8): float accesses through memcpy, some stubs refuse to build (gsl) | undefined, as for i686: wasm loads doubles at any alignment |
| all     | systhreads disabled (no pthreads) | `libthreads.a` built anyway, single-threaded |
| all, wasm32 | integer literals beyond 31 bits in the DATA section ("input_value: integer too large") | `patches/4.x/`, `patches/5.x/`: wrapped to 31 bits while DATA is read (`intern.c`, `startup_byt.c`), from the file (`caml_main`) or from memory (`caml_startup_code`, standalone modules) |
| all     | a program started by `caml_startup_code` (standalone modules) reads its debug events from the executable file, which does not exist: backtraces without locations | `patches/all/`: `backtrace_byt.c` takes them from memory when `main.c` gives them (`caml_emcc_debug_events`), unchanged otherwise |
| all, wasm64 | stubs pass `int` dimensions to `caml_ba_alloc_dims`, read as `intnat` (stb_image: a corrupted heap) | `patches/headers/`: the installed `bigarray.h` converts each one |

Patches go in `share/recipes/ocaml/patches/`: `all/`, `4.x/` or `5.x/`,
`5.4+/`, `<major>.<minor>/` (applied in this order), and `headers/` for the
headers installed for the stubs only. Compilers before 4.08 are not
supported: their build has no autoconf `configure`, and their bytecode,
marshal and runtime layouts differ from what the link step reads.

## Status

`tests/run.sh [--target wasm32|wasm64]` builds each test with
`ocaml-emcc build` (or make), runs it with node and compares the output
with that of the native executable (or with `expected.txt`). CI
(`.github/workflows/ci.yml`) runs the suite on OCaml 4.14 and 5.5, on both
targets.

| test        | what it covers | 4.08.1 | 4.11.2 | 4.12.1 | 4.14.2 | 5.4.1 | 5.5.1 |
|-------------|----------------|--------|--------|--------|--------|-------|-------|
| `hello`     | stdlib, 63-bit ints and literals, Marshal, GC, files, exit code | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `stubs`     | dune `foreign_stubs` (int64, floats, callbacks, C exceptions, custom blocks), unix, str | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `zarith`    | zarith + gmp | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `mixed`     | digestif (dune stubs rebuilt automatically), yojson, re, cmdliner | ✅ | – | ✅ | ✅ | ✅ | ✅ |
| `ocaml5`    | effects, Atomic, Mutex, Dynarray (`Domain.spawn` raises) | – | – | – | – | ✅ | ✅ |
| `gitrecipe` | project recipe cloning cJSON from GitHub | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `nodune`    | Makefile, ocamlfind, hand-compiled stub + `ocaml-emcc link` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `syslibs`   | mlmpfr + zlib through `conf-mpfr`/`conf-zlib`, no configuration | – | – | – | ✅ | – | – |
| `apron`     | apron (box, octagons, polyhedra) + mlgmpidl + camlidl | – | – | – | ✅ | – | ✅ |
| `sqlite`    | sqlite3: SQL, JSON, math functions, a database file | – | – | – | ✅ | – | ✅ |
| `bz2`       | bz2 + libbz2 | – | – | – | ✅ | – | ✅ |
| `pcre2`     | pcre2 + libpcre2-8 (named groups, UTF-8) | – | – | – | ✅ | – | ✅ |
| `zstd`      | zstd (ctypes stub generation) | – | – | – | ✅ | – | ✅ |
| `gsl`       | gsl: special functions, integration, LU, RNG, stats | – | – | – | ✅ | – | ✅ |
| `camlzip`   | camlzip (no dune) + zlib: gzip, zip archives | – | – | – | ✅ | – | ✅ |
| `ctypes`    | ctypes-foreign + libffi: libc functions, callbacks (qsort), structs by value | – | – | – | ✅ | – | ✅ |
| `yaml`      | yaml (ctypes stubs, vendored libyaml) | – | – | – | ✅ | – | ✅ |
| `clibs`     | sha, checkseum (optint's 32-bit code on wasm32), bigstringaf, mtime/ptime clocks, eqaf | – | – | – | – | ✅ | – |
| `mcrypto`   | mirage-crypto, -rng, -ec (X25519, Ed25519, P-256/384/521), -pk (RSA, DSA, DH) | – | – | – | – | ✅ | – |
| `lwt`       | lwt.unix: timers, files, pipes, timeouts | – | – | – | – | ✅ | – |
| `cryptokit` | ciphers, hashes, MACs, RSA, zlib | – | – | – | – | ✅ | – |
| `minisat`   | minisat (vendored C++, exceptions) | – | – | – | – | ✅ | – |
| `lua`       | ocaml-lua (vendored Lua built by `make`), callbacks | – | – | – | – | ✅ | – |
| `stb`       | stb_image (no dune, `ocamlmklib -custom`) | – | – | – | – | ✅ | – |
| `extunix`   | extunix (feature tests with dune-configurator) | – | – | – | – | ✅ | – |
| `lz4`, `snappy`, `expat`, `glpk`, `fftw3` | each binding + its library's recipe | – | – | – | – | ✅ | – |
| `argon2`    | argon2 (ctypes-foreign, `-largon2`) + libargon2 | – | – | – | – | ✅ | – |
| `lmdb`      | lmdb + liblmdb: a database file, cursors, transactions | – | – | – | – | ✅ | – |
| `secp`      | secp256k1-internal (vendored libsecp256k1, gmp) | – | – | – | – | ✅ | – |
| `sdl`       | tsdl + sdl2: timer, events, surfaces, RWops | – | – | – | – | ✅ | – |
| `binio`     | binary data on stdout and stderr under node | – | – | – | – | ✅ | – |
| `depgraph`  | an installed package (`opam install ./tests/depgraph/pkg`): stubs on mpfr with flags from `pkg-config`, zarith; gmp, mpfr and both stub libraries built from the program | – | – | – | ✅ | – | – |

Every test passes on both targets, except `hello` (it checks 63-bit ints
on purpose) and `sdl` (not tried on wasm32 yet), which are wasm64 only.
"–" means the packages were not installed in that switch, or the test does
not apply (mlmpfr 4.2.1 does not build with OCaml 5). The zarith test also
ran unmodified in Chrome, on both targets.

`tests/run.sh --wasi` builds the tests marked `wasi` in `run.sh` (from
`stubs` to `camlzip`, and `binio`) with `--wasi`, and runs them with
wasmtime (`$WASMTIME`, or the one in `PATH`), else with node's WASI. They
pass with wasmtime 50 on OCaml 4.14.2 and 5.5.1 (those whose packages are
installed), and `stubs`, `zarith`, `gitrecipe`, `nodune` and `mixed` also
on 4.08.1, 4.11.2 and 4.12.1. `sqlite`, `stubs`, `camlzip` and `binio`
pass with node 24's WASI too. `ctypes` cannot pass, as libffi's emscripten
port makes its calls in JavaScript, and the tests from `clibs` on were not
tried.

## Next steps

- Domains: a `--threads` variant (runtime, stubs and link with `-pthread`)
  could enable `Domain.spawn`. It needs SharedArrayBuffer (COOP/COEP
  headers on the web).
- OCaml 5.0 to 5.3 are untested and probably need patches of their own:
  the memory code moved around.
- ctypes structs on wasm32 for dune's `(ctypes)` stanza ([#13650 in dune](https://github.com/ocaml/dune/issues/13650)): propose the patch
  that `--docker` applies to dune upstream, then use it in the wasm32
  context.
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
share/tools/          ocamlc / ocamlmklib wrappers for dune -x
share/runtime/        main.c, compat.c, dlsym.c, wasi.c, node_stdio.js
tests/run.sh          test suite (SWITCH=<opam switch> tests/run.sh --target wasm64, --wasi)
```
