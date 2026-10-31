# libsecp256k1 (conf-secp256k1), with the modules Debian enables: recovery,
# ECDH, extrakeys, schnorrsig, ellswift and musig.  Its API changes between
# 0.x versions: the host's minor version.

SOURCE=system:secp256k1
PKGCONFIG=libsecp256k1
COMPAT=minor
LINK=-lsecp256k1

releases() {
  git_tag_releases https://github.com/bitcoin-core/secp256k1.git v \
    'https://github.com/bitcoin-core/secp256k1/archive/refs/tags/v{v}.tar.gz'
}

build() {
  command -v cmake >/dev/null || die "secp256k1 needs cmake"
  local m mods=
  for m in RECOVERY ECDH EXTRAKEYS SCHNORRSIG ELLSWIFT MUSIG; do mods+=" -DSECP256K1_ENABLE_MODULE_$m=ON"; done
  log "cmake (emcmake)"
  # shellcheck disable=SC2086
  emcmake cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$SYSROOT" \
    -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_C_FLAGS="$CFLAGS" -DBUILD_SHARED_LIBS=OFF \
    -DSECP256K1_BUILD_TESTS=OFF -DSECP256K1_BUILD_EXHAUSTIVE_TESTS=OFF -DSECP256K1_BUILD_BENCHMARK=OFF \
    -DSECP256K1_BUILD_CTIME_TESTS=OFF -DSECP256K1_BUILD_EXAMPLES=OFF -DSECP256K1_ASM=OFF $mods \
    > cmake.log 2>&1 || { tail -30 cmake.log; die "cmake failed"; }
  log "make"
  cmake --build build -j"$NPROC" > make.log 2>&1 || { tail -30 make.log; die "make failed"; }
  cmake --install build > install.log 2>&1 || { tail -30 install.log; die "install failed"; }
  provides secp256k1 secp256k1
}
