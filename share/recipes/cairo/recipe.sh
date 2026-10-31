# cairo (conf-cairo), on top of the pixman, libpng, zlib, freetype and
# fontconfig recipes: the image, recording, PDF, PostScript, SVG and script
# surfaces, the PNG functions and FreeType fonts (cairo2 needs cairo-ft.h).
# No X11.

SOURCE=system:cairo
DEPENDS="pixman libpng zlib freetype libfontconfig"
HEADER=cairo/cairo-version.h
VERSION_MACROS="CAIRO_VERSION_MAJOR CAIRO_VERSION_MINOR CAIRO_VERSION_MICRO"
RELEASES=https://www.cairographics.org/releases/
LINK=-lcairo
USE_CFLAGS="-I$SYSROOT/include/cairo"

build() {
  local o off=
  for o in xcb xlib quartz dwrite tests lzo glib spectre symbol-lookup; do
    off+=" -D$o=disabled"; done
  # shellcheck disable=SC2086
  meson_setup -Dpng=enabled -Dzlib=enabled -Dfreetype=enabled -Dfontconfig=enabled $off
  log "ninja"
  ninja -C build install > build.log 2>&1 || { tail -30 build.log; die "build failed"; }
  provides cairo cairo
}
