// Primitives of jp.ml, called with JavaScript values: OCaml ints are
// numbers, js_of_ocaml's values are themselves, other OCaml values are
// opaque and come back unchanged.

//Provides: jp_add
function jp_add(a, b) {
  return a + b;
}

function jp_greet(s) {
  return 'hello ' + s + ' (' + s.length + ' chars)';
}

function jp_apply(f, x) {
  return f(x) + 1;
}

function jp_fail(msg) {
  throw new Error(msg);
}

function jp_same(v) {
  return v;
}

function jp_six(a, b, c, d, e, f) {
  return [a, b, c, d, e, f].join('-');
}

//Provides: jp_config
var jp_config = { name: 'prims.js', version: 3 };
