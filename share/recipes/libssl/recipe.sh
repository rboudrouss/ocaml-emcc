# OpenSSL (conf-libssl): libssl and libcrypto, generic C (no-asm), without
# threads.  OpenSSL knows emscripten: its entropy comes from getentropy.
# No secure heap (mlock), no dynamic engines or providers (no dlopen).

SOURCE=system:libssl
PKGCONFIG=openssl
HEADER=openssl/opensslv.h
VERSION_MACROS="OPENSSL_VERSION_MAJOR OPENSSL_VERSION_MINOR OPENSSL_VERSION_PATCH"
LINK="-lssl -lcrypto"
LIB_PATTERNS="ssl crypto"

releases() {
  git_tag_releases https://github.com/openssl/openssl.git openssl- \
    'https://github.com/openssl/openssl/releases/download/openssl-{v}/openssl-{v}.tar.gz'
}

build() {
  local target=linux-generic32
  [ "$TARGET" = wasm64 ] && target=linux-generic64
  log "Configure ($target)"
  ./Configure "$target" no-asm no-threads no-shared no-dso no-engine no-afalgeng no-secure-memory \
    no-ui-console no-tests no-docs no-apps --prefix="$SYSROOT" --libdir=lib \
    CC="$EMCC" AR="$EMAR" RANLIB="$EMSDK_BIN/emranlib" CFLAGS="$CFLAGS" \
    > configure.log 2>&1 || { tail -30 configure.log; die "Configure failed"; }
  log "make"
  make -j"$NPROC" build_libs > make.log 2>&1 || { tail -30 make.log; die "make failed"; }
  make install_dev > install.log 2>&1 || { tail -30 install.log; die "install failed"; }
  provides libssl ssl crypto
}
