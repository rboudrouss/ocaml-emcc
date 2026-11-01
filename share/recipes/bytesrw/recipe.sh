# bytesrw (built with topkg): the stub archive of each of its optional
# libraries (src/*/lib*.clib) whose C library the sysroot has (zlib, zstd...;
# the others are left out), sysrandom with its getrandom from getentropy on
# emscripten (patches/).

SOURCE=opam:bytesrw

build() {
  apply_patches "$BASE_RECIPE_DIR/patches"
  local clib dir lib o objs ok
  for clib in src/*/lib*_stubs.clib; do
    dir=$(dirname "$clib") lib=$(basename "$clib" .clib) objs= ok=1
    for o in $(cat "$clib"); do
      # shellcheck disable=SC2086
      stub_cc "$dir/${o%.o}.c" -I"$dir" 2> "$dir/$lib.log" || { ok=; break; }
      objs="$objs $dir/$o"
    done
    if [ -n "$ok" ]; then
      # shellcheck disable=SC2086
      (cd "$dir" && mklib "${lib#lib}" $(for o in $objs; do basename "$o"; done)) && install_lib "$dir/$lib.a"
      provides bytesrw "${lib#lib}"
      log "  $lib.a"
    else
      log "  $lib.a: not built (its C library is missing)"
    fi
  done
}
