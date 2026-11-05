# MariaDB Connector/C (conf-mariadb: the mysql and mariadb bindings), the
# MySQL client library, static, with OpenSSL and zlib on top of their
# recipes.  Its authentication plugins are built in (no dlopen); no
# GSSAPI, zstd compression, shared memory, remote I/O or curl.  Its headers
# go to include/mariadb (<mysql.h> with the -I its users get, or
# <mariadb/mysql.h>).

SOURCE=system:mariadb
DEPENDS="libssl zlib"
PKGCONFIG=libmariadb
LINK="-lmariadb -lssl -lcrypto -lz"
LIB_PATTERNS="mariadb mariadbclient mysqlclient"
USE_CFLAGS="-I$SYSROOT/include/mariadb"

releases() {
  git_tag_releases https://github.com/mariadb-corporation/mariadb-connector-c.git v \
    'https://github.com/mariadb-corporation/mariadb-connector-c/archive/refs/tags/v{v}.tar.gz'
}

build() {
  command -v cmake >/dev/null || die "mariadb needs cmake"
  local p
  local plugins=
  for p in DIALOG CLIENT_ED25519 CACHING_SHA2_PASSWORD SHA256_PASSWORD PARSEC MYSQL_CLEAR_PASSWORD; do
    plugins="$plugins -DCLIENT_PLUGIN_$p=STATIC"
  done
  for p in AUTH_GSSAPI_CLIENT ZSTD REMOTE_IO PVIO_SHMEM; do plugins="$plugins -DCLIENT_PLUGIN_$p=OFF"; done
  log "cmake (emcmake)"
  # shellcheck disable=SC2086
  emcmake cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$SYSROOT" \
    -DCMAKE_C_FLAGS="$CFLAGS" -DWITH_UNIT_TESTS=OFF -DWITH_CURL=OFF -DWITH_ICONV=OFF \
    -DWITH_SSL=OPENSSL -DOPENSSL_ROOT_DIR="$SYSROOT" -DOPENSSL_INCLUDE_DIR="$SYSROOT/include" \
    -DOPENSSL_SSL_LIBRARY="$SYSROOT/lib/libssl.a" -DOPENSSL_CRYPTO_LIBRARY="$SYSROOT/lib/libcrypto.a" \
    -DWITH_EXTERNAL_ZLIB=ON -DZLIB_INCLUDE_DIR="$SYSROOT/include" -DZLIB_LIBRARY="$SYSROOT/lib/libz.a" \
    $plugins > cmake.log 2>&1 || { tail -30 cmake.log; die "cmake failed"; }
  log "make"
  # the static library only (libmariadb is the shared one)
  cmake --build build --target mariadbclient -j"$NPROC" > make.log 2>&1 || { tail -30 make.log; die "make failed"; }
  mkdir -p "$SYSROOT/include/mariadb/mysql" "$SYSROOT/include/mariadb/mariadb"
  cp include/mariadb_com.h include/mysql.h include/mariadb_stmt.h include/ma_pvio.h include/ma_tls.h \
    build/include/mariadb_version.h include/ma_list.h include/errmsg.h include/mariadb_dyncol.h \
    include/mariadb_ctype.h include/mariadb_rpl.h include/mysqld_error.h "$SYSROOT/include/mariadb/"
  cp include/mysql/client_plugin.h include/mysql/plugin_auth.h "$SYSROOT/include/mariadb/mysql/"
  cp include/mariadb/ma_io.h "$SYSROOT/include/mariadb/mariadb/"
  local a
  a=$(find build -name libmariadbclient.a | head -1)
  [ -n "$a" ] || die "no libmariadbclient.a"
  cp "$a" "$SYSROOT/lib/libmariadb.a"
  cp "$a" "$SYSROOT/lib/libmariadbclient.a"
  cp "$a" "$SYSROOT/lib/libmysqlclient.a"
  install_pc libmariadb "$SOURCE_VERSION" "-lmariadb -lssl -lcrypto -lz" '-I${includedir}/mariadb'
  install_pc mariadb "$SOURCE_VERSION" "-lmariadb -lssl -lcrypto -lz" '-I${includedir}/mariadb'
  provides mariadb mariadb mariadbclient mysqlclient
}
