# pixman, for cairo.  Generic C (no SIMD), thread-safe (meson's threads
# dependency: its -pthread does not make its users' programs threaded, the
# link of the program decides).

SOURCE=system:pixman
PKGCONFIG=pixman-1
HEADER=pixman-1/pixman-version.h
VERSION_MACROS="PIXMAN_VERSION_MAJOR PIXMAN_VERSION_MINOR PIXMAN_VERSION_MICRO"
RELEASES=https://www.cairographics.org/releases/
LINK=-lpixman-1

build() {
  local o off=
  for o in loongson-mmi mmx sse2 ssse3 vmx arm-simd neon a64-neon mips-dspr2 rvv gnu-inline-asm \
    openmp gtk libpng tests demos; do off+=" -D$o=disabled"; done
  # shellcheck disable=SC2086
  meson_setup $off -Dtimers=false
  log "ninja"
  ninja -C build install > build.log 2>&1 || { tail -30 build.log; die "build failed"; }
  provides pixman pixman-1
}
