# owi's symbolic execution (tests/run.sh --wasi, owi: yes): the values for
# which the program fails.  ocaml-emcc.owi comes from the build of this
# repository.
OCAML_EMCC ?= ocaml-emcc
# (OE_LIB: that of another build, for another switch)
OE_LIB ?= $(abspath ../../_build/install/default/lib)
export OCAMLPATH := $(OE_LIB):$(OCAMLPATH)
export CAML_LD_LIBRARY_PATH := $(OE_LIB)/stublibs:$(CAML_LD_LIBRARY_PATH)

out/ow.wasm: ow.bc
	mkdir -p out
	$(OCAML_EMCC) link ow.bc -o $@ $(LINK_FLAGS)

ow.bc: ow.ml
	ocamlfind ocamlc -package ocaml-emcc.owi -linkpkg ow.ml -o $@

clean:
	rm -f ow.bc ow.cmi ow.cmo
