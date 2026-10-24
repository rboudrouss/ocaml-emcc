# LMDB, the memory-mapped key-value store.  The lmdb bindings bundle it and
# only use a system one when they find it (pkg-config, or lmdb.h and
# liblmdb.a in /usr): this recipe is for the latter (their -llmdb).
# emscripten has no process-shared mutexes (ENOTSUP), and a file mapping
# is a copy, which LMDB's writes with pwrite do not reach: every
# environment is opened lock-free (MDB_NOLOCK; a wasm program is a single
# process) and written through the map (MDB_WRITEMAP).

SOURCE=system:liblmdb
PKGCONFIG=lmdb
HEADER=lmdb.h
VERSION_MACROS="MDB_VERSION_MAJOR MDB_VERSION_MINOR MDB_VERSION_PATCH"
TARBALL=lmdb
LINK=-llmdb

releases() {
  git_tag_releases https://github.com/LMDB/lmdb.git LMDB_ \
    'https://github.com/LMDB/lmdb/archive/refs/tags/LMDB_{v}.tar.gz'
}

build() {
  # the flags forced in mdb_env_open (the lmdb recipe applies it as well)
  apply_patches "$BASE_RECIPE_DIR/patches"
  cd libraries/liblmdb
  "$EMCC" $CFLAGS -c mdb.c -o mdb.o && "$EMCC" $CFLAGS -c midl.c -o midl.o || die "cannot compile liblmdb"
  mklib lmdb mdb.o midl.o
  install_lib liblmdb.a
  install_headers . lmdb.h
  install_pc lmdb "$SOURCE_VERSION" -llmdb
  provides liblmdb lmdb
}
