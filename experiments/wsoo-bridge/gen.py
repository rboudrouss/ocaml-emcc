#!/usr/bin/env python3
"""gen.py bridge.wat PRIMS OUT.wat OUT.c OUT.js C_SOURCES... : PRIMS = lines "name arity".

OUT.js keeps the Callback.register of the names that the C sources look
up (wasm_of_ocaml drops the others)."""
import re, sys
wat, prims, out_wat, out_c, out_js = sys.argv[1:6]
names = set()
for f in sys.argv[6:]:
    names |= set(re.findall(r'caml_named_value\s*\(\s*"([^"]*)"', open(f, errors="replace").read()))
js = ["//Provides: oe_named_values", "//Always", "function oe_named_values() {",
      "  function caml_named_value(n) {}"]
js += [f"  caml_named_value({n!r});".replace("'", '"') for n in sorted(names)]
open(out_js, "w").write("\n".join(js + ["}"]) + "\n")
ps = [l.split() for l in open(prims) if l.strip()]
w = open(wat).read().rstrip()
assert w.endswith(")")
fns = []
for i, p in enumerate(ps):
    name, ar = p[0], int(p[1])
    params = " ".join(f"(param $a{j} (ref eq))" for j in range(ar))
    args = " ".join(f"(local.get $a{j})" for j in range(ar))
    fns.append(f'   (func (export "{name}") {params} (result (ref eq))\n'
               f'      (call $invoke (i32.const {i}) (array.new_fixed $block {ar} {args})))')
open(out_wat, "w").write(w[:-1] + "\n" + "\n".join(fns) + "\n)\n")
c = ["#include <caml/mlvalues.h>"]
# a third column: the arity of the C definition when it differs (ml_z_init())
for p in ps:
    name, ar = p[0], int(p[-1])
    c.append(f"extern value {name}({'value *, int' if ar > 5 else ', '.join(['value'] * ar) or 'void'});")
c.append("value oe_dispatch(int prim, value *a, int argc) {\n  switch (prim) {")
for i, p in enumerate(ps):
    name, ar = p[0], int(p[-1])
    call = f"{name}(a, argc)" if ar > 5 else f"{name}({', '.join(f'a[{j}]' for j in range(ar))})"
    c.append(f"  case {i}: return {call};")
c.append("  }\n  return Val_unit;\n}")
open(out_c, "w").write("\n".join(c) + "\n")
