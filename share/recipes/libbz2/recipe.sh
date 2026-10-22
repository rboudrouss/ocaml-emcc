# libbz2, bzip2's library (conf-libbz2).

SOURCE=system:libbz2
PKGCONFIG=bzip2
HEADER=bzlib.h
TARBALL=bzip2
RELEASES=https://sourceware.org/pub/bzip2/
LINK=-lbz2

build() {
  log "make libbz2.a"
  emmake make libbz2.a CC="$EMCC" AR="$EMAR" RANLIB=true \
    CFLAGS="$CFLAGS -D_FILE_OFFSET_BITS=64" > make.log 2>&1 || { tail -30 make.log; die "make failed"; }
  install_lib libbz2.a
  install_headers . bzlib.h
  install_pc bzip2 "$SOURCE_VERSION" -lbz2
  provides libbz2 bz2
}
