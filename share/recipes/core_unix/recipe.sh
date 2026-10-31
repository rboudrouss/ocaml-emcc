# core_unix: the C stubs, built with dune -x once they know emscripten
# (patches/).  The configuration (JSC_* macros, GET_THREAD_ID) is that of
# jst-config on the host, as for the OCaml side built natively: the stubs
# keep the primitives it declares, and those emscripten cannot do fail with
# ENOSYS, as its unsupported syscalls do:
# - gettid: GET_THREAD_ID is syscall(SYS_gettid) on Linux; emscripten has
#   no syscall(), but gettid() (_GNU_SOURCE);
# - linux_ext: prctl, sendfile, timerfd, eventfd, memfd, affinities,
#   sysinfo, xattrs; core_unix: initgroups, getgrouplist, wordexp;
#   core_thread: the pthread affinities;
# - the time stamp counter (rdtsc) is the high resolution clock
#   (performance.now, in ns);
# - error-checking mutexes: emscripten's libc has the mutexes of a single
#   thread, without _POSIX_THREADS.

SOURCE=opam:core_unix

build() {
  apply_patches "$BASE_RECIPE_DIR/patches"
  dune_stubs core_unix
}
