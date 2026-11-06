# Bytecode plugins of an interpreted program (tests/dynbyte): OCaml's
# Dynlink, with the C stubs of a plugin as wasm dllX.so.
OCAML_EMCC ?= ocaml-emcc
OCAMLC = ocamlfind ocamlc
STR := $(shell ocamlfind query str)

# cst.cma's bytecode and host dllcst.so (ocamlmklib) here, on Dynlink's
# path, its wasm libcst.a in out/w, from which `plugin` makes the wasm
# dllcst.so in out/stublibs ($OCAML_EMCC_STUBLIBS, set by main.ml), and
# str's, which the program does not link; nodll.cma's wasm stubs are not
# built
out/main.js: app.ml main.ml a.ml b1.ml b2.ml u.ml r.ml cst.ml cst_stubs.c nodll.ml
	mkdir -p out/w
	$(OCAMLC) -package dynlink,unix -linkpkg -linkall app.ml main.ml -o main.bc
	$(OCAMLC) -c a.ml b1.ml b2.ml r.ml
	$(OCAMLC) -a b1.cmo b2.cmo -o b.cma
	$(OCAMLC) -package str -c u.ml
	$(OCAMLC) -c cst.ml nodll.ml cst_stubs.c
	ocamlmklib -o cst cst_stubs.o cst.cmo
	ocamlmklib -o nodll cst_stubs.o nodll.cmo
	cp cst.cma out/w/
	emcc $$($(OCAML_EMCC) env --cflags) -c cst_stubs.c -o out/w/cst_stubs.o
	emar rcs out/w/libcst.a out/w/cst_stubs.o
	$(OCAML_EMCC) link main.bc -o $@ --interpreted --dynlink --node-fs $(LINK_FLAGS)
	$(OCAML_EMCC) plugin out/w/cst.cma --main $@ -o out/stublibs
	cp $(STR)/str.cma out/
	$(OCAML_EMCC) plugin --interpreted out/str.cma --main $@ -o out/stublibs
	$(OCAML_EMCC) plugin b.cma --main $@

clean:
	rm -rf out *.cm* *.bc *.a *.so *.o .*.ocaml-emcc
