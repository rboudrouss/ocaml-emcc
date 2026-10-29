#!/usr/bin/env python3
"""missing.py ARITIES WSOO_LOG : the "name arity" lines of ARITIES that wasm_of_ocaml
reports as missing in WSOO_LOG (its list runs names together)."""
import sys
ar = dict(l.split() for l in open(sys.argv[1]) if l.strip())
log = open(sys.argv[2]).read()
text = log.split("Missing primitives:", 1)[1] if "Missing primitives:" in log else ""
text = "".join(text.split())
found = []
for name in sorted(ar, key=len, reverse=True):
    if name in text:
        text = text.replace(name, " ")
        found.append(name)
if text.strip():
    sys.exit(f"unresolved in the missing list: {text.split()}")
for n in sorted(found):
    print(n, ar[n])
