#include <stdio.h>
#include <caml/mlvalues.h>
#include <caml/alloc.h>

value cst_answer(value u) { (void)u; return Val_int(42); }

value cst_show(value n)
{
  char b[32];
  snprintf(b, sizeof b, "<%ld>", (long)Long_val(n));
  return caml_copy_string(b);
}
