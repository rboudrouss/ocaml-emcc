# Argon2, the reference implementation (libargon2; the argon2 bindings use
# it through ctypes-foreign and -largon2), without threads.

SOURCE=system:libargon2
HEADER=
TARBALL=phc-winner-argon2
COMPAT=latest
LINK=-largon2

# releases are dates (tag 20190702)
releases() {
  local v
  git ls-remote --tags --refs https://github.com/P-H-C/phc-winner-argon2.git 2>/dev/null \
    | sed -n 's|.*refs/tags/\([0-9]\{8\}\)$|\1|p' | sort \
    | while read -r v; do echo "$v https://github.com/P-H-C/phc-winner-argon2/archive/refs/tags/$v.tar.gz"; done
}

build() {
  local f objs=()
  for f in argon2 core blake2/blake2b thread encoding ref; do
    "$EMCC" $CFLAGS -DARGON2_NO_THREADS -Iinclude -Isrc -c "src/$f.c" -o "src/$f.o" || die "cannot compile src/$f.c"
    objs+=("src/$f.o")
  done
  mklib argon2 "${objs[@]}"
  install_lib libargon2.a
  install_headers . include/argon2.h
  install_pc libargon2 "$SOURCE_VERSION" -largon2
  provides libargon2 argon2
}
