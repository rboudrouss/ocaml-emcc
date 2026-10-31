# libmad (conf-mad), the MPEG audio decoder: 64-bit fixed point in C, no
# assembly.  Its configure turns -O2 into gcc-only flags (-fforce-mem...):
# make gets the C flags.  It has no pkg-config file (Debian adds mad.pc).

SOURCE=system:mad
HEADER=mad.h
VERSION_MACROS="MAD_VERSION_MAJOR MAD_VERSION_MINOR MAD_VERSION_PATCH"
COMPAT=latest
LINK=-lmad

releases() { echo "0.15.1 https://downloads.sourceforge.net/mad/libmad-0.15.1b.tar.gz"; }

build() {
  log "configure (emconfigure)"
  emconfigure ./configure --host=none --prefix="$SYSROOT" --enable-static --disable-shared \
    --disable-aso --enable-fpm=64bit > configure.log 2>&1 || { tail -30 configure.log; die "configure failed"; }
  log "make"
  emmake make -j"$NPROC" CFLAGS="$CFLAGS" install > make.log 2>&1 || { tail -30 make.log; die "make failed"; }
  install_pc mad "$SOURCE_VERSION" -lmad
  provides mad mad
}
