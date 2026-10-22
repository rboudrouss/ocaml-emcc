# SQLite (conf-sqlite3), compiled from the amalgamation (sqlite3.c) of the
# autoconf tarball, without running its configure.  Single-threaded;
# extension loading is compiled in (for the API) but fails at run time: a
# static wasm program has no dlopen.

SOURCE=system:sqlite3
HEADER=sqlite3.h
VERSION_MACROS=SQLITE_VERSION
SQLITE_SITE=${SQLITE_SITE:-https://sqlite.org}
# the options of the usual distribution builds; a project recipe may change them
SQLITE_CFLAGS=${SQLITE_CFLAGS:-"-DSQLITE_THREADSAFE=0 -DSQLITE_ENABLE_FTS3 -DSQLITE_ENABLE_FTS3_PARENTHESIS -DSQLITE_ENABLE_FTS4 -DSQLITE_ENABLE_FTS5 -DSQLITE_ENABLE_RTREE -DSQLITE_ENABLE_GEOPOLY -DSQLITE_ENABLE_MATH_FUNCTIONS -DSQLITE_ENABLE_COLUMN_METADATA -DSQLITE_ENABLE_DBSTAT_VTAB -DSQLITE_SECURE_DELETE"}

# Tarballs are named after the version number (3.46.1 -> 3460100) and stored
# by year: both come from the release chronology.
releases() {
  curl -fsL "$SQLITE_SITE/chronology.html" | awk -v site="$SQLITE_SITE" '
    /timeline/ && match($0, /[12][0-9][0-9][0-9]-[01][0-9]-[0-3][0-9]/) { y = substr($0, RSTART, 4) }
    /releaselog/ && match($0, /data-sortkey=.[0-9]+/) {
      k = substr($0, RSTART + 14, RLENGTH - 14)
      if (match($0, />3[.0-9]*</) && y >= 2014)
        print substr($0, RSTART + 1, RLENGTH - 2), site "/" y "/sqlite-autoconf-" k ".tar.gz"
    }' | sort -V
}

build() {
  log "emcc sqlite3.c"
  # shellcheck disable=SC2086
  "$EMCC" $CFLAGS $SQLITE_CFLAGS -c sqlite3.c -o sqlite3.o
  mklib sqlite3 sqlite3.o
  install_lib libsqlite3.a
  install_headers . sqlite3.h sqlite3ext.h
  install_pc sqlite3 "$SOURCE_VERSION" -lsqlite3
  provides sqlite3 sqlite3
}
