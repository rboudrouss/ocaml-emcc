# --node-fs (tests/nodefs): the program reads the real files and changes
# directory.  OCAML_EMCC can point to a development build, LINK_FLAGS adds
# link options.
OCAML_EMCC ?= ocaml-emcc

out/prog.js: prog.ml
	ocamlfind ocamlc prog.ml -o prog.bc
	$(OCAML_EMCC) link prog.bc -o $@ --node-fs $(LINK_FLAGS)

clean:
	rm -rf out prog.bc prog.cm*
