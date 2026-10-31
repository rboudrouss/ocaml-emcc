# lwt: the C stubs of lwt.unix, built with dune -x.  Blocking calls
# (Lwt_unix file operations, Lwt_io.with_file...) are "jobs" run by a pool
# of POSIX threads; without pthreads, lwt_unix_start_job raises
# Unix_error (EOPNOTSUPP, "launch_thread").  They run synchronously instead,
# as lwt does when its pool is full (Async_none).  Lwt_preemptive (OCaml
# threads) still fails.  The libev recipe is built first when conf-libev is
# installed: the host's lwt then uses libev, and starts its libev engine.

SOURCE=opam:lwt

build() {
  apply_patches "$BASE_RECIPE_DIR/patches"
  dune_stubs lwt
}
