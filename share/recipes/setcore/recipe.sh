# setcore: its opam build makes src/config.h (autoconf, autoheader,
# ./configure) before dune.  emscripten declares sched_setaffinity without
# defining it: the stubs are built without it, and setcore does nothing (as
# on systems without CPU affinity), without -Werror (unused variables then).

SOURCE=opam:setcore

build() {
  apply_patches "$BASE_RECIPE_DIR/patches"
  log "autoconf, autoheader, configure (emconfigure)"
  { autoconf && autoheader && emconfigure ./configure ac_cv_have_decl_sched_setaffinity=no; } > configure.log 2>&1 \
    || { tail -30 configure.log; die "configure failed"; }
  dune_stubs setcore
}
