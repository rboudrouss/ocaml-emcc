# FAAD2 (conf-faad), the AAC decoder.

SOURCE=system:faad
PKGCONFIG=faad2
LINK=-lfaad

releases() {
  git_tag_releases https://github.com/knik0/faad2.git '' \
    'https://github.com/knik0/faad2/archive/refs/tags/{v}.tar.gz'
}

build() {
  command -v cmake >/dev/null || die "faad needs cmake"
  log "cmake (emcmake)"
  emcmake cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$SYSROOT" \
    -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_C_FLAGS="$CFLAGS" -DBUILD_SHARED_LIBS=OFF -DFAAD_BUILD_CLI=OFF \
    > cmake.log 2>&1 || { tail -30 cmake.log; die "cmake failed"; }
  log "make"
  cmake --build build -j"$NPROC" > make.log 2>&1 || { tail -30 make.log; die "make failed"; }
  cmake --install build > install.log 2>&1 || { tail -30 install.log; die "install failed"; }
  provides faad faad
}
