# LZ4 (conf-liblz4), the library only.

SOURCE=system:liblz4
HEADER=lz4.h
VERSION_MACROS="LZ4_VERSION_MAJOR LZ4_VERSION_MINOR LZ4_VERSION_RELEASE"
TARBALL=lz4
LINK=-llz4

releases() {
  git_tag_releases https://github.com/lz4/lz4.git v \
    'https://github.com/lz4/lz4/releases/download/v{v}/lz4-{v}.tar.gz'
}

build() {
  log "make liblz4.a"
  emmake make -C lib -j"$NPROC" liblz4.a CC="$EMCC" AR="$EMAR" CFLAGS="$CFLAGS" > make.log 2>&1 \
    || { tail -30 make.log; die "make failed"; }
  install_lib lib/liblz4.a
  install_headers . lib/lz4.h lib/lz4hc.h lib/lz4frame.h
  install_pc liblz4 "$SOURCE_VERSION" -llz4
  provides liblz4 lz4
}
