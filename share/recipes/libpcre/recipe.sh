# PCRE, the first one (conf-libpcre: the pcre bindings), 8-bit, with UTF-8
# and Unicode properties, without the JIT or the C++ wrapper.  8.45 is its
# last release (PCRE2 replaces it), from SourceForge.

SOURCE=system:libpcre
PKGCONFIG=libpcre
HEADER=pcre.h
VERSION_MACROS="PCRE_MAJOR PCRE_MINOR"
LINK=-lpcre
LIB_PATTERNS="pcre pcreposix"

releases() {
  echo "8.45 https://sourceforge.net/projects/pcre/files/pcre/8.45/pcre-8.45.tar.bz2/download"
}

build() {
  log "configure (emconfigure)"
  emconfigure ./configure --host=none --prefix="$SYSROOT" --enable-static --disable-shared \
    --disable-jit --disable-cpp --enable-utf --enable-unicode-properties \
    CFLAGS="$CFLAGS" > configure.log 2>&1 || { tail -30 configure.log; die "configure failed"; }
  log "make"
  emmake make -j"$NPROC" libpcre.la libpcreposix.la > make.log 2>&1 || { tail -30 make.log; die "make failed"; }
  make install-libLTLIBRARIES install-includeHEADERS install-nodist_includeHEADERS install-pkgconfigDATA \
    > install.log 2>&1 || { tail -30 install.log; die "make install failed"; }
  provides libpcre pcre pcreposix
}
