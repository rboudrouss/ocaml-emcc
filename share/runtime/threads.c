/* Threads with emscripten's JavaScript glue (--threads, not --wasi).

   A detached thread (OCaml's threads and domains are) that exits asks the
   main thread to give its worker back to the pool with a postMessage
   (_emscripten_thread_cleanup), which the main thread only receives once
   back in its event loop.  An OCaml program blocked in Thread.join or a
   mutex never is: the workers of the exited threads stay taken, and the
   next threads wait for a free one forever in a browser (where a new
   worker only loads from the event loop as well).  threads.js sends the
   request through emscripten's proxying queue instead, which the main
   thread runs while it waits. */

#include <emscripten/em_js.h>
#include <emscripten/proxying.h>
#include <emscripten/threading.h>

EM_JS_DEPS(ocaml_emcc_threads, "$cleanupThread");

/* (wasm64: the pointer arrives as a BigInt) */
EM_JS(void, ocaml_emcc_cleanup_thread, (void *thread), { cleanupThread(Number(thread)); });

static void cleanup_on_main(void *thread) { ocaml_emcc_cleanup_thread(thread); }

EMSCRIPTEN_KEEPALIVE void ocaml_emcc_thread_cleanup_async(void *thread) {
  emscripten_proxy_async(emscripten_proxy_get_system_queue(), emscripten_main_runtime_thread_id(), cleanup_on_main,
                         thread);
}
