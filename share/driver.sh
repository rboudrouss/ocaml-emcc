#!/usr/bin/env bash
# Recipe driver for ocaml-emcc.
#
#   driver.sh describe <recipe>             the variables of a recipe
#   driver.sh build <recipe> <result> [<version>]
#                                            build + install a recipe, its
#                                            dependencies built and its
#                                            sources fetched
#   driver.sh releases <recipe>             its `releases` function
#   driver.sh toolchain                     the toolchain's wrapper scripts
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

# Wrapper scripts with the paths baked in, plus the findlib toolchain that
# makes `dune build -x wasm32` work.
# Bumped whenever write_toolchain changes: the CLI then regenerates it in
# existing sysroots (cheap: the runtime is not rebuilt).  Keep in sync with
# Env.toolchain_version.
TOOLCHAIN_VERSION=10

write_toolchain() {
  local tool host_conf cc=$SYSROOT/bin/emcc-$TARGET
  # The C compiler dune is given: emcc with the target (and stub standard)
  # flags built in.  Some packages replace dune's :standard C flags with
  # their own (mlmpfr's (flags (:include c_flags.sexp))), which would drop
  # -m64 and friends.
  # -pthread (lwt's configuration adds it) is dropped: the program is
  # single-threaded, and with it emcc compiles `caml_state` as a real
  # thread-local variable, which the runtime's is not (see the ocaml recipe).
  # The headers and libraries of the sysroot come last (after the package's
  # own): dune-configurator's C tests only get the C flags, not -I.  Those
  # of the host in CPATH and friends would come before them (the host's
  # ffi.h for ctypes-foreign): the environment loses them.
  # The C standard is left out for C++ (snappy's stubs: -x c++), which
  # clang refuses with -std=gnu23.
  # An executable (-o X.exe, or without extension) is a program the build
  # runs: ctypes' type generators print the layouts of the target's structs.
  # It becomes a node script (the wasm inside, real files) dune can run,
  # with the node of emscripten's configuration (memory64 for wasm64): the
  # one in PATH can be older.
  local node
  node=$("$EMSDK_BIN/em-config" NODE_JS 2>/dev/null | sed -e "s/^\['//" -e "s/'.*//")
  cat > "$cc" <<EOF
#!/bin/sh
unset CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH LIBRARY_PATH
link=-L'$SYSROOT/lib' std='$STUB_STD' prev= exe=
for a; do
  shift
  case \$a in -c|-E|-S|-M|-MM) link= ;; -xc++*|*.cc|*.cpp|*.cxx|*.C) std= ;; esac
  case \$prev\$a in -xc++*) std= ;; esac
  [ "\$prev" = -o ] && case \${a##*/} in *.exe) exe=1 ;; *.*) exe= ;; *) exe=1 ;; esac
  prev=\$a
  [ "\$a" = -pthread ] || set -- "\$@" "\$a"
done
[ -n "\$link" ] && [ -n "\$exe" ] && set -- "\$@" -sEXECUTABLE='${node:-1}' -sSINGLE_FILE=1 -sEXIT_RUNTIME=1 -sNODERAWFS=1
exec '$EMCC' $TARGET_FLAGS \$std -idirafter '$SYSROOT/include' \$link "\$@"
EOF
  chmod +x "$cc"
  for tool in ocamlc ocamlmklib; do
    cat > "$SYSROOT/bin/$tool" <<EOF
#!/bin/sh
OCAML_EMCC_HOST_BIN='$HOST_BIN'
OCAML_EMCC_SYSROOT='$SYSROOT'
OCAML_EMCC_CFLAGS='$BASE_CFLAGS'
OCAML_EMCC_EMCC='$cc'
EMAR='$EMAR'
PATH='$EMSDK_BIN':\$PATH
export OCAML_EMCC_HOST_BIN OCAML_EMCC_SYSROOT OCAML_EMCC_CFLAGS OCAML_EMCC_EMCC EMAR PATH
exec sh '$OCAML_EMCC_SHARE/tools/$tool' "\$@"
EOF
    chmod +x "$SYSROOT/bin/$tool"
  done
  # The other tools dune looks for next to the toolchain's ocamlc (rules
  # using %{ocaml}, %{bin:ocamllex}...) are the host's.  Not ocamlopt: see
  # below.
  for tool in ocaml ocamllex ocamlyacc ocamlobjinfo ocamlcp ocamlmktop ocamlprof; do
    if [ -x "$HOST_BIN/$tool" ]; then ln -sf "$HOST_BIN/$tool" "$SYSROOT/bin/$tool"; fi
  done
  # put first in dune's PATH: rules running `ocamlmklib` directly
  mkdir -p "$SYSROOT/bin/path"
  ln -sf ../ocamlmklib "$SYSROOT/bin/path/ocamlmklib"
  ln -sf ../ocamlmklib "$SYSROOT/bin/path/ocamlmklib.opt"
  # and pkg-config (dune-configurator): the rules of the wasm context only
  # see the wasm libraries of the sysroot, not the host's (lmdb would take
  # the host's liblmdb instead of its own copy).  Those of the host context
  # get the host's pkg-config.
  local pc
  for pc in pkg-config pkgconf; do
    cat > "$SYSROOT/bin/path/$pc" <<EOF
#!/bin/sh
case \$PWD/ in
  */default.$TARGET/*) # also in dune's sandboxes (_build/.sandbox/<hash>/)
    PKG_CONFIG_LIBDIR='$SYSROOT/lib/pkgconfig' PKG_CONFIG_PATH=
    export PKG_CONFIG_LIBDIR PKG_CONFIG_PATH ;;
esac
self='$SYSROOT/bin/path' IFS=:
for d in \$PATH; do
  [ "\$d" = "\$self" ] && continue
  [ -x "\$d/$pc" ] && exec "\$d/$pc" "\$@"
done
echo "$pc: not found" >&2; exit 127
EOF
    chmod +x "$SYSROOT/bin/path/$pc"
  done
  # and llvm-config, for the same reason: dune rules running it (a package
  # configured on the host) get the wasm LLVM of the clang recipe in the
  # wasm context.  clang too, but only for what the recipe's clang
  # answers (-print-resource-dir, --version): it compiles nothing.
  local tool_name
  for tool_name in llvm-config clang; do
    cat > "$SYSROOT/bin/path/$tool_name" <<EOF
#!/bin/sh
case \$PWD/ in
  */default.$TARGET/*)
    if [ -x '$SYSROOT/bin/$tool_name' ]; then
      case $tool_name:\$1 in llvm-config:*|clang:-print-resource-dir|clang:--version) exec '$SYSROOT/bin/$tool_name' "\$@" ;; esac
    elif [ $tool_name = llvm-config ]; then
      echo "llvm-config: no wasm LLVM for $TARGET yet, build it with: ocaml-emcc install clang" >&2; exit 1
    fi ;;
esac
self='$SYSROOT/bin/path' IFS=:
for d in \$PATH; do
  [ "\$d" = "\$self" ] && continue
  [ -x "\$d/$tool_name" ] && exec "\$d/$tool_name" "\$@"
done
echo "$tool_name: not found" >&2; exit 127
EOF
    chmod +x "$SYSROOT/bin/path/$tool_name"
  done
  local findlib_path
  host_conf=$("$HOST_BIN/ocamlfind" printconf conf 2>/dev/null || echo "$PREFIX/lib/findlib.conf")
  findlib_path=$("$HOST_BIN/ocamlfind" printconf path 2>/dev/null | paste -sd: - || true)
  [ -n "$findlib_path" ] || findlib_path="$PREFIX/lib"
  mkdir -p "$SYSROOT/findlib.conf.d"
  if [ -f "$host_conf" ]; then
    # destdir and path may be relative to the file (destdir=".", path="./ocaml:."
    # since ocamlfind 1.9.9): the copy gets absolute ones
    sed -e "s|^destdir *=.*|destdir=\"$("$HOST_BIN/ocamlfind" printconf destdir 2>/dev/null || echo "$PREFIX/lib")\"|" \
        -e "s|^path *=.*|path=\"$findlib_path\"|" "$host_conf" > "$SYSROOT/findlib.conf"
  else # switch without ocamlfind
    printf 'destdir="%s"\npath="%s"\n' "$PREFIX/lib" "$findlib_path" > "$SYSROOT/findlib.conf"
  fi
  # dune reads tools of the host context from this file too, and a variable
  # only defined for a predicate (ocamlmklib(wasm64)) reads as "" there.
  for tool in ocamlc ocamlmklib ocamldep ocamldoc; do
    grep -q "^$tool *=" "$SYSROOT/findlib.conf" || echo "$tool=\"$tool\"" >> "$SYSROOT/findlib.conf"
  done
  # No ocamlopt entry at all: dune then looks for it next to the toolchain's
  # ocamlc ($SYSROOT/bin), finds nothing and treats the wasm context as
  # bytecode-only (there is no native wasm backend).  The host context finds
  # it next to the host ocamlc as usual.
  sed -i '/^ocamlopt *=/d' "$SYSROOT/findlib.conf"
  local t=$TARGET
  cat > "$SYSROOT/findlib.conf.d/$t.conf" <<EOF
path($t) = "$SYSROOT/lib/findlib:$findlib_path"
destdir($t) = "$SYSROOT/lib/findlib"
stdlib($t) = "$("$HOST_BIN/ocamlc" -where)"
ocamlc($t) = "$SYSROOT/bin/ocamlc"
ocamlmklib($t) = "$SYSROOT/bin/ocamlmklib"
ocamldep($t) = "$HOST_BIN/ocamldep"
ocamldoc($t) = "$HOST_BIN/ocamldoc"
EOF
  mkdir -p "$SYSROOT/lib/findlib"
  cat > "$SYSROOT/manifest" <<EOF
toolchain=$TOOLCHAIN_VERSION
ocaml_version=$OCAML_VERSION
target=$TARGET
cflags=$BASE_CFLAGS
ldflags=$LDFLAGS
emcc_version=$EMCC_VERSION
emcc=$EMCC
host_bin=$HOST_BIN
EOF
}

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
  toolchain)    write_toolchain ;;
  *) die "usage: driver.sh describe|build|releases|toolchain ..." ;;
esac
