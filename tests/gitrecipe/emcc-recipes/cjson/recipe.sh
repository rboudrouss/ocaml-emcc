# A project-specific recipe: shallow clone of a C library from GitHub,
# compiled with emcc and installed in the sysroot (lib + headers).
# `requires: cjson` in ocaml-emcc.conf builds it before `build`/`link`,
# `link-flags: -lcjson` links it.

SOURCE=git:https://github.com/DaveGamble/cJSON.git
REF=v1.7.18

build() {
  "$EMCC" $CFLAGS -c cJSON.c -o cJSON.o
  mklib cjson cJSON.o
  install_lib libcjson.a
  install_headers cjson cJSON.h
}
