# FFTW 3 (conf-fftw3), double (libfftw3) and single precision (libfftw3f),
# without threads, SIMD or Fortran.

SOURCE=system:fftw3
PKGCONFIG=fftw3
TARBALL=fftw
RELEASES=https://www.fftw.org/pub/fftw/
COMPAT=minor
LINK="-lfftw3 -lfftw3f"

build() {
  local prec
  for prec in double float; do
    log "configure, $prec (emconfigure)"
    make distclean > /dev/null 2>&1 || true
    emconfigure ./configure --host=none --prefix="$SYSROOT" --enable-static --disable-shared \
      --disable-fortran --disable-threads --disable-doc $([ $prec = float ] && echo --enable-float) \
      CFLAGS="$CFLAGS" > "configure-$prec.log" 2>&1 || { tail -30 "configure-$prec.log"; die "configure failed"; }
    log "make, $prec (a few minutes)"
    emmake make -j"$NPROC" > "make-$prec.log" 2>&1 || { tail -30 "make-$prec.log"; die "make failed"; }
    make install > "install-$prec.log" 2>&1 || { tail -30 "install-$prec.log"; die "make install failed"; }
  done
  provides fftw3 fftw3 fftw3f
}
