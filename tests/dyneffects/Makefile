# Plugins with effects (tests/dyneffects): compiled mode, OCaml >= 5.
OCAML_EMCC ?= ocaml-emcc
OE_LIB ?= $(abspath ../../_build/install/default/lib)
export OCAMLPATH := $(OE_LIB):$(OCAMLPATH)
export CAML_LD_LIBRARY_PATH := $(OE_LIB)/stublibs:$(CAML_LD_LIBRARY_PATH)
OCAMLC = ocamlfind ocamlc -package ocaml-emcc.dynlink

# The program performs effects: double translation without --effects.
# p.wasm follows it, nodt.wasm does not and is refused when loaded, and p
# built without effect handlers is refused by ocaml-emcc
out/main.js: app.ml main.ml p.ml nodt.ml
	mkdir -p out
	$(OCAMLC) -linkpkg -linkall app.ml main.ml -o main.bc
	$(OCAMLC) -c p.ml nodt.ml
	$(OCAML_EMCC) link main.bc -o $@ --dynlink --node-fs $(LINK_FLAGS)
	$(OCAML_EMCC) plugin p.cmo -o out/p.wasm --main $@
	$(OCAML_EMCC) plugin nodt.cmo -o out/nodt.wasm --effects disabled
	! $(OCAML_EMCC) plugin p.cmo -o out/bad.wasm 2> out/bad.log
	grep -q 'performs effects' out/bad.log

clean:
	rm -rf out *.cm* *.bc .*.ocaml-emcc
