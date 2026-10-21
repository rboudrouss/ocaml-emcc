# Zarith: one C file (caml_z.c) on top of GMP.  Its configure/Makefile are
# not cross-friendly (they probe the host and pick x86 assembly), but the
# stubs are trivial to compile directly.

SOURCE=opam:zarith
DEPENDS=gmp

build() {
  stub_cc caml_z.c -DHAS_GMP -I.
  mklib zarith caml_z.o
  install_lib libzarith.a
  install_headers . zarith.h
  link_flags zarith "-lgmp"
  provides zarith zarith
}
