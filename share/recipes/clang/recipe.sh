# Clang's C++ libraries (libclang*.a and the libLLVM*.a they need), for
# programs embedding the clang frontend (C parsers, AST tools), with:
#   include/{llvm,llvm-c,clang,clang-c}   headers
#   lib/clang/<ver>/include               clang's resource headers (stddef.h...)
#   lib/libclang-cpp.a                    all clang libraries in one archive
#                                         (what -lclang-cpp means since LLVM 10)
#   bin/llvm-config                       describes this installation
#   bin/clang                             only answers -print-resource-dir
#                                         and --version (configure scripts)
#
# Version: LLVM_VERSION if set, else the major version of the host's
# llvm-config (newest release of that major), else the newest release.  A
# project pins it with its own recipe:
#   LLVM_VERSION=9.0.1        # or a major: 9
#   include_recipe clang
# Other knobs: CLANG_LIBS (libraries built, their dependencies come along),
# CLANG_RESOURCE_DIR (where the program finds the resource headers in its
# virtual file system; default /usr/lib/clang/<ver>: preload
# $SYSROOT/lib/clang/<ver> there).  `bin/clang -print-resource-dir` answers
# $OCAML_EMCC_CLANG_RESOURCE_DIR instead when set (e.g. the real
# $SYSROOT/lib/clang/<ver> for a node build reading the real file system).
#
# Two cmake builds: tablegen for the host (shared by the targets), then the
# libraries with emcc.  Needs cmake, a host C++ compiler, ideally ninja.  The
# libraries take a while (LLVM 9: about 15 minutes on 4 cores).

SOURCE=fetch
LLVM_VERSION=${LLVM_VERSION:-}
CLANG_LIBS=${CLANG_LIBS:-"clangTooling clangFrontend clangSerialization clangDriver clangParse clangSema clangAnalysis clangEdit clangAST clangLex clangBasic"}
LLVM_RELEASES=${LLVM_RELEASES:-https://github.com/llvm/llvm-project/releases/download}

llvm_releases() {
  git ls-remote --tags --refs https://github.com/llvm/llvm-project.git 'llvmorg-*' 2>/dev/null \
    | sed 's|.*refs/tags/llvmorg-||' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V
}

host_llvm_version() {
  local c
  for c in llvm-config $(compgen -c llvm-config- 2>/dev/null | sort -rV); do
    command -v "$c" >/dev/null && { "$c" --version 2>/dev/null | sed 's/git//'; return; }
  done
  return 1
}

fetch() {
  local dest=$1 want=$LLVM_VERSION v hv file url
  if [ -z "$want" ] && hv=$(host_llvm_version); then
    want=${hv%%.*}; log "host LLVM is $hv: using the newest $want.x release"
  elif [ -z "$want" ]; then
    log "no LLVM_VERSION and no host llvm-config: using the newest release"
  fi
  case $want in
    *.*.*) v=$want ;;
    *) v=$(llvm_releases | version_match "$want" | tail -1)
       [ -n "$v" ] || die "clang: no LLVM release ${want:+matching $want }found" ;;
  esac
  # one source archive for all the targets
  for file in "llvm-project-$v.src.tar.xz" "llvm-project-$v.tar.xz"; do
    url=$LLVM_RELEASES/llvmorg-$v/$file
    [ -f "$SHARED/$file" ] && break
    log "downloading $url (no checksum to verify)"
    curl -fsSL --retry 3 -o "$SHARED/$file.tmp" "$url" && { mv "$SHARED/$file.tmp" "$SHARED/$file"; break; }
    rm -f "$SHARED/$file.tmp"
  done
  [ -f "$SHARED/$file" ] || die "clang: cannot download LLVM $v"
  mkdir -p "$dest"
  log "extracting llvm and clang from $file"
  tar -xf "$SHARED/$file" -C "$dest" --strip-components=1 \
    --exclude='*/test' --exclude='*/unittests' \
    --wildcards '*/llvm/*' '*/clang/*' '*/cmake/*' '*/third-party/*' 2>/dev/null \
    || tar -xf "$SHARED/$file" -C "$dest" --strip-components=1 \
         --exclude='*/test' --exclude='*/unittests' \
         --wildcards '*/llvm/*' '*/clang/*'
  SOURCE_VERSION=$v
}

# clang_lib_closure <build dir> <lib>...: the libraries and every clang/LLVM
# library they depend on, from the build tree's ClangTargets.cmake and
# LLVMExports.cmake.
clang_lib_closure() {
  local b=$1 deps all= t d; shift
  deps=$(cat "$b"/lib/cmake/clang/ClangTargets.cmake "$b"/lib/cmake/llvm/LLVMExports.cmake 2>/dev/null \
    | awk '/^set_target_properties\(/ { t = $1; sub(/^set_target_properties\(/, "", t) }
           /INTERFACE_LINK_LIBRARIES/ { l = $0; sub(/.*INTERFACE_LINK_LIBRARIES *"/, "", l); sub(/".*/, "", l)
                                        gsub(/\$<LINK_ONLY:/, "", l); gsub(/>/, "", l); gsub(/;/, " ", l)
                                        print t, l }')
  set -- "$@"
  while [ $# -gt 0 ]; do
    t=$1; shift
    case " $all " in *" $t "*) continue ;; esac
    all="$all $t"
    for d in $(printf '%s\n' "$deps" | awk -v t="$t" '$1 == t { $1 = ""; print }'); do
      case $d in clang*|LLVM*) set -- "$@" "$d" ;; esac
    done
  done
  echo "${all# }"
}

build() {
  local v=$SOURCE_VERSION major=${SOURCE_VERSION%%.*} gen=() std=c++14
  command -v cmake >/dev/null || die "clang: cmake is needed"
  command -v ninja >/dev/null && gen=(-G Ninja)
  [ "$major" -ge 16 ] && std=c++17
  local triple=$TARGET-unknown-emscripten

  # 1. tablegen for the host, without the wasm flags of the environment
  local tbl=$SHARED/llvm-tblgen-$v
  if [ ! -x "$tbl/clang-tblgen" ]; then
    log "building llvm-tblgen and clang-tblgen $v for the host"
    # old LLVM sources miss includes that recent libstdc++ no longer pulls in
    env -u CFLAGS -u CXXFLAGS -u LDFLAGS CXXFLAGS="-include cstdint -include limits" \
      cmake "${gen[@]}" -S llvm -B build-host -Wno-dev -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DLLVM_ENABLE_PROJECTS=clang \
      -DLLVM_TARGETS_TO_BUILD=WebAssembly -DLLVM_INCLUDE_TESTS=OFF \
      -DLLVM_INCLUDE_BENCHMARKS=OFF -DLLVM_INCLUDE_EXAMPLES=OFF \
      -DLLVM_ENABLE_ZLIB=OFF -DLLVM_ENABLE_ZSTD=OFF -DLLVM_ENABLE_TERMINFO=OFF \
      -DLLVM_ENABLE_LIBXML2=OFF >&2
    env -u CFLAGS -u CXXFLAGS -u LDFLAGS cmake --build build-host -j "$NPROC" \
      --target llvm-tblgen clang-tblgen >&2
    mkdir -p "$tbl.tmp"
    cp build-host/bin/*-tblgen "$tbl.tmp/"
    rm -rf "$tbl"; mv "$tbl.tmp" "$tbl"
    rm -rf build-host
  fi

  # 2. the libraries, with emcc.  The build type adds no optimisation flag:
  #    $CFLAGS has the toolchain's.
  log "building $CLANG_LIBS for $triple"
  [ "$major" -ge 16 ] || export CXXFLAGS="$CXXFLAGS -include cstdint -include limits"
  emcmake cmake "${gen[@]}" -S llvm -B build -Wno-dev \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_FLAGS_RELEASE=-DNDEBUG -DCMAKE_CXX_FLAGS_RELEASE=-DNDEBUG \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DLLVM_ENABLE_PROJECTS=clang -DLLVM_TARGETS_TO_BUILD=WebAssembly \
    -DLLVM_DEFAULT_TARGET_TRIPLE="$triple" -DLLVM_HOST_TRIPLE="$triple" \
    -DLLVM_TABLEGEN="$tbl/llvm-tblgen" -DCLANG_TABLEGEN="$tbl/clang-tblgen" \
    -DLLVM_NATIVE_TOOL_DIR="$tbl" \
    -DLLVM_ENABLE_THREADS=OFF -DLLVM_ENABLE_ZLIB=OFF -DLLVM_ENABLE_ZSTD=OFF \
    -DLLVM_ENABLE_TERMINFO=OFF -DLLVM_ENABLE_LIBEDIT=OFF -DLLVM_ENABLE_LIBXML2=OFF \
    -DLLVM_ENABLE_LIBPFM=OFF -DLLVM_ENABLE_ASSERTIONS=OFF \
    -DLLVM_ENABLE_EH=OFF -DLLVM_ENABLE_RTTI=OFF \
    -DLLVM_BUILD_TOOLS=OFF -DLLVM_INCLUDE_TESTS=OFF -DLLVM_INCLUDE_EXAMPLES=OFF \
    -DLLVM_INCLUDE_BENCHMARKS=OFF -DLLVM_INCLUDE_DOCS=OFF \
    -DCLANG_BUILD_TOOLS=OFF -DCLANG_INCLUDE_TESTS=OFF -DCLANG_INCLUDE_DOCS=OFF \
    -DCLANG_ENABLE_ARCMT=OFF -DCLANG_ENABLE_STATIC_ANALYZER=OFF \
    -DCMAKE_INSTALL_PREFIX="$SYSROOT" >&2
  # Building a static library does not build the ones it depends on: take
  # the closure of CLANG_LIBS from the link interfaces cmake exports.
  local libs_closure
  libs_closure=$(clang_lib_closure build $CLANG_LIBS)
  log "libraries: $libs_closure"
  # shellcheck disable=SC2086
  cmake --build build -j "$NPROC" --target $libs_closure >&2
  cmake --build build --target clang-resource-headers >&2 \
    || cmake --build build --target clang-headers >&2

  # 3. install
  local a libs=
  for a in build/lib/lib*.a; do install_lib "$a"; done
  rm -f libclang-cpp.a
  "$EMAR" qcL libclang-cpp.a build/lib/libclang[A-Z]*.a
  install_lib libclang-cpp.a
  local d
  for d in llvm/include build/include clang/include build/tools/clang/include; do
    (cd "$d" && find . -type f \( -name '*.h' -o -name '*.def' -o -name '*.inc' -o -name '*.gen' -o -name '*.modulemap' \) \
       ! -path '*/CMakeFiles/*' | tar -cf - -T -) | tar -xf - -C "$SYSROOT/include"
  done
  rm -rf "$SYSROOT/lib/clang"
  mkdir -p "$SYSROOT/lib/clang"
  cp -a build/lib/clang/. "$SYSROOT/lib/clang/"
  local resdir=${CLANG_RESOURCE_DIR:-/usr/lib/clang/$(ls build/lib/clang | head -1)}

  # libraries for `llvm-config --libs`: the LLVM ones that were built
  for a in build/lib/libLLVM*.a; do a=$(basename "$a" .a); libs="$libs -l${a#lib}"; done
  cat > "$SYSROOT/bin/llvm-config" <<EOF
#!/bin/sh
# llvm-config of LLVM $v built for $triple (ocaml-emcc clang recipe)
p='$SYSROOT'
defs='-D__STDC_CONSTANT_MACROS -D__STDC_FORMAT_MACROS -D__STDC_LIMIT_MACROS'
for a; do
  case \$a in
    --version) echo '$v' ;;
    --prefix) echo "\$p" ;;
    --bindir) echo "\$p/bin" ;;
    --includedir) echo "\$p/include" ;;
    --libdir) echo "\$p/lib" ;;
    --cppflags|--cflags) echo "-I\$p/include \$defs" ;;
    --cxxflags) echo "-I\$p/include -std=$std -fno-exceptions -fno-rtti \$defs" ;;
    --ldflags) echo "-L\$p/lib" ;;
    --libs) echo '${libs# }' ;;
    --system-libs) echo ;;
    --shared-mode) echo static ;;
    --host-target) echo '$triple' ;;
    --targets-built) echo WebAssembly ;;
    --build-mode) echo Release ;;
    --assertion-mode) echo OFF ;;
    --has-rtti) echo NO ;;
    -*) echo "llvm-config (ocaml-emcc): unsupported option \$a" >&2; exit 1 ;;
  esac
done
EOF
  cat > "$SYSROOT/bin/clang" <<EOF
#!/bin/sh
# Not a compiler: clang $v as seen by the wasm program, for configure scripts.
case "\$1" in
  -print-resource-dir) echo "\${OCAML_EMCC_CLANG_RESOURCE_DIR:-$resdir}" ;;
  --version) echo 'clang version $v (ocaml-emcc, $triple libraries)' ;;
  *) echo "clang (ocaml-emcc): only -print-resource-dir and --version; compile with emcc" >&2; exit 1 ;;
esac
EOF
  chmod +x "$SYSROOT/bin/llvm-config" "$SYSROOT/bin/clang"
  log "resource headers: preload $SYSROOT/lib/clang/$(ls build/lib/clang | head -1) at $resdir"
}
