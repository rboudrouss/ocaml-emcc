# OpenBLAS (conf-openblas): BLAS, CBLAS, and LAPACK and LAPACKE from their C
# translation (C_LAPACK: no Fortran compiler), for blas and lapack users too
# (-lblas, -llapack...).  Generic C kernels: its RISCV64_GENERIC target, as
# Pyodide does, whose -march/-mabi flags clang refuses for wasm and are
# dropped.  No threads.

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
    NO_AFFINITY=1 CFLAGS="$CFLAGS" PREFIX="$SYSROOT"
  log "make"
  make -j"$NPROC" "$@" libs netlib > make.log 2>&1 || { tail -30 make.log; die "make failed"; }
  make "$@" install > install.log 2>&1 || { tail -30 install.log; die "install failed"; }
  for l in blas cblas lapack lapacke; do cp -f "$SYSROOT/lib/libopenblas.a" "$SYSROOT/lib/lib$l.a"; done
  provides openblas openblas blas cblas lapack lapacke
}
