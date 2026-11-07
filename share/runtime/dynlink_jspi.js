// Linked (--js-library) by `ocaml-emcc link --dynlink --threads --jspi`.
//
// With JSPI, emscripten loads a library asynchronously: dlopen is an
// import that suspends (WebAssembly.Suspending) on the promise of the load.
// A thread started after a plugin was loaded loads it in its turn before
// it runs (_emscripten_dlsync_self, called by invokeEntryPoint), outside of
// JSPI, where calling such an import fails (SuspendError), whatever it
// returns.  A worker compiles and instantiates a module synchronously: in
// the threads other than the main one, dlopen loads synchronously, and is
// a plain import.  So is _emscripten_dlsync_threads there, which the end of
// a load (load_url's, in the pthread of main) calls, and which waits for
// the main thread synchronously.
addToLibrary({
  $ocamlEmccDlopenSync__deps: ['$dlopenInternal', '_dlopen_js', '_emscripten_dlsync_threads'],
  $ocamlEmccDlopenSync__postset:
    'if (ENVIRONMENT_IS_PTHREAD) { __dlopen_js = ocamlEmccDlopenSync; __emscripten_dlsync_threads.isAsync = false; }',
  $ocamlEmccDlopenSync: (handle) => {
    var h = dlopenInternal(Number(handle), { loadAsync: false });
#if MEMORY64
    return BigInt(h);
#else
    return h;
#endif
  },
});
