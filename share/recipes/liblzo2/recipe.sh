# LZO 2 (liblzo2, for the lzo bindings' -llzo2), generic C.

SOURCE=system:liblzo2
PKGCONFIG=lzo2
HEADER=lzo/lzoconf.h
VERSION_MACROS=LZO_VERSION_STRING
RELEASES=https://www.oberhumer.com/opensource/lzo/download/
TARBALL=lzo
COMPAT=latest
LINK=-llzo2

build() {
  log "configure (emconfigure)"
  emconfigure ./configure --host=none --prefix="$SYSROOT" --enable-static --disable-shared --disable-asm \
    CFLAGS="$CFLAGS" > configure.log 2>&1 || { tail -30 configure.log; die "configure failed"; }
  log "make"
  emmake make -j"$NPROC" src/liblzo2.la > make.log 2>&1 || { tail -30 make.log; die "make failed"; }
  emmake make install-libLTLIBRARIES install-pkgincludeHEADERS install-pkgconfigDATA > install.log 2>&1 \
    || { tail -30 install.log; die "install failed"; }
  provides liblzo2 lzo2
}
