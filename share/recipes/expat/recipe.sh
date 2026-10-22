# Expat (conf-expat), the XML parser.  Its entropy (hash salts) comes from
# getrandom, which emscripten has.

SOURCE=system:expat
HEADER=expat.h
VERSION_MACROS="XML_MAJOR_VERSION XML_MINOR_VERSION XML_MICRO_VERSION"
LINK=-lexpat

# tags R_2_7_1, release files expat-2.7.1.tar.xz
releases() {
  local v
  git ls-remote --tags --refs https://github.com/libexpat/libexpat.git 2>/dev/null \
    | sed -n 's|.*refs/tags/R_\([0-9]*\)_\([0-9]*\)_\([0-9]*\)$|\1.\2.\3|p' | sort -V \
    | while read -r v; do
        echo "$v https://github.com/libexpat/libexpat/releases/download/R_${v//./_}/expat-$v.tar.xz"
      done
}

build() {
  log "configure (emconfigure)"
  emconfigure ./configure --host=none --prefix="$SYSROOT" --enable-static --disable-shared \
    --without-docbook --without-examples --without-tests --without-xmlwf \
    CFLAGS="$CFLAGS" > configure.log 2>&1 || { tail -30 configure.log; die "configure failed"; }
  log "make"
  emmake make -C lib -j"$NPROC" > make.log 2>&1 || { tail -30 make.log; die "make failed"; }
  make -C lib install > install.log 2>&1 || { tail -30 install.log; die "make install failed"; }
  [ -f "$SYSROOT/lib/pkgconfig/expat.pc" ] || install_pc expat "$SOURCE_VERSION" -lexpat
  provides expat expat
}
