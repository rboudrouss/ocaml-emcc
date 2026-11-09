// Linked (--pre-js) by `ocaml-emcc link --jspi`.
//
// With JSPI (emcc's -sJSPI), main runs asynchronously, and the compiled
// code suspends itself to continue a deep recursion on a new stack of the
// engine (c_of_ocaml's segmented stack).  An engine without JSPI
// (WebAssembly.Suspending) fails to instantiate the module, with an error
// that does not say why: say it before.
// node 24 has it behind its flag --experimental-wasm-jspi, which, set now,
// a new context has (not this one, created before): taken from there.
if (typeof WebAssembly == "object" && typeof WebAssembly.Suspending != "function" &&
    typeof process == "object" && process.versions && process.versions.node &&
    process.versions.node.split(".")[0] == "24") {
  require("v8").setFlagsFromString("--experimental-wasm-jspi");
  (function (w) {
    WebAssembly.Suspending = w.Suspending;
    WebAssembly.promising = w.promising;
  })(require("vm").runInNewContext("WebAssembly"));
}
if (typeof WebAssembly == "object" && typeof WebAssembly.Suspending != "function") {
  if (typeof process == "object" && process.versions && process.versions.node) {
    process.stderr.write(
      "this program was linked with --jspi (JSPI), which needs node 24 or later\n");
    process.exit(2);
  }
  throw new Error(
    "this program was linked with --jspi (JSPI), which this browser does not have " +
    "(Chrome and Edge 137 or later have it): load a build without --jspi");
}
