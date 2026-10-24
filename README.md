# ocaml-emcc

Compile OCaml programs **with their C stubs** to WebAssembly, for the browser
and node.

Your program and its dependencies (zarith/gmp, unix, str, digestif, your own
`foreign_stubs`, a C library cloned from GitHub...) end up in one
emscripten module. Unlike js_of_ocaml / wasm_of_ocaml, no C stub has to be
rewritten in JavaScript, so FFI-heavy code works as is.

But the program runs as bytecode, interpreted by an
`ocamlrun` compiled to wasm, so it is much slower than the same program
compiled by js_of_ocaml or wasm_of_ocaml, which compile OCaml itself. If your
project is pure OCaml, or its C stubs already have JavaScript
implementations, use those instead. ocaml-emcc is for code whose C you
cannot or do not want to rewrite.

## Quick start

```sh
opam switch create myswitch 5.4.1 --keep-build-dir
opam install . --deps-only --keep-build-dir
opam install ocaml-emcc                       # or opam pin add ocaml-emcc git+https://github.com/rboudrouss/ocaml-emcc.git
source /path/to/emsdk/emsdk_env.sh            # emcc in PATH

ocaml-emcc build main.js                      # in your dune project
node main.js                                  # or load main.js in a web page
```

`ocaml-emcc build main.js` finds the dune executable named `main`, builds a
wasm OCaml runtime from the sources of your switch's compiler (the first
time only), compiles the C stubs of your program and of its dependencies
with emcc, and writes `main.js` and `main.wasm`.

## Requirements

- An opam switch with **OCaml 4.08 or later**, 4.x or 5.x.
- The sources of the compiler and of the packages with C stubs, which
  ocaml-emcc rebuilds. opam deletes them after a build unless
  `--keep-build-dir` is given to `opam switch create` and `opam install`, or
  `OPAMKEEPBUILDDIR=true` is set (there is no persistent option). Missing
  sources are fetched again with `opam source`, which needs network and a
  version still in the repository.
- The emscripten SDK, with `emcc` in `PATH` (tested with emsdk 6.0.11).
  Standalone `.wasm` outputs need its clang to support `#embed` (clang 19,
  emsdk 4.0 and later).
- dune ≥ 3.11 for `build` and `dune`. Projects without dune only need
  `link`.

The default opam repository starts at OCaml 4.11. For 4.08 to 4.10, add the
archive repository:

```sh
opam switch create 4.08.1 --keep-build-dir \
  --repos default,archive=git+https://github.com/ocaml/opam-repository-archive
```

Everything ocaml-emcc builds lives in `$OPAM_SWITCH_PREFIX/emcc-sysroot/`
and goes away with the switch.

## Usage

### Building

```sh
ocaml-emcc build main.js                      # the executable `main`, wherever it is
ocaml-emcc build bin/main.js                  # the executable bin/main
ocaml-emcc build dist/app.js --exe bin/main   # any other output path
```

The executable is the one at the same path as the output, else the only
executable of the project with the same name. `--exe DIR/NAME` names it
explicitly. Any `(modes ...)` works, `byte` is not needed.

The extension of the output selects what is written:

- `.js` (+ `.wasm`): runs in node and in browsers
- `.html`: the same, plus a minimal emscripten page
- `.wasm` alone: emcc's standalone mode, without the JavaScript glue. The
  bytecode is linked in as C arrays (there is no file system to ship it
  in). The module still imports emscripten functions (file operations
  other than read/write, `getcwd`, sockets...), which its host must
  provide: emscripten's JavaScript does, a plain WASI host does not.
- `.wasm` with `--wasi`: a WASI module, which only imports WASI functions
  and runs in wasmtime, node's WASI, and other WASI hosts (see
  [WASI](#wasi)). wasm32 only.

Common options: `--target wasm32|wasm64` (see below), `-O -Oz` (default
`-O2`), `--stack-size 16MB`, `--preload`, `--node-fs`, `--wasi`, `-l LIB`,
`-L DIR`, `--emcc-flag F`. Anything after `--` goes to emcc. The full list
is in the [command reference](#command-reference).

### Running

The bytecode is embedded in the `.wasm` and emscripten's default
environment covers both the web and node, so the same files work in both.

Under node, the program behaves like a native executable: arguments, exit
code, and the standard streams of the node process, as bytes (so
`node main.js < in.bin > out.bin` works).

```sh
node main.js arg1 arg2
```

In a web page, the `Module` object gives the arguments and where the output
goes:

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

- Don't declare global `out` or `err` variables in the page: emscripten's
  script declares them.
- `Module.print`, `Module.printErr` and `Module.stdin` take precedence over
  node's streams too, and handle text lines rather than bytes.
- `-- -sMODULARIZE=1 -sEXPORT_NAME=createMain` gives a module to
  instantiate yourself.
- `--preload` moves the bytecode to a separate `main.data`, loaded next to
  the page (under node, relative to the current directory).
- `--node-fs` makes a node-only build with access to the real file system
  and to the environment variables (`Sys.getenv`).

### WASI

```sh
ocaml-emcc build main.wasm --wasi
wasmtime run -W exceptions=y --dir . main.wasm arg1 arg2
```

`--wasi` writes a module whose only imports are WASI (preview1) functions:
no JavaScript is involved, and the program sees the arguments, environment,
standard streams, clocks and the directories its host grants it.

- **Hosts**: wasmtime needs `-W exceptions=y` (OCaml raises exceptions from
  C with longjmp, which uses wasm exception handling) and `--dir DIR` for
  each directory the program may use. With node, `node:wasi` with
  `version: 'preview1'` and `preopens` (`tests/wasi-run.mjs`). The host
  must implement the standard exception handling instructions (exnref):
  wasmtime 50 and node 22 do.
- **Files**: paths are resolved against the preopened directories, as
  wasi-libc does: `/tmp/x` is `x` in the directory preopened as `/tmp`, and
  a directory preopened as `.` holds every other path. `Sys.chdir` and
  `Sys.getcwd` work on a current directory kept by the program (`/`
  first). Opening, reading, writing, `stat`, directories, renaming,
  removing, truncating, links and times are WASI calls.
- **Waiting**: `Unix.sleep` and `Unix.select` wait for the host
  (`poll_oneoff`) instead of spinning, `Sys.time` is the process's CPU
  time (or the time since it started, when the host has no CPU clock).
- **wasm32 only**: WASI is 32-bit, no host runs a wasm64 WASI module. Ints
  are 31-bit (see [targets](#targets-wasm32-or-wasm64)).
- **Descriptors**: WASI cannot duplicate one. `Unix.dup` and `dup2` of a
  file the program opened open it again at the same position, a copy with a
  position of its own (enough for a C library doing `fdopen(dup(fd))`, or
  to redirect `stdout` to a file); the standard streams cannot be
  duplicated. Locks (`fcntl`, `lockf`) always succeed: there is a single
  process.
- **What WASI does not have** fails as it would without the system
  support: sockets, `getaddrinfo`, pipes, processes and `Sys.command`
  (`ENOSYS`). There are no users: everything is owned by root, `chmod` and
  `chown` do nothing. `Unix.localtime` is UTC.
- C libraries that call functions emscripten implements in JavaScript
  (SDL, ctypes-foreign's `dlsym`) keep importing them: `link` lists the
  imports that are not WASI, and the module only runs where they are
  defined (`wasmtime -W unknown-imports-trap=y` runs it until one is
  called).

The C functions behind this are in `share/runtime/wasi.c`. When the
program's own C (its stubs, `-l` archives, `c_library_flags`) defines one of
them, `__syscall_getcwd` or `getaddrinfo` for instance, `link` leaves
ocaml-emcc's out and says so: that definition is the one linked. The same
holds for `compat.c` and `dlsym.c`.

### Targets: wasm32 or wasm64

The bytecode is always the one of your switch, compiled for 64 bits.

- **wasm32** (default): smaller, faster, supported everywhere, but ints
  are 31 bits at run time:
  - integer literals beyond 31 bits (`0x40000000`, `123456789012`) are
    wrapped when the program starts, as a 32-bit compiler would
    (`0x40000000` becomes `min_int`). This is right for code that selects
    32-bit variants with `Sys.word_size` (optint, used by checkseum and
    decompress), wrong otherwise. `build`, `link` and `doctor` **warn**
    when there are any (the check is exact). Marshalled data holding such
    integers fails to load (`input_value: integer too large`), as on 32-bit
    OCaml.
  - arithmetic beyond 31 bits wraps silently (`1 lsl 40` = 256), which no
    tool can detect.
- **wasm64** (`--target wasm64`): memory64, exactly the semantics of the
  native 64-bit program. Needs node ≥ 24 (the one shipped with emsdk
  works), Chrome ≥ 133 or Firefox ≥ 134.

### Configuration

An optional `ocaml-emcc.conf`, looked up from the current directory
upwards:

```
target: wasm32                  # default target of the project
requires: cjson                 # recipes built before building/linking
link-flags: -lcjson -sINITIAL_MEMORY=64MB
cflags: -DNDEBUG
recipes: emcc-recipes           # recipe directories (default: ./emcc-recipes)
```

Emscripten flags come from, in increasing precedence (emcc keeps the last
`-s` setting): `link-flags:`, `$OCAML_EMCC_LDFLAGS`, `--emcc-flag F`, then
the arguments after `--`:

```sh
ocaml-emcc build app.js -- -sMODULARIZE=1 -sEXPORT_NAME=createApp \
  --preload-file assets@/assets -sINITIAL_MEMORY=128MB -sENVIRONMENT=web
```

C flags for stubs and recipes come from `cflags:` and
`$OCAML_EMCC_EXTRA_CFLAGS`.

## C dependencies

### What is built automatically

Most programs need no configuration:

- **Stub libraries of opam packages** (`dllzarith` in the bytecode) are
  rebuilt with emcc from the package that installed them: with the builtin
  recipe of that package if there is one, else with the package's own dune
  rules, else from the C files of its native build (see
  [How it works](#how-it-works)).
- **System C libraries**: when a package depends on `conf-gmp`,
  `conf-zlib`..., the recipe of the same name is built first and linked. So
  are the `-lX` its `.cma` files record when a recipe provides `libX.a`
  (glpk has no `conf-glpk`). `tests/syslibs` (mlmpfr + zlib) has no
  configuration at all.
- **ctypes**: bindings using stub generation (`Cstubs`, dune's `(ctypes)`
  stanza) and ctypes-foreign both work, on both targets (but see
  [struct layouts](#differences-from-native) on wasm32).
- **`c_library_flags`**: the `-lX` that libraries record for their stubs
  (`(c_library_flags (-lfoo))`, `-cclib -lfoo`) are linked when a wasm
  `libX.a` exists or can be built. Host flags (`-L/usr/lib`, `-Wl,-rpath`)
  and the libraries emcc provides (`-lm`, `-lpthread`...) are dropped.
  `-lstdc++` links the program as C++.
- **Packages configured on the host**: dune rules that run `pkg-config`
  or `llvm-config` get the sysroot's answers in the wasm context, and the
  recipes of the libraries a package names (its `conf-*` dependencies, the
  `-lX` of its `.cma` files) are built before its stubs. A C parser
  installed with opam against the host's LLVM gets its stubs rebuilt
  against the `clang` recipe this way. `tests/depgraph` is a smaller case:
  an installed package with mpfr stubs (flags from `pkg-config`) and
  zarith, built from a program that only names that package.

A recipe is built once per switch and target. It is not rebuilt when it
changes (ocaml-emcc says so): `ocaml-emcc install --force NAME` rebuilds
it.

### Builtin recipes

C libraries, named after their `conf-*` package:

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
| `clang` | programs embedding clang's frontend | see [clang](#clang) |

OCaml packages, built from the sources of the installed package:

- `zarith`, `camlidl`, `mlgmpidl`
- `apron`: the C libraries and the stubs of every domain (box, oct, polka,
  t1p, avo) in each numeric variant
- packages whose sources need a change for wasm, then built with their own
  dune rules:
  - `mirage-crypto` (and `-ec`, `-rng`): wasm32 takes the 32-bit code, the
    cycle counter reads the high-resolution clock, entropy comes from
    `getentropy`, no AES-NI
  - `lwt`: blocking calls run synchronously instead of in a thread pool
  - `cryptokit`: a declaration of a runtime function with the wrong
    integer type, a trap on wasm64
  - `secp256k1-internal`: x86-64 assembly disabled
  - `lmdb`: its bundled LMDB, changed as in `liblmdb`.

The C library recipes pin no version: they take the sources of the opam
package that vendors the library if the switch has it (the `gmp` package),
else the newest upstream release compatible with the library of the host
(see [system recipes](#system-recipes)).

### clang

The `clang` recipe builds the libraries of clang's frontend (`libclang*.a`,
the `libLLVM*.a` they need, `libclang-cpp.a`), their headers and clang's
resource headers. It also installs in `$SYSROOT/bin`:

- `llvm-config`, which describes this installation (`--cxxflags`,
  `--ldflags`, `--libs`...), for a configure script or a dune rule
- `clang`, which compiles nothing but answers `-print-resource-dir` with
  where the program will find the resource headers at run time
  (`CLANG_RESOURCE_DIR`, default `/usr/lib/clang/<ver>`, overridden by
  `$OCAML_EMCC_CLANG_RESOURCE_DIR`): preload them there.

A `-lclang-cpp`, `-lclangFrontend`... or `-lLLVM-<major>` in a `.cma`
builds the recipe, and `-lclang-cpp` links the LLVM libraries as well (the
host's `-lLLVM-<major>` is a shared library the recipe does not make). In
the wasm context of `dune -x`, `llvm-config` is the recipe's, so packages
whose dune rules run it compile their stubs against the wasm LLVM. Values
a package's `./configure` wrote into its sources stay the host's, such as
the output of the host's `clang -print-resource-dir`: preload the resource
headers there.

The LLVM version is `LLVM_VERSION` if a project recipe sets it (`9.0.1`, or
a major `9`), else the major version of the host's `llvm-config`, else the
newest release. It needs cmake, a host C++ compiler, and ninja if
available. LLVM 9.0.1 takes about 15 minutes on 4 cores. Only 9.0.1 has
been tested.

### Writing a recipe

A project recipe lives in `emcc-recipes/<name>/recipe.sh` next to
`dune-project`, and is listed in `requires:` and linked with `link-flags:`
in `ocaml-emcc.conf`. This one clones cJSON (`tests/gitrecipe`):

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
`$OCAML_EMCC_RECIPES_PATH`. A project recipe can also **refine** a builtin
one: `include_recipe NAME` reads the next recipe of that name, after the
project's variables are set, and an optional `pre_build` function runs
before its `build`, to patch the sources. Mopsa pins clang 9 and patches
apron this way:

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
# optional: PKGCONFIG=, TARBALL= (prefix), COMPAT=, OPAM_SOURCES= (vendoring
# opam package), LINK= (default -lmpfr; DEPENDS' flags are appended)
# or, for releases not in a directory listing, a releases function printing
# "<version> <tarball url>" lines, oldest first (git_tag_releases helps):
#   releases() { git_tag_releases https://github.com/libffi/libffi.git v \
#     'https://github.com/libffi/libffi/releases/download/v{v}/libffi-{v}.tar.gz'; }

build() {
  emconfigure ./configure --host=none --enable-static --disable-shared \
    --with-gmp="$SYSROOT" --prefix="$SYSROOT" CFLAGS="$CFLAGS"
  emmake make -C src && make -C src install
}
```

The recipe should install a pkg-config file in `$SYSROOT/lib/pkgconfig`
(`install_pc`) when the library's build system does not: in the wasm
context, `pkg-config` (and dune-configurator) only sees the sysroot's
libraries.

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
- functions: `build` (required), `pre_build`, `releases` (see system
  recipes), `fetch`
- helpers: `stub_cc file.c [flags]` (emcc with the OCaml runtime headers),
  `mklib`, `install_lib`, `install_headers`, `install_pc NAME VERSION LIBS
  [CFLAGS]`, `link_flags LIB "-lfoo"` (flags needed whenever `libLIB.a` is
  linked), `apply_patches DIR`, `make_var DIR VAR` (value of a Makefile
  variable), `include_recipe NAME`, `dune_stubs PKG` (build and install the
  stub archives of a dune package from its sources, after changing them),
  `fetch_opam_version PKG VER DEST`, `host_version PCNAME HEADER MACRO...`,
  `git_tag_releases REPO TAG_PREFIX URL_TEMPLATE`, `log`, `die`
- variables: `$EMCC`, `$CFLAGS`, `$LDFLAGS`, `$SYSROOT`, `$OCAML_INC`,
  `$OCAML_VERSION`, `$TARGET`, `$RECIPE_DIR`, `$NPROC`, `$SHARED`
  (target-independent: host tools, big source archives).

## Differences from native

Besides 31-bit integers on wasm32 (see [targets](#targets-wasm32-or-wasm64)):

- **No threads.** `Thread.create` and `Domain.spawn` fail, while `Mutex`
  and `Condition` work. lwt runs its blocking jobs (`Lwt_unix` file
  operations...) synchronously, and `Lwt_preemptive` fails.
- **ctypes struct layouts on wasm32.** The layouts a binding describes
  (`Ctypes.structure`, sizes of `size_t`, `long`...) were computed for the
  64-bit host when the package was built. Constants, enums and functions
  are fine (zstd works on both targets), but bindings that read C structs,
  such as yaml and tsdl, only work on wasm64.
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

## Without dune: step by step

`build` chains the following commands, which can also be run on their own
from scripts and Makefiles:

```sh
ocaml-emcc setup                         # wasm runtime of the switch (once per target)
ocaml-emcc install gmp zarith cjson      # recipes
ocaml-emcc dune ./bin/main.bc            # dune build -x wasm32: C stubs compiled with emcc
ocaml-emcc doctor prog.bc                # how stubs/primitives resolve, 31-bit literal check
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

### Command reference

```
ocaml-emcc [--target wasm32|wasm64] [--switch SW] [--sysroot DIR] [--recipes DIR] [-v] COMMAND
  build OUT.js [--exe DIR/NAME] [LINK OPTIONS] [-- EMCC-ARGS]   everything (dune projects)
  setup [--force]                  wasm runtime of the switch's compiler
  install [--force] RECIPE...      build recipes
  dune [DUNE-BUILD-ARGS]           dune build -x <target> + static stub archives
  deps PROG.bc [-L DIR]            build the missing stub libraries
  doctor PROG.bc [-L DIR]          stub libraries, primitives, 31-bit literals
  link PROG.bc -o OUT.js [LINK OPTIONS] [-- EMCC-ARGS]
  env [--cflags|--sysroot]         configuration / flags for C stubs
link options: -L DIR, -l LIB, --preload, --node-fs, -O FLAG, --stack-size S,
              --no-deps, --wasi (OUT.wasm), --emcc-flag F
```

## How it works

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
   versions, which come first in dune's `PATH`. The wasm `ocamlmklib`
   hands host objects to the host tool.
4. **Dependencies**: the bytecode's `DLLS` section names the stub libraries
   (`dllzarith`...), and each `dll<x>` maps to a wasm `lib<x>.a`. A missing
   one is built from the opam package that installed `dll<x>.so`, by the
   first of:
   1. a recipe with the package's name
   2. the package's own dune rules (`dune -x`), as for digestif
   3. the C files behind each stub archive of the package's native build,
      with its `-I` flags: for packages without dune (glpk), when `dune -x`
      fails (the `(ctypes)` stanza), or when an archive was built by a host
      tool (ocaml-lua runs `make` in its copy of Lua)
   4. every `.c` file of the package that includes `<caml/...>`.

   `c_library_flags` are only used by custom links, which a bytecode build
   does not do, so the toolchain's `ocamlc` records those of every linked
   `.cma` in the sysroot, and `link` builds the missing ones: the stub
   library of the opam package that installed `dllX.so` (libraries built
   with `ocamlmklib -custom`, such as stb_image, are only named there), or
   the recipe providing `libX.a`.
5. **Link**: a primitive table is generated with only the primitives the
   bytecode uses, so wasm-ld drops the rest. The bytecode, without its
   `DLLS`/`DLPT` sections, is embedded in the module and `argv[0]` points
   to it (the `ocamlc -custom` trick), so `Sys.argv` looks native.

**Standalone modules.** A `.wasm` without JavaScript has no file system to
embed the bytecode in. Its sections become the C arrays of a generated
`bytecode.c` (`#embed`), and `main.c` starts the program with
`caml_startup_code`, as the C file of `ocamlc -output-obj` does: `CODE`,
`DATA`, the section table of that compiler for the toplevel and Dynlink
(`SYMB`, `CRCS`, and `PRIM` before 5.0), and the debug events of `DBUG`,
relocated and gathered by `link` into what the runtime would build from
the executable file (backtraces keep their locations).

**WASI.** emscripten's standalone libc already reads, writes and closes
files, and reads clocks, arguments and the environment, with WASI calls.
But opening and `stat`ing a file are stubs that fail (EPERM, ENOSYS),
whatever the host, and the rest of the file system (`unlink`, `rename`,
`getcwd`, `readdir`...), sockets and `system` are imports of emscripten's
JavaScript. `--wasi` adds `share/runtime/wasi.c`, which implements these
system calls with WASI, as wasi-libc does, and links with `-sPURE_WASI`,
which removes emscripten's last import (memory growth notifications).
`setjmp`/`longjmp` (`-sSUPPORT_LONGJMP=wasm`) and C++ exceptions are
compiled into emscripten's default encoding of wasm exceptions, the legacy
one, which WASI hosts do not implement: binaryen translates the module to
the standard one (exnref) as emcc finishes it
(`-sBINARYEN_EXTRA_PASSES=--translate-to-exnref,--emit-exnref`).

**Signature adapters.** A wasm indirect call traps on any signature
mismatch, while native code ignores extra arguments: OCaml calls zarith's
`ml_z_init()` with one argument, for instance. The arity of each call site
is read from the bytecode (`C_CALLn`), wasm-ld reports the definitions that
differ, and an adapter is generated for each of them.

**ctypes-foreign.** A static wasm program has no `dlsym`, so `link` exports
the C functions and variables whose names appear as string literals in the
program, and links a `dlopen`/`dlsym` that looks them up among the module's
exports. ctypes-foreign also needs the `threads` library, which the `ocaml`
recipe builds single-threaded.

**Flags used for all C code**:
- `-fno-strict-overflow`: works around an LLVM bug on wasm64, which folds
  `p[-8]` (`Tag_val`) into an unsigned load offset that traps
- `-sSUPPORT_LONGJMP=wasm`: OCaml raises exceptions from C with longjmp,
  and the JS implementation would route every primitive call through JS
- `-fwasm-exceptions`: C++ exceptions with the same wasm instructions
  (emscripten's JS exceptions cannot be thrown alongside)
- no `-pthread` (lwt asks for it): the program is single-threaded, and
  with it `caml_state` would be a thread-local variable, unlike in the
  runtime.

**Version specifics** of the `ocaml` recipe:

| version | issue | fix |
|---------|-------|-----|
| < 4.10  | `caml_debug_info` defined in two files (needs `-fcommon`, which wasm lacks) | made `extern` in `backtrace.c` |
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
| all, wasm32 | integer literals beyond 31 bits in the DATA section ("input_value: integer too large") | wrapped to 31 bits while DATA is read (`intern.c`, `startup_byt.c`), from the file (`caml_main`) or from memory (`caml_startup_code`, standalone modules) |
| all     | a program started by `caml_startup_code` (standalone modules) reads its debug events from the executable file, which does not exist: backtraces without locations | `backtrace_byt.c` takes them from memory when `main.c` gives them (`caml_emcc_debug_events`), unchanged otherwise |
| all, wasm64 | stubs pass `int` dimensions to `caml_ba_alloc_dims`, read as `intnat` (stb_image: a corrupted heap) | the installed `bigarray.h` converts each one |

Version-specific patches go in `share/recipes/ocaml/patches/4.x/`,
`patches/5.4+/` or `patches/<major>.<minor>/`. Compilers before 4.08 are
not supported: their build has no autoconf `configure`, and their bytecode,
marshal and runtime layouts differ from what the link step reads.

## Status

Prototype. `tests/run.sh [--target wasm32|wasm64]` builds each test with
`ocaml-emcc build` (or make), runs it with node and compares the output
with the native executable (or `expected.txt`). CI
(`.github/workflows/ci.yml`) runs the suite on OCaml 4.14 and 5.5, both
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

Each test passes on both targets, except `hello` (on purpose: it checks
63-bit ints), `yaml` and `sdl` (ctypes structs), which are wasm64 only. "–"
means the packages were not installed in that switch, or the test does not
apply (mlmpfr 4.2.1 does not build with OCaml 5). The 5.4.1 tests from
`clibs` on ran in a Debian 13 container with the system libraries the
bindings need. The zarith test also ran unmodified in Chrome 154, on both
targets.

`tests/run.sh --wasi` builds the tests marked `wasi` in its table with
`--wasi` and runs them with wasmtime (`$WASMTIME`, or the one in `PATH`),
else with node's WASI. They pass with wasmtime 50 on OCaml 4.14.2 and 5.5.1
(stubs, zarith, mixed, ocaml5, gitrecipe, nodune, syslibs, apron, sqlite,
bz2, pcre2, zstd, gsl, camlzip, binio, the packages installed in each
switch), and stubs, zarith, gitrecipe, nodune and mixed on 4.08.1, 4.11.2
and 4.12.1; sqlite, stubs, camlzip and binio also with node 24's WASI.
`ctypes` cannot pass: libffi's emscripten port makes its calls in
JavaScript. The tests from `clibs` on were not tried.

## Next steps

- Domains: a `--threads` variant (runtime, stubs and link with `-pthread`)
  could enable `Domain.spawn`. It needs SharedArrayBuffer (COOP/COEP
  headers on the web).
- OCaml 5.0 to 5.3 are untested and probably need patches of their own:
  the memory code moved around.
- ctypes structs on wasm32: `dune -x` already builds ctypes' OCaml code
  with the sizes of the target. Installing it in the sysroot's findlib
  directory, which the toolchain searches first, would fix bindings that
  lay structs out at run time (tsdl). Type descriptions generated at build
  time (yaml) need the package itself rebuilt that way.
- More recipes: ppl (C++, apron's `ppl` and `polkaGrid` domains), flint,
  openssl, libtidy, and newer LLVM versions for `clang`.
- WASI: sockets the host preopens (preview1's `sock_accept`, `sock_recv`,
  `sock_send`), and a `dlsym` that needs no JavaScript (a table of the
  exported functions generated by `link`), though ctypes-foreign would
  still need a libffi without JavaScript. WASI preview 2 (components) is not
  targeted.
- Distribution: prebuilt runtimes and C libraries (npm, GitHub releases),
  keyed by OCaml version, emsdk version and target, and a
  `conf-emscripten` opam package for the emsdk requirement.

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
