# Plugins (tests/dynlink), compiled mode only: tests/run.sh --compiled.
# ocaml-emcc.dynlink comes from the build of this repository.
OCAML_EMCC ?= ocaml-emcc
# (OE_LIB: that of another build, for another switch)
OE_LIB ?= $(abspath ../../_build/install/default/lib)
export OCAMLPATH := $(OE_LIB):$(OCAMLPATH)
export CAML_LD_LIBRARY_PATH := $(OE_LIB)/stublibs:$(CAML_LD_LIBRARY_PATH)
OCAMLC = ocamlfind ocamlc -package str,ocaml-emcc.dynlink
PLUGINS = out/a.wasm out/b.wasm out/raises.wasm out/stale.wasm out/late.wasm

# the plugins are read from the real file system (--node-fs)
out/main.js: main.bc $(PLUGINS:.wasm=.src)
	mkdir -p out
	$(OCAML_EMCC) link main.bc -o $@ --dynlink --node-fs $(LINK_FLAGS)
	for p in $(PLUGINS); do $(OCAML_EMCC) plugin $$(cat $${p%.wasm}.src) -o $$p --main $@ || exit 1; done

# -linkall: the plugins may use any module of the program
main.bc: app.ml main.ml
	$(OCAMLC) -linkpkg -linkall app.ml main.ml -o $@

out/a.src: a.ml main.bc
	mkdir -p out; $(OCAMLC) -c a.ml; echo a.cmo > $@
out/b.src: b1.ml b2.ml out/a.src
	mkdir -p out; $(OCAMLC) -c b1.ml b2.ml; $(OCAMLC) -a b1.cmo b2.cmo -o b.cma; echo b.cma > $@
out/raises.src: raises.ml main.bc
	mkdir -p out; $(OCAMLC) -c raises.ml; echo raises.cmo > $@
# compiled against another version of App
# (raises.ml: refused before it runs)
out/stale.src: raises.ml main.bc
	mkdir -p out/stale; cp app.ml raises.ml out/stale/; echo 'let extra = 0' >> out/stale/app.ml
	(cd out/stale && $(OCAMLC) -c app.ml raises.ml); echo out/stale/raises.cmo > $@
out/late.src: late.ml out/b.src
	mkdir -p out; $(OCAMLC) -c late.ml; echo late.cmo > $@

clean:
	rm -rf out *.cm* *.bc .*.ocaml-emcc
