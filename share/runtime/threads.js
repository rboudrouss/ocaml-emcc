// Linked (--js-library) by `ocaml-emcc link --threads`: see threads.c.
addToLibrary({
  _emscripten_thread_cleanup__deps: ['$cleanupThread', 'ocaml_emcc_thread_cleanup_async'],
  _emscripten_thread_cleanup: (thread) => {
    if (!ENVIRONMENT_IS_PTHREAD) cleanupThread(thread);
    else _ocaml_emcc_thread_cleanup_async(thread);
  },
});
