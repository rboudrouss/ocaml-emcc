# Plugins fetched by a web page (tests/dynweb): the modules of tests/dynlink,
# compiled mode only, run in headless Chromium by check.mjs.
OCAML_EMCC ?= ocaml-emcc
OE_LIB ?= $(abspath ../../_build/install/default/lib)
export OCAMLPATH := $(OE_LIB):$(OCAMLPATH)
export CAML_LD_LIBRARY_PATH := $(OE_LIB)/stublibs:$(CAML_LD_LIBRARY_PATH)
OCAMLC = ocamlfind ocamlc -package str,ocaml-emcc.dynlink
SRC = app.ml a.ml b1.ml b2.ml raises.ml late.ml

out/main.js: main.ml $(SRC)
	mkdir -p out
	$(OCAMLC) -linkpkg -linkall app.ml main.ml -o main.bc
	$(OCAMLC) -c a.ml b1.ml b2.ml raises.ml late.ml
	$(OCAMLC) -a b1.cmo b2.cmo -o b.cma
	$(OCAML_EMCC) link main.bc -o $@ --dynlink $(LINK_FLAGS)
	for p in a.cmo b.cma raises.cmo late.cmo; do $(OCAML_EMCC) plugin $$p -o out/$${p%.*}.wasm --main $@ || exit 1; done

$(SRC): %.ml: ../dynlink/%.ml
	cp $< $@

clean:
	rm -rf out $(SRC) *.cm* *.bc .*.ocaml-emcc
