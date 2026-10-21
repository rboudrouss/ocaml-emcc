# GNU MP (conf-gmp), generic C: no assembly.  See "system libraries" in
# driver.sh for how the version is chosen; gmp keeps source compatibility
# within a major version.

SOURCE=system:gmp
HEADER=gmp.h
VERSION_MACROS="__GNU_MP_VERSION __GNU_MP_VERSION_MINOR __GNU_MP_VERSION_PATCHLEVEL"
RELEASES=https://ftp.gnu.org/gnu/gmp/
OPAM_SOURCES=gmp

build() {
  log "configure (emconfigure)"
  emconfigure ./configure --host=none --disable-assembly --enable-static --disable-shared \
    --prefix="$SYSROOT" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" > configure.log 2>&1 \
    || { tail -30 configure.log; die "configure failed"; }
  log "make"
  emmake make -j"$NPROC" > make.log 2>&1 || { tail -30 make.log; die "make failed"; }
  make install > install.log 2>&1
  provides gmp gmp
}
