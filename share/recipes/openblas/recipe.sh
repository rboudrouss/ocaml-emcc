# OpenBLAS (conf-openblas): BLAS, CBLAS, and LAPACK and LAPACKE from their C
# translation (C_LAPACK: no Fortran compiler), for blas and lapack users too
# (-lblas, -llapack...).  Generic C kernels: its RISCV64_GENERIC target, as
# Pyodide does, whose -march/-mabi flags clang refuses for wasm and are
# dropped.  No threads.
# Its subroutines (returning nothing in Fortran) are void in its BLAS, int in
# its own LAPACK functions (getrf, potrf... lapack.h's lapack_int) and
# xerbla, and either in the C translation of LAPACK: harmless natively, but
# wasm-ld replaces a call through another signature with a trap (dgeqrf,
# dgesvd, dgeev... would trap).  The translation is made to agree: void,
# but for OpenBLAS's own functions (int); the `return 0;` of those made void
# are allowed (-Wno-return-mismatch).  A rewrite of a thousand files, not a
# patch.

SOURCE=system:openblas
LINK=-lopenblas
LIB_PATTERNS="openblas blas cblas lapack lapacke"

releases() {
  git_tag_releases https://github.com/OpenMathLib/OpenBLAS.git v \
    'https://github.com/OpenMathLib/OpenBLAS/releases/download/v{v}/OpenBLAS-{v}.tar.gz'
}

build() {
  local binary=32 l
  [ "$TARGET" = wasm64 ] && binary=64
  printf '#!/bin/sh\nfor a; do shift; case $a in -march=*|-mabi=*) ;; *) set -- "$@" "$a" ;; esac; done\nexec %s "$@"\n' \
    "$EMCC" > emcc-generic
  chmod +x emcc-generic
  set -- HOSTCC=cc CC="$PWD/emcc-generic" AR="$EMAR" RANLIB="$EMSDK_BIN/emranlib" TARGET=RISCV64_GENERIC \
    BINARY=$binary NOFORTRAN=1 C_LAPACK=1 USE_THREAD=0 USE_LOCKING=0 NO_SHARED=1 DYNAMIC_ARCH=0 \
    NO_AFFINITY=1 CFLAGS="$CFLAGS -Wno-return-mismatch" PREFIX="$SYSROOT"
  local own="[sdcz](getf2|getrf|laswp|getrs|gesv|potf2|potrf|potri|potrs|lauu2|lauum|trti2|trtri|trtrs|laed3)_|xerbla_"
  find lapack-netlib/SRC -name '*.c' -exec sed -i -E -e 's|/\* Subroutine \*/ int |/* Subroutine */ void |' \
    -e "s/\\<(int|void) (($own)\\()/int \\2/g" {} +
  log "make"
  make -j"$NPROC" "$@" libs netlib > make.log 2>&1 || { tail -30 make.log; die "make failed"; }
  make "$@" install > install.log 2>&1 || { tail -30 install.log; die "install failed"; }
  for l in blas cblas lapack lapacke; do cp -f "$SYSROOT/lib/libopenblas.a" "$SYSROOT/lib/lib$l.a"; done
  provides openblas openblas blas cblas lapack lapacke
}
