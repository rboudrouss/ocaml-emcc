# The OCaml bytecode runtime (libcamlrun.a) and the C parts of the otherlibs
# (unix, str, runtime_events), compiled with emscripten from the sources of
# the switch's compiler.  Whatever the switch version, the host compiler keeps
# producing the bytecode; only the C runtime is rebuilt here.
#
# Version specifics:
#   4.x    patches/4.x (Tag_val signed index)
#   >=4.14 runtime/sak is a build-time host tool, it must be built with the
#          host C compiler (emconfigure would turn it into a .wasm that make
#          then fails to execute)
#   5.x    no POSIX signals (no sigaltstack in emscripten), no -pthread
#   >=5.4  patches/5.4+ (commit memory with mprotect, no mmap(MAP_FIXED))
#   all    wasm32: literals beyond 31 bits wrapped while DATA is read;
#          debug events from memory for caml_startup_code (standalone .wasm)

SOURCE=ocaml

host_cc() { command -v cc || command -v gcc || command -v clang; }

# intern.c: a CODE_INT64 read while caml_emcc_wrap_ints is set keeps its low
# 32 bits (the stream is big-endian), which Val_long truncates to 31;
# startup_byt.c sets it while reading the DATA section.
wrap_data_literals() {
  local args=; [ "$OCAML_MAJOR" -ge 5 ] && args=s
  perl -0pi -e 's/(#else\n(\s*))((?:intern_cleanup\(\);\s*caml_failwith\("input_value: integer too large"\)|intern_cleanup_failwith2\(s, fun_name, "integer too large"\));)/$1if (caml_emcc_wrap_ints) { (void) read32u('"$args"'); v = Val_long((intnat) (int32_t) read32u('"$args"')); break; }\n$2$3/' runtime/intern.c
  grep -q caml_emcc_wrap_ints runtime/intern.c || die "intern.c: cannot patch the CODE_INT64 case"
  perl -0pi -e 's/(\n#include "caml\/intext.h"\n)/$1int caml_emcc_wrap_ints = 0;\n/' runtime/intern.c
  grep -q '^int caml_emcc_wrap_ints' runtime/intern.c || die "intern.c: cannot define caml_emcc_wrap_ints"
  perl -0pi -e 's/^(\s*)((?:caml_global_data|value global_data) = caml_input_val\(chan\);)/$1caml_emcc_wrap_ints = 1;\n$1$2\n$1caml_emcc_wrap_ints = 0;/m; s/(\n#include "caml\/intext.h"\n)/$1extern int caml_emcc_wrap_ints;\n/' runtime/startup_byt.c
  [ "$(grep -c caml_emcc_wrap_ints runtime/startup_byt.c)" = 3 ] || die "startup_byt.c: cannot patch the DATA section reading"
  # caml_startup_code (a standalone OUT.wasm: the bytecode linked in as C
  # arrays) reads the DATA section from memory
  perl -0pi -e 's/caml_input_value_from_block\(data, data_size\)/caml_emcc_input_data(data, data_size)/; s/(\nextern int caml_emcc_wrap_ints;\n)/$1static value caml_emcc_input_data(char *data, asize_t size)\n{\n  value v;\n  caml_emcc_wrap_ints = 1;\n  v = caml_input_value_from_block(data, size);\n  caml_emcc_wrap_ints = 0;\n  return v;\n}\n/' runtime/startup_byt.c
  [ "$(grep -c caml_emcc_input_data runtime/startup_byt.c)" = 2 ] || die "startup_byt.c: cannot patch caml_startup_code's DATA reading"
}

# backtrace_byt.c: the debug events of a program started by
# caml_startup_code come from memory (caml_emcc_debug_events, set by the
# main.c of a standalone OUT.wasm), already relocated and gathered in an
# array by `link`, instead of the DBUG section of the executable file, which
# does not exist.  NULL otherwise: the runtime behaves as before.
embedded_debug_info() {
  perl -0pi -e 's/(\nstatic void read_main_debug_info\()/\nchar *caml_emcc_debug_events = NULL;\nuintnat caml_emcc_debug_events_size = 0;\n$1/; s/(\n(\s*)di->already_read = 1;\n)/$1\n$2if (caml_emcc_debug_events != NULL) {\n$2  events = caml_input_value_from_block(caml_emcc_debug_events, caml_emcc_debug_events_size);\n$2  di->events = process_debug_events(caml_start_code, events, &di->num_events);\n$2  CAMLreturn0;\n$2}\n/' runtime/backtrace_byt.c
  [ "$(grep -c caml_emcc_debug_events runtime/backtrace_byt.c)" = 4 ] || die "backtrace_byt.c: cannot patch read_main_debug_info"
}

build() {
  # The build dir kept by opam has been built for the host: start clean.
  if [ -f Makefile.config ] || [ -f Makefile.build_config ]; then
    make distclean >/dev/null 2>&1 || true
  fi

  if [ "$OCAML_MAJOR" -lt 5 ]; then apply_patches "$RECIPE_DIR/patches/4.x"; fi
  if ocaml_version_ge 5 4; then apply_patches "$RECIPE_DIR/patches/5.4+"; fi
  apply_patches "$RECIPE_DIR/patches/$OCAML_MAJOR.$OCAML_MINOR"

  # OCaml 5 sets up an alternate signal stack per domain when POSIX signals
  # are available; emscripten has no sigaltstack ("Failed to allocate signal
  # stack for domain 0").  Signals are never delivered asynchronously there
  # anyway: take the non-POSIX (Windows-like) code path.
  local cache_vars=()
  [ "$OCAML_MAJOR" -ge 5 ] && cache_vars+=(ac_cv_func_sigaction=no)

  # Before 4.10, caml_debug_info is defined in both backtrace.c and
  # backtrace_byt.c, which only links with common symbols (-fcommon), not
  # supported on wasm.  Keep the backtrace_byt.c one.
  ocaml_version_ge 4 10 || sed -i 's/^struct ext_table caml_debug_info;/extern &/' runtime/backtrace.c

  # Target flags (-m64, longjmp flavour...) go in CC as well: some versions
  # (4.08 to 4.11) compile the otherlibs without the configure-time CFLAGS.
  log "configure (emconfigure)"
  emconfigure ./configure \
    --disable-native-compiler --disable-ocamltest --disable-ocamldoc \
    --disable-debugger --disable-systhreads \
    CC="$EMCC $TARGET_FLAGS" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" "${cache_vars[@]}" > configure.log 2>&1 || { tail -30 configure.log; die "configure failed"; }

  # OCaml 5's configure appends -pthread to CFLAGS.  Objects built with it
  # access caml_state through real wasm TLS, objects built without it (the
  # stubs) through a plain global: mixed, the stubs read a wrong address
  # ("no domain lock held").  Stay single-threaded everywhere.
  if grep -q -- '-pthread' Makefile.config; then
    sed -i -e '/^CFLAGS=/s/ -pthread//g' -e '/^LDFLAGS=/s/ -pthread//g' Makefile.config
  fi

  # wasm loads doubles and 64-bit ints at any alignment, like i686, the only
  # 32-bit target configure exempts.  With ARCH_ALIGN_DOUBLE every float field
  # access is a copy, and stubs with views on float arrays refuse to build
  # (gsl: "double-word alignment for doubles is not supported").
  if [ "$TARGET" = wasm32 ]; then
    sed -i -e 's|^#define ARCH_ALIGN_DOUBLE 1|/* #undef ARCH_ALIGN_DOUBLE */|' \
           -e 's|^#define ARCH_ALIGN_INT64 1|/* #undef ARCH_ALIGN_INT64 */|' runtime/caml/m.h
  fi

  # wasm32 runs 64-bit bytecode: the literals that do not fit in 31 bits
  # are in the DATA section, as 64-bit integers, which intern refuses
  # ("input_value: integer too large").  A 32-bit ocamlc would have wrapped
  # those it accepts (0x40000000 is min_int there), and they are mostly in
  # code meant for 32-bit platforms, selected at run time by Sys.word_size
  # (optint).  The DATA section is read with them wrapped to 31 bits, like
  # the arithmetic; `ocaml-emcc link` warns about each one.  Marshalled data
  # read by the program still fails on them.
  if [ "$TARGET" = wasm32 ]; then wrap_data_literals; fi
  embedded_debug_info

  local cc; cc=$(host_cc)
  # sak (OCaml >= 4.14): build it for the host.  SAK_CC/SAK_LINK exist in
  # every version that has sak; pre-building it as well keeps make from
  # retrying with emcc through the dependency chain.
  local sak_vars=()
  if [ -f runtime/sak.c ]; then
    log "sak: host build with $cc"
    "$cc" -c -Iruntime -o runtime/sak.o runtime/sak.c
    "$cc" -o runtime/sak runtime/sak.o
    touch runtime/sak.o runtime/sak
    sak_vars=(SAK_CC="$cc" SAK_CFLAGS="-Iruntime" "SAK_LINK=$cc -o \$(1) \$(2)")
  fi

  # via sh: opam installs share/ without the executable bit
  local mk="sh $OCAML_EMCC_SHARE/tools/ocamlmklib"
  export OCAML_EMCC_HOST_BIN=$HOST_BIN

  # The runtime: runtime/Makefile in 4.x, the root Makefile in 5.x.
  log "make libcamlrun.a"
  if [ "$OCAML_MAJOR" -lt 5 ]; then
    make -C runtime -j"$NPROC" "${sak_vars[@]}" libcamlrun.a > make.log 2>&1
  else
    make -j"$NPROC" "${sak_vars[@]}" runtime/libcamlrun.a > make.log 2>&1
  fi || { tail -30 make.log; die "runtime build failed"; }
  install_lib runtime/libcamlrun.a
  provides ocaml camlrun

  # C stubs of the otherlibs.  Their archive is built by ocamlmklib, which
  # needs a working ocamlrun: substitute our emar-based replacement
  # (MKLIB_CMD in 4.x, MKLIB in 5.x).  Bytecode stub archives got a "byt"
  # suffix in 5.0.
  local sfx=; [ "$OCAML_MAJOR" -ge 5 ] && sfx=byt
  local dir clib
  # systhreads (configured out) builds as well: without -pthread, emscripten's
  # pthread functions are single-threaded stubs, so Mutex, Condition and
  # Thread.self work and Thread.create fails.  Libraries that merely depend on
  # threads (ctypes-foreign...) then link.
  for dir in unix str runtime_events systhreads; do
    [ -d "otherlibs/$dir" ] || continue
    case $dir in
      unix) clib=unix$sfx ;; str) clib=camlstr$sfx ;;
      runtime_events) clib=camlruntime_events$sfx ;; systhreads) clib=threads ;;
    esac
    log "make otherlibs/$dir (lib$clib.a)"
    make -C "otherlibs/$dir" -j"$NPROC" MKLIB="$mk" MKLIB_CMD="$mk" "lib$clib.a" >> make.log 2>&1 \
      || { tail -30 make.log; die "otherlibs/$dir failed"; }
    install_lib "otherlibs/$dir/lib$clib.a"
    provides ocaml "$clib"
  done

  # wasm headers: these, not the host's, must be seen by stub code.
  rm -rf "$OCAML_INC/caml"; mkdir -p "$OCAML_INC/caml"
  cp runtime/caml/*.h "$OCAML_INC/caml/"
  # for stubs only (the runtime is built): the dimensions of
  # caml_ba_alloc_dims converted to intnat, see ba_alloc_dims.h
  OCAML_EMCC_BA="$(cat "$RECIPE_DIR/ba_alloc_dims.h")" perl -0pi -e \
    's{(#endif /\* CAML_BIGARRAY_H \*/\s*)$}{$ENV{OCAML_EMCC_BA}\n$1}' "$OCAML_INC/caml/bigarray.h"
  grep -q OCAML_EMCC_BA_COUNT "$OCAML_INC/caml/bigarray.h" || die "bigarray.h: cannot add the caml_ba_alloc_dims macro"
  cp runtime/caml/*.tbl "$OCAML_INC/caml/" 2>/dev/null || true
  # Headers installed by otherlibs (unixsupport.h, socketaddr.h...).
  for h in otherlibs/unix/unixsupport.h otherlibs/unix/socketaddr.h; do
    [ -f "$h" ] && cp "$h" "$OCAML_INC/caml/"
  done
  # and the other headers the host installs (threads.h, which ctypes stubs
  # include...): not generated, so the host's are the same
  for h in "$("$HOST_BIN/ocamlc" -where)"/caml/*.h; do
    [ -f "$OCAML_INC/caml/${h##*/}" ] || cp "$h" "$OCAML_INC/caml/"
  done

  write_toolchain
}
