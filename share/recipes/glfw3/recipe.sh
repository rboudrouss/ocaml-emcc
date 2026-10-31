# GLFW 3 (conf-glfw3): emscripten's, a JS library over the canvas, WebGL
# and the browser's events (-sUSE_GLFW=3; its headers are in emscripten's
# sysroot), as for raylib, with WebGL 2 (OpenGL ES 3: glBlitFramebuffer...).
# A window needs a web page.  libglfw3_compat.a:
# the GLFW 3.3 functions it declares without implementing them
# (glfw3_compat.c).

SOURCE=none
LINK="-lglfw3_compat -sUSE_GLFW=3 -sMAX_WEBGL_VERSION=2"

build() {
  "$EMCC" $CFLAGS -c "$RECIPE_DIR/glfw3_compat.c" -o glfw3_compat.o || die "cannot compile glfw3_compat.c"
  mklib glfw3_compat glfw3_compat.o
  install_lib libglfw3_compat.a
  provides glfw3 glfw3_compat
}
