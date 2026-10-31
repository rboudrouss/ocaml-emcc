# libev (conf-libev), for lwt.unix: an lwt configured on the host with
# libev starts its libev engine (Lwt_engine), whose primitives then have to
# be there.  The poll backend: emscripten's epoll is an emulation of it
# (both busy-wait, timeouts are not supported).  Not its event.h (the
# libevent API).

SOURCE=system:libev
HEADER=ev.h
VERSION_MACROS="EV_VERSION_MAJOR EV_VERSION_MINOR"
RELEASES=http://dist.schmorp.de/libev/
LINK=-lev

build() {
  log "configure (emconfigure)"
  emconfigure ./configure --host=none --prefix="$SYSROOT" --enable-static --disable-shared \
    ac_cv_header_sys_epoll_h=no ac_cv_func_epoll_ctl=no \
    CFLAGS="$CFLAGS" > configure.log 2>&1 || { tail -30 configure.log; die "configure failed"; }
  log "make"
  emmake make -j"$NPROC" > make.log 2>&1 || { tail -30 make.log; die "make failed"; }
  install_lib .libs/libev.a
  install_headers . ev.h ev++.h
  install_pc libev "$SOURCE_VERSION" -lev
  provides libev ev
}
