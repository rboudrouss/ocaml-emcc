# raylib (raylib-ocaml): the ctypes stubs, built with dune -x, and the
# raylib it vendors, built by make for PLATFORM_WEB (see patches/): GLFW
# and OpenGL ES 2 are emscripten's (-sUSE_GLFW=3, WebGL), so a window needs
# a web page with a canvas.  Its WindowShouldClose() gives the browser a
# frame with emscripten_sleep, hence -sASYNCIFY: the usual loop
# `while not (window_should_close ()) do ... done` runs as is.  -sJSPI
# after it (`ocaml-emcc build app.html -- -sJSPI`) replaces it.

SOURCE=opam:raylib

build() {
  apply_patches "$BASE_RECIPE_DIR/patches"
  dune_stubs raylib
  link_flags raylib "-sUSE_GLFW=3 -sASYNCIFY"
}
