# FLINT (conf-flint), the Fast Library for Number Theory, for the flint
# bindings and apron's PPLite domain: on top of the gmp and mpfr recipes,
# generic C (no assembly), thread-safe (its caches in thread-local
# variables; its own threads only when a program asks for them, with
# --threads).  Functions change between minor versions: the host's minor
# version.
SOURCE=system:flint
DEPENDS="gmp mpfr"
HEADER=flint/flint.h
VERSION_MACROS="__FLINT_VERSION __FLINT_VERSION_MINOR __FLINT_VERSION_PATCHLEVEL"
COMPAT=minor
LINK="-lflint -lmpfr -lgmp"
releases() {
  git_tag_releases https://github.com/flintlib/flint.git v \
    'https://github.com/flintlib/flint/releases/download/v{v}/flint-{v}.tar.gz'
}

build() {
  log "configure (emconfigure)"
  emconfigure ./configure --host="$TARGET-unknown-emscripten" --prefix="$SYSROOT" \
    --enable-static --disable-shared --disable-assembly --disable-dependency-tracking \
    --with-gmp="$SYSROOT" --with-mpfr="$SYSROOT" CFLAGS="$CFLAGS" > configure.log 2>&1 \
    || { tail -30 configure.log; die "configure failed"; }
  log "make (its thousands of files: a while)"
  # (it merges the objects of each directory with `$(LD) -r`: emcc, with
  # the target's flags, -m64)
  emmake make -j"$NPROC" LD="$EMCC $TARGET_FLAGS" > make.log 2>&1 || { tail -30 make.log; die "make failed"; }
  emmake make install LD="$EMCC $TARGET_FLAGS" > install.log 2>&1 || { tail -30 install.log; die "install failed"; }
  provides flint flint
}
