# ocaml-lua: its opam file unpacks and patches the Lua it bundles
# (src/lua_c/lua515) before dune builds it, which `opam source` does not
# do.  The dune rule then runs Lua's make with the host's compiler: those
# objects are rebuilt from the C files of the native build (dune_stubs).

SOURCE=opam:ocaml-lua

build() {
  if [ ! -d src/lua_c/lua515 ]; then
    local t
    t=$(cd src/lua_c && ls lua-*.tar.gz | head -1)
    [ -n "$t" ] || die "ocaml-lua: no Lua archive in src/lua_c"
    log "unpacking ${t%.tar.gz}, as its opam file does"
    ( cd src/lua_c && tar xf "$t" && cd "${t%.tar.gz}" && patch -p1 -s -i ../lua.patch \
        && cd .. && mv "${t%.tar.gz}" lua515 ) || die "ocaml-lua: cannot unpack $t"
  fi
  dune_stubs ocaml-lua
}
