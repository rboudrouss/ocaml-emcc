// Linked (--pre-js) by `ocaml-emcc link --jspi`.
//
// With JSPI (emcc's -sJSPI), main runs asynchronously, and the compiled
// code suspends itself to continue a deep recursion on a new stack of the
// engine (c_of_ocaml's segmented stack).  An engine without JSPI
// (WebAssembly.Suspending) fails to instantiate the module, with an error
// that does not say why: say it before.
if (typeof WebAssembly == "object" && typeof WebAssembly.Suspending != "function") {
  if (typeof process == "object" && process.versions && process.versions.node) {
    process.stderr.write(
      "this program was linked with --jspi (JSPI): node 24 runs it with --experimental-wasm-jspi\n");
    process.exit(2);
  }
  throw new Error(
    "this program was linked with --jspi (JSPI), which this browser does not have " +
    "(Chrome and Edge 137 or later have it): load a build without --jspi");
}
