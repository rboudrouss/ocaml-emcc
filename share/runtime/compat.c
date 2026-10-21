/* libc functions the OCaml runtime/otherlibs reference but emscripten's libc
 * does not provide.  Weak: a real definition (newer emscripten, user code)
 * takes precedence.  They fail with ENOSYS, as unsupported syscalls do. */

#include <errno.h>
#include <signal.h>

__attribute__((weak)) int sigsuspend(const sigset_t *mask)
{
  (void)mask;
  errno = ENOSYS;
  return -1;
}

/* OCaml < 4.12: runtime/afl.c (AFL fuzzing support) attaches shared memory
   when AFL asks for it, which never happens here. */
__attribute__((weak)) void *shmat(int shmid, const void *shmaddr, int shmflg)
{
  (void)shmid; (void)shmaddr; (void)shmflg;
  errno = ENOSYS;
  return (void *)-1;
}
