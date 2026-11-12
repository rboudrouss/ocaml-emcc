/* Outside of owi: every value is 0 (see share/runtime/owi.c) */

#include <stdio.h>
#include <stdlib.h>
#include <caml/mlvalues.h>
#include <caml/alloc.h>

value caml_emcc_owi_int(value unit) { (void)unit; return Val_long(0); }
value caml_emcc_owi_int64(value unit) { (void)unit; return caml_copy_int64(0); }
value caml_emcc_owi_bool(value unit) { (void)unit; return Val_false; }
value caml_emcc_owi_char(value unit) { (void)unit; return Val_int(0); }

value caml_emcc_owi_assume(value b)
{
  if (!Bool_val(b)) exit(0);
  return Val_unit;
}

value caml_emcc_owi_check(value b)
{
  if (!Bool_val(b)) {
    fprintf(stderr, "Emcc_owi.check: assertion failed\n");
    abort();
  }
  return Val_unit;
}
