#!/usr/bin/env bash
# Recipe driver for ocaml-emcc: reads recipes and runs their `build`.  The
# CLI decides what to build (stamps, DEPENDS) and fetches the sources
# (src/recipes/).
#
#   driver.sh describe <recipe>             the variables of a recipe
#   driver.sh build <recipe> <result> [<version>]
#                                            build + install a recipe, its
#                                            dependencies built and its
#                                            sources fetched
#   driver.sh releases <recipe>             its `releases` function
#
# Environment (set by the `ocaml-emcc` CLI):
#   OCAML_EMCC_SHARE         share directory (recipes/, tools/, runtime/)
#   OCAML_EMCC_SWITCH_PREFIX opam switch prefix providing the host compiler
#   OCAML_EMCC_SYSROOT       where wasm artifacts are installed
#   OCAML_EMCC_TARGET        wasm32 (default) or wasm64
#   OCAML_EMCC_BASE_CFLAGS, OCAML_EMCC_TARGET_FLAGS, OCAML_EMCC_STUB_STD
#                            C flags (see Toolchain)
#   OCAML_EMCC_RECIPES_PATH  extra ':'-separated recipe directories (optional,
#                            searched before the builtin ones)
#   OCAML_EMCC_EXTRA_CFLAGS  extra C flags for recipes (optional)
#   OCAML_EMCC_EXE           the CLI, run as `ocaml-emcc internal ...` for
#                            what is done in OCaml
#
# A recipe is a directory `<name>/` containing `recipe.sh`, which may set
#   SOURCE   "opam:<package>"     sources of an installed opam package
#            "url:<tarball url>"  (+ SHA256=<checksum>)
#            "git:<repo url>"     shallow clone (+ REF=<tag|branch|commit>)
#            "dir:<path>"         a directory, relative to the recipe
#            "system:<name>"      a system C library (conf-<name>), version
#                                 chosen from the host's: see "system libraries"
#            "fetch"              the recipe's own `fetch <dest>` function
#                                 (e.g. to pick the version the host uses)
#            "ocaml" | "none"
#   SHA256   checksum of the tarball (url: sources)
#   REF      git tag, branch or commit (git: sources; default: HEAD)
#   DEPENDS  space separated recipe names built first
# and must define a `build` function (or include one: `include_recipe NAME`,
# with an optional `pre_build` function run before it).  `build` runs inside
# a fresh copy of the sources with the helpers below available (install_lib, install_headers,
# link_flags, mklib, apply_patches...).

set -euo pipefail

: "${OCAML_EMCC_SHARE:?}" "${OCAML_EMCC_SWITCH_PREFIX:?}" "${OCAML_EMCC_SYSROOT:?}" "${OCAML_EMCC_EXE:?}" \
  "${OCAML_EMCC_BASE_CFLAGS:?}" "${OCAML_EMCC_TARGET_FLAGS:?}"

SYSROOT=$OCAML_EMCC_SYSROOT
PREFIX=$OCAML_EMCC_SWITCH_PREFIX
HOST_BIN=$PREFIX/bin
# opam commands (opam source, opam show, opam var) act on this switch, not on
# opam's current one: opam ignores OPAM_SWITCH_PREFIX, and only takes a
# switch name, or the directory of a local switch.
case $PREFIX in
  */_opam) export OPAMSWITCH=${PREFIX%/_opam} ;;
  *) if [ -f "$(dirname "$PREFIX")/config" ]; then
       export OPAMROOT; OPAMROOT=$(dirname "$PREFIX"); OPAMSWITCH=$(basename "$PREFIX"); export OPAMSWITCH
     fi ;;
esac
OCAML_VERSION=$("$HOST_BIN/ocamlc" -vnum)
OCAML_MAJOR=${OCAML_VERSION%%.*}
OCAML_MINOR=${OCAML_VERSION#*.}; OCAML_MINOR=${OCAML_MINOR%%.*}
OCAML_INC=$SYSROOT/lib/ocaml
NPROC=$(nproc 2>/dev/null || echo 2)
RECIPES_PATH="${OCAML_EMCC_RECIPES_PATH:+$OCAML_EMCC_RECIPES_PATH:}$OCAML_EMCC_SHARE/recipes"

TARGET=${OCAML_EMCC_TARGET:-wasm32}
# The flags every piece of C code agrees on (Toolchain).  BASE_CFLAGS is what
# the toolchain wrappers and the link step record; extra flags are added on
# top at each use (recipes here, stubs in tools/ocamlc).
TARGET_FLAGS=$OCAML_EMCC_TARGET_FLAGS
BASE_CFLAGS=$OCAML_EMCC_BASE_CFLAGS
export CFLAGS="$BASE_CFLAGS ${OCAML_EMCC_EXTRA_CFLAGS:-}"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="$TARGET_FLAGS"
# the C standard of the host compiler, when newer than emcc's default
STUB_STD=$OCAML_EMCC_STUB_STD
# Flags to compile OCaml stubs against the wasm32 runtime headers.
STUB_CFLAGS="$CFLAGS $STUB_STD -I$OCAML_INC -I$SYSROOT/include -D_FILE_OFFSET_BITS=64"

EMCC=$(command -v emcc) || { echo "ocaml-emcc: emcc not found in PATH (source emsdk_env.sh)" >&2; exit 1; }
EMSDK_BIN=$(dirname "$EMCC")
EMAR=$EMSDK_BIN/emar
EMCC_VERSION=$("$EMCC" -dumpversion)
export EMAR

# Target-independent files (host tools built by recipes, big source archives)
SHARED=$(dirname "$SYSROOT")/shared
mkdir -p "$SYSROOT"/{lib,include,bin,build,src,stamps,meta} "$OCAML_INC" "$SHARED"

log() { printf '\033[1;34m[ocaml-emcc]\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31m[ocaml-emcc]\033[0m %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- versions

ocaml_version_ge() { # ocaml_version_ge 4 14
  [ "$OCAML_MAJOR" -gt "$1" ] || { [ "$OCAML_MAJOR" -eq "$1" ] && [ "$OCAML_MINOR" -ge "$2" ]; }
}

# ----------------------------------------------------------------- sources
#
# The sources of a recipe are fetched by the CLI (Source), before `build`.
# These helpers, for recipes, run it.

# fetch_opam_source <pkg> <dest>: copy the sources of an installed package
# (opam's kept build dir, else `opam source`).
fetch_opam_source() {
  SOURCE_VERSION=$("$OCAML_EMCC_EXE" internal fetch-opam-source "$1" "$2") || exit 1
}

# fetch_opam_version <pkg> <version> <dest>: sources of any version known to
# the opam repository, installed or not (opam checks the archive checksum).
# Fails if the repository has no such version.
fetch_opam_version() {
  "$OCAML_EMCC_EXE" internal fetch-opam-version "$1" "$2" "$3" && SOURCE_VERSION=$2
}

# host_version <pkg-config name> <header> <major macro> <minor macro> [<patch macro>]
# Version of a C library as the host (hence the native build) sees it:
# pkg-config, else the version macros of its header.
host_version() { "$OCAML_EMCC_EXE" internal host-version "$@"; }

# Keep the versions (first word of each line) compatible with <want>.
version_match() { "$OCAML_EMCC_EXE" internal version-match "$1"; }

# ------------------------------------------------------- system libraries
#
# SOURCE=system:<name> is for C libraries that opam packages take from the
# system (conf-<name>).  The recipe only describes the library:
#   HEADER=mpfr.h  VERSION_MACROS="MAJOR MINOR PATCH macros"   host version
#   PKGCONFIG      pkg-config name (default: <name>), tried first
#   RELEASES       upstream directory listing the <TARBALL>-<ver>.tar.* files
#   TARBALL        tarball prefix (default: <name>)
#   COMPAT         which upstream versions can replace the host's:
#                  major (default), minor, exact, latest
#   OPAM_SOURCES   opam package vendoring the upstream sources (optional)
#   LINK           flags a user of the library needs (default: -l<name>);
#                  those of the DEPENDS recipes are appended
#   releases()     optional function replacing RELEASES: prints a
#                  "<version> <tarball url>" line per release, oldest first
#                  (git_tag_releases helps for releases named after git tags)
# Choice (Source.system): the sources of OPAM_SOURCES if the switch has it
# installed (that is what the project links natively).  Otherwise the newest
# upstream release compatible with the host's version (any version without a
# host library), fetched through opam when opam knows it (checksum verified).

# git_tag_releases <repo> <tag prefix> <url template>: "<version> <url>" for
# each tag <prefix><version> of <repo> (final versions only), {v} in the
# template standing for the version.
git_tag_releases() {
  local repo=$1 prefix=$2 template=$3 v
  git ls-remote --tags --refs "$repo" 2>/dev/null | sed -n "s|.*refs/tags/$prefix||p" \
    | grep -E '^[0-9]+(\.[0-9]+)+$' | sort -V \
    | while read -r v; do echo "$v ${template//\{v\}/$v}"; done
}

# Flags for users of system recipe <name> (meta/<name>.uselink), and the C
# flags their stubs need besides the sysroot's include directory
# (USE_CFLAGS, meta/<name>.usecflags; sdl2's -I.../include/SDL2).
record_use_flags() {
  local name=$1 d flags=${LINK:--l$1}
  echo "${USE_CFLAGS:-}" > "$SYSROOT/meta/$name.usecflags"
  for d in $DEPENDS; do
    if [ -f "$SYSROOT/meta/$d.uselink" ]; then flags="$flags $(cat "$SYSROOT/meta/$d.uselink")"
    else flags="$flags -l$d"; fi
  done
  echo "$flags" > "$SYSROOT/meta/$name.uselink"
  # and, for each library of the recipe, what it needs besides itself (for
  # programs naming it in their c_library_flags: -lffi)
  local p l
  for p in "$SYSROOT"/meta/*.provider; do
    [ "$(cat "$p")" = "$name" ] || continue
    l=$(basename "$p" .provider)
    [ -f "$SYSROOT/meta/$l.link" ] && continue
    # shellcheck disable=SC2086
    printf '%s\n' $flags | { grep -vx -- "-l$l" || true; } | paste -sd' ' - > "$SYSROOT/meta/$l.link"
  done
}

# ----------------------------------------------------------------- helpers

# apply_patches <dir>: apply <dir>/*.patch in order.  Their hunks are placed
# by their text, not their line numbers (tools/patch.awk): `@@` lines need
# no numbers, and the context lines only have to tell the place apart.
apply_patches() {
  local p out
  [ -d "$1" ] || return 0
  for p in "$1"/*.patch; do
    [ -f "$p" ] || continue
    out=$(awk -f "$OCAML_EMCC_SHARE/tools/patch.awk" "$p") || die "patch $p failed"
    log "patch $(basename "$p")${out:+ ($out)}"
  done
}

# make_var <dir> <variable>: value of a variable of <dir>/Makefile
make_var() {
  printf '__ocaml_emcc_var:\n\t@echo $(%s)\n' "$2" \
    | make -s --no-print-directory -C "$1" -f Makefile -f - __ocaml_emcc_var
}

# mklib <name> <objects...>: archive objects into lib<name>.a
mklib() { local n=$1; shift; rm -f "lib$n.a"; "$EMAR" rcs "lib$n.a" "$@"; }

# stub_cc <src.c> [flags...]: compile one stub file against the wasm runtime
stub_cc() { local f=$1; shift; "$EMCC" $STUB_CFLAGS "$@" -c "$f" -o "${f%.c}.o"; }

install_lib() { local f; for f in "$@"; do cp -f "$f" "$SYSROOT/lib/"; done; }

install_headers() { # install_headers <subdir|.> <files...>
  local d=$SYSROOT/include/$1; shift; mkdir -p "$d"; cp -f "$@" "$d/"
}

# link_flags <libname> <flags>: extra flags needed when lib<libname>.a is
# linked (e.g. zarith needs -lgmp).  Read back by `ocaml-emcc link`.
link_flags() { echo "$2" > "$SYSROOT/meta/$1.link"; }

# install_pc <name> <version> <libs> [<cflags>]: write lib/pkgconfig/<name>.pc,
# for libraries built without their own build system (pkg-config users, such
# as dune-configurator scripts, then find the wasm library).
install_pc() {
  mkdir -p "$SYSROOT/lib/pkgconfig"
  cat > "$SYSROOT/lib/pkgconfig/$1.pc" <<PC
prefix=$SYSROOT
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: $1
Description: $1 (ocaml-emcc, $TARGET)
Version: $2
Libs: -L\${libdir} $3
Cflags: -I\${includedir} ${4:-}
PC
}

# provides <recipe> <libname>...: record which recipe builds which library,
# so that `ocaml-emcc deps` knows how to obtain a missing lib<name>.a.
provides() { local r=$1 l; shift; for l in "$@"; do echo "$r" > "$SYSROOT/meta/$l.provider"; done; }

find_recipe() {
  local IFS=: d
  for d in $RECIPES_PATH; do
    [ -f "$d/$1/recipe.sh" ] && { echo "$d/$1"; return 0; }
  done
  return 1
}

# include_recipe <name>: in a recipe, read the recipe <name>; for the recipe's
# own name, the next one down the recipe path.  A project recipe can thus
# refine a builtin one:
#   LLVM_VERSION=9.0.1; include_recipe clang
# BASE_RECIPE_DIR is the directory of the included recipe.
include_recipe() {
  local IFS=: d seen=no found=
  if [ "$1" != "$RECIPE_NAME" ]; then found=$(find_recipe "$1") || die "include_recipe: no recipe $1"
  else
    for d in $RECIPES_PATH; do
      if [ $seen = yes ] && [ -f "$d/$1/recipe.sh" ]; then found=$d/$1; break; fi
      [ "$d/$1" = "$RECIPE_DIR" ] && seen=yes
    done
    [ -n "$found" ] || die "include_recipe $1: no other recipe named $1 after $RECIPE_DIR"
  fi
  BASE_RECIPE_DIR=$found
  # shellcheck disable=SC1091
  . "$found/recipe.sh"
}

# --------------------------------------------------------------- toolchain

# write_toolchain: the wrapper scripts and the findlib toolchain of the
# sysroot (Wrappers), for the ocaml recipe once the runtime is built.
write_toolchain() { "$OCAML_EMCC_EXE" internal toolchain; }

# ----------------------------------------------------------------- recipes

# The variables a recipe may set, and the functions it may define.
RECIPE_VARS="SOURCE SHA256 REF DEPENDS HEADER VERSION_MACROS PKGCONFIG RELEASES TARBALL COMPAT OPAM_SOURCES LINK LIB_PATTERNS USE_CFLAGS"

# load_recipe <name>: read the recipe in the current shell
load_recipe() {
  local dir v
  dir=$(find_recipe "$1") || die "no recipe named '$1'"
  for v in $RECIPE_VARS; do eval "$v="; done
  SOURCE=none
  RECIPE_DIR=$dir RECIPE_NAME=$1 BASE_RECIPE_DIR=$dir
  unset -f pre_build fetch releases
  # shellcheck disable=SC1091
  . "$dir/recipe.sh"
}

# describe <name>: the variables of the recipe, and the optional functions it
# defines (FUNCTIONS), NAME=value NUL-terminated
describe_recipe() {
  ( load_recipe "$1"
    local v f fns=
    for v in $RECIPE_VARS; do printf '%s=%s\0' "$v" "${!v}"; done
    for f in fetch releases pre_build; do declare -F $f >/dev/null && fns="$fns $f"; done
    printf 'FUNCTIONS=%s\0' "${fns# }" )
}

# build_recipe <name> <result> [<version>]: build and install the recipe,
# its dependencies built and its sources in $SYSROOT/build/<name> (of that
# version), unless it fetches them itself (SOURCE=fetch); writes the version
# of its sources and emcc's in <result>, for its stamp.
build_recipe() {
  local name=$1 result=$2
  (
    load_recipe "$name"
    local work=$SYSROOT/build/$name
    case "$SOURCE" in
      fetch) rm -rf "$work"; SOURCE_VERSION=; fetch "$work" ;;
      *) SOURCE_VERSION=${3-} ;;
    esac
    log "building $name ${SOURCE_VERSION:-}"
    cd "$work"
    # pre_build: a hook for project recipes refining a builtin one
    if declare -F pre_build >/dev/null; then pre_build; fi
    build
    # a C library: system:, or another source with LINK (sdl2)
    case "$SOURCE" in system:*) record_use_flags "$name" ;; *) [ -z "$LINK" ] || record_use_flags "$name" ;; esac
    printf '%s\n%s\n' "${SOURCE_VERSION:-}" "$EMCC_VERSION" > "$result"
    log "installed $name"
  )
}

# releases <name>: the output of the recipe's `releases` function
releases_of() { ( load_recipe "$1"; releases ) }

# dune_stubs <opam-package> [<provider>]: in the sources of a dune package
# (the current directory), build its stub archives with `dune build -x` and
# install them (Stubs.dune_stubs).  For recipes that patch a package before
# (`SOURCE=opam:PKG`, see mirage-crypto).
dune_stubs() { "$OCAML_EMCC_EXE" internal dune-stubs "$1" "${2:-$RECIPE_NAME}"; }

cmd=${1:-}; shift || true
case "$cmd" in
  describe)     describe_recipe "$1" ;;
  build)        build_recipe "$@" ;;
  releases)     releases_of "$1" ;;
  *) die "usage: driver.sh describe|build|releases ..." ;;
esac
