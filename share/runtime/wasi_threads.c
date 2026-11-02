/* Threads for a WASI module (--wasi --threads): wasi-threads.

   emscripten's pthread library (musl's, with -pthread) starts a thread by
   asking its JavaScript glue (__pthread_create_js), which runs it in a web
   worker sharing the memory.  A WASI module has no glue: here the thread is
   started with wasi-threads' `thread-spawn` import, the host running the
   module's `wasi_thread_start` export in a new instance (same shared
   memory, its own globals: stack pointer, TLS base) on a new thread.  This
   is the ABI of wasi-libc's threads (wasm32-wasip1-threads): wasmtime <= 46
   (-S threads), WAMR, wasmer...

   The functions below are the JavaScript ones of emscripten's
   libpthread.js the C library imports (env.*), as the worker side of a
   thread would run them. */

#define _GNU_SOURCE
#include <errno.h>
#include <pthread.h>
#include <setjmp.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdlib.h>
#include <emscripten/stack.h>

#ifndef OCAML_EMCC_THREAD_STACK_SIZE
#define OCAML_EMCC_THREAD_STACK_SIZE (1024 * 1024)
#endif

/* emscripten's internals (system/lib/pthread) */
extern void _emscripten_thread_init(pthread_t, int is_main, int is_runtime, int can_block, int default_stacksize,
                                    int start_profiling);
extern void *_emscripten_tls_init(void);
extern void _emscripten_thread_exit(void *result);
extern void _emscripten_thread_free_data(pthread_t);

__attribute__((import_module("wasi"), import_name("thread-spawn"))) int32_t ocaml_emcc_thread_spawn(int32_t arg);

/* What wasi_thread_start gets: the top of the thread's stack comes first */
struct start {
  void *stack_top;
  size_t stack_size;
  pthread_t thread;
  void *(*fn)(void *);
  void *arg;
};

/* The exited threads whose memory is still to be freed (detached ones
   cannot free their own stack while running on it), a list linked through
   their start block */
struct zombie {
  struct zombie *next;
  pthread_t thread;
};
static _Atomic(struct zombie *) zombies;

static void free_zombies(void) {
  struct zombie *z = atomic_exchange(&zombies, NULL);
  while (z) {
    struct zombie *next = z->next;
    _emscripten_thread_free_data(z->thread);
    free(z);
    z = next;
  }
}

int __pthread_create_js(pthread_t thread, const pthread_attr_t *attr, void *(*fn)(void *), void *arg) {
  (void)attr;
  free_zombies();
  struct start *s = malloc(sizeof *s);
  if (!s) return EAGAIN;
  pthread_attr_t a;
  void *stack;
  size_t size;
  /* the stack __pthread_create allocated with the thread */
  if (pthread_getattr_np(thread, &a) || pthread_attr_getstack(&a, &stack, &size)) {
    free(s);
    return EAGAIN;
  }
  s->stack_top = (char *)stack + size;
  s->stack_size = size;
  s->thread = thread;
  s->fn = fn;
  s->arg = arg;
  if (ocaml_emcc_thread_spawn((int32_t)(intptr_t)s) < 0) {
    free(s);
    return EAGAIN;
  }
  return 0;
}

/* pthread_exit unwinds to the start of the thread */
static _Thread_local jmp_buf *thread_exit;

__attribute__((used)) void ocaml_emcc_thread_start(int32_t tid, struct start *s) {
  (void)tid;
  pthread_t thread = s->thread;
  void *(*fn)(void *) = s->fn;
  void *arg = s->arg;
  emscripten_stack_set_limits(s->stack_top, (char *)s->stack_top - s->stack_size);
  free(s);
  _emscripten_thread_init(thread, 0, 0, 1, 0, 0);
  _emscripten_tls_init();
  jmp_buf buf;
  if (!setjmp(buf)) {
    thread_exit = &buf;
    _emscripten_thread_exit(fn(arg));
  }
}

/* wasi_thread_start(tid, start): the stack pointer first, before any C
   code runs (this instance's starts at the top of the main thread's) */
__asm__(
  "\t.text\n"
  "\t.export_name wasi_thread_start, wasi_thread_start\n"
  "\t.globaltype __stack_pointer, i32\n"
  "\t.functype ocaml_emcc_thread_start (i32, i32) -> ()\n"
  "\t.globl wasi_thread_start\n"
  "\t.type wasi_thread_start,@function\n"
  "wasi_thread_start:\n"
  "\t.functype wasi_thread_start (i32, i32) -> ()\n"
  "\tlocal.get 1\n"
  "\ti32.load 0\n"
  "\tglobal.set __stack_pointer\n"
  "\tlocal.get 0\n"
  "\tlocal.get 1\n"
  "\tcall ocaml_emcc_thread_start\n"
  "\tend_function\n");

/* pthread_exit, once the thread's exit is done (its glue unwinds the
   worker to its event loop) */
void emscripten_unwind_to_js_event_loop(void) {
  if (thread_exit) longjmp(*thread_exit, 1);
  abort();
}

/* The main thread (a constructor of the C library): it can block */
void _emscripten_init_main_thread_js(pthread_t main) {
  _emscripten_thread_init(main, 1, 1, 1, OCAML_EMCC_THREAD_STACK_SIZE, 0);
  _emscripten_tls_init();
}

/* A thread that can be freed: joined (by the joining thread), or detached
   and exiting (itself) */
void _emscripten_thread_cleanup(pthread_t thread) {
  if (thread != pthread_self()) {
    free_zombies();
    _emscripten_thread_free_data(thread);
    return;
  }
  struct zombie *z = malloc(sizeof *z);
  if (!z) return;
  z->thread = thread;
  z->next = atomic_load(&zombies);
  while (!atomic_compare_exchange_weak(&zombies, &z->next, z)) {
  }
}

/* The mailboxes (messages to a thread, used to proxy calls to the main
   thread's JavaScript) are unused: there is no JavaScript */
void _emscripten_thread_mailbox_await(pthread_t thread) { (void)thread; }
void _emscripten_notify_mailbox_postmessage(pthread_t target, pthread_t current) {
  (void)target;
  (void)current;
}
void _emscripten_thread_set_strongref(pthread_t thread) { (void)thread; }
void emscripten_check_blocking_allowed(void) {}
void emscripten_exit_with_live_runtime(void) { abort(); }
double _emscripten_receive_on_main_thread_js(int func, int sync, pthread_t thread, int n, void *args, void *ctx,
                                             void *result) {
  (void)func; (void)sync; (void)thread; (void)n; (void)args; (void)ctx; (void)result;
  abort();
}

/* JavaScript in emscripten (navigator.hardwareConcurrency, os.cpus()):
   WASI has no way to know, $OCAML_EMCC_CPUS or 4 */
int emscripten_has_threading_support(void) { return 1; }
int emscripten_num_logical_cores(void) {
  const char *n = getenv("OCAML_EMCC_CPUS");
  int k = n ? atoi(n) : 0;
  return k > 0 ? k : 4;
}
