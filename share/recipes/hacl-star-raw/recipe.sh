# hacl-star-raw: HACL*'s verified C (libhacl_static.a) and its ctypes stubs
# (libocamlevercrypt.a), which its Makefile builds with cmake, then with C
# files that OCaml generators print (lib_gen/*_gen.exe).
#
# The C library is configured by cmake for emscripten: its portable code,
# without the vectorized variants (libintvector.h only knows x86, ARM and
# s390x) or Vale's x86 assembly.  The generators are built and run on the
# host, against the host's libhacl_static.a: they only print C.  The host's
# build has OCaml modules for every variant, so stubs are generated for all
# of them, and the functions of the missing variants trap when called, as
# they would natively on a CPU without them (EverCrypt does not pick them:
# its CPU detection finds no x86 features).

SOURCE=opam:hacl-star-raw

build() {
  command -v cmake >/dev/null || die "hacl-star-raw: cmake is needed"
  [ -f "$PREFIX/lib/hacl-star-raw/libhacl_static.a" ] || die "hacl-star-raw: the host's libhacl_static.a is needed"
  cd hacl-star-raw
  log "cmake (emcmake): HACL* C library"
  rm -rf build/CMakeCache.txt build/CMakeFiles
  ( cd build && emcmake cmake -G"Unix Makefiles" -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_C_FLAGS="$CFLAGS" .. ) > cmake.log 2>&1 || { tail -30 cmake.log; die "cmake failed"; }
  log "make hacl_static"
  emmake make -C build -j"$NPROC" hacl_static > make.log 2>&1 || { tail -30 make.log; die "make failed"; }

  log "generating the ctypes stubs (host generators)"
  local stubs m
  stubs=$(for m in lib_gen/*_gen.ml; do m=${m#lib_gen/}; echo "lib/${m%_gen.ml}_c_stubs.c"; done)
  # shellcheck disable=SC2086
  env -u OCAMLFIND_CONF -u OCAMLFIND_TOOLCHAIN -u CFLAGS -u CXXFLAGS -u LDFLAGS PATH="$HOST_BIN:$PATH" \
    make -j1 BLOCKLIST= CC=cc \
    OCAMLOPT="$HOST_BIN/ocamlfind opt -package ctypes,ctypes.stubs -linkpkg -I lib -I build" \
    OCAMLDEP="$HOST_BIN/ocamlfind dep -I lib -slash" \
    C_LIB="$PREFIX/lib/hacl-star-raw/libhacl_static.a" $stubs > gen.log 2>&1 \
    || { tail -30 gen.log; die "the ctypes generators failed"; }

  local inc="-Iinclude -Ikaramel/include -Ikaramel/krmllib/dist/minimal -Ibuild -I$PREFIX/lib/ctypes" objs= c
  for c in $stubs; do
    # shellcheck disable=SC2086
    stub_cc "$c" $inc || die "hacl-star-raw: cannot compile $c"
    objs="$objs ${c%.c}.o"
  done

  # the HACL* functions the stubs call that the library lacks: traps
  local nm=$EMSDK_BIN/../bin/llvm-nm
  # shellcheck disable=SC2086
  comm -23 <("$nm" --undefined-only --format=just-symbols $objs 2>/dev/null | grep -E '^(Hacl|EverCrypt|Lib)_' | sort -u) \
           <("$nm" --defined-only --format=just-symbols build/libhacl_static.a 2>/dev/null | sort -u) \
    | awk 'BEGIN { print "/* variants not built for wasm: they trap if called */" }
           { print "void " $1 "(void) { __builtin_trap(); }" }' > missing.c
  log "$(($(wc -l < missing.c) - 1)) functions of variants not built for wasm (they trap)"
  "$EMCC" $CFLAGS -c missing.c -o missing.o
  # shellcheck disable=SC2086
  mklib ocamlevercrypt $objs
  mklib hacl_static_missing missing.o
  cp build/libhacl_static.a libhacl_static.a
  "$EMAR" q libhacl_static.a missing.o
  install_lib libocamlevercrypt.a libhacl_static.a
  link_flags ocamlevercrypt "-lhacl_static"
  provides hacl-star-raw ocamlevercrypt hacl_static
}
