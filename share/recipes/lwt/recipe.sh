# lwt: the C stubs of lwt.unix, built with dune -x.  Blocking calls
# (Lwt_unix file operations, Lwt_io.with_file...) are "jobs" run by a pool
# of POSIX threads; without pthreads, lwt_unix_start_job raises
# Unix_error (EOPNOTSUPP, "launch_thread").  They run synchronously instead,
# as lwt does when its pool is full (Async_none).  Lwt_preemptive (OCaml
# threads) still fails.  libev is not used: dune-configurator does not find
# it for wasm, the select engine is the default.

SOURCE=opam:lwt

build() {
  perl -0pi -e 's/(\n  int done = 0;\n)/$1\n#if defined(__EMSCRIPTEN__) \&\& !defined(__EMSCRIPTEN_PTHREADS__)\n  async_method = LWT_UNIX_ASYNC_METHOD_NONE; \/* no threads (ocaml-emcc) *\/\n#endif\n/' \
    src/unix/lwt_unix_stubs.c
  grep -q __EMSCRIPTEN_PTHREADS__ src/unix/lwt_unix_stubs.c || die "lwt_unix_stubs.c: cannot run the jobs synchronously"
  dune_stubs lwt
}
