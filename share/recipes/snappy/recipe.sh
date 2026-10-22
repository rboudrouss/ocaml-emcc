# Snappy (conf-snappy), Google's compression library.  It is C++: its users
# link as C++ (libc++).  Built with -Werror, and its loops marked for
# vectorization are not vectorized without SIMD: that warning is off.

SOURCE=system:snappy
HEADER=snappy-stubs-public.h
VERSION_MACROS="SNAPPY_MAJOR SNAPPY_MINOR SNAPPY_PATCHLEVEL"
LINK="-lsnappy -sDEFAULT_TO_CXX=1"

releases() {
  git_tag_releases https://github.com/google/snappy.git '' \
    'https://github.com/google/snappy/archive/refs/tags/{v}.tar.gz'
}

build() {
  command -v cmake >/dev/null || die "snappy needs cmake"
  log "cmake (emcmake)"
  emcmake cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$SYSROOT" \
    -DCMAKE_C_FLAGS="$CFLAGS" -DCMAKE_CXX_FLAGS="$CXXFLAGS -Wno-pass-failed" -DBUILD_SHARED_LIBS=OFF \
    -DSNAPPY_BUILD_TESTS=OFF -DSNAPPY_BUILD_BENCHMARKS=OFF -DSNAPPY_INSTALL=ON \
    > cmake.log 2>&1 || { tail -30 cmake.log; die "cmake failed"; }
  log "make"
  cmake --build build -j"$NPROC" > make.log 2>&1 || { tail -30 make.log; die "make failed"; }
  cmake --install build > install.log 2>&1 || { tail -30 install.log; die "install failed"; }
  install_pc snappy "$SOURCE_VERSION" "-lsnappy"
  provides snappy snappy
}
