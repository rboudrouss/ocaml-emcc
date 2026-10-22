# PCRE2, 8-bit code units (conf-libpcre2-8), without the JIT.

SOURCE=system:libpcre2-8
HEADER=pcre2.h
VERSION_MACROS="PCRE2_MAJOR PCRE2_MINOR"
TARBALL=pcre2
LINK=-lpcre2-8

releases() {
  git_tag_releases https://github.com/PCRE2Project/pcre2.git pcre2- \
    'https://github.com/PCRE2Project/pcre2/releases/download/pcre2-{v}/pcre2-{v}.tar.bz2'
}

build() {
  log "configure (emconfigure)"
  emconfigure ./configure --host=none --prefix="$SYSROOT" --enable-static --disable-shared \
    --disable-jit --enable-pcre2-8 --disable-pcre2-16 --disable-pcre2-32 \
    CFLAGS="$CFLAGS" > configure.log 2>&1 || { tail -30 configure.log; die "configure failed"; }
  log "make"
  # the library only, not pcre2grep/pcre2test
  emmake make -j"$NPROC" libpcre2-8.la > make.log 2>&1 || { tail -30 make.log; die "make failed"; }
  make install-libLTLIBRARIES install-nodist_includeHEADERS install-pkgconfigDATA > install.log 2>&1 \
    || { tail -30 install.log; die "make install failed"; }
  provides libpcre2-8 pcre2-8
}
