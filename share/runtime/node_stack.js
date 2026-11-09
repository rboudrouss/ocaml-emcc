// Linked (--pre-js) by `ocaml-emcc link` in compiled mode.
//
// Compiled OCaml functions run on the stack of the wasm engine, about 1 MB
// on node's main thread: some tens of thousands of nested non-tail calls,
// where the bytecode interpreter has its own stack (1 GB by default).  So
// under node the program runs in a worker thread with a stack of
// $OCAML_EMCC_STACK_MB megabytes (default 1024), and this thread only
// waits for its exit code.  Running out of stack is reported as an uncaught
// Stack_overflow, as a native program would.  OCAML_EMCC_STACK_MB=0 runs
// on the main thread, the default for a program whose deep recursions go
// on off the stack of the engine (--cps-stack, --jspi: node_main_stack.js,
// linked before), which saves starting the worker (some 20 ms).  A node
// with JSPI runs main on a stack of that size of its own instead
// (node_main_jspi.js).
if (typeof process == "object" && process.versions && process.versions.node) {
  var ocamlEmccStackMb = Number(
    process.env.OCAML_EMCC_STACK_MB || (typeof ocamlEmccMainStack != "undefined" ? 0 : 1024));
  var ocamlEmccPromising =
    ocamlEmccStackMb > 0 && typeof ocamlEmccMainJspi != "undefined" ? ocamlEmccJspi() : undefined;
  var ocamlEmccJspiStack = typeof ocamlEmccPromising == "function";
  // (worker_threads loads node's streams, some 3 ms: only for the worker)
  var ocamlEmccThreads = ocamlEmccStackMb > 0 && !ocamlEmccJspiStack ? require("worker_threads") : null;
  if (ocamlEmccThreads && ocamlEmccThreads.isMainThread) {
    var ocamlEmccWorker = new ocamlEmccThreads.Worker(__filename, {
      argv: process.argv.slice(2),
      resourceLimits: { stackSizeMb: ocamlEmccStackMb },
      workerData: { ocamlEmccStack: true },
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
    // The module is instantiated by the worker only, compiled here while
    // the worker starts, then given to it
    Module["instantiateWasm"] = function () {
      var give = function (m) {
        ocamlEmccWorker.postMessage({ ocamlEmccModule: m });
      };
      try {
        WebAssembly.compile(ocamlEmccWasmBinary()).then(give, function () {
          give(null);
        });
      } catch (e) {
        give(null);
      }
    };
  } else if (!ocamlEmccThreads) {
    // on this thread, running out of the stack of the engine (through C
    // code: functions of C calling OCaml)
    var ocamlEmccOverflow = function (e) {
      if (e instanceof RangeError && /call stack/.test(e.message)) {
        process.stderr.write("Fatal error: exception Stack_overflow\n");
        process.exit(2);
      }
      // (node's own report of it)
      process.removeListener("uncaughtException", ocamlEmccOverflow);
      process.nextTick(function () {
        throw e;
      });
    };
    process.on("uncaughtException", ocamlEmccOverflow);
    if (ocamlEmccJspiStack)
      Module["onRuntimeInitialized"] = (function (next) {
        return function () {
          _main = ocamlEmccMainOnStack(_main, ocamlEmccStackMb, ocamlEmccOverflow);
          if (next) next();
        };
      })(Module["onRuntimeInitialized"]);
  } else {
    // the worker started above: the module compiled by the main thread
    if (ocamlEmccThreads.workerData && ocamlEmccThreads.workerData.ocamlEmccStack)
      Module["instantiateWasm"] = function (imports, done) {
        ocamlEmccThreads.parentPort.once("message", function (msg) {
          var m = msg && msg.ocamlEmccModule;
          (m ? WebAssembly.instantiate(m, imports).then(function (i) {
                 return { instance: i, module: m };
               })
             : WebAssembly.instantiate(ocamlEmccWasmBinary(), imports)
          ).then(function (r) {
            // (the module too: the dynamic linker reads it, --dynlink)
            done(r.instance, r.module);
          });
        });
      };
    // A worker cannot change the current directory of the process
    // (process.chdir throws, which emscripten's NODERAWFS turned into a
    // chdir that silently did nothing): the worker keeps its own, as
    // getcwd(3) the directory's real path, and the file system functions of
    // NODERAWFS, which give node the paths as they are (stat, open...), get
    // them made absolute from it.
    var ocamlEmccFs = require("fs");
    var ocamlEmccPath = require("path");
    var ocamlEmccCwd = process.cwd();
    var ocamlEmccAbs = function (p) {
      return typeof p == "string" && p !== "" ? ocamlEmccPath.resolve(ocamlEmccCwd, p) : p;
    };
    Module["preRun"] = [].concat(Module["preRun"] || [], function () {
      if (typeof NODERAWFS == "undefined") return;
      var wrap = function (name, first, second) {
        var f = FS[name];
        if (typeof f != "function") return;
        FS[name] = function (a, b) {
          var args = Array.prototype.slice.call(arguments);
          if (first) args[0] = ocamlEmccAbs(a);
          if (second) args[1] = ocamlEmccAbs(b);
          return f.apply(this, args);
        };
      };
      ["lookupPath", "mknod", "mkdir", "rmdir", "readdir", "unlink", "readlink", "stat", "lstat",
       "statfs", "chmod", "lchmod", "chown", "lchown", "truncate", "utime", "open"].forEach(function (n) {
        wrap(n, true, false);
      });
      wrap("rename", true, true);
      wrap("link", true, true);
      // the target of a symbolic link is relative to the link
      wrap("symlink", false, true);
    });
    process.cwd = function () {
      return ocamlEmccCwd;
    };
    process.chdir = function (dir) {
      var d = ocamlEmccFs.realpathSync(ocamlEmccAbs(dir));
      if (!ocamlEmccFs.statSync(d).isDirectory()) {
        var e = new Error("ENOTDIR: not a directory, chdir '" + dir + "'");
        e.code = "ENOTDIR";
        throw e;
      }
      ocamlEmccCwd = d;
    };
  }
}

// The bytes of the module (emscripten's glue: wasmBinary, findWasmBinary)
function ocamlEmccWasmBinary() {
  if (typeof wasmBinary != "undefined" && wasmBinary) return wasmBinary;
  return require("fs").readFileSync(findWasmBinary());
}

// WebAssembly.promising, of node 25 and later, and of node 24 once its flag
// --experimental-wasm-jspi is set, in a new context (not in this one,
// created before)
function ocamlEmccJspi() {
  if (typeof WebAssembly.promising == "function") return WebAssembly.promising;
  if (process.versions.node.split(".")[0] != "24") return undefined;
  require("v8").setFlagsFromString("--experimental-wasm-jspi");
  return require("vm").runInNewContext("WebAssembly.promising");
}

// main run by WebAssembly.promising, on a new stack of the engine of mb
// megabytes: the size V8 gives to the stacks it creates (in KB), set for
// that one, and the limit of the stack (--stack-size: ineffective on the
// stack of the thread, which exists already).  Nothing suspends it, so it
// is done when promising returns, its outcome only coming in a promise:
// emscripten's callMain sees main unwind (as one keeping the runtime
// alive), and the outcome is handled as callMain would have.
function ocamlEmccMainOnStack(main, mb, overflow) {
  var promising = ocamlEmccPromising(main);
  var v8 = require("v8");
  var flags = function (kb) {
    v8.setFlagsFromString("--stack-size=" + kb);
    v8.setFlagsFromString("--wasm-stack-switching-stack-size=" + kb);
  };
  return function (argc, argv) {
    flags(mb * 1024);
    try {
      var p = promising(argc, argv);
    } finally {
      // (V8's defaults: the stacks of the callbacks main runs come from a
      // pool, only of small stacks)
      flags(984);
    }
    p.then(
      function (ret) {
        try {
          exitJS(ret, true);
        } catch (e) {
          handleException(e);
        }
      },
      function (e) {
        try {
          handleException(e);
        } catch (e2) {
          overflow(e2);
        }
      });
    throw "unwind";
  };
}
