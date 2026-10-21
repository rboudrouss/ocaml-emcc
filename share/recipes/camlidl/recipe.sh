# CamlIDL runtime (libcamlidl.a), needed by the stubs camlidl generates
# (mlgmpidl, apron...).  The camlidl tool itself runs on the host.

SOURCE=opam:camlidl

build() {
  cd runtime
  local objs o
  # the object list of the Unix runtime, whatever the version
  objs=$(sed -n 's/^OBJS *= *//p' Makefile.unix)
  [ -n "$objs" ] || objs="idlalloc.o comintf.o comerror.o"
  for o in $objs; do stub_cc "${o%.o}.c"; done
  mklib camlidl $objs
  install_lib libcamlidl.a
  install_headers caml camlidlruntime.h
  provides camlidl camlidl
}
