# liblo (conf-liblo), Open Sound Control over UDP and TCP (emscripten's
# sockets: under node, through its WebSocket emulation).  Its server
# thread (lo_server_thread) needs a program linked with --threads.

SOURCE=system:liblo
PKGCONFIG=liblo
LINK=-llo
LIB_PATTERNS=lo

releases() {
  git_tag_releases https://github.com/radarsat1/liblo.git '' \
    'https://github.com/radarsat1/liblo/releases/download/{v}/liblo-{v}.tar.gz'
}

build() {
  log "configure (emconfigure)"
  emconfigure ./configure --host=none --prefix="$SYSROOT" --enable-static --disable-shared \
    --disable-tests --disable-examples --disable-network-tests --disable-doc \
    CFLAGS="$CFLAGS" > configure.log 2>&1 || { tail -30 configure.log; die "configure failed"; }
  log "make"
  emmake make -j"$NPROC" -C src liblo.la > make.log 2>&1 || { tail -30 make.log; die "make failed"; }
  emmake make -C src install-libLTLIBRARIES > install.log 2>&1 || { tail -30 install.log; die "install failed"; }
  emmake make -C lo install > install-h.log 2>&1 || { tail -30 install-h.log; die "install failed"; }
  emmake make install-pkgconfigDATA > install-pc.log 2>&1 || { tail -30 install-pc.log; die "install failed"; }
  provides liblo lo
}
