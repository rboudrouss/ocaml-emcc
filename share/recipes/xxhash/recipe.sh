# xxHash (conf-xxhash), the hash functions, for the xxhash bindings: the
# library only (not xxhsum), without the x86 dispatch (no SIMD).
SOURCE=system:xxhash
PKGCONFIG=libxxhash
HEADER=xxhash.h
VERSION_MACROS="XXH_VERSION_MAJOR XXH_VERSION_MINOR XXH_VERSION_RELEASE"
LINK=-lxxhash
releases() {
  git_tag_releases https://github.com/Cyan4973/xxHash.git v \
    'https://github.com/Cyan4973/xxHash/archive/refs/tags/v{v}.tar.gz'
}

build() {
  log "make libxxhash.a"
  emmake make libxxhash.a CC="$EMCC" AR="$EMAR" CFLAGS="$CFLAGS" > make.log 2>&1 \
    || { tail -30 make.log; die "make failed"; }
  install_lib libxxhash.a
  install_headers . xxhash.h xxh3.h
  install_pc libxxhash "$SOURCE_VERSION" -lxxhash
  provides xxhash xxhash
}
