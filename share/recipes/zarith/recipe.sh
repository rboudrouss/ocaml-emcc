# Zarith: one C file (caml_z.c) on top of GMP.  Its configure/Makefile are
# not cross-friendly (they probe the host and pick x86 assembly), but the
# stubs are trivial to compile directly, with the defines configure gives
# every OCaml >= 4.08 (used before zarith 1.12) and, before 1.12, the
# z_features.h that z_pp.pl writes (the assembly functions: none here).

SOURCE=opam:zarith
DEPENDS=gmp

build() {
  if grep -q '#include "z_features.h"' caml_z.c && [ ! -f z_features.h ]; then : > z_features.h; fi
  stub_cc caml_z.c -DHAS_GMP -DZ_OCAML_COMPARE_EXT -DZ_OCAML_HASH -I.
  mklib zarith caml_z.o
  install_lib libzarith.a
  install_headers . zarith.h
  link_flags zarith "-lgmp"
  provides zarith zarith
}
