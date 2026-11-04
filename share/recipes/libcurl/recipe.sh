# libcurl (conf-libcurl), with OpenSSL and zlib on top of their recipes; no
# HTTP/2, HTTP/3, IDN, PSL, brotli, zstd, LDAP or SSH.  Names are resolved
# by the blocking resolver (no resolver thread).

SOURCE=system:libcurl
DEPENDS="libssl zlib"
PKGCONFIG=libcurl
HEADER=curl/curlver.h
VERSION_MACROS="LIBCURL_VERSION_MAJOR LIBCURL_VERSION_MINOR LIBCURL_VERSION_PATCH"
LINK="-lcurl -lssl -lcrypto -lz"
LIB_PATTERNS=curl

releases() {
  local v
  git ls-remote --tags --refs https://github.com/curl/curl.git 2>/dev/null \
    | sed -n 's|.*refs/tags/curl-\([0-9_]*\)$|\1|p' | tr _ . | sort -V \
    | while read -r v; do echo "$v https://curl.se/download/curl-$v.tar.xz"; done
}

build() {
  log "configure (emconfigure)"
  EM_PKG_CONFIG_PATH=$SYSROOT/lib/pkgconfig emconfigure ./configure --host=wasm32-unknown-emscripten \
    --prefix="$SYSROOT" --enable-static --disable-shared --with-openssl="$SYSROOT" --with-zlib="$SYSROOT" \
    --without-libpsl --without-brotli --without-zstd --without-nghttp2 --without-nghttp3 --without-ngtcp2 \
    --without-libidn2 --without-libssh2 --without-librtmp --disable-ldap --disable-ldaps \
    --disable-threaded-resolver --disable-docs --disable-manual --disable-unix-sockets \
    CFLAGS="$CFLAGS" CPPFLAGS="-I$SYSROOT/include" LDFLAGS="$LDFLAGS -L$SYSROOT/lib" \
    > configure.log 2>&1 || { tail -30 configure.log; die "configure failed"; }
  log "make"
  emmake make -j"$NPROC" -C lib > make.log 2>&1 || { tail -30 make.log; die "make failed"; }
  emmake make -C lib install > install.log 2>&1 && emmake make -C include install >> install.log 2>&1 \
    || { tail -30 install.log; die "install failed"; }
  install_pc libcurl "$SOURCE_VERSION" "-lcurl -lssl -lcrypto -lz"
  provides libcurl curl
}
