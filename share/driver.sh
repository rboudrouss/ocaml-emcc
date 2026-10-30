#!/usr/bin/env bash
# Recipe driver for ocaml-emcc.
#
#   driver.sh describe <recipe>             the variables of a recipe
#   driver.sh build <recipe> <result> [<version>]
#                                            build + install a recipe, its
#                                            dependencies built and its
#                                            sources fetched
#   driver.sh releases <recipe>             its `releases` function
#   driver.sh install-dune [--force] <opam-package>
#                                            rebuild the C stubs of a dune
#                                            package with the wasm32 toolchain
#   driver.sh shadow [--force] <opam-package>...
#                                            its OCaml libraries built for the
#                                            target (ctypes: C layouts)
#   driver.sh patched-dune                   path of a dune building the
#                                            (ctypes) stanza for the target
#   driver.sh auto [--force] <opam-package> <lib-name>
#                                            compile every OCaml stub file of
#                                            a package into lib<lib-name>.a
#
# Environment (set by the `ocaml-emcc` CLI):
#   OCAML_EMCC_SHARE         share directory (recipes/, tools/, runtime/)
#   OCAML_EMCC_SWITCH_PREFIX opam switch prefix providing the host compiler
#   OCAML_EMCC_SYSROOT       where wasm artifacts are installed
#   OCAML_EMCC_TARGET        wasm32 (default) or wasm64
#   OCAML_EMCC_OPT           optimisation flag for C code (default -O2)
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

: "${OCAML_EMCC_SHARE:?}" "${OCAML_EMCC_SWITCH_PREFIX:?}" "${OCAML_EMCC_SYSROOT:?}" "${OCAML_EMCC_EXE:?}"

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

# Target.  wasm32 runs the host's 64-bit bytecode with 31-bit ints; wasm64
# (memory64) matches its semantics exactly (see README).
TARGET=${OCAML_EMCC_TARGET:-wasm32}
case "$TARGET" in
  wasm64) TARGET_FLAGS="-m64" ;;
  wasm32) TARGET_FLAGS="" ;;
  *) echo "ocaml-emcc: unknown target $TARGET" >&2; exit 1 ;;
esac
# Every piece of C code (runtime, stubs, C libraries) must agree on these.
#  -fno-strict-overflow  pointer arithmetic may wrap: stops LLVM from folding
#                        negative offsets (Tag_val, Hd_val: p[-8]) into the
#                        unsigned offset of wasm64 loads, which traps.
#  -sSUPPORT_LONGJMP=wasm  OCaml raises exceptions from C with longjmp; the
#                        wasm EH implementation avoids routing every call made
#                        by the interpreter through JS invoke_* trampolines.
#  -fwasm-exceptions     C++ exceptions with the same wasm EH instructions
#                        (minisat); emscripten's JS ones cannot be thrown
#                        with SUPPORT_LONGJMP=wasm.  No effect on C code.
TARGET_FLAGS="$TARGET_FLAGS -fno-strict-overflow -sSUPPORT_LONGJMP=wasm -fwasm-exceptions"
OPT=${OCAML_EMCC_OPT:--O2}
# BASE_CFLAGS is what the toolchain wrappers and the link step record; extra
# flags are added on top at each use (recipes here, stubs in tools/ocamlc).
BASE_CFLAGS="$OPT -fno-strict-aliasing -fwrapv $TARGET_FLAGS"
export CFLAGS="$BASE_CFLAGS ${OCAML_EMCC_EXTRA_CFLAGS:-}"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="$TARGET_FLAGS"
# The C standard of the host compiler, when newer than emcc's default
# (gnu17): stub sources generated at build time follow it (ctypes writes
# `bool`, a keyword only since C23, the default of gcc >= 15).
host_c_std() {
  local cc v
  cc=$("$HOST_BIN/ocamlc" -config-var c_compiler 2>/dev/null) || cc=cc
  # shellcheck disable=SC2086
  v=$(printf '__STDC_VERSION__\n' | $cc -x c -E -P - 2>/dev/null | tr -dc 0-9)
  if [ "${v:-0}" -ge 202311 ]; then echo -std=gnu23; fi
}
STUB_STD=$(host_c_std)
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

# Installed version of an opam package in the switch.
opam_pkg_version() {
  local d
  for d in "$PREFIX/.opam-switch/packages/$1".*; do
    [ -d "$d" ] && { basename "$d" | sed "s/^$1\.//"; return 0; }
  done
  return 1
}

# ----------------------------------------------------------------- sources
#
# The sources of a recipe are fetched by the CLI (Source), before `build`.
# These helpers, for recipes and the code below, run it.

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

# The system libraries <pkg> uses for which a recipe exists (Syslib.recipes)
system_recipes_of() { "$OCAML_EMCC_EXE" internal system-recipes "$1"; }

# The C flags of the system recipes <pkg> uses (once built).
system_cflags() {
  local r
  for r in $(system_recipes_of "$1"); do cat "$SYSROOT/meta/$r.usecflags" 2>/dev/null || true; done | paste -sd' ' -
}

# Build the system recipes <pkg> needs; prints the link flags they require.
system_deps() {
  local r flags=
  for r in $(system_recipes_of "$1"); do
    log "$1 uses the system library $r: building the $r recipe"
    run_recipe "$r" >&2 || die "$1: the $r recipe failed"
    flags="$flags $(cat "$SYSROOT/meta/$r.uselink" 2>/dev/null)"
  done
  echo "$flags"
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

FORCE=no

# run_recipe <name>: build the recipe unless its stamp says it is built
# (Recipe.install).  Its dependencies are built first.
run_recipe() {
  local force=
  [ "$FORCE" = no ] || force=--force
  # shellcheck disable=SC2086
  "$OCAML_EMCC_EXE" internal install $force "$1"
}

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

# Rebuild a dune package's foreign stubs with `dune build -x wasm32`.
run_dune_package() {
  local pkg=$1 stamp=$SYSROOT/stamps/dune-$1 work=$SYSROOT/build/dune-$1
  if [ "$FORCE" = no ] && [ -f "$stamp" ] && [ "$(cut -d' ' -f1 "$stamp")" = "$(opam_pkg_version "$pkg")" ]; then return 0; fi
  rm -rf "$work"
  fetch_opam_source "$pkg" "$work"
  ( cd "$work" && dune_stubs "$pkg" "dune-$pkg" ) || die "$pkg: no C archive built"
  echo "$SOURCE_VERSION emcc-$EMCC_VERSION" > "$stamp"
}

# patched_dune: a dune whose (ctypes) stanza links its generators as custom
# bytecode in a context without ocamlopt, as dune does for ppx drivers and
# cinaps (tools/dune/*.patch); the stock one links them natively only
# (ocaml/dune#13650), which the target's toolchain cannot.  Built from the
# sources of the switch's dune, once per version and patch; prints its path.
patched_dune() {
  local ver sum bin=$SYSROOT/libexec/dune stamp=$SYSROOT/stamps/patched-dune work=$SYSROOT/build/patched-dune
  ver=$(opam_pkg_version dune) || die "dune is not installed in $PREFIX"
  sum=$(cat "$OCAML_EMCC_SHARE"/tools/dune/*.patch | sha256sum | cut -c1-16)
  if [ -x "$bin" ] && [ "$(cat "$stamp" 2>/dev/null)" = "$ver patch=$sum" ]; then echo "$bin"; return 0; fi
  rm -rf "$work"
  fetch_opam_source dune "$work"
  log "building dune $ver, its (ctypes) stanza patched for the target's toolchain"
  ( cd "$work" && rm -rf _build _boot && apply_patches "$OCAML_EMCC_SHARE/tools/dune" \
      && PATH=$HOST_BIN:$PATH make release > build.log 2>&1 ) \
    || { tail -n 20 "$work/build.log" >&2 2>/dev/null; die "could not build the patched dune (log: $work/build.log)"; }
  mkdir -p "$(dirname "$bin")"
  cp "$work/_build/install/default/bin/dune" "$bin"
  echo "$ver patch=$sum" > "$stamp"
  rm -rf "$work"
  echo "$bin"
}

# dune_for <dir>: the dune that builds the package in <dir>, patched_dune's
# if it uses the (ctypes) stanza.
dune_for() {
  if grep -rqE '\(using[[:space:]]+ctypes' --include=dune-project --exclude-dir='_build*' "$1"; then patched_dune
  else echo "$HOST_BIN/dune"; fi
}

# shadow <opam-package>: the OCaml libraries of a package, built for the
# target and installed in $SYSROOT/lib/findlib, which the toolchain searches
# before the switch.  For ctypes and its users: ctypes lays C types out with
# the sizes it generated when it was built (ctypes_primitives.ml), and
# bindings generating their type descriptions (Cstubs_structs, dune's
# (ctypes) stanza) print the offsets of the structs from a C program: on the
# host, those of LP64.  The build has a single context on the target's
# toolchain, without the host context of `dune -x`, whose executables dune
# would run instead: OCaml generators are bytecode run by the host ocamlrun
# (with the host's stub DLLs), C ones are compiled by emcc and run by node
# (see write_toolchain), dune-configurator gets the target's answers.
# The stamp records the package version and the outcome: ok (installed),
# failed (it lays C types out when built, and could not be rebuilt), none
# (it does not: the host's build is kept).  Rebuilt when the package
# changes version.
run_shadow() {
  local pkg=$1 stamp=$SYSROOT/stamps/shadow-$1 work=$SYSROOT/build/shadow-$1 dirs=$SYSROOT/meta/shadow-$1.dirs
  local ver status layouts=no d dune
  ver=$(opam_pkg_version "$pkg") || die "$pkg is not installed in $PREFIX"
  if [ "$FORCE" = no ] && [ -f "$stamp" ] && [ "$(cut -d' ' -f1 "$stamp")" = "$ver" ]; then return 0; fi
  # the libraries of the previous version
  if [ -f "$dirs" ]; then
    while IFS= read -r d; do [ -n "$d" ] && rm -rf "${SYSROOT:?}/lib/findlib/$d"; done < "$dirs"
    rm -f "$dirs"
  fi
  rm -rf "$work"
  fetch_opam_source "$pkg" "$work"
  # generated type descriptions, with structs or unions (`seal`): zstd's
  # only have constants
  if grep -rqE 'Cstubs_structs|Cstubs\.Types|type_description' --include='*.ml' --include=dune --exclude-dir='_build*' "$work" 2>/dev/null \
     && grep -rqw seal --include='*.ml' --exclude-dir='_build*' "$work" 2>/dev/null; then
    layouts=yes
  fi
  status=none; [ $layouts = yes ] && status=failed
  if [ -f "$work/dune-project" ]; then
    dune=$(dune_for "$work")
    FORCE=no system_deps "$pkg" >/dev/null
    log "building the OCaml libraries of $pkg for $TARGET (C layouts of $TARGET)"
    printf '(lang dune 3.0)\n(context (default (name default.%s) (toolchain %s)))\n' "$TARGET" "$TARGET" > "$work/.ocaml-emcc-workspace"
    if ( cd "$work" && PATH=$SYSROOT/bin/path:$PATH OCAMLFIND_CONF=$SYSROOT/findlib.conf \
           CAML_LD_LIBRARY_PATH=$PREFIX/lib/stublibs:$PREFIX/lib/ocaml/stublibs \
           "$dune" build --build-dir _build.ocaml-emcc --workspace .ocaml-emcc-workspace \
             -p "$pkg" @install > ocaml-emcc-build.log 2>&1 ) \
       && find "$work/_build.ocaml-emcc/install/default.$TARGET/lib" -name '*.cmi' -print -quit | grep -q .; then
      mkdir -p "$SYSROOT/lib/findlib"
      for d in "$work/_build.ocaml-emcc/install/default.$TARGET/lib"/*; do
        # (dune -p of a package that another build system builds installs
        # an empty library: hacl-star-raw, built by make next to hacl-star)
        [ -d "$d" ] && [ "$(basename "$d")" != stublibs ] || continue
        find "$d" -name '*.cmi' -print -quit | grep -q . || continue
        rm -rf "$SYSROOT/lib/findlib/$(basename "$d")"
        cp -rL "$d" "$SYSROOT/lib/findlib/"
        basename "$d" >> "$dirs"
        log "  $SYSROOT/lib/findlib/$(basename "$d")"
      done
      status=ok
    elif [ $layouts = yes ]; then
      tail -n 30 "$work/ocaml-emcc-build.log" >&2
      log "$pkg: could not be built for $TARGET (log: $work/ocaml-emcc-build.log)"
    else
      log "  not built for $TARGET, which it does not need: no structs in its generated types"
    fi
  fi
  echo "$ver $status emcc-$EMCC_VERSION" > "$stamp"
}

# dune_stubs <opam-package> [<provider>]: in the sources of a dune package
# (the current directory), build its stub archives with `dune build -x` and
# install them, with the link flags of the system libraries it uses.  Also
# for recipes that patch a package before (`SOURCE=opam:PKG`, see
# mirage-crypto).
dune_stubs() {
  local pkg=$1 provider=${2:-$RECIPE_NAME}
  [ -f "$SYSROOT/findlib.conf.d/$TARGET.conf" ] || run_recipe ocaml
  local sysflags
  sysflags=$(system_deps "$pkg")
  log "building the C stubs of $pkg with dune -x $TARGET"
  # The kept _build may be another tool's (lmdb is built with ocamlbuild,
  # whose _build/install is a file): dune gets its own then.
  DUNE_BDIR=_build
  if [ -e _build ] && ! [ -d _build/default ] && ! [ -e _build/.lock ]; then DUNE_BDIR=_build.dune; fi
  local a l found=no archives dune
  dune=$(dune_for .)
  if PATH=$SYSROOT/bin/path:$PATH OCAMLFIND_CONF=$SYSROOT/findlib.conf \
       "$dune" build --build-dir "$DUNE_BDIR" -x "$TARGET" -p "$pkg" @install >&2; then
    archives=$(find "$DUNE_BDIR/default.$TARGET" -name 'lib*.a' ! -path '*/.*')
    # Archives made by a rule of the package with its own build system
    # (ocaml-lua: `make` in the vendored Lua) hold host objects.  Those of
    # stubs (with their dllX.so) are rebuilt, the others were intermediate.
    local host= wasm= b
    while IFS= read -r a; do
      [ -n "$a" ] || continue
      if wasm_archive "$a"; then wasm="$wasm$a"$'\n'; continue; fi
      b=$(basename "$a" .a)
      if [ -f "$(dirname "$a")/dll${b#lib}.so" ]; then host="$host $b.a"
      else log "  $b.a: host objects, not a stub archive: ignored"; fi
    done <<< "$archives"
    archives=$wasm
    if [ -n "$host" ]; then
      log "host objects in${host}: compiling the C files of the native build instead"
      # shellcheck disable=SC2086
      archives="$archives$(dune_native_stubs "$pkg" $host)"
    fi
  else
    log "dune -x $TARGET failed: compiling the C files of the native build instead"
    archives=$(dune_native_stubs "$pkg")
  fi
  while IFS= read -r a; do
    [ -n "$a" ] || continue
    l=$(basename "$a" .a | sed 's/^lib//')
    install_lib "$a"; provides "$provider" "$l"; found=yes
    [ -z "${sysflags// }" ] || link_flags "$l" "${sysflags# }"
    log "  $(basename "$a")"
  done <<< "$archives"
  [ $found = yes ] || { log "  (no C archive produced)"; return 1; }
}

# Fallback of run_dune_package, for what dune cannot cross-compile, and for
# the archives of `dune -x` holding host objects (see dune_stubs).  Each
# stub archive of the native build ($DUNE_BDIR/default, see dune_stubs; kept
# by OPAMKEEPBUILDDIR, else built here) is rebuilt with emcc from the C
# files behind its members: hand-written stubs, vendored C, and the C that
# ctypes generated (architecture independent).  The stubs' own C flags are
# not known: only -I flags are given (the file's directory and its source
# directory, the headers of the opam packages it depends on, those of the
# system recipes).
#   dune_native_stubs <pkg> [<libX.a>...]   (default: every archive)
# Prints the wasm archives.
dune_native_stubs() {
  local pkg=$1 nat=${DUNE_BDIR:-_build}/default ver a dir m c incs= dep objs only
  shift; only=" $* "
  # (dune -x also makes _build/default, with only what the target needs)
  local missing=no x
  [ -d "$nat" ] || missing=yes
  for x in "$@"; do [ -n "$(find "$nat" -name "$x" 2>/dev/null | head -1)" ] || missing=yes; done
  if [ $# -eq 0 ] && [ -z "$(find "$nat" -name 'lib*.a' 2>/dev/null | head -1)" ]; then missing=yes; fi
  if [ $missing = yes ]; then
    log "no native build kept for $pkg: building it"
    "$HOST_BIN/dune" build --build-dir "${DUNE_BDIR:-_build}" -p "$pkg" @install >&2 || die "$pkg: native build failed"
  fi
  ver=$(opam_pkg_version "$pkg")
  for dep in $(grep -oE '"[a-z0-9_-]+"' "$PREFIX/.opam-switch/packages/$pkg.$ver/opam" 2>/dev/null | tr -d '"' | sort -u); do
    [ "$dep" != ocaml ] && compgen -G "$PREFIX/lib/$dep/*.h" >/dev/null && incs="$incs -I$PREFIX/lib/$dep"
  done
  incs="$incs $(system_cflags "$pkg")"
  mkdir -p _wasm_stubs
  while IFS= read -r a; do
    [ "$only" = "  " ] || [[ "$only" == *" $(basename "$a") "* ]] || continue
    dir=$(dirname "$a"); objs=()
    for m in $(ar t "$a"); do
      c=$dir/${m%.o}.c
      # (include_subdirs): the sources are in subdirectories
      [ -f "$c" ] || c=$(find "$dir" -name "${m%.o}.c" ! -path '*/.*' | head -1)
      [ -f "$c" ] || die "$pkg: no C source for $m (in $a)"
      # shellcheck disable=SC2086
      stub_cc "$c" -I"$(dirname "$c")" -I"$dir" -I"${dir#"$nat"/}" $incs >&2 || die "$pkg: cannot compile $c"
      objs+=("$PWD/${c%.c}.o")
    done
    ( cd _wasm_stubs && mklib "$(basename "$a" .a | sed 's/^lib//')" "${objs[@]}" )
    echo "_wasm_stubs/$(basename "$a")"
  done < <(find "$nat" -name 'lib*.a' ! -path '*/.*')
}

# wasm_archive <lib.a>: whether its (first) object is a wasm one.
wasm_archive() {
  local m
  # (sed reads all of it: ar killed by SIGPIPE would fail the pipeline)
  m=$(ar t "$1" 2>/dev/null | grep '\.o$' | sed -n 1p) || return 0
  [ "$(ar p "$1" "$m" | head -c 4 | od -An -tx1 | tr -d ' \n')" = 0061736d ]
}

# Last resort for packages with neither a recipe nor dune.  If the kept
# native build has lib<libname>.a, the C files behind its members are
# compiled (glpk: with oldapi/lpx.c, which does not include the OCaml
# headers); otherwise every C file that includes the OCaml headers.
# dep_includes <pkg>: -I flags for the lib/<dep> directories of the
# installed opam dependencies of <pkg>, where packages install the C
# headers of their stubs (integers: ocaml_integers.h, which ctypes's
# include).
dep_includes() {
  local ver d
  ver=$(opam_pkg_version "$1") || return 0
  for d in $(awk '/^depends: \[/ { on = 1; next } on && /^\]/ { exit }
                  on { while (match($0, /"[^"]+"/)) { print substr($0, RSTART + 1, RLENGTH - 2); $0 = substr($0, RSTART + RLENGTH) } }' \
               "$PREFIX/.opam-switch/packages/$1.$ver/opam" 2>/dev/null | sort -u); do
    # (not ocaml: those of the host's runtime)
    case $d in ocaml|dune) continue ;; esac
    if [ -d "$PREFIX/lib/$d" ]; then echo "-I$PREFIX/lib/$d"; fi
  done
}

run_auto() {
  local pkg=$1 lib=$2 stamp=$SYSROOT/stamps/auto-$1-$2 work=$SYSROOT/build/auto-$1
  if [ "$FORCE" = no ] && [ -f "$stamp" ] && [ "$(cut -d' ' -f1 "$stamp")" = "$(opam_pkg_version "$pkg")" ]; then return 0; fi
  local sysflags syscflags
  sysflags=$(system_deps "$pkg")
  syscflags="$(system_cflags "$pkg") $(dep_includes "$pkg" | tr '\n' ' ')"
  rm -rf "$work"
  fetch_opam_source "$pkg" "$work"
  cd "$work"
  local files= objs=() f native
  native=$(find . -name "lib$lib.a" | head -1)
  if [ -n "$native" ] && files=$(archive_sources "$native"); then
    log "  the C files of the native lib$lib.a"
  else
    # _build: the copies of the sources in the kept native build (ocamlbuild,
    # topkg), only used when the stubs are nowhere else (generated)
    files=$(grep -rlE '#include *[<"]caml/' --include='*.c' --exclude-dir=_build . || true)
    [ -n "$files" ] || files=$(grep -rlE '#include *[<"]caml/' --include='*.c' . || true)
  fi
  [ -n "$files" ] || die "$pkg: no OCaml stub found"
  for f in $files; do
    log "  emcc $f"
    # shellcheck disable=SC2086
    stub_cc "$f" -I"$(dirname "$f")" -I"$(dirname "${native:-.}")" $syscflags || die "$pkg: cannot compile $f"
    objs+=("${f%.c}.o")
  done
  mklib "$lib" "${objs[@]}"
  install_lib "lib$lib.a"
  provides "auto-$pkg" "$lib"
  [ -z "${sysflags// }" ] || link_flags "$lib" "${sysflags# }"
  echo "$SOURCE_VERSION emcc-$EMCC_VERSION" > "$stamp"
}

# archive_sources <lib.a>: the C file of each member of a host archive, the
# one outside _build first; fails if one has none.
archive_sources() {
  local m c
  for m in $(ar t "$1" 2>/dev/null | grep '\.o$'); do
    c=$(find . -name "${m%.o}.c" ! -path '*/_build/*' | head -1)
    [ -n "$c" ] || c=$(find . -name "${m%.o}.c" | head -1)
    [ -n "$c" ] || return 1
    echo "$c"
  done
}

# obtain <opam-package> <lib-name>: get lib<lib-name>.a by the best available
# means: a recipe named after the package (level 3), the package's own dune
# rules (level 1), or blind compilation of its stubs (level 2 fallback).
run_obtain() {
  local pkg=$1 lib=$2 r
  # A recipe named after the package, unless it is a system library recipe:
  # the opam package `zlib` is the OCaml binding, not the C library.
  # (built again if it was: the library is missing, or built for another
  # version of the package)
  if r=$(find_recipe "$pkg") && ! grep -q '^SOURCE=system:' "$r/recipe.sh"; then
    FORCE=yes run_recipe "$pkg"; return
  fi
  local probe=$SYSROOT/build/probe-$pkg
  rm -rf "$probe"; fetch_opam_source "$pkg" "$probe"
  if [ -f "$probe/dune-project" ]; then
    rm -rf "$probe"; run_dune_package "$pkg"
  else
    rm -rf "$probe"; run_auto "$pkg" "$lib"
  fi
}

cmd=${1:-}; shift || true
if [ "${1:-}" = --force ]; then FORCE=yes; shift; fi
case "$cmd" in
  describe)     describe_recipe "$1" ;;
  build)        build_recipe "$@" ;;
  releases)     releases_of "$1" ;;
  install-dune) run_dune_package "$1" ;;
  shadow)       for p in "$@"; do run_shadow "$p"; done ;;
  patched-dune) patched_dune ;;
  auto)         run_auto "$1" "$2" ;;
  obtain)       run_obtain "$1" "$2" ;;
  toolchain)    write_toolchain ;;
  *) die "usage: driver.sh describe|build|install-dune|shadow|patched-dune|auto|obtain|toolchain ..." ;;
esac
