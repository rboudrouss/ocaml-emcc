# Zstandard (conf-zstd), single-threaded, without the x86 assembly.

SOURCE=system:zstd
PKGCONFIG=libzstd
HEADER=zstd.h
VERSION_MACROS="ZSTD_VERSION_MAJOR ZSTD_VERSION_MINOR ZSTD_VERSION_RELEASE"
LINK=-lzstd

releases() {
  git_tag_releases https://github.com/facebook/zstd.git v \
    'https://github.com/facebook/zstd/releases/download/v{v}/zstd-{v}.tar.gz'
}

build() {
  log "make libzstd.a"
  emmake make -C lib -j"$NPROC" libzstd.a CC="$EMCC" AR="$EMAR" \
    CFLAGS="$CFLAGS" ZSTD_NO_ASM=1 ZSTD_LEGACY_SUPPORT=0 > make.log 2>&1 \
    || { tail -30 make.log; die "make failed"; }
  install_lib lib/libzstd.a
  install_headers . lib/zstd.h lib/zdict.h lib/zstd_errors.h
  install_pc libzstd "$SOURCE_VERSION" -lzstd
  provides zstd zstd
}
