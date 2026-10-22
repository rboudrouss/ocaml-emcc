# ocaml-emcc

Compile OCaml programs **with their C stubs** to WebAssembly, for the browser
and node.

Your program and its dependencies (zarith/gmp, unix, str, digestif, your own
`foreign_stubs`, a C library cloned from GitHub...) end up in one
emscripten module. Unlike js_of_ocaml / wasm_of_ocaml, no C stub has to be
rewritten in JavaScript, so FFI-heavy code works as is.

## Quick start

```sh
opam switch create myswitch 5.4.1 --keep-build-dir
opam install . --deps-only --keep-build-dir   # or install your dependencies with --keep-build-dir
opam install ocaml-emcc                       # not published yet: opam pin add ocaml-emcc <this repo>
source /path/to/emsdk/emsdk_env.sh            # emcc in PATH

ocaml-emcc build main.js                      # in your dune project
node main.js                                  # or load main.js in a web page
```

`ocaml-emcc build main.js` finds the dune executable named `main`, and the
first time builds a wasm OCaml runtime from the sources of your switch's
compiler. Then it compiles your C stubs and those of your dependencies with
emcc, and writes `main.js` + `main.wasm`.

`--keep-build-dir` matters: ocaml-emcc rebuilds C code from the sources opam
used. Without it they are downloaded again with `opam source`.

## Usage

### `ocaml-emcc build OUT.js`

The executable is the one at the same place as `OUT` in the project
(`ocaml-emcc build bin/main.js` → `bin/main`), else the only executable of the
project named like `OUT`. Use `--exe DIR/NAME` otherwise:

```sh
ocaml-emcc build main.js                    # the executable `main`, wherever it is
ocaml-emcc build dist/app.js --exe bin/main
ocaml-emcc build main.html                  # + an emscripten test page
```

It works with any `(modes ...)`: no need to add `byte`. Output:

- `OUT.js` (+ `OUT.wasm`): runs in node and in browsers (default);
- `OUT.html`: the same plus a minimal emscripten page;
- `OUT.wasm` alone: emcc's standalone mode, **without the JavaScript glue**
  (file system, console, bytecode loading). It still imports emscripten
  functions, so it does not run in a plain WASI host; ocaml-emcc warns.

Common options: `--target wasm32|wasm64` (see below), `-O -Oz` (default
`-O2`), `--stack-size 16MB`, `--preload`, `--node-fs`, `-l LIB`, `-L DIR`,
`--emcc-flag F`, and anything after `--` goes to emcc.

### In a web page, in node

The same files work in both: emscripten's default environment is
`web,webview,worker,node`, and the bytecode is embedded in the `.wasm`.

```sh
node main.js arg1 arg2      # exit code, stdout/stderr as usual
```

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

Don't declare global `out`/`err` variables in the page: emscripten's script
declares them. For a module you instantiate yourself, add
`-- -sMODULARIZE=1 -sEXPORT_NAME=createMain`. `--preload` puts the bytecode in
a separate `main.data` (web; under node it is resolved relative to the current
directory). `--node-fs` makes a node-only build with access to the real file
system and the environment variables of the node process (`Sys.getenv`).

### Targets: wasm32 (default) or wasm64

The bytecode is the one of your switch, compiled for 64 bits.

- **wasm32** (default): smaller, faster, supported everywhere. Ints are 31
  bits at run time:
  - integer literals outside 31 bits (`0x40000000`, `123456789012`) abort
    the program at startup (`input_value: integer too large`).
    `ocaml-emcc build`/`link`/`doctor` **warn** when there are any (the check
    is exact);
  - arithmetic beyond 31 bits wraps silently (`1 lsl 40` = 256), which no
    tool can detect.
- **wasm64** (`--target wasm64`): memory64, exactly the semantics of the
  native 64-bit program. Needs node ≥ 24 (the one shipped with emsdk works),
  Chrome ≥ 133 or Firefox ≥ 134.

### Extra emscripten flags

From lowest to highest precedence (emcc keeps the last `-s` setting):
`link-flags:` in `ocaml-emcc.conf`, `$OCAML_EMCC_LDFLAGS`, `--emcc-flag F`
and arguments after `--`.

```sh
ocaml-emcc build app.js -- -sMODULARIZE=1 -sEXPORT_NAME=createApp \
  --preload-file assets@/assets -sINITIAL_MEMORY=128MB -sENVIRONMENT=web
```

C flags for the stubs and recipes: `cflags:` in `ocaml-emcc.conf` or
`$OCAML_EMCC_EXTRA_CFLAGS`.

### Project configuration: `ocaml-emcc.conf`

Optional, looked up from the current directory upwards:

```
target: wasm32                  # default target of the project
requires: cjson                 # recipes built before building/linking
link-flags: -lcjson -sINITIAL_MEMORY=64MB
cflags: -DNDEBUG
recipes: emcc-recipes           # recipe directories (default: ./emcc-recipes)
```

### C libraries and project recipes

Stub libraries of your opam dependencies are rebuilt automatically. To add a
C library your stubs need, write a **recipe** in `emcc-recipes/<name>/recipe.sh`
(picked up automatically, next to `dune-project`), list it in `requires:`, and
link it with `link-flags:`. Recipes can clone from git without history:

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

`tests/gitrecipe` is this exact example.

A project recipe can also **refine a builtin one**: `include_recipe NAME`
reads the next recipe of that name down the recipe path, after the project
has set its variables, and an optional `pre_build` function runs before its
`build` (to patch the sources). Mopsa pins clang 9 and patches apron this way:

```sh
# emcc-recipes/clang/recipe.sh
LLVM_VERSION=9.0.1
include_recipe clang

# emcc-recipes/apron/recipe.sh
include_recipe apron
pre_build() { sed -i '...' apron/ap_manager.c; }
```

A recipe is not rebuilt when it changes. ocaml-emcc
says so, and `ocaml-emcc install --force NAME` rebuilds it.

#### Libraries of your C stubs: `c_library_flags`

The flags dune records in a library for its stubs (`(c_library_flags
(-lfoo))`, `-cclib`) are only used by a custom link, which the bytecode build
does not do. The toolchain's `ocamlc` records those of every linked `.cma`
(in the sysroot, under the MD5 of the bytecode), and `link` adds each `-lX`
for which a wasm `libX.a` exists (in the sysroot, `-L` dirs, the dune
build). Host flags (`-L/usr/lib`,
`-Wl,-rpath`) are dropped, so are the libraries emcc provides (`-lm`,
`-lpthread`...), and `-lstdc++` links the program as C++ (libc++).

#### System libraries (`conf-*` packages)

Many opam packages take a C library from the system through a `conf-*`
package: `conf-gmp`, `conf-mpfr`, `conf-zlib`... When ocaml-emcc rebuilds
the stubs of such a package, it builds the recipe of the same name (`gmp`,
`mpfr`, `zlib`) first and adds its link flags (`-lmpfr -lgmp`). There is
nothing to configure: `tests/syslibs` (mlmpfr + zlib) has no
`ocaml-emcc.conf`.

These recipes use `SOURCE=system:NAME` and pin no version. They take:
1. the sources of the opam package that vendors the library, if the switch
   has it (e.g. the `gmp` package), since that is what the native build uses;
2. otherwise, the newest upstream release compatible with the host's
   library, found by pkg-config or from the version macros of its header.
   By default "compatible" means same major version (`COMPAT=major`; also
   `minor`, `exact`, `latest`). Without a host library, the newest release.

opam fetches the release when its repository knows that version, and then
checks the checksum. Otherwise the tarball is downloaded from `RELEASES`
without a checksum, and the log says so. To pin a version, write a project
recipe with the same name. A system recipe only describes the library:

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

Builtin system recipes, named after their `conf-*` package:

| recipe | for (opam) | notes |
|--------|------------|-------|
| `gmp`, `mpfr` | zarith, mlmpfr, mlgmpidl, apron... | |
| `zlib` | camlzip, zlib | |
| `sqlite3` | sqlite3 | the amalgamation, single-threaded, FTS3/4/5, R-tree, math functions (`SQLITE_CFLAGS`); the version from sqlite.org's release history |
| `libffi` | ctypes-foreign | see "ctypes" below |
| `libbz2` | bz2 (camlbz2) | |
| `libpcre2-8` | pcre2 | no JIT |
| `zstd` | zstd | single-threaded |
| `gsl` | gsl | with its CBLAS (`-lgsl -lgslcblas`) |

Each writes a pkg-config file in `$SYSROOT/lib/pkgconfig` when its build
system does not. Other recipes pin no version either:
- `zarith`, `camlidl`, `mlgmpidl`, `apron` use the sources of the installed
  package (for the camlidl bindings, the C files camlidl generated in its
  build directory, else regenerated with the host camlidl). `apron` builds
  the C libraries and the stubs of every domain (box, oct, polka, t1p, avo;
  each numeric variant). wasm cannot set the FPU rounding mode, so the box
  and octagon managers warn when allocated (the MPQ domains are exact);
- `clang`: clang's C++ libraries for programs embedding the frontend, see
  below.

#### clang

The `clang` recipe builds the libraries of clang's frontend
(`libclang*.a`, the `libLLVM*.a` they need, `libclang-cpp.a` with all of
them) with their headers and clang's resource headers
(`lib/clang/<ver>/include`). It also writes into `$SYSROOT/bin`:
- `llvm-config`, which describes this installation (`--cxxflags`,
  `--ldflags`, `--libs`...): give it to a configure script or dune rule;
- `clang`, which compiles nothing but answers `-print-resource-dir` with
  where the program will find the resource headers at run time
  (`CLANG_RESOURCE_DIR`, default `/usr/lib/clang/<ver>`: preload them there;
  `$OCAML_EMCC_CLANG_RESOURCE_DIR` overrides it).

The version is `LLVM_VERSION` when a project recipe sets it (`9.0.1`, or a
major `9`), else the major version of the host's `llvm-config`, else the
newest release. It takes a while: cmake builds tablegen for the host (kept
in the sysroot's `shared/`, for both targets) and then the libraries with
emcc. It needs cmake and a host C++ compiler, and ninja if available. LLVM
9.0.1 on 4 cores: about 15 minutes.

#### ctypes

Bindings with ctypes' **stub generation** (`Cstubs`, dune's `(ctypes)`
stanza: zstd, yaml...) need nothing: their generated C stubs are compiled
like hand-written ones. dune cannot cross-compile the `(ctypes)` stanza (its
generators would be native executables of the wasm context); ocaml-emcc
then compiles the C files of the package's native build instead (they do
not depend on the architecture).

On **wasm32**, the layouts of the C structs a binding describes
(`Ctypes.structure` in a type description, sizes of `size_t`, `long`...) are
those of the host: they were computed when the package's bytecode was
built, and wasm32 is ILP32. Constants, enums and functions are fine (zstd
passes on both targets), but yaml, which reads libyaml's event structs, only
works on wasm64 (LP64, as the host).

**ctypes-foreign** (`Foreign.foreign "strlen"`, bound at run time through
libffi) works on both targets, callbacks (C calling OCaml closures) and
structs by value included:
- the `libffi` recipe is built automatically (`conf-libffi`);
- symbols are found with `dlsym`, which a static wasm program does not have.
  `link` exports the C functions and variables named by string literals of
  the program (and defined by the linked libraries or emscripten's libc), and
  links an implementation of `dlopen`/`dlsym` that looks them up among the
  module's exports. A name computed at run time is not found; `dlopen`
  accepts any file name, since everything is linked in;
- ctypes-foreign depends on the `threads` library, built by the `ocaml`
  recipe: Mutex and Condition work, `Thread.create` fails (no pthreads).

#### Recipe reference

- `SOURCE=` `git:URL` (+ `REF=`), `url:TARBALL` (+ `SHA256=`), `dir:PATH`
  (relative to the recipe), `opam:PACKAGE` (sources of an installed package),
  `system:NAME` (see above), `fetch` (the recipe defines its own
  `fetch DEST` function), `none`;
- `DEPENDS=` other recipes to build first;
- helpers: `stub_cc file.c [flags]` (emcc with the OCaml runtime headers),
  `mklib`, `install_lib`, `install_headers`, `link_flags LIB "-lfoo"`
  (flags needed whenever `libLIB.a` is linked), `apply_patches DIR`, `log`,
  `die`, `make_var DIR VAR` (value of a Makefile variable),
  `include_recipe NAME`, `install_pc NAME VERSION LIBS [CFLAGS]` (a
  pkg-config file); for `fetch`: `fetch_opam_version PKG VER DEST`,
  `host_version PCNAME HEADER MACRO...` (version of a host C library);
- `pre_build`: optional function run before `build`; `releases`: see
  system libraries (`git_tag_releases REPO TAG_PREFIX URL_TEMPLATE`);
- variables: `$EMCC`, `$CFLAGS`, `$LDFLAGS`, `$SYSROOT`, `$OCAML_INC`,
  `$OCAML_VERSION`, `$TARGET`, `$RECIPE_DIR`, `$NPROC`, `$SHARED`
  (target-independent: host tools, big source archives).

Project recipes take precedence over the builtin ones (`share/recipes/`:
`ocaml`, `gmp`, `mpfr`, `zlib`, `sqlite3`, `libffi`, `libbz2`,
`libpcre2-8`, `zstd`, `gsl`, `zarith`, `camlidl`, `mlgmpidl`, `apron`,
`clang`). More directories: `--recipes DIR`,
`$OCAML_EMCC_RECIPES_PATH`. A recipe is built once per switch and target;
`ocaml-emcc install --force NAME` rebuilds it.

### Step by step: scripts, Makefiles, projects without dune

`build` chains these commands, which can also be used on their own:

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
`emcc $(ocaml-emcc env --cflags)`, and give their archive to `link`
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

The stubs of `zarith` and `unix` are found from the bytecode itself.

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
              --no-deps, --emcc-flag F
```

## Requirements

- An opam switch, **OCaml 4.08 or later** (4.x and 5.x), that keeps the
  sources of the compiler and of the packages with C stubs:
  `--keep-build-dir` on each `opam switch create` / `opam install`, or
  `OPAMKEEPBUILDDIR=true` in the environment (there is no persistent opam
  option for it). The sources are then in
  `$OPAM_SWITCH_PREFIX/.opam-switch/build/`. When they are missing,
  `opam source` is used (needs network, and the version must still be in the
  repository).
  The default opam repository now starts at 4.11; older compilers are in the
  archive repository:
  `opam switch create 4.08.1 --repos default,archive=git+https://github.com/ocaml/opam-repository-archive --keep-build-dir`.
  Before 4.08 the compiler had no autoconf `configure` (the `ocaml` recipe
  relies on it), and the bytecode, marshal and runtime layouts the link step
  reads are older: not supported.
- The emscripten SDK, with `emcc` in `PATH`.
- dune ≥ 3.11 for `build`/`dune`. Projects without dune only need `link`.
- Everything ocaml-emcc builds lives in `$OPAM_SWITCH_PREFIX/emcc-sysroot/`,
  and is removed with the switch.

## How it works

1. **Runtime** (`setup`, the `ocaml` recipe): the switch's compiler sources
   are configured with `emconfigure`. Then `libcamlrun.a` and the C parts of
   `unix`, `str` and `runtime_events` are built and installed in the sysroot
   with the wasm headers. A findlib toolchain (`wasm32`/`wasm64`) is written
   for dune.
2. **Bytecode**: the host's own `ocamlc`, ppx, menhir and every installed
   `.cma` are used unchanged.
3. **dune -x**: in the wasm context, an `ocamlc` wrapper rewrites
   `ocamlc -config`. Dune's C compiler becomes emcc and the stubs are
   compiled with the wasm headers. An `ocamlmklib` replacement builds the
   `lib*.a` with `emar`. `(modes exe)` executables come out as plain
   bytecode (`-output-complete-exe` is intercepted).
4. **Dependencies**: the bytecode's `DLLS` section names the stub libraries
   (`dllzarith`...). Each `dll<x>` maps to a wasm `lib<x>.a`. A missing one
   is built from the opam package that installed `dll<x>.so`, trying in
   order:
   1. a recipe with the package's name;
   2. the package's own dune rules (`dune -x`), as for digestif. If dune
      fails (ctypes' `(ctypes)` stanza), the C files behind each stub archive
      of the package's native build, with `-I` flags only;
   3. the compilation of every `.c` file that includes `<caml/...>`.

   Rules that run `ocamlmklib` themselves (yaml's vendored libyaml) get the
   wasm one: it comes first in dune's `PATH`, and hands host objects to the
   host tool.
5. **Link**: a primitive table is generated with only the primitives the
   bytecode uses, so wasm-ld drops the rest. Stubs whose C signature does
   not match the OCaml call are adapted (see below). The bytecode, without
   its `DLLS`/`DLPT` sections (nothing to dlopen), is embedded in the module,
   and `argv[0]` points to it (the `ocamlc -custom` trick), so `Sys.argv`
   looks native.

**Signature adapters.** A wasm indirect call traps on any signature
mismatch, while native code ignores extra arguments. Zarith's `ml_z_init()`
is called with one argument by OCaml, for instance. The arity of each call
site is read from the bytecode (`C_CALLn`), and wasm-ld reports the
definitions that differ. An adapter is generated for each of them.

**Flags used for all C code**:
- `-fno-strict-overflow`: works around an LLVM bug on wasm64, which folds
  `p[-8]` (`Tag_val`) into an unsigned load offset that traps;
- `-sSUPPORT_LONGJMP=wasm`: OCaml raises exceptions from C with longjmp,
  and the JS implementation would route every primitive call through JS.

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
| 5.4     | minor heap committed with `mmap(MAP_FIXED)` ("Failed to create main domain") | `patches/5.4/` |
| all     | `sigsuspend` missing (unix) | weak stub |
| all, wasm32 | `ARCH_ALIGN_DOUBLE` (`alignof(double)` is 8): float accesses through memcpy, some stubs refuse to build (gsl) | undefined, as for i686: wasm loads doubles at any alignment |
| all     | systhreads disabled (no pthreads) | `libthreads.a` built anyway, single-threaded |

Version-specific patches go in `share/recipes/ocaml/patches/4.x/` or
`patches/<major>.<minor>/`.

## Status

Prototype. `tests/run.sh [--target wasm32|wasm64]` builds each test with
`ocaml-emcc build` (or make), runs it with node and compares the output with
the native executable (or `expected.txt`). All pass:

| test        | what it covers | 4.08.1 | 4.11.2 | 4.12.1 | 4.14.2 | 5.4.1 |
|-------------|----------------|--------|--------|--------|--------|-------|
| `hello`     | stdlib, 63-bit ints and literals, Marshal, GC, files, exit code (wasm64 only, on purpose) | ✅ | ✅ | ✅ | ✅ | ✅ |
| `stubs`     | dune `foreign_stubs` (int64, floats, callbacks, C exceptions, custom blocks), unix, str | ✅ | ✅ | ✅ | ✅ | ✅ |
| `zarith`    | zarith + gmp | ✅ | ✅ | ✅ | ✅ | ✅ |
| `mixed`     | digestif (dune stubs rebuilt automatically), yojson, re, cmdliner | ✅ | – | ✅ | ✅ | ✅ |
| `ocaml5`    | effects, Atomic, Mutex, Dynarray (`Domain.spawn` raises) | – | – | – | – | ✅ |
| `gitrecipe` | project recipe cloning cJSON from GitHub | ✅ | ✅ | ✅ | ✅ | ✅ |
| `nodune`    | Makefile, ocamlfind, hand-compiled stub + `ocaml-emcc link` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `syslibs`   | mlmpfr + zlib bindings: `conf-mpfr`/`conf-zlib` → system recipes, no project configuration | – | – | – | ✅ | – |
| `apron`     | apron (box, octagons, polyhedra) + mlgmpidl + camlidl recipes | – | – | – | ✅ | – |
| `sqlite`    | sqlite3 bindings + recipe: SQL, JSON, math functions, a database file | – | – | – | ✅ | – |
| `bz2`       | bz2 bindings + libbz2 recipe | – | – | – | ✅ | – |
| `pcre2`     | pcre2 bindings + libpcre2-8 recipe (named groups, UTF-8) | – | – | – | ✅ | – |
| `zstd`      | zstd (ctypes stub generation: native-build fallback) + zstd recipe | – | – | – | ✅ | – |
| `gsl`       | gsl bindings + recipe: special functions, integration, LU, RNG, stats | – | – | – | ✅ | – |
| `camlzip`   | camlzip (no dune) + zlib recipe: gzip, zip archives | – | – | – | ✅ | – |
| `ctypes`    | ctypes-foreign + libffi recipe: libc functions, callbacks (qsort), structs by value | – | – | – | ✅ | – |
| `yaml`      | yaml (ctypes stubs, vendored libyaml; wasm64 only, see "ctypes") | – | – | – | ✅ | – |

Each test passes for both wasm32 and wasm64 (`hello` and `yaml`: wasm64
only). "–"
means the packages were not installed in that switch, or the test does not
apply (mlmpfr 4.2.1 does not build natively with OCaml 5.4, an upstream
issue). The zarith test also ran unmodified in Chrome 154, for both targets.

Beyond the tests: Mopsa (the whole analyzer, its C parser linked with clang
9's libraries) builds with the `clang` and `apron` recipes and runs under
node with the same results as the native build on its C, Python and
universal unit tests (wasm32, OCaml 4.14.2; see the `ocaml-emcc` branch of
mopsa-analyzer-32-bit, `emcc/README.md`).
Tested with emsdk 6.0.11.

## Limitations / next steps

- `Domain.spawn` fails (no pthreads). A `--threads` variant (runtime, stubs
  and link with `-pthread`) could enable domains; it needs SharedArrayBuffer
  (COOP/COEP headers on the web).
- OCaml 5.0–5.3 are untested and probably need a `patches/5.x` of their own:
  the memory code moved around.
- More recipes. Other system libraries worth a recipe: ppl (C++, apron's
  `ppl` and `polkaGrid` domains), flint, expat, lz4, openssl; SDL2 could map
  to emscripten's port (`-sUSE_SDL=2`) for tsdl. The `clang` recipe is only
  tested with LLVM 9.0.1; newer versions follow the same steps but may need
  other cmake options.
- ctypes on wasm32: struct layouts computed for the host (see "ctypes").
  Running the type generators for the target would need the package's OCaml
  code rebuilt from source in the wasm context.
- Distribution: prebuilt runtimes and C libraries could be published (npm,
  GitHub releases), keyed by OCaml version, emsdk version and target. There
  is no `conf-emscripten` opam package yet to express the emsdk requirement.

## Development

```
bin/main.ml           CLI
src/                  bytecode reading, linking, dependency resolution, project config
share/driver.sh       recipe driver
share/recipes/        ocaml (runtime + patches), gmp, mpfr, zlib, zarith, camlidl,
                      mlgmpidl, apron, clang
share/tools/          ocamlc / ocamlmklib wrappers for dune -x
share/runtime/        main.c, compat.c
tests/run.sh          test suite (SWITCH=<opam switch> tests/run.sh --target wasm64)
```
