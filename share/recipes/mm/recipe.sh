# mm: the C stubs, built with dune -x once mm.oss's compile without OSS's
# sys/soundcard.h (patches/): its requests, Linux's numbers, fail as on a
# host without a sound device.

SOURCE=opam:mm

build() {
  apply_patches "$BASE_RECIPE_DIR/patches"
  dune_stubs mm
}
