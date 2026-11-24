# LevelDB (conf-leveldb), Google's key-value store, for the leveldb
# bindings: C++, with Snappy compression as the host's (the snappy recipe:
# databases written natively are read), without crc32c or tcmalloc.  Its
# compactions run in a thread of their own: a program writing more than a
# memtable (4 MB by default) needs --threads.
SOURCE=system:leveldb
DEPENDS=snappy
LINK="-lleveldb -lsnappy -sDEFAULT_TO_CXX=1"
releases() {
  git_tag_releases https://github.com/google/leveldb.git '' \
    'https://github.com/google/leveldb/archive/refs/tags/{v}.tar.gz'
}

build() {
  command -v cmake >/dev/null || die "leveldb needs cmake"
  log "cmake (emcmake)"
  # (its checks of the optional libraries link a C program, which cannot
  # link the C++ snappy: given)
  emcmake cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$SYSROOT" \
    -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_C_FLAGS="$CFLAGS" -DCMAKE_CXX_FLAGS="$CXXFLAGS -I$SYSROOT/include" \
    -DBUILD_SHARED_LIBS=OFF -DLEVELDB_BUILD_TESTS=OFF -DLEVELDB_BUILD_BENCHMARKS=OFF -DLEVELDB_INSTALL=ON \
    -DHAVE_SNAPPY=1 -DHAVE_CRC32C=0 -DHAVE_TCMALLOC=0 > cmake.log 2>&1 \
    || { tail -30 cmake.log; die "cmake failed"; }
  log "make (the library: not leveldbutil)"
  cmake --build build --target leveldb -j"$NPROC" > make.log 2>&1 || { tail -30 make.log; die "make failed"; }
  cmake --install build > install.log 2>&1 || { tail -30 install.log; die "install failed"; }
  install_pc leveldb "$SOURCE_VERSION" "-lleveldb -lsnappy"
  provides leveldb leveldb
}
