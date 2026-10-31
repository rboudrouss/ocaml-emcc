# libogg (conf-libogg), the Ogg container.

SOURCE=system:libogg
PKGCONFIG=ogg
RELEASES=https://downloads.xiph.org/releases/ogg/
LINK=-logg

build() {
  log "configure (emconfigure)"
  emconfigure ./configure --host=none --prefix="$SYSROOT" --enable-static --disable-shared \
    CFLAGS="$CFLAGS" > configure.log 2>&1 || { tail -30 configure.log; die "configure failed"; }
  log "make"
  emmake make -j"$NPROC" install > make.log 2>&1 || { tail -30 make.log; die "make failed"; }
  provides libogg ogg
}
