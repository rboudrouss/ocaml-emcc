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

/* wasm32: stubs compiled against the headers of an older ocaml-emcc runtime,
   built with ARCH_ALIGN_DOUBLE / ARCH_ALIGN_INT64, read floats and int64s
   through these functions, which the runtime no longer defines.  (A value is
   a pointer-sized integer; the int64 of a custom block follows its ops.) */
#if defined(__wasm32__)
#include <stdint.h>
#include <string.h>

__attribute__((weak)) double caml_Double_val(intptr_t v)
{
  double d;
  memcpy(&d, (void *)v, sizeof d);
  return d;
}

__attribute__((weak)) void caml_Store_double_val(intptr_t v, double d)
{
  memcpy((void *)v, &d, sizeof d);
}

__attribute__((weak)) int64_t caml_Int64_val(intptr_t v)
{
  int64_t i;
  memcpy(&i, (char *)v + sizeof(intptr_t), sizeof i);
  return i;
}
#endif
