// Linked (--pre-js) by `ocaml-emcc link --compiled --threads`, instead of
// node_stack.js: the program runs in a pthread (-sPROXY_TO_PTHREAD), a
// worker as each of its threads.  Under node they all get a stack of
// $OCAML_EMCC_STACK_MB megabytes (default 1024), on which compiled OCaml
// functions run; running out of it is reported as an uncaught
// Stack_overflow, as a native program would.
if (typeof process == "object" && process.versions && process.versions.node && typeof globalThis.Worker == "function") {
  var ocamlEmccStackMb = Number(process.env.OCAML_EMCC_STACK_MB || 1024);
  if (ocamlEmccStackMb > 0) {
    var OcamlEmccWorker = globalThis.Worker;
    globalThis.Worker = class extends OcamlEmccWorker {
      constructor(file, options) {
        options = Object.assign({}, options);
        options.resourceLimits = Object.assign({}, options.resourceLimits, { stackSizeMb: ocamlEmccStackMb });
        super(file, options);
        this.on("error", function (e) {
          if (e instanceof RangeError && /call stack/.test(e.message)) {
            process.stderr.write("Fatal error: exception Stack_overflow\n");
            process.exit(2);
          }
        });
      }
    };
  }
}
