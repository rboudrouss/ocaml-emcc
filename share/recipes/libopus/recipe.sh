# libopus (conf-libopus), the Opus codec: fixed C (no intrinsics).

SOURCE=system:libopus
PKGCONFIG=opus
RELEASES=https://downloads.xiph.org/releases/opus/
TARBALL=opus
LINK=-lopus

build() {
  log "configure (emconfigure)"
  emconfigure ./configure --host=none --prefix="$SYSROOT" --enable-static --disable-shared \
    --disable-intrinsics --disable-rtcd --disable-asm --disable-doc --disable-extra-programs \
    --disable-stack-protector CFLAGS="$CFLAGS" > configure.log 2>&1 \
    || { tail -30 configure.log; die "configure failed"; }
  log "make"
  emmake make -j"$NPROC" install > make.log 2>&1 || { tail -30 make.log; die "make failed"; }
  provides libopus opus
}
