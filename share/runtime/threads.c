/* Threads with emscripten's JavaScript glue (--threads, not --wasi).

   A detached thread (OCaml's threads and domains are) that exits asks the
   main thread to give its worker back to the pool with a postMessage
   (_emscripten_thread_cleanup), which the main thread only receives once
   back in its event loop.  An OCaml program blocked in Thread.join or a
   mutex never is: the workers of the exited threads stay taken, and the
   next threads wait for a free one forever in a browser (where a new
   worker only loads from the event loop as well).  threads.js sends the
   request through emscripten's proxying queue instead, which the main
   thread runs while it waits.

   The other threads' system calls on files (open, stat, write...) run on
   the main thread, where emscripten's file system is, through that queue
   too.  The main thread runs it when it waits (a mutex, a join), but not in
   poll and select, which never wait there: a main thread looping on them
   (Lwt_main, Async's scheduler) waiting for a job of another thread to
   finish (Lwt_unix.stat) never ran the job's stat.  They run it first.
   Without descriptors, they only wait: in the calling thread, rather than
   on the main one (OCaml 4.14's tick thread sleeps with select, which never
   returned while the main thread computed: no preemption). */

#include <errno.h>
#include <poll.h>
#include <stdlib.h>
#include <sys/select.h>
#include <time.h>
#include <emscripten/em_js.h>
#include <emscripten/proxying.h>
#include <emscripten/syscalls.h>
#include <emscripten/threading.h>

EM_JS_DEPS(ocaml_emcc_threads, "$cleanupThread");

/* (wasm64: the pointer arrives as a BigInt) */
EM_JS(void, ocaml_emcc_cleanup_thread, (void *thread), { cleanupThread(Number(thread)); });

static void cleanup_on_main(void *thread) { ocaml_emcc_cleanup_thread(thread); }

EMSCRIPTEN_KEEPALIVE void ocaml_emcc_thread_cleanup_async(void *thread) {
  emscripten_proxy_async(emscripten_proxy_get_system_queue(), emscripten_main_runtime_thread_id(), cleanup_on_main,
                         thread);
}

static void run_queued_calls(void) {
  if (emscripten_is_main_runtime_thread()) emscripten_main_thread_process_queued_calls();
}

static int sleep_ms(int timeout) {
  if (timeout < 0) {
    errno = EINVAL;
    return -1;
  }
  struct timespec t = { timeout / 1000, (long)(timeout % 1000) * 1000000 };
  nanosleep(&t, NULL);
  return 0;
}

int poll(struct pollfd *fds, nfds_t n, int timeout) {
  if (n == 0) return sleep_ms(timeout);
  run_queued_calls();
  int r = __syscall_poll(fds, n, timeout);
  if (r < 0) {
    errno = -r;
    return -1;
  }
  return r;
}

/* emscripten's (musl's select.c): select through poll */
int select(int nfds, fd_set *readfds, fd_set *writefds, fd_set *exceptfds, struct timeval *tv) {
  if (nfds < 0) {
    errno = EINVAL;
    return -1;
  }
  int timeout = tv ? tv->tv_sec * 1000 + tv->tv_usec / 1000 : -1;
  if (!(readfds || writefds || exceptfds) || nfds == 0) return sleep_ms(timeout);
  struct pollfd *fds = calloc(nfds ? nfds : 1, sizeof *fds);
  if (!fds) {
    errno = ENOMEM;
    return -1;
  }
  int n = 0;
  for (int i = 0; i < nfds; i++) {
    short events = 0;
    if (readfds && FD_ISSET(i, readfds)) events |= POLLIN;
    if (writefds && FD_ISSET(i, writefds)) events |= POLLOUT;
    if (exceptfds && FD_ISSET(i, exceptfds)) events |= POLLPRI;
    if (events) {
      fds[n].fd = i;
      fds[n++].events = events;
    }
  }
  int r = poll(fds, n, timeout);
  if (r < 0) {
    free(fds);
    return -1;
  }
  for (int k = 0; k < n; k++)
    if (fds[k].revents & POLLNVAL) {
      free(fds);
      errno = EBADF;
      return -1;
    }
  if (readfds) FD_ZERO(readfds);
  if (writefds) FD_ZERO(writefds);
  if (exceptfds) FD_ZERO(exceptfds);
  int count = 0;
  for (int k = 0; k < n; k++) {
    short re = fds[k].revents;
    if (readfds && (re & (POLLIN | POLLHUP | POLLERR))) { FD_SET(fds[k].fd, readfds); count++; }
    if (writefds && (re & (POLLOUT | POLLERR))) { FD_SET(fds[k].fd, writefds); count++; }
    if (exceptfds && (re & POLLPRI)) { FD_SET(fds[k].fd, exceptfds); count++; }
  }
  free(fds);
  return count;
}
