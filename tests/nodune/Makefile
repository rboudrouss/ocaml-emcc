# Building without dune: the C stubs with emcc, the bytecode with ocamlfind,
# then `ocaml-emcc link`.  OCAML_EMCC can point to a development build.
OCAML_EMCC ?= ocaml-emcc

out/prog.js: prog.bc libstub.a
	$(OCAML_EMCC) link prog.bc -o $@ -l ./libstub.a

# The stub archive for wasm: emcc with the runtime's headers and flags.
libstub.a: stub.c
	emcc $$($(OCAML_EMCC) env --cflags) -c stub.c -o stub.o
	emar rcs $@ stub.o

# Plain bytecode.  -no-check-prims: our primitives only exist in libstub.a,
# which `ocaml-emcc link` adds (zarith and unix are found automatically).
prog.bc: prog.ml
	ocamlfind ocamlc -package zarith,unix -linkpkg -no-check-prims prog.ml -o $@

clean:
	rm -rf out prog.bc prog.cm* stub.o libstub.a
