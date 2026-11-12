/* A module for owi, OCamlPro's symbolic execution engine for wasm
 * (`ocaml-emcc link --owi`).
 *
 * owi implements WASI's calls with no way to write the module's memory: these
 * definitions replace the WASI imports (wasm-ld prefers a definition), so the
 * module imports only owi's functions and proc_exit, whose code other than 0
 * owi reports as a bug (an uncaught exception, exit 2).  No files, no
 * arguments but argv[0], no environment; stdout is dropped (printing a
 * symbolic value would make it concrete), stderr goes to owi's print_char
 * (the message of an uncaught exception); the clock ticks at each reading,
 * random bytes are zeros. */

#include <stdint.h>
#include <string.h>
#include <wasi/api.h>

#define OWI(name) __attribute__((import_module("owi"), import_name(#name)))
#define UNUSED __attribute__((unused))

OWI(print_char) void owi_print_char(int32_t);

static const char argv0[] = "owi";

__wasi_errno_t __wasi_args_sizes_get(__wasi_size_t *argc, __wasi_size_t *size)
{ *argc = 1; *size = sizeof argv0; return 0; }
__wasi_errno_t __wasi_args_get(uint8_t **argv, uint8_t *buf)
{ memcpy(buf, argv0, sizeof argv0); argv[0] = buf; return 0; }
__wasi_errno_t __wasi_environ_sizes_get(__wasi_size_t *n, __wasi_size_t *size)
{ *n = 0; *size = 0; return 0; }
__wasi_errno_t __wasi_environ_get(uint8_t **env UNUSED, uint8_t *buf UNUSED)
{ return 0; }

__wasi_errno_t __wasi_fd_write(__wasi_fd_t fd, const __wasi_ciovec_t *iovs, size_t n, __wasi_size_t *written)
{
  if (fd > 2) return __WASI_ERRNO_BADF;
  size_t t = 0;
  for (size_t i = 0; i < n; i++) {
    if (fd == 2)
      for (size_t j = 0; j < iovs[i].buf_len; j++) owi_print_char(iovs[i].buf[j]);
    t += iovs[i].buf_len;
  }
  *written = t;
  return 0;
}
__wasi_errno_t __wasi_fd_read(__wasi_fd_t fd, const __wasi_iovec_t *iovs UNUSED, size_t n UNUSED, __wasi_size_t *nread)
{ if (fd > 2) return __WASI_ERRNO_BADF; *nread = 0; return 0; }
__wasi_errno_t __wasi_fd_pread(__wasi_fd_t fd UNUSED, const __wasi_iovec_t *iovs UNUSED, size_t n UNUSED,
                               __wasi_filesize_t off UNUSED, __wasi_size_t *nread UNUSED)
{ return __WASI_ERRNO_BADF; }
__wasi_errno_t __wasi_fd_pwrite(__wasi_fd_t fd UNUSED, const __wasi_ciovec_t *iovs UNUSED, size_t n UNUSED,
                                __wasi_filesize_t off UNUSED, __wasi_size_t *nw UNUSED)
{ return __WASI_ERRNO_BADF; }
__wasi_errno_t __wasi_fd_seek(__wasi_fd_t fd, __wasi_filedelta_t off UNUSED, __wasi_whence_t w UNUSED,
                              __wasi_filesize_t *pos UNUSED)
{ return fd <= 2 ? __WASI_ERRNO_SPIPE : __WASI_ERRNO_BADF; }
__wasi_errno_t __wasi_fd_close(__wasi_fd_t fd)
{ return fd <= 2 ? 0 : __WASI_ERRNO_BADF; }
__wasi_errno_t __wasi_fd_sync(__wasi_fd_t fd)
{ return fd <= 2 ? 0 : __WASI_ERRNO_BADF; }
__wasi_errno_t __wasi_fd_fdstat_get(__wasi_fd_t fd, __wasi_fdstat_t *st)
{
  if (fd > 2) return __WASI_ERRNO_BADF;
  memset(st, 0, sizeof *st);
  st->fs_filetype = __WASI_FILETYPE_CHARACTER_DEVICE;
  st->fs_rights_base = st->fs_rights_inheriting = ~(__wasi_rights_t)0;
  return 0;
}
__wasi_errno_t __wasi_fd_fdstat_set_flags(__wasi_fd_t fd UNUSED, __wasi_fdflags_t f UNUSED)
{ return __WASI_ERRNO_NOSYS; }
__wasi_errno_t __wasi_fd_filestat_get(__wasi_fd_t fd, __wasi_filestat_t *st)
{
  if (fd > 2) return __WASI_ERRNO_BADF;
  memset(st, 0, sizeof *st);
  st->filetype = __WASI_FILETYPE_CHARACTER_DEVICE;
  return 0;
}
__wasi_errno_t __wasi_fd_filestat_set_size(__wasi_fd_t fd UNUSED, __wasi_filesize_t s UNUSED)
{ return __WASI_ERRNO_BADF; }
__wasi_errno_t __wasi_fd_filestat_set_times(__wasi_fd_t fd UNUSED, __wasi_timestamp_t a UNUSED,
                                            __wasi_timestamp_t m UNUSED, __wasi_fstflags_t f UNUSED)
{ return __WASI_ERRNO_BADF; }
__wasi_errno_t __wasi_fd_prestat_get(__wasi_fd_t fd UNUSED, __wasi_prestat_t *p UNUSED)
{ return __WASI_ERRNO_BADF; }
__wasi_errno_t __wasi_fd_prestat_dir_name(__wasi_fd_t fd UNUSED, uint8_t *p UNUSED, __wasi_size_t n UNUSED)
{ return __WASI_ERRNO_BADF; }
__wasi_errno_t __wasi_fd_readdir(__wasi_fd_t fd UNUSED, uint8_t *buf UNUSED, __wasi_size_t len UNUSED,
                                 __wasi_dircookie_t cookie UNUSED, __wasi_size_t *used UNUSED)
{ return __WASI_ERRNO_BADF; }

/* no file system: no file is found */
__wasi_errno_t __wasi_path_open(__wasi_fd_t fd UNUSED, __wasi_lookupflags_t lf UNUSED, const char *path UNUSED,
                                size_t len UNUSED, __wasi_oflags_t of UNUSED, __wasi_rights_t rb UNUSED,
                                __wasi_rights_t ri UNUSED, __wasi_fdflags_t ff UNUSED, __wasi_fd_t *out UNUSED)
{ return __WASI_ERRNO_NOENT; }
__wasi_errno_t __wasi_path_filestat_get(__wasi_fd_t fd UNUSED, __wasi_lookupflags_t lf UNUSED,
                                        const char *path UNUSED, size_t len UNUSED, __wasi_filestat_t *st UNUSED)
{ return __WASI_ERRNO_NOENT; }
__wasi_errno_t __wasi_path_filestat_set_times(__wasi_fd_t fd UNUSED, __wasi_lookupflags_t lf UNUSED,
                                              const char *path UNUSED, size_t len UNUSED,
                                              __wasi_timestamp_t a UNUSED, __wasi_timestamp_t m UNUSED,
                                              __wasi_fstflags_t f UNUSED)
{ return __WASI_ERRNO_NOENT; }
__wasi_errno_t __wasi_path_readlink(__wasi_fd_t fd UNUSED, const char *path UNUSED, size_t len UNUSED,
                                    uint8_t *buf UNUSED, __wasi_size_t n UNUSED, __wasi_size_t *used UNUSED)
{ return __WASI_ERRNO_NOENT; }
__wasi_errno_t __wasi_path_unlink_file(__wasi_fd_t fd UNUSED, const char *path UNUSED, size_t len UNUSED)
{ return __WASI_ERRNO_NOENT; }
__wasi_errno_t __wasi_path_create_directory(__wasi_fd_t fd UNUSED, const char *path UNUSED, size_t len UNUSED)
{ return __WASI_ERRNO_NOENT; }
__wasi_errno_t __wasi_path_remove_directory(__wasi_fd_t fd UNUSED, const char *path UNUSED, size_t len UNUSED)
{ return __WASI_ERRNO_NOENT; }
__wasi_errno_t __wasi_path_rename(__wasi_fd_t fd UNUSED, const char *old UNUSED, size_t oldlen UNUSED,
                                  __wasi_fd_t fd2 UNUSED, const char *new UNUSED, size_t newlen UNUSED)
{ return __WASI_ERRNO_NOENT; }
__wasi_errno_t __wasi_path_symlink(const char *old UNUSED, size_t oldlen UNUSED, __wasi_fd_t fd UNUSED,
                                   const char *new UNUSED, size_t newlen UNUSED)
{ return __WASI_ERRNO_NOENT; }
__wasi_errno_t __wasi_path_link(__wasi_fd_t fd UNUSED, __wasi_lookupflags_t lf UNUSED, const char *old UNUSED,
                                size_t oldlen UNUSED, __wasi_fd_t fd2 UNUSED, const char *new UNUSED,
                                size_t newlen UNUSED)
{ return __WASI_ERRNO_NOENT; }

__wasi_errno_t __wasi_clock_time_get(__wasi_clockid_t id UNUSED, __wasi_timestamp_t prec UNUSED,
                                     __wasi_timestamp_t *t)
{ static __wasi_timestamp_t now = 1; *t = now++; return 0; }
__wasi_errno_t __wasi_clock_res_get(__wasi_clockid_t id UNUSED, __wasi_timestamp_t *res)
{ *res = 1; return 0; }
__wasi_errno_t __wasi_poll_oneoff(const __wasi_subscription_t *in UNUSED, __wasi_event_t *out UNUSED,
                                  __wasi_size_t n UNUSED, __wasi_size_t *ne UNUSED)
{ return __WASI_ERRNO_NOSYS; }
__wasi_errno_t __wasi_sched_yield(void)
{ return 0; }
__wasi_errno_t __wasi_random_get(uint8_t *buf, __wasi_size_t n)
{ memset(buf, 0, n); return 0; }
__wasi_errno_t __wasi_sock_accept(__wasi_fd_t fd UNUSED, __wasi_fdflags_t f UNUSED, __wasi_fd_t *out UNUSED)
{ return __WASI_ERRNO_BADF; }
__wasi_errno_t __wasi_sock_recv(__wasi_fd_t fd UNUSED, const __wasi_iovec_t *iovs UNUSED, size_t n UNUSED,
                                __wasi_riflags_t f UNUSED, __wasi_size_t *len UNUSED, __wasi_roflags_t *of UNUSED)
{ return __WASI_ERRNO_BADF; }
__wasi_errno_t __wasi_sock_send(__wasi_fd_t fd UNUSED, const __wasi_ciovec_t *iovs UNUSED, size_t n UNUSED,
                                __wasi_siflags_t f UNUSED, __wasi_size_t *len UNUSED)
{ return __WASI_ERRNO_BADF; }
__wasi_errno_t __wasi_sock_shutdown(__wasi_fd_t fd UNUSED, __wasi_sdflags_t how UNUSED)
{ return __WASI_ERRNO_BADF; }
