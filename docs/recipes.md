# Writing recipes

A recipe is a `recipe.sh` in a directory named after it: the builtin ones
are in `share/recipes/`, a project's in `emcc-recipes/` (see
[project recipes](../README.md#project-recipes)).

## System recipes

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

## Recipe reference

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
  linked), `apply_patches DIR` (see [patches](#patches)), `make_var DIR VAR` (value of a Makefile
  variable), `include_recipe NAME`, `dune_stubs PKG` (build and install the
  stub archives of a dune package from its sources, after changing them),
  `fetch_opam_version PKG VER DEST`, `host_version PCNAME HEADER MACRO...`,
  `git_tag_releases REPO TAG_PREFIX URL_TEMPLATE`, `log`, `die`
- variables: `$EMCC`, `$CFLAGS`, `$LDFLAGS`, `$SYSROOT`, `$OCAML_INC`,
  `$OCAML_VERSION`, `$TARGET`, `$RECIPE_DIR`, `$BASE_RECIPE_DIR` (that of
  the recipe read by `include_recipe`, where its patches are), `$NPROC`,
  `$SHARED` (target-independent: host tools, big source archives)

## Patches

`apply_patches DIR` applies the `DIR/*.patch` files in order. They are
unified diffs (`diff -u`, `git diff`), but each hunk is placed by its
text, not by line numbers: its old text must occur exactly once in the
file, and its `@@` lines need no numbers. A hunk that matches no place, or
several, stops the build, and one already applied is skipped.

## The clang recipe

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
