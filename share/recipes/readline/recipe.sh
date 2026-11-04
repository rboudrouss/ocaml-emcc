# GNU readline (conf-readline), with ncurses (its recipe) for the terminal.

SOURCE=system:readline
DEPENDS=ncurses
PKGCONFIG=readline
HEADER=readline/readline.h
VERSION_MACROS="RL_VERSION_MAJOR RL_VERSION_MINOR"
RELEASES=https://ftp.gnu.org/gnu/readline/
LINK="-lreadline -lhistory"

build() {
  log "configure (emconfigure)"
  emconfigure ./configure --host=none --prefix="$SYSROOT" --enable-static --disable-shared \
    --with-curses --disable-install-examples bash_cv_signal_vintage=posix CFLAGS="$CFLAGS" CPPFLAGS="-I$SYSROOT/include" \
    LDFLAGS="$LDFLAGS -L$SYSROOT/lib" > configure.log 2>&1 || { tail -30 configure.log; die "configure failed"; }
  log "make"
  emmake make -j"$NPROC" static > make.log 2>&1 || { tail -30 make.log; die "make failed"; }
  emmake make install-static install-headers > install.log 2>&1 || { tail -30 install.log; die "install failed"; }
  install_pc readline "$SOURCE_VERSION" "-lreadline -lhistory -lncursesw"
  provides readline readline history
}
