#include <stdio.h>
#include <string.h>
#include <gmp.h>
#include <mpfr.h>
#include <caml/alloc.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>

#ifndef DEPGRAPH_DUNE
#error "not built with the flags of src/dune"
#endif

/* the square root of a decimal integer, as 0.<digits>e<exponent> */
value depgraph_sqrt(value dec, value digits)
{
  CAMLparam2(dec, digits);
  CAMLlocal1(res);
  mpfr_t x;
  mpfr_exp_t e;
  char *s, buf[64];
  mpfr_init2(x, 256);
  if (mpfr_set_str(x, String_val(dec), 10, MPFR_RNDN) != 0) {
    mpfr_clear(x);
    caml_invalid_argument("Depgraph.sqrt");
  }
  mpfr_sqrt(x, x, MPFR_RNDN);
  s = mpfr_get_str(NULL, &e, 10, Long_val(digits), x, MPFR_RNDN);
  snprintf(buf, sizeof buf, "e%ld", (long)e);
  res = caml_alloc_string(2 + strlen(s) + strlen(buf));
  sprintf((char *)Bytes_val(res), "0.%s%s", s, buf);
  mpfr_free_str(s);
  mpfr_clear(x);
  CAMLreturn(res);
}

/* the major versions (the minor ones may differ between host and recipe) */
value depgraph_versions(value unit)
{
  char buf[64];
  snprintf(buf, sizeof buf, "gmp %d, mpfr %d", __GNU_MP_VERSION, MPFR_VERSION_MAJOR);
  return caml_copy_string(buf);
}
