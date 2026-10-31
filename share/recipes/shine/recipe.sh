# shine (conf-shine), the fixed-point MP3 encoder.

SOURCE=system:shine
LINK=-lshine

releases() {
  git_tag_releases https://github.com/toots/shine.git '' \
    'https://github.com/toots/shine/releases/download/{v}/shine-{v}.tar.gz'
}

build() {
  log "configure (emconfigure)"
  emconfigure ./configure --host=none --prefix="$SYSROOT" --enable-static --disable-shared \
    CFLAGS="$CFLAGS" > configure.log 2>&1 || { tail -30 configure.log; die "configure failed"; }
  log "make"
  emmake make -j"$NPROC" libshine.la > make.log 2>&1 || { tail -30 make.log; die "make failed"; }
  emmake make install-libLTLIBRARIES install-pkgconfigDATA install-libshine_laHEADERS > install.log 2>&1 \
    || { tail -30 install.log; die "install failed"; }
  provides shine shine
}
