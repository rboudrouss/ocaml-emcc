# osdp: its opam build runs ./configure (src/config.h, Sdp_default...)
# before dune.  The C stubs are then built with dune -x.

SOURCE=opam:osdp

build() {
  log "configure (emconfigure)"
  emconfigure ./configure > configure.log 2>&1 || { tail -30 configure.log; die "configure failed"; }
  dune_stubs osdp
}
