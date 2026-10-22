#!/usr/bin/env bash
# Recipe driver for ocaml-emcc.
#
#   driver.sh install [--force] <recipe>...   build + install recipes
#   driver.sh install-dune [--force] <opam-package>
#                                            rebuild the C stubs of a dune
#                                            package with the wasm32 toolchain
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

: "${OCAML_EMCC_SHARE:?}" "${OCAML_EMCC_SWITCH_PREFIX:?}" "${OCAML_EMCC_SYSROOT:?}"

SYSROOT=$OCAML_EMCC_SYSROOT
PREFIX=$OCAML_EMCC_SWITCH_PREFIX
HOST_BIN=$PREFIX/bin
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
TARGET_FLAGS="$TARGET_FLAGS -fno-strict-overflow -sSUPPORT_LONGJMP=wasm"
OPT=${OCAML_EMCC_OPT:--O2}
# BASE_CFLAGS is what the toolchain wrappers and the link step record; extra
# flags are added on top at each use (recipes here, stubs in tools/ocamlc).
BASE_CFLAGS="$OPT -fno-strict-aliasing -fwrapv $TARGET_FLAGS"
export CFLAGS="$BASE_CFLAGS ${OCAML_EMCC_EXTRA_CFLAGS:-}"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="$TARGET_FLAGS"
# Flags to compile OCaml stubs against the wasm32 runtime headers.
STUB_CFLAGS="$CFLAGS -I$OCAML_INC -I$SYSROOT/include -D_FILE_OFFSET_BITS=64"

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

# fetch_opam_source <pkg> <dest>: copy the sources of an installed package.
# Looks, in order, at the build dir kept by opam (OPAMKEEPBUILDDIR / keep-
# build-dir), the sources of pinned packages, then falls back to `opam source`.
fetch_opam_source() {
  local pkg=$1 dest=$2 ver src=
  ver=$(opam_pkg_version "$pkg") || die "$pkg is not installed in $PREFIX"
  for cand in "$PREFIX/.opam-switch/build/$pkg.$ver" \
              "$PREFIX/.opam-switch/sources/$pkg.$ver" \
              "$PREFIX/.opam-switch/sources/$pkg"; do
    if [ -d "$cand" ]; then src=$cand; break; fi
  done
  if [ -n "$src" ]; then
    log "using sources of $pkg.$ver from $src"
    cp -a "$src" "$dest"
  else
    local cache="$SYSROOT/src/$pkg.$ver"
    if [ ! -d "$cache" ]; then
      log "sources of $pkg.$ver not kept in the switch, running opam source"
      opam source "$pkg.$ver" --dir "$cache.tmp" >&2 && mv "$cache.tmp" "$cache"
    fi
    cp -a "$cache" "$dest"
  fi
  SOURCE_VERSION=$ver
}

# fetch_opam_version <pkg> <version> <dest>: sources of any version known to
# the opam repository, installed or not (opam checks the archive checksum).
# Fails if the repository has no such version.
fetch_opam_version() {
  local pkg=$1 ver=$2 dest=$3 cache
  cache="$SYSROOT/src/$pkg.$ver"
  if [ ! -d "$cache" ]; then
    opam show --field=version "$pkg.$ver" >/dev/null 2>&1 || return 1
    log "fetching $pkg.$ver with opam source"
    opam source "$pkg.$ver" --dir "$cache.tmp" >&2 && mv "$cache.tmp" "$cache" || return 1
  fi
  cp -a "$cache" "$dest"
  SOURCE_VERSION=$ver
}

# host_version <pkg-config name> <header> <major macro> <minor macro> [<patch macro>]
# Version of a C library as the host (hence the native build) sees it:
# pkg-config, else the version macros of its header.
host_version() {
  local pc=$1 header=$2; shift 2
  local defs m v=
  if command -v pkg-config >/dev/null && v=$(pkg-config --modversion "$pc" 2>/dev/null) && [ -n "$v" ]; then
    echo "$v"; return
  fi
  v=
  [ -n "$header" ] || return 1
  defs=$(printf '#include <%s>\n' "$header" | cc -E -dM - 2>/dev/null) || return 1
  for m in "$@"; do
    m=$(printf '%s\n' "$defs" | awk -v m="$m" '$1 == "#define" && $2 == m { print $3 }' | tr -d '"')
    [ -n "$m" ] || return 1
    v=${v:+$v.}$m
  done
  echo "$v"
}

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
# Choice: the sources of OPAM_SOURCES if the switch has it installed (that is
# what the project links natively).  Otherwise the newest upstream release
# compatible with the host's version (any version without a host library),
# fetched through opam when opam knows it (checksum verified).

# "<version> <file>" for each release in the listing, oldest first.
release_files() {
  local prefix=$1 url=$2
  curl -fsL "$url" 2>/dev/null \
    | grep -oE "$prefix-[0-9][0-9.]*[0-9]\.tar\.(xz|bz2|gz)" \
    | sed -E "s/^$prefix-([0-9.]*[0-9])\.tar\.(xz|bz2|gz)$/\1 \2 &/" \
    | sed -e 's/ xz / 1 /' -e 's/ bz2 / 2 /' -e 's/ gz / 3 /' \
    | sort -k1,1V -k2,2n -u | awk '$1 != last { print $1, $3; last = $1 }'
}

# git_tag_releases <repo> <tag prefix> <url template>: "<version> <url>" for
# each tag <prefix><version> of <repo> (final versions only), {v} in the
# template standing for the version.
git_tag_releases() {
  local repo=$1 prefix=$2 template=$3 v
  git ls-remote --tags --refs "$repo" 2>/dev/null | sed -n "s|.*refs/tags/$prefix||p" \
    | grep -E '^[0-9]+(\.[0-9]+)+$' | sort -V \
    | while read -r v; do echo "$v ${template//\{v\}/$v}"; done
}

# Keep the versions (first word of each line) compatible with <want>.
version_match() {
  local want=$1
  if [ -z "$want" ]; then cat; else grep -E "^${want//./\\.}([.-]| |$)" || true; fi
}

# An opam package wrapping the upstream sources: either they are the package
# sources themselves, or the upstream tarball is inside (opam's `gmp`).
unpack_vendored() {
  local src=$1 prefix=$2 dest=$3 t
  if [ -x "$src/configure" ] || [ -f "$src/configure" ]; then mv "$src" "$dest"; return; fi
  t=$(find "$src" -maxdepth 3 -name "$prefix-*.tar.*" | head -1)
  [ -n "$t" ] || die "no $prefix sources in $src"
  mkdir -p "$dest"
  tar -xf "$t" -C "$dest" --strip-components=1
  rm -rf "$src"
}

fetch_system() {
  local name=$1 dest=$2 prefix=${TARBALL:-$1} hv want= v= file= ov=
  if [ -n "$OPAM_SOURCES" ] && opam_pkg_version "$OPAM_SOURCES" >/dev/null; then
    fetch_opam_source "$OPAM_SOURCES" "$dest.opam"
    unpack_vendored "$dest.opam" "$prefix" "$dest"; return
  fi
  # shellcheck disable=SC2086
  if { [ -n "$HEADER" ] || [ -n "$PKGCONFIG" ]; } \
     && hv=$(host_version "${PKGCONFIG:-$name}" "$HEADER" $VERSION_MACROS) && [ -n "$hv" ]; then
    case ${COMPAT:-major} in
      major)  want=${hv%%.*} ;;
      minor)  want=$(echo "$hv" | cut -d. -f1-2) ;;
      exact)  want=$hv ;;
      latest) want= ;;
      *) die "$name: bad COMPAT '$COMPAT'" ;;
    esac
    log "host $name is $hv: using the newest ${want:+$want.x }release"
  else
    log "no host $name found (pkg-config${HEADER:+, $HEADER}): using the newest release"
  fi
  if declare -F releases >/dev/null; then
    read -r v file < <(releases | version_match "$want" | tail -1) || true
  elif [ -n "$RELEASES" ]; then
    read -r v file < <(release_files "$prefix" "$RELEASES" | version_match "$want" | tail -1) || true
  fi
  if [ -n "$OPAM_SOURCES" ]; then
    # opam versions may carry a packaging revision (6.3.0-1)
    ov=$(opam show --field=all-versions "$OPAM_SOURCES" 2>/dev/null | tr -s ' ' '\n' \
           | version_match "${v:-$want}" | tail -1)
    if [ -n "$ov" ] && { [ -z "$v" ] || [ "${ov%%-*}" = "$v" ]; } \
       && fetch_opam_version "$OPAM_SOURCES" "$ov" "$dest.opam"; then
      unpack_vendored "$dest.opam" "$prefix" "$dest"; SOURCE_VERSION=$ov; return
    fi
  fi
  [ -n "$v" ] || die "$name: no release found${want:+ for version $want} (${RELEASES:-no RELEASES})"
  log "$prefix $v: not in the opam repository, downloading it (no checksum to verify)"
  case $file in *://*) ;; *) file=${RELEASES%/}/$file ;; esac
  SHA256= fetch_url "$file" "$dest"
  SOURCE_VERSION=$v
}

# Flags for users of system recipe <name> (meta/<name>.uselink).
record_use_flags() {
  local name=$1 d flags=${LINK:--l$1}
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

# opam packages of <pkg> that stand for system libraries (installed conf-X
# among its dependencies) and for which a recipe X exists.
system_recipes_of() {
  local pkg=$1 ver f c
  ver=$(opam_pkg_version "$pkg") || return 0
  f=$PREFIX/.opam-switch/packages/$pkg.$ver/opam
  [ -f "$f" ] || return 0
  for c in $(grep -oE '"conf-[a-z0-9_-]+"' "$f" | tr -d '"' | sort -u); do
    opam_pkg_version "$c" >/dev/null || continue
    find_recipe "${c#conf-}" >/dev/null && echo "${c#conf-}"
  done
  return 0
}

# Build the system recipes <pkg> needs; prints the link flags they require.
system_deps() {
  local r flags=
  for r in $(system_recipes_of "$1"); do
    log "$1 uses the system library $r (conf-$r): building the $r recipe"
    run_recipe "$r" >&2 || die "$1: the $r recipe failed"
    flags="$flags $(cat "$SYSROOT/meta/$r.uselink" 2>/dev/null)"
  done
  echo "$flags"
}

fetch_url() {
  local url=$1 dest=$2 file
  file="$SYSROOT/src/$(basename "$url")"
  if [ ! -f "$file" ]; then
    log "downloading $url"
    curl -fsSL --retry 3 -o "$file.tmp" "$url" && mv "$file.tmp" "$file"
  fi
  if [ -n "${SHA256:-}" ] && ! echo "$SHA256  $file" | sha256sum -c --quiet - >/dev/null 2>&1; then
    rm -f "$file"; die "checksum mismatch for $url"
  fi
  mkdir -p "$dest"
  tar -xf "$file" -C "$dest" --strip-components=1
  SOURCE_VERSION=$(basename "$url")
}

# fetch_git <url> <ref> <dest>: shallow clone, no history.  Tags and branches
# go through `clone --branch`; commits through `fetch --depth 1 <sha>`, which
# GitHub/GitLab allow.  Clones are cached per (repo, ref).
fetch_git() {
  local url=$1 ref=$2 dest=$3 cache
  cache="$SYSROOT/src/git/$(basename "$url" .git)-${ref:-HEAD}"
  if [ ! -d "$cache" ]; then
    log "git clone --depth 1 $url ${ref:+($ref)}"
    rm -rf "$cache.tmp"; mkdir -p "$SYSROOT/src/git"
    if [ -z "$ref" ]; then
      git clone -q --depth 1 --recurse-submodules --shallow-submodules "$url" "$cache.tmp" >&2
    elif ! git clone -q --depth 1 --branch "$ref" --recurse-submodules --shallow-submodules \
           "$url" "$cache.tmp" >&2 2>/dev/null; then
      rm -rf "$cache.tmp"; mkdir -p "$cache.tmp"
      ( cd "$cache.tmp" && git init -q && git remote add origin "$url" \
          && git fetch -q --depth 1 origin "$ref" && git checkout -q FETCH_HEAD \
          && git submodule -q update --init --depth 1 --recursive ) >&2 \
        || { rm -rf "$cache.tmp"; die "cannot fetch $ref from $url"; }
    fi
    mv "$cache.tmp" "$cache"
  fi
  cp -a "$cache" "$dest"
  SOURCE_VERSION=${ref:-HEAD}
}

# The compiler sources: whichever compiler package of the switch carries them.
# Since OCaml 5.3 the sources live in `ocaml-compiler` (ocaml-base-compiler is
# a meta package), hence the order.
fetch_ocaml_source() {
  local p ver
  for p in ocaml-variants ocaml-compiler ocaml-base-compiler; do
    ver=$(opam_pkg_version "$p") || continue
    if [ -d "$PREFIX/.opam-switch/build/$p.$ver" ]; then
      fetch_opam_source "$p" "$1"; return
    fi
  done
  for p in ocaml-variants ocaml-compiler ocaml-base-compiler; do
    if opam_pkg_version "$p" >/dev/null; then fetch_opam_source "$p" "$1"; return; fi
  done
  die "cannot find the compiler package of the switch"
}

# ----------------------------------------------------------------- helpers

apply_patches() { # apply_patches <dir>: apply <dir>/*.patch in order
  local p
  [ -d "$1" ] || return 0
  for p in "$1"/*.patch; do
    [ -f "$p" ] || continue
    log "patch $(basename "$p")"
    patch -p1 --forward --silent < "$p" || die "patch $p failed"
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
TOOLCHAIN_VERSION=3

write_toolchain() {
  local tool host_conf cc=$SYSROOT/bin/emcc-$TARGET
  # The C compiler dune is given: emcc with the target flags built in.  Some
  # packages replace dune's :standard C flags with their own (mlmpfr's
  # (flags (:include c_flags.sexp))), which would drop -m64 and friends.
  cat > "$cc" <<EOF
#!/bin/sh
exec '$EMCC' $TARGET_FLAGS "\$@"
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
  # put first in dune's PATH: rules running `ocamlmklib` directly
  mkdir -p "$SYSROOT/bin/path"
  ln -sf ../ocamlmklib "$SYSROOT/bin/path/ocamlmklib"
  ln -sf ../ocamlmklib "$SYSROOT/bin/path/ocamlmklib.opt"
  local findlib_path
  host_conf=$("$HOST_BIN/ocamlfind" printconf conf 2>/dev/null || echo "$PREFIX/lib/findlib.conf")
  findlib_path=$("$HOST_BIN/ocamlfind" printconf path 2>/dev/null | paste -sd: - || true)
  [ -n "$findlib_path" ] || findlib_path="$PREFIX/lib"
  mkdir -p "$SYSROOT/findlib.conf.d"
  if [ -f "$host_conf" ]; then
    cp -f "$host_conf" "$SYSROOT/findlib.conf"
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

# Checksum of every recipe.sh named <name> along the recipe path (a recipe
# may include the next one).
recipe_sum() {
  local IFS=: d
  for d in $RECIPES_PATH; do if [ -f "$d/$1/recipe.sh" ]; then cat "$d/$1/recipe.sh"; fi; done \
    | sha256sum | cut -c1-16
}

run_recipe() {
  local name=$1 dir stamp work sum
  stamp=$SYSROOT/stamps/$name
  sum=$(recipe_sum "$name")
  if [ -f "$stamp" ] && [ "$FORCE" = no ]; then
    # not rebuilt automatically: some recipes take a while (clang)
    # (stamps written before this check have no checksum)
    grep -q "recipe=" "$stamp" && ! grep -q "recipe=$sum" "$stamp" \
      && log "note: the $name recipe changed since it was built; rebuild with: ocaml-emcc install --force $name"
    return 0
  fi
  dir=$(find_recipe "$name") || die "no recipe named '$name'"
  (
    SOURCE=none DEPENDS= SHA256= REF=
    HEADER= VERSION_MACROS= PKGCONFIG= RELEASES= TARBALL= COMPAT= OPAM_SOURCES= LINK=
    RECIPE_DIR=$dir RECIPE_NAME=$name BASE_RECIPE_DIR=$dir
    unset -f pre_build fetch releases
    # shellcheck disable=SC1091
    . "$dir/recipe.sh"
    local d
    for d in $DEPENDS; do FORCE=no run_recipe "$d"; done
    work=$SYSROOT/build/$name
    rm -rf "$work"
    case "$SOURCE" in
      opam:*) fetch_opam_source "${SOURCE#opam:}" "$work" ;;
      url:*)  fetch_url "${SOURCE#url:}" "$work" ;;
      git:*)
        local repo=${SOURCE#git:}
        case "$repo" in *'#'*) REF=${repo##*#}; repo=${repo%#*} ;; esac
        fetch_git "$repo" "$REF" "$work" ;;
      dir:*)
        local d=${SOURCE#dir:}
        case "$d" in /*) ;; *) d=$RECIPE_DIR/$d ;; esac
        cp -a "$d" "$work"; SOURCE_VERSION=$(basename "$d") ;;
      ocaml)  fetch_ocaml_source "$work" ;;
      fetch)  SOURCE_VERSION=; fetch "$work" ;;
      system:*) fetch_system "${SOURCE#system:}" "$work" ;;
      none)   mkdir -p "$work"; SOURCE_VERSION= ;;
      *) die "$name: bad SOURCE '$SOURCE'" ;;
    esac
    log "building $name ${SOURCE_VERSION:-}"
    cd "$work"
    # pre_build: a hook for project recipes refining a builtin one
    if declare -F pre_build >/dev/null; then pre_build; fi
    build
    case "$SOURCE" in system:*) record_use_flags "$name" ;; esac
    echo "${SOURCE_VERSION:-} emcc-$EMCC_VERSION recipe=$sum" > "$stamp"
    log "installed $name"
  )
}

# Rebuild a dune package's foreign stubs with `dune build -x wasm32`.
run_dune_package() {
  local pkg=$1 stamp=$SYSROOT/stamps/dune-$1 work=$SYSROOT/build/dune-$1
  if [ -f "$stamp" ] && [ "$FORCE" = no ]; then return 0; fi
  [ -f "$SYSROOT/findlib.conf.d/$TARGET.conf" ] || run_recipe ocaml
  local sysflags
  sysflags=$(system_deps "$pkg")
  rm -rf "$work"
  fetch_opam_source "$pkg" "$work"
  cd "$work"
  log "building the C stubs of $pkg with dune -x $TARGET"
  local a l found=no archives
  if PATH=$SYSROOT/bin/path:$PATH OCAMLFIND_CONF=$SYSROOT/findlib.conf \
       "$HOST_BIN/dune" build -x "$TARGET" -p "$pkg" @install >&2; then
    archives=$(find "_build/default.$TARGET" -name 'lib*.a' ! -path '*/.*')
  else
    log "dune -x $TARGET failed: compiling the C files of the native build instead"
    archives=$(dune_native_stubs "$pkg")
  fi
  while IFS= read -r a; do
    [ -n "$a" ] || continue
    l=$(basename "$a" .a | sed 's/^lib//')
    install_lib "$a"; provides "dune-$pkg" "$l"; found=yes
    [ -z "${sysflags// }" ] || link_flags "$l" "${sysflags# }"
    log "  $(basename "$a")"
  done <<< "$archives"
  [ $found = yes ] || log "  (no C archive produced)"
  echo "$SOURCE_VERSION emcc-$EMCC_VERSION" > "$stamp"
}

# Fallback of run_dune_package, for what dune cannot cross-compile: the
# (ctypes) stanza builds its generators as native executables of the target
# context.  Each stub archive of the native build (_build/default, kept by
# OPAMKEEPBUILDDIR, else built here) is rebuilt with emcc from the C files
# behind its members: hand-written stubs, vendored C, and the C that ctypes
# generated (architecture independent).  The stanza's own C flags are not
# known: only -I flags are given (the file's directory and its source
# directory, the headers of the opam packages it depends on).  Prints the
# wasm archives.
dune_native_stubs() {
  local pkg=$1 nat=_build/default ver a dir m c incs= dep objs
  if [ ! -d "$nat" ]; then
    log "no native build kept for $pkg: building it"
    "$HOST_BIN/dune" build -p "$pkg" @install >&2 || die "$pkg: native build failed"
  fi
  ver=$(opam_pkg_version "$pkg")
  for dep in $(grep -oE '"[a-z0-9_-]+"' "$PREFIX/.opam-switch/packages/$pkg.$ver/opam" 2>/dev/null | tr -d '"' | sort -u); do
    [ "$dep" != ocaml ] && compgen -G "$PREFIX/lib/$dep/*.h" >/dev/null && incs="$incs -I$PREFIX/lib/$dep"
  done
  mkdir -p _wasm_stubs
  while IFS= read -r a; do
    dir=$(dirname "$a"); objs=()
    for m in $(ar t "$a"); do
      c=$dir/${m%.o}.c
      [ -f "$c" ] || die "$pkg: no C source for $m (in $a)"
      # shellcheck disable=SC2086
      stub_cc "$c" -I"$dir" -I"${dir#"$nat"/}" $incs >&2 || die "$pkg: cannot compile $c"
      objs+=("$PWD/${c%.c}.o")
    done
    ( cd _wasm_stubs && mklib "$(basename "$a" .a | sed 's/^lib//')" "${objs[@]}" )
    echo "_wasm_stubs/$(basename "$a")"
  done < <(find "$nat" -name 'lib*.a' ! -path '*/.*')
}

# Last resort for packages with neither a recipe nor dune: compile every C
# file that includes the OCaml headers into lib<libname>.a.
run_auto() {
  local pkg=$1 lib=$2 stamp=$SYSROOT/stamps/auto-$1-$2 work=$SYSROOT/build/auto-$1
  if [ -f "$stamp" ] && [ "$FORCE" = no ]; then return 0; fi
  local sysflags
  sysflags=$(system_deps "$pkg")
  rm -rf "$work"
  fetch_opam_source "$pkg" "$work"
  cd "$work"
  local files objs=() f
  files=$(grep -rlE '#include *[<"]caml/' --include='*.c' . || true)
  [ -n "$files" ] || die "$pkg: no OCaml stub found"
  for f in $files; do
    log "  emcc $f"
    stub_cc "$f" -I"$(dirname "$f")"
    objs+=("${f%.c}.o")
  done
  mklib "$lib" "${objs[@]}"
  install_lib "lib$lib.a"
  provides "auto-$pkg" "$lib"
  [ -z "${sysflags// }" ] || link_flags "$lib" "${sysflags# }"
  echo "$SOURCE_VERSION emcc-$EMCC_VERSION" > "$stamp"
}

# obtain <opam-package> <lib-name>: get lib<lib-name>.a by the best available
# means: a recipe named after the package (level 3), the package's own dune
# rules (level 1), or blind compilation of its stubs (level 2 fallback).
run_obtain() {
  local pkg=$1 lib=$2 r
  # A recipe named after the package, unless it is a system library recipe:
  # the opam package `zlib` is the OCaml binding, not the C library.
  if r=$(find_recipe "$pkg") && ! grep -q '^SOURCE=system:' "$r/recipe.sh"; then
    run_recipe "$pkg"; return
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
  install)      for r in "$@"; do run_recipe "$r"; done ;;
  install-dune) run_dune_package "$1" ;;
  auto)         run_auto "$1" "$2" ;;
  obtain)       run_obtain "$1" "$2" ;;
  toolchain)    write_toolchain ;;
  *) die "usage: driver.sh install|install-dune|auto|obtain|toolchain ..." ;;
esac
