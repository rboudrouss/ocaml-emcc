# cpu: the same as setcore (same author and build), whose patch it shares.

SOURCE=opam:cpu

build() {
  apply_patches "$OCAML_EMCC_SHARE/recipes/setcore/patches"
  log "autoconf, autoheader, configure (emconfigure)"
  { autoconf && autoheader && emconfigure ./configure ac_cv_have_decl_sched_setaffinity=no; } > configure.log 2>&1 \
    || { tail -30 configure.log; die "configure failed"; }
  dune_stubs cpu
}
