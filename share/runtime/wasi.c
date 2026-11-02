/* The system calls of emscripten's libc that a WASI host lacks, on WASI
 * preview1 (`ocaml-emcc link --wasi`).
 *
 * In standalone mode, emscripten's libc reads, writes, seeks and closes
 * files with WASI calls, but opening and stat'ing a file are weak stubs
 * failing with EPERM or ENOSYS (system/lib/standalone/standalone.c), and the
 * other calls (unlink, rename, getcwd, readdir...) are imports of
 * emscripten's JavaScript.  These definitions replace both: paths are
 * resolved against the directories the host preopens, as wasi-libc does,
 * pipes are buffers in memory, and what WASI has no notion of (users,
 * sockets, a shell) fails or is a no-op.  A function the program's libraries define themselves is left out
 * by `link` (renamed at compile time), so theirs is used. */

#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <netdb.h>
#include <poll.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <sys/uio.h>
#include <unistd.h>
#include <wasi/api.h>
#include <emscripten/syscalls.h>
#include <emscripten/threading.h>

/* ----------------------------------------------------------------- paths */

#define MAX_PREOPENS 64
static struct { char *name; int fd; } preopens[MAX_PREOPENS];
static int npreopens = -1;
static char cwd[PATH_MAX] = "/";

/* "/tmp/" -> "tmp", "." -> "", "./a" -> "a" */
static void strip_name(char *s)
{
  char *p = s;
  for (;;) {
    if (*p == '/') p++;
    else if (p[0] == '.' && (p[1] == '/' || p[1] == 0)) p++;
    else break;
  }
  memmove(s, p, strlen(p) + 1);
  size_t n = strlen(s);
  while (n > 0 && s[n - 1] == '/') s[--n] = 0;
}

/* The preopened directories, fd 3 and up (the host numbers them so). */
static void load_preopens(void)
{
  if (npreopens >= 0) return;
  npreopens = 0;
  for (int fd = 3; npreopens < MAX_PREOPENS; fd++) {
    __wasi_prestat_t ps;
    if (__wasi_fd_prestat_get(fd, &ps) != 0) break;
    if (ps.pr_type != __WASI_PREOPENTYPE_DIR) continue;
    char *name = malloc(ps.u.dir.pr_name_len + 1);
    if (!name) break;
    if (__wasi_fd_prestat_dir_name(fd, (uint8_t *)name, ps.u.dir.pr_name_len) != 0) {
      free(name);
      break;
    }
    name[ps.u.dir.pr_name_len] = 0;
    strip_name(name);
    preopens[npreopens].name = name;
    preopens[npreopens].fd = fd;
    npreopens++;
  }
}

/* PATH (relative to the current directory) -> absolute, without "." and
   "..", in OUT (PATH_MAX bytes). */
static int absolute(const char *path, char *out)
{
  char in[PATH_MAX];
  if (path[0] == '/') {
    if (strlen(path) >= PATH_MAX) return -ENAMETOOLONG;
    strcpy(in, path);
  } else {
    if (strlen(cwd) + 1 + strlen(path) >= PATH_MAX) return -ENAMETOOLONG;
    strcpy(in, cwd);
    strcat(in, "/");
    strcat(in, path);
  }
  size_t n = 0;
  const char *p = in;
  while (*p) {
    while (*p == '/') p++;
    const char *q = p;
    while (*q && *q != '/') q++;
    size_t len = q - p;
    if (len == 0 || (len == 1 && p[0] == '.')) {
      /* nothing */
    } else if (len == 2 && p[0] == '.' && p[1] == '.') {
      while (n > 0 && out[n - 1] != '/') n--;
      if (n > 0) n--;
    } else {
      out[n++] = '/';
      memcpy(out + n, p, len);
      n += len;
    }
    p = q;
  }
  if (n == 0) out[n++] = '/';
  out[n] = 0;
  return 0;
}

/* PATH relative to DIRFD -> a directory descriptor and a path relative to
   it, in REL (PATH_MAX bytes): the preopened directory with the longest
   name prefixing the absolute path ("." and "/" prefix everything).
   Returns the descriptor or -errno. */
static int resolve(int dirfd, const char *path, char *rel)
{
  if (!path || !*path) return -ENOENT;
  if (path[0] != '/' && dirfd != AT_FDCWD) {
    if (strlen(path) >= PATH_MAX) return -ENAMETOOLONG;
    strcpy(rel, path);
    return dirfd;
  }
  char abs[PATH_MAX];
  int r = absolute(path, abs);
  if (r) return r;
  load_preopens();
  const char *a = abs + 1;
  int best = -1;
  size_t best_len = 0;
  for (int i = 0; i < npreopens; i++) {
    const char *name = preopens[i].name;
    size_t len = strlen(name);
    if ((len == 0 || (strncmp(a, name, len) == 0 && (a[len] == '/' || a[len] == 0)))
        && (best < 0 || len > best_len)) {
      best = i;
      best_len = len;
    }
  }
  if (best < 0) return -ENOENT;
  const char *s = a + best_len;
  while (*s == '/') s++;
  strcpy(rel, *s ? s : ".");
  return preopens[best].fd;
}

#define RESOLVE(dirfd, path, rel)               \
  char rel[PATH_MAX];                           \
  int rel##_fd = resolve((dirfd), (path), rel); \
  if (rel##_fd < 0) return rel##_fd

/* ------------------------------------------------------------ open, stat */

/* What each descriptor opened here was opened from, to duplicate it (WASI
   has no dup), and fd_readdir's position in each directory being read. */
#define MAX_FD 1024
static struct { int dirfd; char *rel; int flags; __wasi_dircookie_t cookie; } opened[MAX_FD];

static int open_rel(int dirfd, const char *rel, int flags)
{
  __wasi_oflags_t oflags = 0;
  if (flags & O_CREAT) oflags |= __WASI_OFLAGS_CREAT;
  if (flags & O_DIRECTORY) oflags |= __WASI_OFLAGS_DIRECTORY;
  if (flags & O_EXCL) oflags |= __WASI_OFLAGS_EXCL;
  if (flags & O_TRUNC) oflags |= __WASI_OFLAGS_TRUNC;
  __wasi_fdflags_t fdflags = 0;
  if (flags & O_APPEND) fdflags |= __WASI_FDFLAGS_APPEND;
  if (flags & O_NONBLOCK) fdflags |= __WASI_FDFLAGS_NONBLOCK;
  if ((flags & O_SYNC) == O_SYNC) fdflags |= __WASI_FDFLAGS_SYNC;
  else if (flags & O_DSYNC) fdflags |= __WASI_FDFLAGS_DSYNC;
  /* As wasi-libc: every right but those the access mode excludes, within
     what the directory hands down (a directory asked for FD_WRITE is
     EISDIR). */
  __wasi_rights_t base = ~(__WASI_RIGHTS_FD_DATASYNC | __WASI_RIGHTS_FD_READ | __WASI_RIGHTS_FD_WRITE
                           | __WASI_RIGHTS_FD_ALLOCATE | __WASI_RIGHTS_FD_READDIR
                           | __WASI_RIGHTS_FD_FILESTAT_SET_SIZE);
  int acc = flags & O_ACCMODE;
  if (acc == O_RDONLY || acc == O_RDWR) base |= __WASI_RIGHTS_FD_READ | __WASI_RIGHTS_FD_READDIR;
  if (acc == O_WRONLY || acc == O_RDWR)
    base |= __WASI_RIGHTS_FD_DATASYNC | __WASI_RIGHTS_FD_WRITE | __WASI_RIGHTS_FD_ALLOCATE
          | __WASI_RIGHTS_FD_FILESTAT_SET_SIZE;
  __wasi_rights_t inheriting = ~(__wasi_rights_t)0;
  __wasi_fdstat_t dir;
  if (__wasi_fd_fdstat_get(dirfd, &dir) == 0) {
    inheriting = dir.fs_rights_inheriting;
    base &= inheriting;
  }
  __wasi_lookupflags_t look = (flags & O_NOFOLLOW) ? 0 : __WASI_LOOKUPFLAGS_SYMLINK_FOLLOW;
  __wasi_fd_t fd;
  __wasi_errno_t e = __wasi_path_open(dirfd, look, rel, strlen(rel), oflags, base, inheriting, fdflags, &fd);
  if (e) return -e;
  if (fd < MAX_FD) {
    free(opened[fd].rel);
    opened[fd].dirfd = dirfd;
    opened[fd].rel = strdup(rel);
    opened[fd].flags = flags & ~(O_CREAT | O_EXCL | O_TRUNC);
    opened[fd].cookie = 0;
  }
  return fd;
}

/* ----------------------------------------------------------------- pipes */

/* WASI has none: a pipe is a buffer between descriptors of the program
   (the wake-up pipes of Async and lwt, which only the program reads).
   Each end is a descriptor of the host, a preopened directory opened
   again, so that the host gives its number to no other file; reading,
   writing, polling and closing it use the buffer.  Reading an empty pipe
   whose write end is open fails with EAGAIN even when blocking, unless the
   program has threads (--threads): it then waits for another thread to
   write, as poll does.  The pipes are shared by the threads: pipe_lock. */
struct pipe { char *buf; size_t len, cap; int ends; /* 1: read end open, 2: write end */ };
static struct { struct pipe *p; int write_end; int flags; } pipes[MAX_FD];
static pthread_mutex_t pipe_lock = PTHREAD_MUTEX_INITIALIZER;
/* broadcast when a pipe is written or an end closed */
static pthread_cond_t pipe_changed = PTHREAD_COND_INITIALIZER;

static int is_pipe(int fd) { return fd >= 0 && fd < MAX_FD && pipes[fd].p; }

int __syscall_pipe2(int fd[2], int flags)
{
  load_preopens();
  if (npreopens == 0) return -ENOSYS;
  int ends[2];
  for (int i = 0; i < 2; i++) {
    ends[i] = open_rel(preopens[0].fd, ".", O_RDONLY | O_DIRECTORY);
    if (ends[i] >= 0 && ends[i] >= MAX_FD) {
      (void)__wasi_fd_close(ends[i]);
      ends[i] = -EMFILE;
    }
    if (ends[i] < 0) {
      if (i == 1) (void)__wasi_fd_close(ends[0]);
      return ends[i];
    }
    free(opened[ends[i]].rel);
    opened[ends[i]].rel = NULL;
  }
  struct pipe *p = calloc(1, sizeof *p);
  if (!p) {
    (void)__wasi_fd_close(ends[0]);
    (void)__wasi_fd_close(ends[1]);
    return -ENOMEM;
  }
  p->ends = 3;
  pthread_mutex_lock(&pipe_lock);
  for (int i = 0; i < 2; i++) {
    pipes[ends[i]].p = p;
    pipes[ends[i]].write_end = i;
    pipes[ends[i]].flags = (i ? O_WRONLY : O_RDONLY) | (flags & O_NONBLOCK);
    fd[i] = ends[i];
  }
  pthread_mutex_unlock(&pipe_lock);
  return 0;
}

static ssize_t pipe_read_locked(int fd, const struct iovec *iov, int count)
{
  struct pipe *p = pipes[fd].p;
  if (pipes[fd].write_end) { errno = EBADF; return -1; }
  while (p->len == 0 && (p->ends & 2) && !(pipes[fd].flags & O_NONBLOCK) && emscripten_has_threading_support())
    pthread_cond_wait(&pipe_changed, &pipe_lock);
  if (p->len == 0) {
    if (p->ends & 2) { errno = EAGAIN; return -1; }
    return 0;
  }
  size_t n = 0;
  for (int i = 0; i < count && n < p->len; i++) {
    size_t k = iov[i].iov_len < p->len - n ? iov[i].iov_len : p->len - n;
    memcpy(iov[i].iov_base, p->buf + n, k);
    n += k;
  }
  memmove(p->buf, p->buf + n, p->len - n);
  p->len -= n;
  return n;
}

static ssize_t pipe_read(int fd, const struct iovec *iov, int count)
{
  pthread_mutex_lock(&pipe_lock);
  ssize_t n = pipe_read_locked(fd, iov, count);
  pthread_mutex_unlock(&pipe_lock);
  return n;
}

static ssize_t pipe_write_locked(int fd, const struct iovec *iov, int count)
{
  struct pipe *p = pipes[fd].p;
  if (!pipes[fd].write_end) { errno = EBADF; return -1; }
  if (!(p->ends & 1)) { errno = EPIPE; return -1; }
  size_t n = 0;
  for (int i = 0; i < count; i++) n += iov[i].iov_len;
  if (p->len + n > p->cap) {
    size_t cap = p->cap ? p->cap : 4096;
    while (cap < p->len + n) cap *= 2;
    char *b = realloc(p->buf, cap);
    if (!b) { errno = ENOMEM; return -1; }
    p->buf = b;
    p->cap = cap;
  }
  for (int i = 0; i < count; i++) {
    memcpy(p->buf + p->len, iov[i].iov_base, iov[i].iov_len);
    p->len += iov[i].iov_len;
  }
  return n;
}

static ssize_t pipe_write(int fd, const struct iovec *iov, int count)
{
  pthread_mutex_lock(&pipe_lock);
  ssize_t n = pipe_write_locked(fd, iov, count);
  if (n > 0) pthread_cond_broadcast(&pipe_changed);
  pthread_mutex_unlock(&pipe_lock);
  return n;
}

/* emscripten's read, write, readv, writev and close (WASI calls), with
   pipes */
ssize_t readv(int fd, const struct iovec *iov, int count)
{
  if (is_pipe(fd)) return pipe_read(fd, iov, count);
  size_t n;
  __wasi_errno_t e = __wasi_fd_read(fd, (const __wasi_iovec_t *)iov, count, &n);
  if (e) { errno = e; return -1; }
  return n;
}

ssize_t writev(int fd, const struct iovec *iov, int count)
{
  if (is_pipe(fd)) return pipe_write(fd, iov, count);
  size_t n;
  __wasi_errno_t e = __wasi_fd_write(fd, (const __wasi_ciovec_t *)iov, count, &n);
  if (e) { errno = e; return -1; }
  return n;
}

ssize_t read(int fd, void *buf, size_t count)
{
  struct iovec iov = { buf, count };
  return readv(fd, &iov, 1);
}

ssize_t write(int fd, const void *buf, size_t count)
{
  struct iovec iov = { (void *)buf, count };
  return writev(fd, &iov, 1);
}

int close(int fd)
{
  pthread_mutex_lock(&pipe_lock);
  if (is_pipe(fd)) {
    struct pipe *p = pipes[fd].p;
    p->ends &= pipes[fd].write_end ? ~2 : ~1;
    if (!p->ends) {
      free(p->buf);
      free(p);
    }
    pipes[fd].p = NULL;
    pthread_cond_broadcast(&pipe_changed);
  }
  pthread_mutex_unlock(&pipe_lock);
  __wasi_errno_t e = __wasi_fd_close(fd);
  if (e == __WASI_ERRNO_INTR) e = 0;
  if (e) { errno = e; return -1; }
  return 0;
}

/* POLLIN/POLLOUT/POLLHUP/POLLERR of pipe end FD for EVENTS */
static short pipe_revents(int fd, short events)
{
  struct pipe *p = pipes[fd].p;
  short r = 0;
  if (pipes[fd].write_end) {
    if (!(p->ends & 1)) r |= POLLERR;
    else if (events & POLLOUT) r |= POLLOUT;
  } else {
    if ((events & POLLIN) && p->len > 0) r |= POLLIN;
    if (!(p->ends & 2)) r |= POLLHUP;
  }
  return r;
}

int __syscall_openat(int dirfd, const char *path, int flags, ...)
{
  RESOLVE(dirfd, path, rel);
  return open_rel(rel_fd, rel, flags);
}

/* WASI cannot duplicate a descriptor: a file opened here is opened again,
   at the same position.  The copy has a position of its own, unlike a real
   duplicate, which is enough for the usual dup + fdopen.  Descriptors not
   opened here (the standard streams) cannot be duplicated. */
static int reopen(int fd)
{
  if (fd < 0 || fd >= MAX_FD || !opened[fd].rel) return -ENOSYS;
  __wasi_fdstat_t s;
  if (__wasi_fd_fdstat_get(fd, &s) != 0) return -EBADF;
  int dup = open_rel(opened[fd].dirfd, opened[fd].rel, opened[fd].flags);
  __wasi_filesize_t pos;
  __wasi_filesize_t newpos;
  if (dup >= 0 && __wasi_fd_tell(fd, &pos) == 0) (void)__wasi_fd_seek(dup, pos, __WASI_WHENCE_SET, &newpos);
  return dup;
}

int __syscall_dup(int fd)
{
  return reopen(fd);
}

/* dup2/dup3: the copy is moved to NEWFD (closing what was there) */
int __syscall_dup3(int oldfd, int newfd, int flags)
{
  (void)flags;
  if (oldfd == newfd) return -EINVAL;
  if (newfd < 0 || newfd >= MAX_FD) return -EBADF;
  int dup = reopen(oldfd);
  if (dup < 0) return dup;
  __wasi_errno_t e = __wasi_fd_renumber(dup, newfd);
  if (e) {
    (void)__wasi_fd_close(dup);
    return -e;
  }
  free(opened[newfd].rel);
  opened[newfd] = opened[dup];
  opened[dup].rel = NULL;
  return newfd;
}

static void fill_stat(struct stat *st, const __wasi_filestat_t *f)
{
  memset(st, 0, sizeof *st);
  st->st_dev = f->dev;
  st->st_ino = f->ino;
  st->st_nlink = f->nlink;
  st->st_size = f->size;
  st->st_blksize = 4096;
  st->st_blocks = (f->size + 511) / 512;
  switch (f->filetype) {
  case __WASI_FILETYPE_DIRECTORY: st->st_mode = S_IFDIR | 0755; break;
  case __WASI_FILETYPE_SYMBOLIC_LINK: st->st_mode = S_IFLNK | 0777; break;
  case __WASI_FILETYPE_CHARACTER_DEVICE: st->st_mode = S_IFCHR | 0666; break;
  case __WASI_FILETYPE_BLOCK_DEVICE: st->st_mode = S_IFBLK | 0666; break;
  /* node reports the standard streams piped so; they cannot be used as
     sockets here (no socket calls), a library treating them as such
     fails (Async's writers) */
  case __WASI_FILETYPE_SOCKET_STREAM:
  case __WASI_FILETYPE_SOCKET_DGRAM: st->st_mode = S_IFIFO | 0666; break;
  default: st->st_mode = S_IFREG | 0644; break;
  }
  st->st_atim.tv_sec = f->atim / 1000000000;
  st->st_atim.tv_nsec = f->atim % 1000000000;
  st->st_mtim.tv_sec = f->mtim / 1000000000;
  st->st_mtim.tv_nsec = f->mtim % 1000000000;
  st->st_ctim.tv_sec = f->ctim / 1000000000;
  st->st_ctim.tv_nsec = f->ctim % 1000000000;
}

int __syscall_fstat64(int fd, struct stat *st)
{
  if (is_pipe(fd)) {
    memset(st, 0, sizeof *st);
    st->st_mode = S_IFIFO | 0600;
    st->st_nlink = 1;
    st->st_blksize = 4096;
    return 0;
  }
  __wasi_filestat_t f;
  __wasi_errno_t e = __wasi_fd_filestat_get(fd, &f);
  if (e) return -e;
  fill_stat(st, &f);
  return 0;
}

int __syscall_newfstatat(int dirfd, const char *path, struct stat *st, int flags)
{
  if ((flags & AT_EMPTY_PATH) && path && !*path) return __syscall_fstat64(dirfd, st);
  RESOLVE(dirfd, path, rel);
  __wasi_filestat_t f;
  __wasi_lookupflags_t look = (flags & AT_SYMLINK_NOFOLLOW) ? 0 : __WASI_LOOKUPFLAGS_SYMLINK_FOLLOW;
  __wasi_errno_t e = __wasi_path_filestat_get(rel_fd, look, rel, strlen(rel), &f);
  if (e) return -e;
  fill_stat(st, &f);
  return 0;
}

int __syscall_stat64(const char *path, struct stat *st)
{
  return __syscall_newfstatat(AT_FDCWD, path, st, 0);
}

int __syscall_lstat64(const char *path, struct stat *st)
{
  return __syscall_newfstatat(AT_FDCWD, path, st, AT_SYMLINK_NOFOLLOW);
}

/* no permissions in WASI: existing is enough */
int __syscall_faccessat(int dirfd, const char *path, int amode, int flags)
{
  struct stat st;
  (void)amode;
  return __syscall_newfstatat(dirfd, path, &st, flags & AT_SYMLINK_NOFOLLOW);
}

int __syscall_fcntl64(int fd, int cmd, ...)
{
  va_list ap;
  va_start(ap, cmd);
  unsigned long arg = va_arg(ap, unsigned long); /* always passed by libc */
  va_end(ap);
  if (is_pipe(fd)) {
    switch (cmd) {
    case F_GETFD: case F_SETFD: return 0;
    case F_GETFL: return pipes[fd].flags;
    case F_SETFL: pipes[fd].flags = (pipes[fd].flags & O_ACCMODE) | (arg & O_NONBLOCK); return 0;
    default: return -EINVAL;
    }
  }
  __wasi_fdstat_t s;
  __wasi_errno_t e = __wasi_fd_fdstat_get(fd, &s);
  if (e) return -e;
  switch (cmd) {
  case F_GETFD: case F_SETFD:
    return 0; /* nothing is ever exec'd: close-on-exec is moot */
  case F_GETFL: {
    int r = (s.fs_rights_base & __WASI_RIGHTS_FD_READ) != 0;
    int w = (s.fs_rights_base & __WASI_RIGHTS_FD_WRITE) != 0;
    int fl = r && w ? O_RDWR : w ? O_WRONLY : O_RDONLY;
    if (s.fs_flags & __WASI_FDFLAGS_APPEND) fl |= O_APPEND;
    if (s.fs_flags & __WASI_FDFLAGS_NONBLOCK) fl |= O_NONBLOCK;
    return fl;
  }
  case F_SETFL: {
    __wasi_fdflags_t fl = s.fs_flags & ~(__WASI_FDFLAGS_APPEND | __WASI_FDFLAGS_NONBLOCK);
    if (arg & O_APPEND) fl |= __WASI_FDFLAGS_APPEND;
    if (arg & O_NONBLOCK) fl |= __WASI_FDFLAGS_NONBLOCK;
    return -__wasi_fd_fdstat_set_flags(fd, fl);
  }
  case F_GETLK: case F_OFD_GETLK:
    ((struct flock *)arg)->l_type = F_UNLCK;
    return 0;
  case F_SETLK: case F_SETLKW: case F_OFD_SETLK: case F_OFD_SETLKW:
    return 0; /* a single process, no one to lock against (sqlite) */
  case F_DUPFD: case F_DUPFD_CLOEXEC:
    return reopen(fd);
  default:
    return -EINVAL;
  }
}

int __syscall_ioctl(int fd, int op, ...)
{
  (void)fd; (void)op;
  return -ENOTTY;
}

/* ------------------------------------------------ directories and links */

int __syscall_mkdirat(int dirfd, const char *path, mode_t mode)
{
  (void)mode;
  RESOLVE(dirfd, path, rel);
  return -__wasi_path_create_directory(rel_fd, rel, strlen(rel));
}

int __syscall_unlinkat(int dirfd, const char *path, int flags)
{
  RESOLVE(dirfd, path, rel);
  if (flags & AT_REMOVEDIR) return -__wasi_path_remove_directory(rel_fd, rel, strlen(rel));
  return -__wasi_path_unlink_file(rel_fd, rel, strlen(rel));
}

int __syscall_rmdir(const char *path)
{
  return __syscall_unlinkat(AT_FDCWD, path, AT_REMOVEDIR);
}

int __syscall_renameat(int olddirfd, const char *oldpath, int newdirfd, const char *newpath)
{
  RESOLVE(olddirfd, oldpath, from);
  RESOLVE(newdirfd, newpath, to);
  return -__wasi_path_rename(from_fd, from, strlen(from), to_fd, to, strlen(to));
}

int __syscall_linkat(int olddirfd, const char *oldpath, int newdirfd, const char *newpath, int flags)
{
  RESOLVE(olddirfd, oldpath, from);
  RESOLVE(newdirfd, newpath, to);
  __wasi_lookupflags_t look = (flags & AT_SYMLINK_FOLLOW) ? __WASI_LOOKUPFLAGS_SYMLINK_FOLLOW : 0;
  return -__wasi_path_link(from_fd, look, from, strlen(from), to_fd, to, strlen(to));
}

int __syscall_symlinkat(const char *target, int newdirfd, const char *linkpath)
{
  RESOLVE(newdirfd, linkpath, rel);
  return -__wasi_path_symlink(target, strlen(target), rel_fd, rel, strlen(rel));
}

int __syscall_readlinkat(int dirfd, const char *path, char *buf, size_t size)
{
  RESOLVE(dirfd, path, rel);
  __wasi_size_t used;
  __wasi_errno_t e = __wasi_path_readlink(rel_fd, rel, strlen(rel), (uint8_t *)buf, size, &used);
  return e ? -e : (int)used;
}

/* fd_readdir's entries as struct dirent records */
int __syscall_getdents64(int fd, void *dirp, size_t count)
{
  static uint8_t buf[4096];
  if (fd < 0 || fd >= MAX_FD) return -EBADF;
  __wasi_size_t used;
  __wasi_errno_t e = __wasi_fd_readdir(fd, buf, sizeof buf, opened[fd].cookie, &used);
  if (e) return -e;
  size_t in = 0, out = 0;
  while (in + sizeof(__wasi_dirent_t) <= used) {
    __wasi_dirent_t d;
    memcpy(&d, buf + in, sizeof d);
    if (in + sizeof d + d.d_namlen > used) break; /* cut: read again from there */
    size_t reclen = (offsetof(struct dirent, d_name) + d.d_namlen + 1 + 7) & ~(size_t)7;
    if (out + reclen > count) {
      if (out == 0) return -EINVAL;
      break;
    }
    struct dirent *de = (struct dirent *)((char *)dirp + out);
    de->d_ino = d.d_ino;
    de->d_off = d.d_next;
    de->d_reclen = reclen;
    switch (d.d_type) {
    case __WASI_FILETYPE_DIRECTORY: de->d_type = DT_DIR; break;
    case __WASI_FILETYPE_REGULAR_FILE: de->d_type = DT_REG; break;
    case __WASI_FILETYPE_SYMBOLIC_LINK: de->d_type = DT_LNK; break;
    case __WASI_FILETYPE_CHARACTER_DEVICE: de->d_type = DT_CHR; break;
    case __WASI_FILETYPE_BLOCK_DEVICE: de->d_type = DT_BLK; break;
    case __WASI_FILETYPE_SOCKET_DGRAM:
    case __WASI_FILETYPE_SOCKET_STREAM: de->d_type = DT_SOCK; break;
    default: de->d_type = DT_UNKNOWN; break;
    }
    memcpy(de->d_name, buf + in + sizeof d, d.d_namlen);
    de->d_name[d.d_namlen] = 0;
    opened[fd].cookie = d.d_next;
    in += sizeof d + d.d_namlen;
    out += reclen;
  }
  return out;
}

/* The current directory only exists here: WASI has none. */
int __syscall_chdir(const char *path)
{
  struct stat st;
  char abs[PATH_MAX];
  int r = __syscall_stat64(path, &st);
  if (r) return r;
  if (!S_ISDIR(st.st_mode)) return -ENOTDIR;
  r = absolute(path, abs);
  if (r) return r;
  strcpy(cwd, abs);
  return 0;
}

/* The path DIRFD was opened from: a preopened directory, or a path
   relative to a directory opened from one. */
static int path_of_fd(int fd, char *out, int depth)
{
  load_preopens();
  for (int i = 0; i < npreopens; i++)
    if (preopens[i].fd == fd) {
      snprintf(out, PATH_MAX, "/%s", preopens[i].name);
      return 0;
    }
  if (depth > 16 || fd < 0 || fd >= MAX_FD || !opened[fd].rel) return -EBADF;
  int r = path_of_fd(opened[fd].dirfd, out, depth + 1);
  if (r) return r;
  size_t n = strlen(out);
  if (n + 1 + strlen(opened[fd].rel) >= PATH_MAX) return -ENAMETOOLONG;
  out[n] = '/';
  strcpy(out + n + 1, opened[fd].rel);
  return 0;
}

int __syscall_fchdir(int fd)
{
  char path[PATH_MAX];
  int r = path_of_fd(fd, path, 0);
  return r ? r : __syscall_chdir(path);
}

int __syscall_getcwd(char *buf, size_t size)
{
  size_t n = strlen(cwd) + 1;
  if (size < n) return -ERANGE;
  memcpy(buf, cwd, n);
  return n;
}

/* ------------------------------------------------------- sizes and times */

int __syscall_fdatasync(int fd)
{
  return is_pipe(fd) ? -EINVAL : -__wasi_fd_datasync(fd);
}

int __syscall_ftruncate64(int fd, off_t length)
{
  return -__wasi_fd_filestat_set_size(fd, length);
}

int __syscall_truncate64(const char *path, off_t length)
{
  int fd = __syscall_openat(AT_FDCWD, path, O_WRONLY);
  if (fd < 0) return fd;
  int r = __syscall_ftruncate64(fd, length);
  (void)__wasi_fd_close(fd);
  return r;
}

int __syscall_utimensat(int dirfd, const char *path, const struct timespec times[2], int flags)
{
  __wasi_timestamp_t t[2] = { 0, 0 };
  __wasi_fstflags_t fl = 0;
  for (int i = 0; i < 2; i++) {
    __wasi_fstflags_t now = i ? __WASI_FSTFLAGS_MTIM_NOW : __WASI_FSTFLAGS_ATIM_NOW;
    __wasi_fstflags_t set = i ? __WASI_FSTFLAGS_MTIM : __WASI_FSTFLAGS_ATIM;
    if (!times || times[i].tv_nsec == UTIME_NOW) fl |= now;
    else if (times[i].tv_nsec != UTIME_OMIT) {
      fl |= set;
      t[i] = (__wasi_timestamp_t)times[i].tv_sec * 1000000000 + times[i].tv_nsec;
    }
  }
  if (!path) return -__wasi_fd_filestat_set_times(dirfd, t[0], t[1], fl);
  RESOLVE(dirfd, path, rel);
  __wasi_lookupflags_t look = (flags & AT_SYMLINK_NOFOLLOW) ? 0 : __WASI_LOOKUPFLAGS_SYMLINK_FOLLOW;
  return -__wasi_path_filestat_set_times(rel_fd, look, rel, strlen(rel), t[0], t[1], fl);
}

/* emscripten's reports a constant 1s (Sys.time never moves) */
int __syscall_getrusage(int who, struct rusage *usage)
{
  __wasi_timestamp_t t;
  (void)who;
  memset(usage, 0, sizeof *usage);
  if (__wasi_clock_time_get(__WASI_CLOCKID_PROCESS_CPUTIME_ID, 1000, &t) != 0
      && __wasi_clock_time_get(__WASI_CLOCKID_MONOTONIC, 1000, &t) != 0)
    t = 0;
  usage->ru_utime.tv_sec = t / 1000000000;
  usage->ru_utime.tv_usec = t % 1000000000 / 1000;
  return 0;
}

/* --------------------------------------------- waiting: poll_oneoff */

/* emscripten's spins on the clock */
int nanosleep(const struct timespec *req, struct timespec *rem)
{
  if (!req || req->tv_sec < 0 || req->tv_nsec < 0 || req->tv_nsec > 999999999) {
    errno = EINVAL;
    return -1;
  }
  __wasi_subscription_t sub;
  __wasi_event_t ev;
  __wasi_size_t n;
  memset(&sub, 0, sizeof sub);
  sub.type = __WASI_EVENTTYPE_CLOCK;
  sub.u.clock.id = __WASI_CLOCKID_MONOTONIC;
  sub.u.clock.timeout = (__wasi_timestamp_t)req->tv_sec * 1000000000 + req->tv_nsec;
  __wasi_errno_t e = __wasi_poll_oneoff(&sub, &ev, 1, &n);
  if (e) {
    errno = e;
    return -1;
  }
  if (rem) rem->tv_sec = rem->tv_nsec = 0;
  return 0;
}

static int poll_once(struct pollfd *fds, nfds_t nfds, int timeout)
{
  __wasi_subscription_t *subs = calloc(2 * nfds + 1, sizeof *subs);
  __wasi_event_t *evs = calloc(2 * nfds + 1, sizeof *evs);
  if (!subs || !evs) {
    free(subs);
    free(evs);
    return -ENOMEM;
  }
  size_t n = 0;
  int ready = 0;
  for (nfds_t i = 0; i < nfds; i++) {
    fds[i].revents = 0;
    if (fds[i].fd < 0) continue;
    pthread_mutex_lock(&pipe_lock);
    if (is_pipe(fds[i].fd)) {
      fds[i].revents = pipe_revents(fds[i].fd, fds[i].events);
      pthread_mutex_unlock(&pipe_lock);
      if (fds[i].revents) ready++;
      continue;
    }
    pthread_mutex_unlock(&pipe_lock);
    /* a file is always ready (node:wasi cannot wait for one: EPERM, epoll) */
    __wasi_fdstat_t st;
    __wasi_errno_t e = __wasi_fd_fdstat_get(fds[i].fd, &st);
    if (e || st.fs_filetype == __WASI_FILETYPE_REGULAR_FILE || st.fs_filetype == __WASI_FILETYPE_DIRECTORY) {
      fds[i].revents = e ? POLLNVAL : fds[i].events & (POLLIN | POLLOUT);
      if (fds[i].revents) ready++;
      continue;
    }
    if (fds[i].events & POLLIN) {
      subs[n].userdata = i;
      subs[n].type = __WASI_EVENTTYPE_FD_READ;
      subs[n++].u.fd_readwrite.file_descriptor = fds[i].fd;
    }
    if (fds[i].events & POLLOUT) {
      subs[n].userdata = i;
      subs[n].type = __WASI_EVENTTYPE_FD_WRITE;
      subs[n++].u.fd_readwrite.file_descriptor = fds[i].fd;
    }
  }
  /* (a pipe ready: the others are only checked) */
  if (ready) timeout = 0;
  if (timeout >= 0) {
    subs[n].userdata = (__wasi_userdata_t)-1;
    subs[n].type = __WASI_EVENTTYPE_CLOCK;
    subs[n].u.clock.id = __WASI_CLOCKID_MONOTONIC;
    subs[n++].u.clock.timeout = (__wasi_timestamp_t)timeout * 1000000;
  }
  if (n > 0) {
    __wasi_size_t nev;
    __wasi_errno_t e = __wasi_poll_oneoff(subs, evs, n, &nev);
    if (e) ready = -e;
    else
      for (__wasi_size_t k = 0; k < nev; k++) {
        if (evs[k].type == __WASI_EVENTTYPE_CLOCK) continue;
        struct pollfd *p = &fds[evs[k].userdata];
        if (p->revents == 0) ready++;
        if (evs[k].error) p->revents |= POLLERR;
        else if (evs[k].type == __WASI_EVENTTYPE_FD_READ) p->revents |= POLLIN;
        else p->revents |= POLLOUT;
        if (evs[k].u.fd_readwrite.flags & __WASI_EVENTRWFLAGS_FD_READWRITE_HANGUP) p->revents |= POLLHUP;
      }
  }
  free(subs);
  free(evs);
  return ready;
}

static long long now_ms(void)
{
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return (long long)t.tv_sec * 1000 + t.tv_nsec / 1000000;
}

/* select() goes through poll in emscripten's libc.  With threads, another
   thread may write to a pipe being waited for: poll waits for that (pipes
   only), or checks the pipes again every 10 ms (with other descriptors,
   which the host waits for). */
int __syscall_poll(struct pollfd *fds, nfds_t nfds, int timeout)
{
  int pipes_only = 1, some_pipe = 0;
  for (nfds_t i = 0; i < nfds; i++) {
    if (fds[i].fd < 0) continue;
    if (is_pipe(fds[i].fd)) some_pipe = 1; else pipes_only = 0;
  }
  if (!some_pipe || timeout == 0 || !emscripten_has_threading_support()) return poll_once(fds, nfds, timeout);
  long long deadline = timeout < 0 ? -1 : now_ms() + timeout;
  for (;;) {
    long long left = deadline < 0 ? -1 : deadline - now_ms();
    if (deadline >= 0 && left < 0) left = 0;
    if (!pipes_only) {
      int r = poll_once(fds, nfds, left < 0 || left > 10 ? 10 : (int)left);
      if (r != 0 || left == 0) return r;
      continue;
    }
    pthread_mutex_lock(&pipe_lock);
    int ready = 0;
    for (nfds_t i = 0; i < nfds; i++) {
      if (fds[i].fd < 0) continue;
      fds[i].revents = is_pipe(fds[i].fd) ? pipe_revents(fds[i].fd, fds[i].events) : POLLNVAL;
      if (fds[i].revents) ready++;
    }
    if (ready || left == 0) {
      pthread_mutex_unlock(&pipe_lock);
      return ready;
    }
    if (left < 0) pthread_cond_wait(&pipe_changed, &pipe_lock);
    else {
      struct timespec until;
      clock_gettime(CLOCK_REALTIME, &until);
      until.tv_sec += left / 1000;
      until.tv_nsec += (left % 1000) * 1000000;
      if (until.tv_nsec >= 1000000000) { until.tv_sec++; until.tv_nsec -= 1000000000; }
      pthread_cond_timedwait(&pipe_changed, &pipe_lock, &until);
    }
    pthread_mutex_unlock(&pipe_lock);
  }
}

/* poll(..., 0): a probe of its own in recent emscripten (for JSPI) */
int __syscall_poll_nonblocking(struct pollfd *fds, nfds_t nfds)
{
  return __syscall_poll(fds, nfds, 0);
}

/* -------------------------------------- what WASI preview1 does not have */

/* no users nor permissions: everything belongs to root, modes and owners
   are ignored */
uid_t __syscall_getuid32(void) { return 0; }
uid_t __syscall_geteuid32(void) { return 0; }
gid_t __syscall_getgid32(void) { return 0; }
gid_t __syscall_getegid32(void) { return 0; }
mode_t __syscall_umask(mode_t mask) { (void)mask; return 022; }

int __syscall_chmod(const char *path, mode_t mode)
{
  struct stat st;
  (void)mode;
  return __syscall_stat64(path, &st);
}

int __syscall_fchmod(int fd, mode_t mode)
{
  struct stat st;
  (void)mode;
  return __syscall_fstat64(fd, &st);
}

int __syscall_fchmodat2(int dirfd, const char *path, mode_t mode, int flags)
{
  struct stat st;
  (void)mode;
  return __syscall_newfstatat(dirfd, path, &st, flags);
}

int __syscall_fchown32(int fd, uid_t owner, gid_t group)
{
  struct stat st;
  (void)owner; (void)group;
  return __syscall_fstat64(fd, &st);
}

int __syscall_fchownat(int dirfd, const char *path, uid_t owner, gid_t group, int flags)
{
  struct stat st;
  (void)owner; (void)group;
  return __syscall_newfstatat(dirfd, path, &st, flags);
}

/* every page of a wasm memory is accessible (emscripten's warns in debug
   builds; the OCaml 5.4+ runtime commits its heap with mprotect) */
int __syscall_mprotect(size_t start, size_t len, int prot)
{
  (void)start; (void)len; (void)prot;
  return 0;
}

/* no pipes nor special files */

int __syscall_mknodat(int dirfd, const char *path, mode_t mode, dev_t dev)
{
  (void)dirfd; (void)path; (void)mode; (void)dev;
  return -ENOSYS;
}

/* Sockets: preview1 can only use sockets the host preopens, which these
   calls cannot create nor name. */
#define NO_SOCKET(name, ...) int __syscall_##name(__VA_ARGS__) { return -ENOSYS; }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-parameter"
NO_SOCKET(socket, int a, int b, int c, int d, int e, int f)
NO_SOCKET(bind, int s, const struct sockaddr *a, socklen_t l, int x, int y, int z)
NO_SOCKET(connect, int s, const struct sockaddr *a, socklen_t l, int x, int y, int z)
NO_SOCKET(listen, int s, int b, int w, int x, int y, int z)
NO_SOCKET(accept4, int s, struct sockaddr *a, socklen_t *l, int f, int y, int z)
NO_SOCKET(getsockopt, int s, int lv, int o, void *v, socklen_t *l, int z)
NO_SOCKET(setsockopt, int s, int lv, int o, const void *v, socklen_t l, int z)
NO_SOCKET(getsockname, int s, struct sockaddr *a, socklen_t *l, int x, int y, int z)
NO_SOCKET(getpeername, int s, struct sockaddr *a, socklen_t *l, int x, int y, int z)
NO_SOCKET(sendto, int s, const void *b, size_t n, int f, const struct sockaddr *a, socklen_t l)
NO_SOCKET(recvfrom, int s, void *b, size_t n, int f, struct sockaddr *a, socklen_t *l)
NO_SOCKET(shutdown, int s, int h, int w, int x, int y, int z)
NO_SOCKET(sendmsg, int s, const struct msghdr *m, int f, int x, int y, int z)
NO_SOCKET(recvmsg, int s, struct msghdr *m, int f, int x, int y, int z)

/* name resolution (JavaScript in emscripten) */
int getaddrinfo(const char *n, const char *s, const struct addrinfo *h, struct addrinfo **r) { return EAI_FAIL; }
int getnameinfo(const struct sockaddr *a, socklen_t al, char *h, socklen_t hl, char *s, socklen_t sl, int f) { return EAI_FAIL; }
struct protoent *getprotobyname(const char *n) { return NULL; }
struct protoent *getprotobynumber(int p) { return NULL; }
uint32_t _emscripten_lookup_name(const char *name) { return 0; }
#pragma clang diagnostic pop

/* system(): no shell (system(NULL) tells so) */
int _emscripten_system(const char *command)
{
  return command ? -ENOSYS : 0;
}
