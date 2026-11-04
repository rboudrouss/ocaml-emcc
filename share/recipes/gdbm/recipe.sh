# GNU dbm (the dbm bindings' -lgdbm, conf-dbm), without readline or NLS.

SOURCE=system:gdbm
HEADER=gdbm.h
VERSION_MACROS="GDBM_VERSION_MAJOR GDBM_VERSION_MINOR GDBM_VERSION_PATCH"
RELEASES=https://ftp.gnu.org/gnu/gdbm/
TARBALL=gdbm
LINK=-lgdbm

build() {
  log "configure (emconfigure)"
  emconfigure ./configure --host=none --prefix="$SYSROOT" --enable-static --disable-shared \
    --without-readline --disable-nls CFLAGS="$CFLAGS" > configure.log 2>&1 \
    || { tail -30 configure.log; die "configure failed"; }
  log "make"
  emmake make -j"$NPROC" -C src libgdbm.la > make.log 2>&1 || { tail -30 make.log; die "make failed"; }
  emmake make -C src install-libLTLIBRARIES install-nodist_includeHEADERS > install.log 2>&1 \
    || { tail -30 install.log; die "install failed"; }
  provides gdbm gdbm
}
