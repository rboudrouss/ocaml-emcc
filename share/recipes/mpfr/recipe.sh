# GNU MPFR (conf-mpfr), on top of the gmp recipe.

SOURCE=system:mpfr
DEPENDS=gmp
HEADER=mpfr.h
VERSION_MACROS="MPFR_VERSION_MAJOR MPFR_VERSION_MINOR MPFR_VERSION_PATCHLEVEL"
RELEASES=https://ftp.gnu.org/gnu/mpfr/

build() {
  log "configure (emconfigure)"
  emconfigure ./configure --host=none --enable-static --disable-shared --disable-thread-safe \
    --with-gmp="$SYSROOT" --prefix="$SYSROOT" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" > configure.log 2>&1 \
    || { tail -30 configure.log; die "configure failed"; }
  log "make"
  emmake make -j"$NPROC" -C src > make.log 2>&1 || { tail -30 make.log; die "make failed"; }
  make -C src install > install.log 2>&1
  provides mpfr mpfr
}
