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
#   5.4    patches/5.4 (commit memory with mprotect, no mmap(MAP_FIXED))

SOURCE=ocaml

host_cc() { command -v cc || command -v gcc || command -v clang; }

build() {
  # The build dir kept by opam has been built for the host: start clean.
  if [ -f Makefile.config ] || [ -f Makefile.build_config ]; then
    make distclean >/dev/null 2>&1 || true
  fi

  if [ "$OCAML_MAJOR" -lt 5 ]; then apply_patches "$RECIPE_DIR/patches/4.x"; fi
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
  cp runtime/caml/*.tbl "$OCAML_INC/caml/" 2>/dev/null || true
  # Headers installed by otherlibs (unixsupport.h, socketaddr.h...).
  for h in otherlibs/unix/unixsupport.h otherlibs/unix/socketaddr.h; do
    [ -f "$h" ] && cp "$h" "$OCAML_INC/caml/"
  done

  write_toolchain
}
