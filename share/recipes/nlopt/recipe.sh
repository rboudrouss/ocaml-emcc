# NLopt (conf-nlopt), its C algorithms (not those in C++: StoGO, AGS).

SOURCE=system:nlopt
HEADER=nlopt.h
VERSION_MACROS="NLOPT_MAJOR_VERSION NLOPT_MINOR_VERSION NLOPT_BUGFIX_VERSION"
LINK=-lnlopt

releases() {
  git_tag_releases https://github.com/stevengj/nlopt.git v \
    'https://github.com/stevengj/nlopt/archive/refs/tags/v{v}.tar.gz'
}

build() {
  command -v cmake >/dev/null || die "nlopt needs cmake"
  log "cmake (emcmake)"
  emcmake cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$SYSROOT" \
    -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_C_FLAGS="$CFLAGS" -DBUILD_SHARED_LIBS=OFF -DNLOPT_CXX=OFF \
    -DNLOPT_PYTHON=OFF -DNLOPT_OCTAVE=OFF -DNLOPT_MATLAB=OFF -DNLOPT_GUILE=OFF -DNLOPT_JAVA=OFF \
    -DNLOPT_SWIG=OFF -DNLOPT_FORTRAN=OFF -DNLOPT_TESTS=OFF > cmake.log 2>&1 || { tail -30 cmake.log; die "cmake failed"; }
  log "make"
  cmake --build build -j"$NPROC" > make.log 2>&1 || { tail -30 make.log; die "make failed"; }
  cmake --install build > install.log 2>&1 || { tail -30 install.log; die "install failed"; }
  provides nlopt nlopt
}
