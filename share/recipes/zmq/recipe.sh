# ZeroMQ (conf-zmq: libzmq), C++ linked with libc++, without CURVE
# (libsodium) or the draft API; its poller: poll.  Configured for a Linux
# host (its configure refuses others), the emscripten compiler and libc
# answering the checks.

SOURCE=system:zmq
PKGCONFIG=libzmq
HEADER=zmq.h
VERSION_MACROS="ZMQ_VERSION_MAJOR ZMQ_VERSION_MINOR ZMQ_VERSION_PATCH"
LINK="-lzmq -sDEFAULT_TO_CXX=1"
LIB_PATTERNS=zmq

releases() {
  git_tag_releases https://github.com/zeromq/libzmq.git v \
    'https://github.com/zeromq/libzmq/releases/download/v{v}/zeromq-{v}.tar.gz'
}

build() {
  log "configure (emconfigure)"
  emconfigure ./configure --host=x86_64-unknown-linux-gnu --build=x86_64-pc-linux-gnu --prefix="$SYSROOT" \
    --enable-static --disable-shared --without-libsodium --disable-curve --with-poller=poll \
    --disable-Werror --without-docs --disable-drafts --disable-libbsd --disable-libunwind --disable-perf \
    --disable-eventfd CFLAGS="$CFLAGS" CXXFLAGS="$CXXFLAGS" > configure.log 2>&1 \
    || { tail -30 configure.log; die "configure failed"; }
  log "make"
  emmake make -j"$NPROC" src/libzmq.la > make.log 2>&1 || { tail -30 make.log; die "make failed"; }
  emmake make install-libLTLIBRARIES install-includeHEADERS install-pkgconfigDATA > install.log 2>&1 \
    || { tail -30 install.log; die "install failed"; }
  provides zmq zmq
}
