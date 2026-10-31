# Oniguruma (conf-oniguruma), the regular expression library.

SOURCE=system:oniguruma
HEADER=oniguruma.h
VERSION_MACROS="ONIGURUMA_VERSION_MAJOR ONIGURUMA_VERSION_MINOR ONIGURUMA_VERSION_TEENY"
LINK=-lonig

releases() {
  git_tag_releases https://github.com/kkos/oniguruma.git v \
    'https://github.com/kkos/oniguruma/releases/download/v{v}/onig-{v}.tar.gz'
}

build() {
  log "configure (emconfigure)"
  emconfigure ./configure --host=none --prefix="$SYSROOT" --enable-static --disable-shared \
    CFLAGS="$CFLAGS" > configure.log 2>&1 || { tail -30 configure.log; die "configure failed"; }
  log "make"
  emmake make -j"$NPROC" -C src install > make.log 2>&1 || { tail -30 make.log; die "make failed"; }
  install_pc oniguruma "$SOURCE_VERSION" -lonig
  provides oniguruma onig
}
