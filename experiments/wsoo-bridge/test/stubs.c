#include <string.h>
#include <stdio.h>
#include <caml/mlvalues.h>
#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/fail.h>
#include <caml/callback.h>
#include <caml/custom.h>

value t_add(value a, value b) { return Val_long(Long_val(a) + Long_val(b)); }

value t_pair(value s, value f) {
  CAMLparam2(s, f); CAMLlocal2(r, s2);
  s2 = caml_alloc_sprintf("<%s>", String_val(s));
  r = caml_alloc_tuple(2);
  Store_field(r, 0, s2);
  Store_field(r, 1, caml_copy_double(Double_val(f) * 2));
  CAMLreturn(r);
}

value t_sum(value l) { long s = 0; for (; l != Val_emptylist; l = Field(l, 1)) s += Long_val(Field(l, 0)); return Val_long(s); }

value t_range(value n) {
  CAMLparam1(n); CAMLlocal2(l, c);
  l = Val_emptylist;
  for (long i = Long_val(n) - 1; i >= 0; i--) { c = caml_alloc(2, 0); Store_field(c, 0, Val_long(i)); Store_field(c, 1, l); l = c; }
  CAMLreturn(l);
}

value t_fail(value s) { caml_failwith(String_val(s)); }
value t_invalid(value u) { caml_invalid_argument("from C"); }

static void counter_finalize(value v) { fprintf(stderr, "(counter finalized)\n"); free(*(long **) Data_custom_val(v)); }
static struct custom_operations counter_ops = { "t.counter", counter_finalize, custom_compare_default, custom_hash_default, custom_serialize_default, custom_deserialize_default, custom_compare_ext_default, custom_fixed_length_default };
value t_counter_new(value n) { long *p = malloc(sizeof(long)); *p = Long_val(n); value v = caml_alloc_custom(&counter_ops, sizeof(long *), 0, 1); *(long **) Data_custom_val(v) = p; return v; }
value t_counter_incr(value c) { long *p = *(long **) Data_custom_val(c); return Val_long(++*p); }

value t_fill(value b, value c) { memset(Bytes_val(b), Int_val(c), caml_string_length(b)); return Val_unit; }
value t_apply(value f, value x) { return caml_callback(f, x); }
value t_apply2(value f, value x, value y) { return caml_callback2(f, x, y); }
value t_mul64(value a, value b) { return caml_copy_int64(Int64_val(a) * Int64_val(b)); }
value t_area(value r) { return caml_copy_double(Double_field(r, 0) * Double_field(r, 1)); }

value t_describe(value s) {
  char buf[200];
  if (Is_long(s)) return caml_copy_string("Empty");
  if (Tag_val(s) == 0) snprintf(buf, sizeof buf, "Circle %g", Double_val(Field(s, 0)));
  else { int n = 0; for (value l = Field(s, 0); l != Val_emptylist; l = Field(l, 1)) n++; snprintf(buf, sizeof buf, "Poly of %d points", n); }
  return caml_copy_string(buf);
}

value t_six(value a, value b, value c, value d, value e, value f) { return Val_long(Long_val(a)+Long_val(b)+Long_val(c)+Long_val(d)+Long_val(e)+Long_val(f)); }
value t_six_byte(value *argv, int argn) { return t_six(argv[0], argv[1], argv[2], argv[3], argv[4], argv[5]); }

value t_raise_named(value n) { const value *e = caml_named_value("t_mine"); if (!e) caml_failwith("t_mine not registered"); caml_raise_with_arg(*e, n); }
