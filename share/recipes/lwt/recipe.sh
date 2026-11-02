# lwt: the C stubs of lwt.unix, built with dune -x.  Blocking calls
# (Lwt_unix file operations, Lwt_io.with_file...) are "jobs" run by a pool
# of POSIX threads, which a program linked without threads (--threads)
# cannot start: lwt_unix_start_job would raise Unix_error (EOPNOTSUPP,
# "launch_thread").  They run synchronously there instead, as lwt does
# when its pool is full (Async_none), and Lwt_preemptive fails.  The libev recipe is built first when conf-libev is
# installed: the host's lwt then uses libev, and starts its libev engine.

SOURCE=opam:lwt

build() {
  apply_patches "$BASE_RECIPE_DIR/patches"
  dune_stubs lwt
}
