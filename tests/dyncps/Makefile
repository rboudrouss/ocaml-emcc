# Plugins with --cps-stack (tests/dyncps): compiled mode only.
OCAML_EMCC ?= ocaml-emcc
OE_LIB ?= $(abspath ../../_build/install/default/lib)
export OCAMLPATH := $(OE_LIB):$(OCAMLPATH)
export CAML_LD_LIBRARY_PATH := $(OE_LIB)/stublibs:$(CAML_LD_LIBRARY_PATH)
OCAMLC = ocamlfind ocamlc -package ocaml-emcc.dynlink

# The program has cps-stack: yes (ocaml-emcc.conf): pdeep.wasm follows it
# (--main), pplain.wasm has double translation without --cps-stack, nodt.wasm
# has no effects and is refused
out/main.js: app.ml main.ml pdeep.ml pplain.ml nodt.ml
	mkdir -p out
	$(OCAMLC) -linkpkg -linkall app.ml main.ml -o main.bc
	$(OCAMLC) -c pdeep.ml pplain.ml nodt.ml
	$(OCAML_EMCC) link main.bc -o $@ --dynlink --node-fs $(LINK_FLAGS)
	$(OCAML_EMCC) plugin pdeep.cmo -o out/pdeep.wasm --main $@
	$(OCAML_EMCC) plugin pplain.cmo -o out/pplain.wasm --effects double-translation
	$(OCAML_EMCC) plugin nodt.cmo -o out/nodt.wasm --effects disabled

clean:
	rm -rf out *.cm* *.bc .*.ocaml-emcc
