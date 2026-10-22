# cryptokit: the C stubs, built with dune -x.  src/stubs-md5.c declares the
# runtime's caml_MD5Update with an `unsigned` length where the runtime has
# `uintnat`: the same type on wasm32, not on wasm64, where wasm-ld turns the
# call into a trap (MD5 hashing then stops with "unreachable").

SOURCE=opam:cryptokit

build() {
  sed -i 's/unsigned char \*buf, unsigned len);/unsigned char *buf, uintnat len);/' src/stubs-md5.c
  grep -q 'uintnat len' src/stubs-md5.c || die "stubs-md5.c: cannot fix the caml_MD5Update prototype"
  dune_stubs cryptokit
}
