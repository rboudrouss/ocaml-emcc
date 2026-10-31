# libjpeg (conf-libjpeg): libjpeg-turbo's libjpeg (its jpeg62 API, as
# Debian's), without SIMD or TurboJPEG.

SOURCE=system:libjpeg
HEADER=jconfig.h
VERSION_MACROS=LIBJPEG_TURBO_VERSION
COMPAT=latest
LINK=-ljpeg
LIB_PATTERNS=jpeg

releases() {
  git_tag_releases https://github.com/libjpeg-turbo/libjpeg-turbo.git '' \
    'https://github.com/libjpeg-turbo/libjpeg-turbo/releases/download/{v}/libjpeg-turbo-{v}.tar.gz'
}

build() {
  command -v cmake >/dev/null || die "libjpeg needs cmake"
  log "cmake (emcmake)"
  emcmake cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$SYSROOT" \
    -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_C_FLAGS="$CFLAGS" -DENABLE_SHARED=OFF -DENABLE_STATIC=ON \
    -DWITH_SIMD=OFF -DWITH_TURBOJPEG=OFF -DWITH_TOOLS=OFF -DWITH_TESTS=OFF \
    > cmake.log 2>&1 || { tail -30 cmake.log; die "cmake failed"; }
  log "make"
  cmake --build build -j"$NPROC" > make.log 2>&1 || { tail -30 make.log; die "make failed"; }
  cmake --install build > install.log 2>&1 || { tail -30 install.log; die "install failed"; }
  provides libjpeg jpeg
}
