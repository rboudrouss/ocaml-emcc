# SDL2 (conf-sdl2, -lSDL2): emscripten's port (-sUSE_SDL=2), built with
# embuilder and installed as libSDL2.a with its headers in include/SDL2.
# Its video and audio need a web page (canvas, Web Audio): under node,
# SDL_Init only succeeds for the timer and events subsystems.

SOURCE=none
LINK="-lSDL2 -sUSE_SDL=2"
USE_CFLAGS="-I$SYSROOT/include/SDL2"

build() {
  local cache flag=
  [ "$TARGET" = wasm64 ] && flag=--wasm64
  log "embuilder build sdl2"
  "$EMSDK_BIN/embuilder" $flag build sdl2 > embuilder.log 2>&1 || { tail -20 embuilder.log; die "embuilder failed"; }
  cache=$("$EMSDK_BIN/em-config" CACHE)
  install_lib "$cache/sysroot/lib/$TARGET-emscripten/libSDL2.a"
  rm -rf "$SYSROOT/include/SDL2"; mkdir -p "$SYSROOT/include"
  cp -r "$cache/sysroot/include/SDL2" "$SYSROOT/include/SDL2"
  install_pc sdl2 "$(sed -n 's/^#define SDL_MAJOR_VERSION *//p;s/^#define SDL_MINOR_VERSION *//p;s/^#define SDL_PATCHLEVEL *//p' "$SYSROOT/include/SDL2/SDL_version.h" | paste -sd. -)" \
    "-lSDL2 -sUSE_SDL=2" "-I\${includedir}/SDL2"
  provides sdl2 SDL2
}
