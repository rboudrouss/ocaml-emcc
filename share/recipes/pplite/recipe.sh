# PPLite, the polyhedra library apron's PPLite domain wraps: C++, on top of
# the flint recipe (its integers) and gmp, thread-safe.  No opam package
# provides it (apron finds it on the host): with no host version, its newest
# release.  Its releases are tarballs in its git repository.
SOURCE=system:pplite
DEPENDS="flint gmp mpfr"
HEADER=pplite/pplite-config.h
VERSION_MACROS=PPLITE_PACKAGE_VERSION
LINK="-lpplite -lflint -lmpfr -lgmpxx -lgmp -sDEFAULT_TO_CXX=1"
releases() {
  git ls-remote --tags --refs https://github.com/ezaffanella/PPLite.git 2>/dev/null \
    | sed -n 's|.*refs/tags/pplite-\([0-9.]*\)-tag$|\1|p' | sort -V | while read -r v; do
        echo "$v https://raw.githubusercontent.com/ezaffanella/PPLite/pplite-$v-tag/releases/pplite-$v.tar.gz"
      done
}

build() {
  log "configure (emconfigure)"
  emconfigure ./configure --host=none --prefix="$SYSROOT" --enable-static --disable-shared \
    --disable-arch --enable-thread-safe --with-flint="$SYSROOT" --with-gmp="$SYSROOT" \
    CFLAGS="$CFLAGS" CXXFLAGS="$CXXFLAGS" > configure.log 2>&1 \
    || { tail -30 configure.log; die "configure failed"; }
  log "make (a few minutes)"
  emmake make -j"$NPROC" -C src > make.log 2>&1 || { tail -30 make.log; die "make failed"; }
  emmake make -C src install > install.log 2>&1 || { tail -30 install.log; die "install failed"; }
  # pplite-config.h, at the top of the build
  [ -f "$SYSROOT/include/pplite/pplite-config.h" ] || install_headers pplite pplite-config.h
  install_pc pplite "$SOURCE_VERSION" "-lpplite -lflint -lmpfr -lgmpxx -lgmp"
  provides pplite pplite
}
