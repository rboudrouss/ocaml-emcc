// Linked (--pre-js) by `ocaml-emcc link --cps-stack` or `--jspi`, before
// node_stack.js: the deep recursions of the compiled code go on off the
// stack of the engine (on the heap, or on new stacks), so under node the
// program runs on the main thread, without the worker of node_stack.js and
// its large stack, unless $OCAML_EMCC_STACK_MB asks for one.
var ocamlEmccMainStack = true;
