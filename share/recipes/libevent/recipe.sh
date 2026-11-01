# libevent (conf-libevent), without threads or OpenSSL; its backends: poll
# and select (emscripten's epoll is an emulation without timeouts).

SOURCE=system:libevent
HEADER=event2/event-config.h
VERSION_MACROS="EVENT__VERSION_MAJOR EVENT__VERSION_MINOR EVENT__VERSION_PATCH"
LINK=-levent
LIB_PATTERNS="event event_core event_extra"

releases() {
  local v
  git ls-remote --tags --refs https://github.com/libevent/libevent.git 2>/dev/null \
    | sed -n 's|.*refs/tags/release-\([0-9.]*\)-stable$|\1|p' | sort -V \
    | while read -r v; do
        echo "$v https://github.com/libevent/libevent/releases/download/release-$v-stable/libevent-$v-stable.tar.gz"
      done
}

build() {
  log "configure (emconfigure)"
  emconfigure ./configure --host=none --prefix="$SYSROOT" --enable-static --disable-shared \
    --disable-openssl --disable-thread-support --disable-samples --disable-libevent-regress \
    --disable-debug-mode ac_cv_header_sys_epoll_h=no ac_cv_func_epoll_ctl=no CFLAGS="$CFLAGS" \
    > configure.log 2>&1 || { tail -30 configure.log; die "configure failed"; }
  log "make"
  emmake make -j"$NPROC" install > make.log 2>&1 || { tail -30 make.log; die "make failed"; }
  provides libevent event event_core event_extra
}
