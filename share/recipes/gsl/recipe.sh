# GNU Scientific Library (conf-gsl), with its reference CBLAS (libgslcblas).

SOURCE=system:gsl
HEADER=gsl/gsl_version.h
VERSION_MACROS="GSL_MAJOR_VERSION GSL_MINOR_VERSION"
RELEASES=https://ftp.gnu.org/gnu/gsl/
LINK="-lgsl -lgslcblas"

build() {
  log "configure (emconfigure)"
  emconfigure ./configure --host=none --prefix="$SYSROOT" --enable-static --disable-shared \
    CFLAGS="$CFLAGS" > configure.log 2>&1 || { tail -30 configure.log; die "configure failed"; }
  log "make (a few minutes)"
  emmake make -j"$NPROC" > make.log 2>&1 || { tail -30 make.log; die "make failed"; }
  make install-exec install-data > install.log 2>&1 || { tail -30 install.log; die "make install failed"; }
  provides gsl gsl gslcblas
}
