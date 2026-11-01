# frei0r (conf-frei0r): its plugin API, a header (frei0r.h).  The plugins
# themselves are shared libraries loaded at run time: none here.

SOURCE=system:frei0r
HEADER=frei0r.h
VERSION_MACROS="FREI0R_MAJOR_VERSION FREI0R_MINOR_VERSION"
LINK=-lm  # (a header: nothing to link)

releases() {
  git_tag_releases https://github.com/dyne/frei0r.git v \
    'https://github.com/dyne/frei0r/archive/refs/tags/v{v}.tar.gz'
}

build() {
  install_headers . include/frei0r.h
  install_pc frei0r "$SOURCE_VERSION" ""
  provides frei0r frei0r
}
