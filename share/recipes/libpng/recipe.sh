# libpng (conf-libpng), on top of the zlib recipe.  No hardware
# optimizations (SIMD filters).

SOURCE=system:libpng
DEPENDS=zlib
HEADER=png.h
VERSION_MACROS="PNG_LIBPNG_VER_MAJOR PNG_LIBPNG_VER_MINOR PNG_LIBPNG_VER_RELEASE"
COMPAT=minor
LINK=-lpng16
LIB_PATTERNS="png png16"

releases() {
  git_tag_releases https://github.com/pnggroup/libpng.git v \
    'https://download.sourceforge.net/libpng/libpng-{v}.tar.xz'
}

build() {
  log "configure (emconfigure)"
  emconfigure ./configure --host=none --prefix="$SYSROOT" --enable-static --disable-shared \
    --disable-hardware-optimizations --disable-tools CFLAGS="$CFLAGS" \
    CPPFLAGS="-I$SYSROOT/include" LDFLAGS="$LDFLAGS -L$SYSROOT/lib" > configure.log 2>&1 \
    || { tail -30 configure.log; die "configure failed"; }
  log "make"
  emmake make -j"$NPROC" install > make.log 2>&1 || { tail -30 make.log; die "make failed"; }
  provides libpng png png16
}
