# LAME (conf-lame), the MP3 encoder: libmp3lame (with its mpglib decoder),
# no assembly.

SOURCE=system:lame
COMPAT=latest
LINK=-lmp3lame
LIB_PATTERNS=mp3lame

releases() { echo "3.100 https://downloads.sourceforge.net/lame/lame-3.100.tar.gz"; }

build() {
  log "configure (emconfigure)"
  emconfigure ./configure --host=none --prefix="$SYSROOT" --enable-static --disable-shared \
    --disable-frontend --disable-gtktest --disable-nasm CFLAGS="$CFLAGS" > configure.log 2>&1 \
    || { tail -30 configure.log; die "configure failed"; }
  log "make"
  { emmake make -j"$NPROC" -C mpglib && emmake make -j"$NPROC" -C libmp3lame; } > make.log 2>&1 \
    || { tail -30 make.log; die "make failed"; }
  emmake make -C libmp3lame install > install.log 2>&1 && emmake make -C include install >> install.log 2>&1 \
    || { tail -30 install.log; die "install failed"; }
  provides lame mp3lame
}
