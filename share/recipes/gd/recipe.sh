# libgd (conf-gd), with PNG, JPEG and FreeType, on top of their recipes; no
# fontconfig, XPM, TIFF, WebP, AVIF or HEIF.  Its configure finds them with
# the sysroot's pkg-config files (emconfigure sets PKG_CONFIG_LIBDIR to
# emscripten's: EM_PKG_CONFIG_PATH).

SOURCE=system:gd
DEPENDS="libpng libjpeg freetype zlib"
PKGCONFIG=gdlib
HEADER=gd.h
VERSION_MACROS="GD_MAJOR_VERSION GD_MINOR_VERSION GD_RELEASE_VERSION"
TARBALL=libgd
LINK=-lgd

releases() {
  git_tag_releases https://github.com/libgd/libgd.git gd- \
    'https://github.com/libgd/libgd/releases/download/gd-{v}/libgd-{v}.tar.xz'
}

build() {
  log "configure (emconfigure)"
  EM_PKG_CONFIG_PATH=$SYSROOT/lib/pkgconfig emconfigure ./configure --host=none --prefix="$SYSROOT" \
    --enable-static --disable-shared --with-png --with-jpeg --with-freetype --with-zlib \
    --without-fontconfig --without-xpm --without-tiff --without-webp --without-avif --without-heif \
    --without-raqm --without-liq --without-x CFLAGS="$CFLAGS" CPPFLAGS="-I$SYSROOT/include" \
    LDFLAGS="$LDFLAGS -L$SYSROOT/lib" > configure.log 2>&1 || { tail -30 configure.log; die "configure failed"; }
  log "make"
  emmake make -j"$NPROC" -C src libgd.la > make.log 2>&1 || { tail -30 make.log; die "make failed"; }
  emmake make -C src install-libLTLIBRARIES install-includeHEADERS > install.log 2>&1 \
    || { tail -30 install.log; die "install failed"; }
  install_pc gdlib "$SOURCE_VERSION" "-lgd -lpng16 -ljpeg -lfreetype -lz"
  provides gd gd
}
