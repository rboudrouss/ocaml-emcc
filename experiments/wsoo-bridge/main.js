// Loads the C module (emscripten), then the OCaml program (wasm_of_ocaml)
// with the C module's memory and functions as its "c" imports.
const path = require("node:path");
(async () => {
  const createC = require("./oec.js");
  const C = await createC();
  const ex = C.wasmExports;
  globalThis.__oe = {};
  const registry = new FinalizationRegistry((h) => ex.oe_handle_free(h));
  globalThis.__oe_c = Object.assign({}, ex, {
    oe_register_wat: (apply, named) => { globalThis.__oe.apply = apply; globalThis.__oe.named = named; },
    oe_track: (obj, h) => registry.register(obj, h),
  });
  ex.oe_init();
  const prog = path.resolve(process.argv[2]);
  process.argv.splice(1, 1); // the program sees its own argv
  require(prog);
})();
