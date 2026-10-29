#!/usr/bin/env python3
"""mismatch.py PRIMS LINK_STDERR: PRIMS with, for each primitive that wasm-ld
reports defined with another signature than dispatch.o's call, the arity of
its C definition as a third column (zarith's ml_z_init() is called with ())."""
import re, sys
prims = [l.split() for l in open(sys.argv[1]) if l.strip()]
err = open(sys.argv[2]).read()
c_arity = {}
for m in re.finditer(r"function signature mismatch: (\S+)\n>>> defined as .* in dispatch\.o\n>>> defined as \(([^)]*)\)", err):
    c_arity[m.group(1)] = 0 if not m.group(2).strip() else m.group(2).count(",") + 1
for p in prims:
    print(" ".join(p[:2] + ([str(c_arity[p[0]])] if p[0] in c_arity else [])))
