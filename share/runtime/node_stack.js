// Linked (--pre-js) by `ocaml-emcc link --compiled`.
//
// Compiled OCaml functions run on the stack of the wasm engine, about 1 MB
// on node's main thread: some tens of thousands of nested non-tail calls,
// where the bytecode interpreter has its own stack (1 GB by default).  So
// under node the program runs in a worker thread with a stack of
// $OCAML_EMCC_STACK_MB megabytes (default 1024), and this thread only
// waits for its exit code.  Running out of stack is reported as an uncaught
// Stack_overflow, as a native program would.  OCAML_EMCC_STACK_MB=0 runs
// on the main thread.
if (typeof process == "object" && process.versions && process.versions.node) {
  var ocamlEmccThreads = require("worker_threads");
  var ocamlEmccStackMb = Number(process.env.OCAML_EMCC_STACK_MB || 1024);
  if (ocamlEmccThreads.isMainThread && ocamlEmccStackMb > 0) {
    var ocamlEmccWorker = new ocamlEmccThreads.Worker(__filename, {
      argv: process.argv.slice(2),
      resourceLimits: { stackSizeMb: ocamlEmccStackMb },
    });
    ocamlEmccWorker.on("error", function (e) {
      if (e instanceof RangeError && /call stack/.test(e.message)) {
        process.stderr.write("Fatal error: exception Stack_overflow\n");
        process.exit(2);
      }
      throw e;
    });
    ocamlEmccWorker.on("exit", function (code) {
      process.exit(code);
    });
    // The module is instantiated by the worker only
    Module["instantiateWasm"] = function () {};
  }
}
