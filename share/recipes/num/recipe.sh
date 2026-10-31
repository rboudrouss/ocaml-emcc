# num: its stubs, under both names: libnums.a (its Makefile, which opam
# runs) and libnum_core_stubs.a (its dune build).  bng.c with the portable
# code (BNG_ARCH_generic): the Makefile picks the host's architecture, whose
# assembly (amd64) clang cannot compile for wasm.

SOURCE=opam:num

build() {
  cd src
  log "compiling bng.c and nat_stubs.c"
  stub_cc bng.c -DBNG_ARCH_generic || die "cannot compile bng.c"
  stub_cc nat_stubs.c || die "cannot compile nat_stubs.c"
  mklib nums bng.o nat_stubs.o
  cp libnums.a libnum_core_stubs.a
  install_lib libnums.a libnum_core_stubs.a
  provides num nums num_core_stubs
}
