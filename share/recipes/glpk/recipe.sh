# GLPK, the GNU Linear Programming Kit (the glpk bindings, which have no
# conf-glpk: found from their -lglpk).

SOURCE=system:glpk
HEADER=glpk.h
VERSION_MACROS="GLP_MAJOR_VERSION GLP_MINOR_VERSION"
RELEASES=https://ftp.gnu.org/gnu/glpk/
LINK=-lglpk

build() {
  log "configure (emconfigure)"
  emconfigure ./configure --host=none --prefix="$SYSROOT" --enable-static --disable-shared \
    CFLAGS="$CFLAGS" > configure.log 2>&1 || { tail -30 configure.log; die "configure failed"; }
  log "make"
  emmake make -C src -j"$NPROC" > make.log 2>&1 || { tail -30 make.log; die "make failed"; }
  make -C src install > install.log 2>&1 || { tail -30 install.log; die "make install failed"; }
  install_pc glpk "$SOURCE_VERSION" -lglpk
  provides glpk glpk
}
