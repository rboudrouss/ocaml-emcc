# fontconfig (conf-libfontconfig), with expat, on top of the freetype
# recipe.  Its configuration is in the sysroot (etc/fonts), and finds the
# fonts of the host's usual directories (/usr/share/fonts...) where the
# file system is the host's (node).  Thread-safe, as pixman.  It needs
# gperf.

SOURCE=system:libfontconfig
DEPENDS="freetype expat"
PKGCONFIG=fontconfig
HEADER=fontconfig/fontconfig.h
VERSION_MACROS="FC_MAJOR FC_MINOR FC_REVISION"
RELEASES=https://www.freedesktop.org/software/fontconfig/release/
TARBALL=fontconfig
LINK=-lfontconfig
LIB_PATTERNS=fontconfig

build() {
  command -v gperf >/dev/null || die "fontconfig needs gperf"
  meson_setup -Ddoc=disabled -Dnls=disabled -Dtests=disabled -Dtools=disabled -Dcache-build=disabled \
    -Dxml-backend=expat
  log "ninja"
  ninja -C build install > build.log 2>&1 || { tail -30 build.log; die "build failed"; }
  provides libfontconfig fontconfig
}
