# The lmdb bindings: their C stubs, built with dune -x, and the copy of LMDB
# they bundle (used when there is no system one, see the liblmdb recipe)
# opened lock-free and written through the map on emscripten, as there.

SOURCE=opam:lmdb

build() {
  local f=liblmdb/libraries/liblmdb/mdb.c
  perl -0pi -e 's/(\nmdb_env_open\(MDB_env \*env, const char \*path, unsigned int flags, mdb_mode_t mode\)\n\{\n)/$1#ifdef __EMSCRIPTEN__\n\tflags |= MDB_NOLOCK | MDB_WRITEMAP; \/* ocaml-emcc *\/\n#endif\n/' "$f"
  grep -q 'MDB_NOLOCK | MDB_WRITEMAP; /\* ocaml-emcc' "$f" || die "$f: cannot force MDB_NOLOCK | MDB_WRITEMAP"
  dune_stubs lmdb
}
