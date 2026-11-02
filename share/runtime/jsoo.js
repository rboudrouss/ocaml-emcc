// JavaScript side of js_of_ocaml's primitives (jsoo.c), an emscripten
// library (--js-library), linked by `ocaml-emcc link` with jsoo.c.
//
// JavaScript values are kept in a table and handed to OCaml as handles,
// with the conventions of wasm_of_ocaml: a JavaScript number that is an
// integer of the range of OCaml ints is an OCaml int, any other value is a
// custom block holding its handle (released by the block's finalizer). An
// OCaml int is a JavaScript number, an OCaml float too, and any other OCaml
// value given to JavaScript is an opaque object (OcamlValue) holding it
// through a GC root, that gives back the same OCaml value.
//
// Between C and JavaScript, a value is a pair (tag, x): tag 0 for the number
// x, a positive tag for the handle tag, -1 for the OCaml value at the root x
// (an address), -2 for the UTF-8 string of length len at address x (property
// names).  Results are an int: a handle (> 0), 0 for the int stored at
// retAddr, -1 for the OCaml value at the root whose address is stored there,
// -2 for a JavaScript exception that is an Error (its handle stored
// there), -5 for another one, -3 for an OCaml exception crossing JavaScript
// (its root), -4 for a stack overflow.

addToLibrary({
  $ocamlJs__deps: ['$runtimeKeepalivePush', '$ExitStatus', 'ocaml_emcc_js_callback', 'ocaml_emcc_js_release', 'free'],
  $ocamlJs: {
    // 1 undefined, 2 null, 3 true, 4 false, 5 globalThis: never released
    // (set by init: the library's values are evaluated by emcc)
    vals: null,
    freeList: [],
    retAddr: 0,
    outAddr: 0,
    intMin: -0x40000000,
    intMax: 0x3fffffff,
    cbArgs: [],
    pending: null,
    alive: false,
    registry: null,
    OcamlValue: null,
    OcamlExn: null,
    utf8: null,

    init(retAddr, outAddr, bits) {
      var J = ocamlJs;
      J.vals = [undefined, undefined, null, true, false, globalThis];
      J.retAddr = retAddr;
      J.outAddr = outAddr;
      if (bits == 64) { J.intMin = Number.MIN_SAFE_INTEGER; J.intMax = Number.MAX_SAFE_INTEGER; }
      J.utf8 = new TextDecoder('utf-8');
      J.OcamlValue = class OcamlValue { constructor(cell) { this.cell = cell; } };
      J.OcamlExn = class OcamlExn extends Error {
        constructor(cell, msg) { super(msg); this.name = 'OCamlException'; this.cell = cell; }
      };
      // the roots of OCaml values (callbacks, opaque values) are released
      // once JavaScript no longer references them
      if (typeof FinalizationRegistry != 'undefined')
        J.registry = new FinalizationRegistry((cell) => _ocaml_emcc_js_release(cell));
      // values of the runtime of js_of_ocaml that programs name
      J.runtime = {
        jsoo_exports: (typeof module == 'object' && module && module.exports) || globalThis,
        jsoo_runtime: J,
      };
    },

    handle(v) {
      if (v === undefined) return 1;
      if (v === null) return 2;
      if (v === true) return 3;
      if (v === false) return 4;
      var J = ocamlJs, h = J.freeList.length ? J.freeList.pop() : J.vals.length;
      J.vals[h] = v;
      return h;
    },

    // a result
    ret(v) {
      var J = ocamlJs;
      if (typeof v == 'number') {
        if (Number.isInteger(v) && v >= J.intMin && v <= J.intMax && !Object.is(v, -0)) {
          HEAPF64[J.retAddr / 8] = v;
          return 0;
        }
      } else if (v instanceof J.OcamlValue) {
        HEAPF64[J.retAddr / 8] = v.cell;
        return -1;
      }
      return J.handle(v);
    },

    exn(e) {
      var J = ocamlJs;
      if (e instanceof ExitStatus || e == 'unwind') throw e;
      if (e instanceof J.OcamlExn) { HEAPF64[J.retAddr / 8] = e.cell; return -3; }
      if (e instanceof RangeError && /call stack/i.test(e.message)) return -4;
      HEAPF64[J.retAddr / 8] = J.handle(e);
      return e instanceof Error ? -2 : -5;
    },

    // runs f, returning its result as above
    run(f) {
      try { return ocamlJs.ret(f()); } catch (e) { return ocamlJs.exn(e); }
    },

    // the value of a pair
    val(t, x) {
      var J = ocamlJs;
      if (t > 0) return J.vals[t];
      if (t == 0) return x;
      var o = new J.OcamlValue(x);
      if (J.registry) J.registry.register(o, x);
      return o;
    },

    key(t, x, len) {
      return t == -2 ? ocamlJs.decode(x, len) : ocamlJs.val(t, x);
    },

    // UTF-8 at p: short ASCII strings (property names) without TextDecoder,
    // which costs much more for them
    decode(p, len) {
      if (len <= 32) {
        var s = '';
        for (var i = 0; i < len; i++) {
          var c = HEAPU8[p + i];
          if (c >= 0x80) return ocamlJs.utf8.decode(HEAPU8.subarray(p, p + len));
          s += String.fromCharCode(c);
        }
        return s;
      }
      return ocamlJs.utf8.decode(HEAPU8.subarray(p, p + len));
    },

    // the arguments written by C: n pairs (int32 tag, pad, double x)
    args(p, n) {
      var a = new Array(n);
      for (var i = 0; i < n; i++) a[i] = ocamlJs.val(HEAP32[(p + 16 * i) / 4], HEAPF64[(p + 16 * i + 8) / 8]);
      return a;
    },

    // a JavaScript function calling the OCaml function at root cell (see
    // caml_js_wrap_callback* in js_of_ocaml's runtime)
    wrap(kind, arity, cell) {
      var J = ocamlJs;
      var f = function (...args) {
        switch (kind) {
          case 0: case 3: if (args.length === 0) args = [undefined]; break;
          case 1: args = [args]; break;
          case 2: args.length = arity; break;
          case 4: case 7: args.unshift(this); break;
          case 5: args = [this, args]; break;
          case 6: args.length = arity; args.unshift(this); break;
        }
        return J.call(cell, kind, args);
      };
      if (J.registry) J.registry.register(f, cell);
      // the program goes on running callbacks once its main code is done
      if (!J.alive) { J.alive = true; runtimeKeepalivePush(); }
      return f;
    },

    call(cell, kind, args) {
      var J = ocamlJs, st;
      J.cbArgs.push(args);
      try {
        st = _ocaml_emcc_js_callback(cell, kind, args.length);
      } catch (e) {
        // exit in a callback: the process ends, as natively
        if (e instanceof ExitStatus && typeof process == 'object' && process.exit) process.exit(e.status);
        throw e;
      } finally {
        J.cbArgs.pop();
      }
      var t = HEAP32[J.outAddr / 4], x = HEAPF64[J.outAddr / 8 + 1];
      if (st) {
        var msg = J.pending;
        J.pending = null;
        throw new J.OcamlExn(x, msg);
      }
      return J.val(t, x);
    },

    // UTF-8 (or Latin-1) bytes of a string, copied by stringCopy (or the
    // string itself when it is short and ASCII)
    bytes: null,
    ascii: null,
    stringLength(v, latin1) {
      var J = ocamlJs, s = String(v);
      if (s.length <= 64) {
        var i = 0;
        while (i < s.length && s.charCodeAt(i) < 0x80) i++;
        if (i == s.length) { J.ascii = s; return s.length; }
      }
      if (latin1) {
        var b = new Uint8Array(s.length);
        for (var i = 0; i < s.length; i++) b[i] = s.charCodeAt(i);
        J.bytes = b;
      } else J.bytes = new TextEncoder().encode(s);
      return J.bytes.length;
    },
  },

  ocaml_js_init__deps: ['$ocamlJs'],
  ocaml_js_init: (retAddr, outAddr, bits) => ocamlJs.init(retAddr, outAddr, bits),

  ocaml_js_free__deps: ['$ocamlJs'],
  ocaml_js_free: (h) => {
    if (h > 5) { ocamlJs.vals[h] = undefined; ocamlJs.freeList.push(h); }
  },

  ocaml_js_get__deps: ['$ocamlJs'],
  ocaml_js_get: (ot, ox, kt, kx, kl) => ocamlJs.run(() => ocamlJs.val(ot, ox)[ocamlJs.key(kt, kx, kl)]),

  ocaml_js_set__deps: ['$ocamlJs'],
  ocaml_js_set: (ot, ox, kt, kx, kl, vt, vx) =>
    ocamlJs.run(() => { ocamlJs.val(ot, ox)[ocamlJs.key(kt, kx, kl)] = ocamlJs.val(vt, vx); }),

  ocaml_js_delete__deps: ['$ocamlJs'],
  ocaml_js_delete: (ot, ox, kt, kx, kl) => ocamlJs.run(() => { delete ocamlJs.val(ot, ox)[ocamlJs.key(kt, kx, kl)]; }),

  // f.apply(o, args)
  ocaml_js_call__deps: ['$ocamlJs'],
  ocaml_js_call: (ft, fx, ot, ox, p, n) =>
    ocamlJs.run(() => ocamlJs.val(ft, fx).apply(ocamlJs.val(ot, ox), ocamlJs.args(p, n))),

  ocaml_js_meth_call__deps: ['$ocamlJs'],
  ocaml_js_meth_call: (ot, ox, kt, kx, kl, p, n) =>
    ocamlJs.run(() => {
      var o = ocamlJs.val(ot, ox);
      return o[ocamlJs.key(kt, kx, kl)](...ocamlJs.args(p, n));
    }),

  ocaml_js_new__deps: ['$ocamlJs'],
  ocaml_js_new: (ct, cx, p, n) => ocamlJs.run(() => new (ocamlJs.val(ct, cx))(...ocamlJs.args(p, n))),

  ocaml_js_new_arr__deps: ['$ocamlJs'],
  ocaml_js_new_arr: (ct, cx, at, ax) => ocamlJs.run(() => new (ocamlJs.val(ct, cx))(...ocamlJs.val(at, ax))),

  ocaml_js_array__deps: ['$ocamlJs'],
  ocaml_js_array: (p, n) => ocamlJs.run(() => ocamlJs.args(p, n)),

  ocaml_js_new_obj__deps: ['$ocamlJs'],
  ocaml_js_new_obj: () => ocamlJs.handle({}),

  // the number of elements of an array-like value
  ocaml_js_length__deps: ['$ocamlJs'],
  ocaml_js_length: (t, x) => ocamlJs.val(t, x).length | 0,

  ocaml_js_equals__deps: ['$ocamlJs'],
  ocaml_js_equals: (at, ax, bt, bx) => (ocamlJs.val(at, ax) == ocamlJs.val(bt, bx) ? 1 : 0),

  ocaml_js_strict_equals__deps: ['$ocamlJs'],
  ocaml_js_strict_equals: (at, ax, bt, bx) => (ocamlJs.val(at, ax) === ocamlJs.val(bt, bx) ? 1 : 0),

  ocaml_js_instanceof__deps: ['$ocamlJs'],
  ocaml_js_instanceof: (at, ax, ct, cx) => {
    try { return ocamlJs.val(at, ax) instanceof ocamlJs.val(ct, cx) ? 1 : 0; } catch (e) { return 0; }
  },

  ocaml_js_typeof__deps: ['$ocamlJs'],
  ocaml_js_typeof: (t, x) => ocamlJs.handle(typeof ocamlJs.val(t, x)),

  ocaml_js_truthy__deps: ['$ocamlJs'],
  ocaml_js_truthy: (t, x) => (ocamlJs.val(t, x) ? 1 : 0),

  ocaml_js_number__deps: ['$ocamlJs'],
  ocaml_js_number: (t, x) => +ocamlJs.val(t, x),

  ocaml_js_int32__deps: ['$ocamlJs'],
  ocaml_js_int32: (t, x) => ocamlJs.val(t, x) | 0,

  ocaml_js_float__deps: ['$ocamlJs'],
  ocaml_js_float: (d) => ocamlJs.ret(d),

  // a string from UTF-8 (or Latin-1) bytes
  ocaml_js_string__deps: ['$ocamlJs'],
  ocaml_js_string: (p, len, latin1) => {
    if (!latin1) return ocamlJs.handle(ocamlJs.decode(p, len));
    var s = '';
    for (var i = 0; i < len; i += 8192)
      s += String.fromCharCode.apply(null, HEAPU8.subarray(p + i, p + Math.min(len, i + 8192)));
    return ocamlJs.handle(s);
  },

  ocaml_js_string_length__deps: ['$ocamlJs'],
  ocaml_js_string_length: (t, x, latin1) => ocamlJs.stringLength(ocamlJs.val(t, x), latin1),

  ocaml_js_string_copy__deps: ['$ocamlJs'],
  ocaml_js_string_copy: (p) => {
    var J = ocamlJs;
    if (J.ascii !== null) {
      for (var i = 0, s = J.ascii; i < s.length; i++) HEAPU8[p + i] = s.charCodeAt(i);
      J.ascii = null;
    } else {
      HEAPU8.set(J.bytes, p);
      J.bytes = null;
    }
  },

  ocaml_js_eval__deps: ['$ocamlJs'],
  ocaml_js_eval: (p, len, kind) =>
    ocamlJs.run(() => {
      var s = ocamlJs.decode(p, len);
      var J = ocamlJs;
      if (Object.prototype.hasOwnProperty.call(J.runtime, s)) return J.runtime[s];
      // the values of --js-file files (Js.Unsafe.runtime_value)
      if (typeof ocamlEmccJsPrims == 'object' && Object.prototype.hasOwnProperty.call(ocamlEmccJsPrims, s))
        return ocamlEmccJsPrims[s];
      // kind 0: statements (eval_string), 1: an expression, 2: a variable
      if (kind == 0) return (0, eval)('"use strict";' + s);
      if (kind == 2 && /^[a-zA-Z_$][a-zA-Z_$0-9]*(\.[a-zA-Z_$][a-zA-Z_$0-9]*)*$/.test(s)) {
        var v = globalThis, path = s.split('.');
        for (var i = 0; i < path.length && v != null; i++) v = v[path[i]];
        if (v !== undefined || path[0] in globalThis) return v;
      }
      return (0, eval)('"use strict";(' + s + ')');
    }),

  // the element i of an array-like value
  ocaml_js_index__deps: ['$ocamlJs'],
  ocaml_js_index: (t, x, i) => ocamlJs.run(() => ocamlJs.val(t, x)[i]),

  // the arguments of the callback being run
  ocaml_js_cb_arg__deps: ['$ocamlJs'],
  ocaml_js_cb_arg: (i) => ocamlJs.ret(ocamlJs.cbArgs[ocamlJs.cbArgs.length - 1][i]),

  // the message of an OCaml exception leaving a callback
  ocaml_js_cb_exn__deps: ['$ocamlJs', '$UTF8ToString'],
  ocaml_js_cb_exn: (p) => { ocamlJs.pending = 'Fatal error: exception ' + UTF8ToString(p); },

  ocaml_js_wrap__deps: ['$ocamlJs'],
  ocaml_js_wrap: (kind, arity, cell) => ocamlJs.handle(ocamlJs.wrap(kind, arity, cell)),

  ocaml_js_console__deps: ['$ocamlJs'],
  ocaml_js_console: () => ocamlJs.handle(console),

  ocaml_js_debugger: () => { debugger; },

  ocaml_js_html_entities__deps: ['$ocamlJs'],
  ocaml_js_html_entities: (t, x) =>
    ocamlJs.run(() => {
      var s = ocamlJs.val(t, x);
      if (!/^&#?[0-9a-zA-Z]+;$/.test(s) || typeof document == 'undefined') return null;
      var p = document.createElement('p');
      p.innerHTML = s;
      return p.textContent || p.innerText;
    }),

  ocaml_js_xhr__deps: ['$ocamlJs'],
  ocaml_js_xhr: () => (typeof XMLHttpRequest == 'undefined' ? 0 : ocamlJs.handle(new XMLHttpRequest())),

  ocaml_js_promise_wrap__deps: ['$ocamlJs'],
  ocaml_js_promise_wrap: (t, x) =>
    ocamlJs.run(() => {
      var v = ocamlJs.val(t, x);
      return v != null && typeof v.then == 'function' ? { ocamlPromiseWrapped: v } : v;
    }),

  ocaml_js_promise_unwrap__deps: ['$ocamlJs'],
  ocaml_js_promise_unwrap: (t, x) =>
    ocamlJs.run(() => {
      var v = ocamlJs.val(t, x);
      return v != null && typeof v == 'object' && 'ocamlPromiseWrapped' in v ? v.ocamlPromiseWrapped : v;
    }),

  // typed arrays: the bigarray kind of one (-1: none), a new one of a kind
  // from a copy of n elements at p, and the copy of one to p
  ocaml_js_ta_kind__deps: ['$ocamlJs'],
  ocaml_js_ta_kind: (t, x) => {
    var v = ocamlJs.val(t, x);
    // kinds of caml/bigarray.h
    if (v instanceof Float32Array) return 0;
    if (v instanceof Float64Array) return 1;
    if (v instanceof Int8Array) return 2;
    if (v instanceof Uint8Array || v instanceof Uint8ClampedArray) return 3;
    if (v instanceof Int16Array) return 4;
    if (v instanceof Uint16Array) return 5;
    if (v instanceof Int32Array) return 6;
    if (typeof BigInt64Array != 'undefined' && v instanceof BigInt64Array) return 7;
    return -1;
  },

  ocaml_js_ta_create__deps: ['$ocamlJs'],
  ocaml_js_ta_create: (kind, p, n, buffer) => {
    var C = [Float32Array, Float64Array, Int8Array, Uint8Array, Int16Array, Uint16Array, Int32Array, BigInt64Array][kind];
    var a = new C(n);
    a.set(new C(HEAPU8.buffer, p, n));
    return ocamlJs.handle(buffer ? a.buffer : a);
  },

  ocaml_js_ta_copy__deps: ['$ocamlJs'],
  ocaml_js_ta_copy: (t, x, p) => {
    var v = ocamlJs.val(t, x);
    if (v instanceof ArrayBuffer) v = new Uint8Array(v);
    new Uint8Array(HEAPU8.buffer, p, v.byteLength).set(new Uint8Array(v.buffer, v.byteOffset, v.byteLength));
  },

  // a primitive of a --js-file (`link` declares them in ocamlEmccJsPrims)
  ocaml_js_prim__deps: ['$ocamlJs', '$UTF8ToString'],
  ocaml_js_prim: (name, p, n) =>
    ocamlJs.run(() => {
      var s = UTF8ToString(name);
      var f = typeof ocamlEmccJsPrims == 'object' ? ocamlEmccJsPrims[s] : undefined;
      if (typeof f != 'function') throw new Error('primitive ' + s + ' is not defined in JavaScript');
      return f(...ocamlJs.args(p, n));
    }),

  ocaml_js_ta_bytes__deps: ['$ocamlJs'],
  ocaml_js_ta_bytes: (t, x) => {
    var v = ocamlJs.val(t, x);
    return v.byteLength | 0;
  },
});
