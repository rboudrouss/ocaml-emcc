# FFmpeg (conf-ffmpeg): its libraries (avutil, avcodec, avformat, avfilter,
# avdevice, swscale, swresample), with the codecs, formats and filters it
# has itself.  Generic C (no assembly), without threads or networking, and
# no external libraries (--disable-autodetect).  The version is the one of
# the host's libavutil/ffversion.h (its libraries have their own versions).

SOURCE=system:ffmpeg
HEADER=libavutil/ffversion.h
VERSION_MACROS=FFMPEG_VERSION
RELEASES=https://ffmpeg.org/releases/
LINK="-lavdevice -lavfilter -lavformat -lavcodec -lswresample -lswscale -lavutil"
LIB_PATTERNS="avdevice avfilter avformat avcodec swresample swscale avutil"

build() {
  local arch=x86_32
  [ "$TARGET" = wasm64 ] && arch=x86_64
  log "configure"
  ./configure --prefix="$SYSROOT" --libdir="$SYSROOT/lib" --target-os=none --arch=$arch \
    --enable-cross-compile --disable-asm --disable-runtime-cpudetect --disable-autodetect \
    --disable-pthreads --disable-w32threads --disable-os2threads --disable-network \
    --disable-programs --disable-doc --disable-debug --disable-stripping \
    --enable-static --disable-shared \
    --cc="$EMCC" --cxx="$EMSDK_BIN/em++" --ar="$EMAR" --ranlib="$EMSDK_BIN/emranlib" \
    --nm="$EMSDK_BIN/emnm" --extra-cflags="$CFLAGS" --extra-ldflags="$CFLAGS" \
    > configure.log 2>&1 || { tail -30 configure.log; die "configure failed"; }
  log "make"
  make -j"$NPROC" > make.log 2>&1 || { tail -30 make.log; die "make failed"; }
  make install > install.log 2>&1 || { tail -30 install.log; die "install failed"; }
  provides ffmpeg avdevice avfilter avformat avcodec swresample swscale avutil
}
