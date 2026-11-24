# The Parma Polyhedra Library (conf-ppl), for apron's PPL domains (ppl,
# polkaGrid) and jasmin: its C++ library and C interface (libppl,
# libppl_c), on top of the gmp recipe (gmpxx), integer coefficients of GMP
# (mpz).  C++: its users link as C++.  Without its floating-point abstract
# domains (--disable-fpmath: they need control of the FPU rounding mode,
# which wasm lacks), nor its programs.
SOURCE=system:ppl
DEPENDS=gmp
HEADER=ppl.hh
VERSION_MACROS="PPL_VERSION_MAJOR PPL_VERSION_MINOR PPL_VERSION_REVISION"
# (bugseng.com, its home, refuses downloads: Sage's mirror of its releases)
RELEASES=https://mirrors.mit.edu/sage/spkg/upstream/ppl/
LINK="-lppl_c -lppl -lgmpxx -lgmp -sDEFAULT_TO_CXX=1"
LIB_PATTERNS="ppl ppl_c"

build() {
  apply_patches "$BASE_RECIPE_DIR/patches"
  log "configure (emconfigure)"
  emconfigure ./configure --host=none --prefix="$SYSROOT" --enable-static --disable-shared \
    --with-gmp="$SYSROOT" --enable-coefficients=mpz --disable-fpmath --enable-interfaces="c cxx" \
    --disable-ppl_lcdd --disable-ppl_lpsol --disable-ppl_pips --disable-documentation \
    CFLAGS="$CFLAGS" CXXFLAGS="$CXXFLAGS -std=c++11" > configure.log 2>&1 \
    || { tail -30 configure.log; die "configure failed"; }
  log "make (a few minutes)"
  emmake make -j"$NPROC" -C src > make.log 2>&1 || { tail -30 make.log; die "make failed"; }
  emmake make -j"$NPROC" -C interfaces > make-c.log 2>&1 || { tail -30 make-c.log; die "make (C interface) failed"; }
  make -C src install > install.log 2>&1 && make -C interfaces install >> install.log 2>&1 \
    || { tail -30 install.log; die "install failed"; }
  provides ppl ppl ppl_c
}
