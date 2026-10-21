# zlib (conf-zlib).

SOURCE=system:zlib
HEADER=zlib.h
VERSION_MACROS=ZLIB_VERSION
RELEASES=https://zlib.net/fossils/
LINK=-lz

build() {
  log "configure (emconfigure)"
  CFLAGS="$CFLAGS" emconfigure ./configure --static --prefix="$SYSROOT" > configure.log 2>&1 \
    || { tail -30 configure.log; die "configure failed"; }
  log "make"
  emmake make -j"$NPROC" libz.a > make.log 2>&1 || { tail -30 make.log; die "make failed"; }
  install_lib libz.a
  install_headers . zlib.h zconf.h
  provides zlib z
}
