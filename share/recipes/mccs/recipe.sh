# mccs: the C++ stubs and the copy of GLPK it bundles, built with dune -x.
# To keep GLPK quiet, the solver closes stdout (fclose) and puts fd 1 back
# afterwards (dup2).  musl, unlike glibc, buffers what is written to the
# closed stdout and writes it once fd 1 is back: GLPK's messages end up in
# the program's output.  GLPK's own switch (glp_term_out) is used instead.

SOURCE=opam:mccs

build() {
  apply_patches "$BASE_RECIPE_DIR/patches"
  dune_stubs mccs
}
