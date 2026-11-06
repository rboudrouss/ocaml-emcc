# Plugins of a program with threads (tests/dynthreads): compiled mode only.
OCAML_EMCC ?= ocaml-emcc
OE_LIB ?= $(abspath ../../_build/install/default/lib)
export OCAMLPATH := $(OE_LIB):$(OCAMLPATH)
export CAML_LD_LIBRARY_PATH := $(OE_LIB)/stublibs:$(CAML_LD_LIBRARY_PATH)
OCAMLC = ocamlfind ocamlc -thread -package threads.posix,ocaml-emcc.dynlink

# The program has threads: yes (ocaml-emcc.conf), its plugin follows it
# (--main: linked with -pthread, for the shared memory), q.wasm uses p.wasm
# and is loaded by load_url, after main
out/main.js: app.ml main.ml p.ml q.ml
	mkdir -p out
	$(OCAMLC) -linkpkg -linkall app.ml main.ml -o main.bc
	$(OCAMLC) -c p.ml q.ml
	$(OCAML_EMCC) link main.bc -o $@ --dynlink --node-fs $(LINK_FLAGS)
	$(OCAML_EMCC) plugin p.cmo -o out/p.wasm --main $@
	$(OCAML_EMCC) plugin q.cmo -o out/q.wasm --main $@

clean:
	rm -rf out *.cm* *.bc .*.ocaml-emcc
