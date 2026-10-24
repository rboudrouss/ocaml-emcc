# libffi (conf-libffi), for ctypes-foreign.  libffi supports emscripten
# (wasm32 since 3.4.5, wasm64 since 3.5): calls go through JS, and closures
# (OCaml callbacks passed to C) are new entries of the function table, hence
# -sALLOW_TABLE_GROWTH for every program using it.  Its JS also uses
# stackSave & co without declaring them (its tests link with -sEXPORT_ALL).

SOURCE=system:libffi
PKGCONFIG=libffi
HEADER=ffi.h
TARBALL=libffi
LINK='-lffi -sALLOW_TABLE_GROWTH -sDEFAULT_LIBRARY_FUNCS_TO_INCLUDE=$stackSave,$stackRestore,$stackAlloc'

releases() {
  git_tag_releases https://github.com/libffi/libffi.git v \
    'https://github.com/libffi/libffi/releases/download/v{v}/libffi-{v}.tar.gz'
}

build() {
  # configure: no -fexceptions.  wasm64 (src/wasm/ffi.c, since 3.7): the
  # integral returns widened without assuming 8-byte alignment.
  apply_patches "$BASE_RECIPE_DIR/patches"
  if grep -q STORE_ARG_WIDENED src/wasm/ffi.c 2>/dev/null; then
    apply_patches "$BASE_RECIPE_DIR/patches/3.7+"
  fi
  log "configure (emconfigure)"
  emconfigure ./configure --host="$TARGET-unknown-linux" --prefix="$SYSROOT" \
    --enable-static --disable-shared --disable-dependency-tracking --disable-builddir \
    --disable-multi-os-directory --disable-raw-api --disable-docs --disable-exec-static-tramp \
    CFLAGS="$CFLAGS" > configure.log 2>&1 || { tail -30 configure.log; die "configure failed"; }
  grep -q '^#define HAVE_LONG_DOUBLE 1' fficonfig.h || die "configure did not detect long double"
  log "make"
  emmake make -j"$NPROC" > make.log 2>&1 || { tail -30 make.log; die "make failed"; }
  make install > install.log 2>&1
  provides libffi ffi
}
