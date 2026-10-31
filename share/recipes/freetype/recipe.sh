# FreeType (conf-freetype), with zlib (compressed fonts), without brotli,
# bzip2, libpng or HarfBuzz.  Its pkg-config version is libtool's: the
# version is the one of its header.

SOURCE=system:freetype
DEPENDS=zlib
HEADER=freetype2/freetype/freetype.h
VERSION_MACROS="FREETYPE_MAJOR FREETYPE_MINOR FREETYPE_PATCH"
RELEASES=https://download.savannah.gnu.org/releases/freetype/
LINK=-lfreetype

build() {
  meson_setup -Dzlib=system -Dbrotli=disabled -Dbzip2=disabled -Dpng=disabled -Dharfbuzz=disabled \
    -Dtests=disabled
  log "ninja"
  ninja -C build install > build.log 2>&1 || { tail -30 build.log; die "build failed"; }
  provides freetype freetype
}
