# wasm_of_ocaml + C stubs compiled by emscripten (experiment)

ocaml-emcc interprets bytecode, about 7 to 14 times slower than the same
program compiled by wasm_of_ocaml (see the timings below). This
experiment keeps wasm_of_ocaml for the OCaml code, and runs the C stubs
that wasm_of_ocaml does not implement in an emscripten module, with the
libcamlrun of ocaml-emcc's sysroot: the C is unchanged, as with
ocaml-emcc.

```sh
ocamlc -custom stubs.c prog.ml -o prog.bc     # or any bytecode executable
experiments/wsoo-bridge/build.sh prog.bc out stubs.c -lzarith -lgmp
node out/main.js out/prog.js args...
```

Needs wasm_of_ocaml (tried with 6.4.1) and binaryen in `PATH`, and an
ocaml-emcc sysroot for wasm32 (`ocaml-emcc setup`). Tried with OCaml 5.4.1
only, in node only.

## How it works

The two modules have their own values: Wasm GC objects for wasm_of_ocaml
(`(ref eq)`: `i31`, arrays for blocks and strings...), OCaml values in
linear memory for the C. Each call to a bridged primitive converts its
arguments, calls the C function, and converts the result back:

- `build.sh` lists the primitives that wasm_of_ocaml reports missing,
  with their arity in the bytecode (`arity/arity.ml`). `gen.py` writes a
  Wasm export per primitive (wasm_of_ocaml's way of providing primitives)
  calling `$invoke` with its index, and the C `oe_dispatch` calling the
  function with that index. A C function defined with another arity
  than its call (zarith's `ml_z_init()`, called with `()`) is called with
  its own, read from wasm-ld's warnings (`mismatch.py`).
- `bridge.wat`, linked into the wasm_of_ocaml module, imports the C
  module's memory and functions (`"c"`, given by `main.js`). `$to_c`
  copies a value into the C heap: ints, strings, floats, float arrays,
  blocks (recursively), int32/int64/nativeint. Values are allocated in
  the major heap (`caml_alloc_shr`), which does not move them while a
  value is being built, and the arguments go to a stack of GC roots
  (`oe_stack`). `$of_c` copies a C value back.
- `oe_call` calls the C function with its own `setjmp`, as the
  interpreter does: an exception raised by the C (`caml_failwith`...)
  comes back to the GC side, where it is thrown as an OCaml exception.
  The predefined exceptions are paired with wasm_of_ocaml's (`Failure`
  from C is caught by `with Failure`), and so is each exception
  constructor that crossed (an exception of the program raised by C, or
  passing through C, keeps its identity).
- An OCaml closure given to C becomes a bytecode closure whose code is
  `ACC 0; PUSHENVACC 2; C_CALL2 oe_apply_prim; RETURN 1`: the runtime's
  `caml_callback` applies it unchanged, and `oe_apply_prim` calls the GC
  closure back (through JS). An exception it raises crosses the C frames
  as an OCaml exception of the interpreter.
- Mutable arguments: the bytes given to C are copied back after the call
  (`Bytes` filled by a stub).
- Custom blocks without finalizer (zarith's integers) are plain data: they
  are copied, word by word. Those with a finalizer (C resources), abstract
  blocks and C closures stay in C, held by a handle (a generational global
  root), freed by a `FinalizationRegistry` once the GC side's wrapper is
  dead. Polymorphic compare and hash of both kinds call the C custom
  operations.
- `caml_named_value` in C looks up the names that the program registered
  with `Callback.register` on the GC side. wasm_of_ocaml drops the
  registrations of names that nothing looks up: `named.js` declares the
  names found in the C inputs.
- After each call, the C runtime's pending actions run (major GC slices
  requested by major-heap allocations), as at the interpreter's polls.

```sh
cd /tmp && ocamlc -custom $OLDPWD/test/stubs.c $OLDPWD/test/t.ml -o t.bc
$OLDPWD/build.sh t.bc out $OLDPWD/test/stubs.c && node out/main.js out/t.js | diff $OLDPWD/test/expected.txt -
```

The test passes (`test/expected.txt` is the output of the native bytecode):
tuples, lists, strings, floats, variants and float records built or read
by C, `Failure` and `Invalid_argument` raised by C, a custom block with a
finalizer, a `Bytes` filled by C, callbacks (curried too), an OCaml
exception raised in a callback and caught around the C call, int64, a
primitive with 6 arguments, `caml_named_value` on an exception of the
program. `tests/zarith/zt.ml` runs with zarith and gmp (`-lzarith -lgmp`)
except its last line (marshalling).

## Timings

OCaml 5.4.1, node 24, on a shared machine.

| program | native ocamlrun | ocaml-emcc | wasm_of_ocaml + bridge |
|---------|-----------------|------------|------------------------|
| fib (no C) | 15.8 s | 23.9 s | 2.4 s (wasm_of_ocaml alone) |
| pidigits 8000 (zarith) | 1.2 s | 4.9 s | 8.1 s |

A bridged call costs about 50 ns (`int -> int -> int`), 200 ns when it
builds a tuple or a list or calls back an OCaml closure, plus the copies:
pidigits, where the C side (GMP) does nearly all the work, copies its big
integers both ways at each operation.

## Limitations

- Values are copied, so their identity is lost: a mutable record given to
  C and modified there is not updated (only `Bytes` are), C code that
  keeps an OCaml value (a global root) keeps a copy, cyclic values loop.
- A custom block with a finalizer, given to the GC side, lives until the
  JS event loop runs the `FinalizationRegistry`: never, in a program that
  runs synchronously from start to end. GC closures given to C are never
  freed.
- Bigarrays, JS values, objects and lazy values cannot cross yet, nor can
  custom blocks be marshalled (`output_value: abstract value (Custom)`).
- Effects (`--effects=cps` or JSPI) across C frames are not handled.
- Browsers: `main.js` is for node; the C module is instantiated first,
  and its exports are the `"c"` imports patched into wasm_of_ocaml's
  loader (`sed`).
