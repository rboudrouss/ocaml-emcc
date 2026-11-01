# scrypt: its stubs and the scrypt 1.1.6 it bundles (libscrypt/), built by
# its Makefile with the host's compiler, in one archive libscrypt.a, as it
# does.  Its configure runs with emscripten's (config.h: no sysinfo, which
# emscripten declares without defining).  OpenSSL: the libssl recipe.

SOURCE=opam:scrypt
DEPENDS=libssl

build() {
  local s=libscrypt/scrypt-1.1.6 f objs=
  log "configure (emconfigure)"
  ( cd "$s" && emconfigure ./configure ) > configure.log 2>&1 || { tail -30 configure.log; die "configure failed"; }
  cp "$s/lib/scryptenc/scryptenc.h" libscrypt/scrypt.h
  for f in lib/crypto/crypto_aesctr.c lib/crypto/crypto_scrypt-nosse.c lib/scryptenc/scryptenc.c \
    lib/scryptenc/scryptenc_cpuperf.c lib/util/memlimit.c lib/crypto/sha256.c lib/util/warn.c; do
    "$EMCC" $CFLAGS -DHAVE_CONFIG_H -I"$s" -I"$s/lib/crypto" -I"$s/lib/scryptenc" -I"$s/lib/util" \
      -I"$SYSROOT/include" -c "$s/$f" -o "$s/${f%.c}.o" || die "scrypt: cannot compile $f"
    objs="$objs $s/${f%.c}.o"
  done
  stub_cc scrypt_stubs.c -Ilibscrypt || die "scrypt: cannot compile scrypt_stubs.c"
  # shellcheck disable=SC2086
  mklib scrypt scrypt_stubs.o $objs
  install_lib libscrypt.a
  link_flags scrypt "-lcrypto"
  provides scrypt scrypt
}
