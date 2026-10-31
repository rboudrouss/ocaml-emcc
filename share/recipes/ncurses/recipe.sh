# ncurses (conf-ncurses): the wide-character libraries (ncursesw, panelw,
# menuw, formw), with the headers where the host has them (no ncursesw/
# subdirectory).  No terminfo database of its own: it reads the host's
# (/usr/share/terminfo...) where the file system is the host's (node).
# Its programs need a stack of more than 64 KB (ocaml-emcc's is 8 MB).

SOURCE=system:ncurses
PKGCONFIG=ncursesw
HEADER=ncurses.h
VERSION_MACROS="NCURSES_VERSION_MAJOR NCURSES_VERSION_MINOR"
RELEASES=https://ftp.gnu.org/gnu/ncurses/
LINK=-lncursesw
LIB_PATTERNS="ncursesw panelw menuw formw"

build() {
  log "configure (emconfigure)"
  emconfigure ./configure --host="$TARGET-unknown-emscripten" --build="$(./config.guess)" \
    --prefix="$SYSROOT" --with-build-cc=cc --enable-widec --enable-overwrite --with-normal \
    --without-shared --without-debug --without-progs --without-tests --without-manpages \
    --without-cxx --without-cxx-binding --without-ada --without-dlsym --disable-db-install \
    --enable-pc-files --with-pkg-config-libdir="$SYSROOT/lib/pkgconfig" \
    --with-terminfo-dirs=/etc/terminfo:/lib/terminfo:/usr/share/terminfo \
    --with-default-terminfo-dir=/usr/share/terminfo CFLAGS="$CFLAGS" > configure.log 2>&1 \
    || { tail -30 configure.log; die "configure failed"; }
  log "make"
  emmake make -j"$NPROC" libs > make.log 2>&1 || { tail -30 make.log; die "make failed"; }
  emmake make install.libs > install.log 2>&1 || { tail -30 install.log; die "install failed"; }
  provides ncurses ncursesw panelw menuw formw
}
