// Linked (--pre-js) by `ocaml-emcc link` in compiled mode, before
// node_stack.js, for a program whose compiled code only runs from main: no
// callbacks of JavaScript (js_of_ocaml's primitives) nor asyncify, which
// enter the wasm code again from node's event loop.  Under a node with JSPI
// (WebAssembly.promising, node 24+), main then runs on a large stack of the
// engine of its own, on the main thread, instead of in the worker of
// node_stack.js, which takes some 20 to 35 ms to start.
var ocamlEmccMainJspi = true;
