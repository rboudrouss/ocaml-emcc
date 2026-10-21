#include <string.h>
#include <caml/mlvalues.h>
#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/callback.h>
#include <caml/fail.h>
#include <caml/custom.h>

value ml_add_int64(value a, value b) {
  return caml_copy_int64(Int64_val(a) + Int64_val(b));
}

value ml_sum_floats(value arr) {
  double s = 0;
  for (mlsize_t i = 0; i < Wosize_val(arr) / Double_wosize; i++) s += Double_flat_field(arr, i);
  return caml_copy_double(s);
}

value ml_greeting(value unit) { return caml_copy_string(MYSTUBS_MAGIC == 7 ? "hi from C (flags ok)" : "flags lost"); }

value ml_apply_twice(value f, value x) {
  CAMLparam2(f, x);
  CAMLlocal1(r);
  r = caml_callback(f, x);
  r = caml_callback(f, r);
  CAMLreturn(r);
}

value ml_fail_if_negative(value n) {
  if (Long_val(n) < 0) caml_failwith("negative!");
  return n;
}

value ml_word_size(value unit) { return Val_int(8 * sizeof(value)); }

static int finalized = 0;
static void counter_finalize(value v) { finalized++; }
static struct custom_operations counter_ops = {
  "mystubs.counter", counter_finalize, custom_compare_default, custom_hash_default,
  custom_serialize_default, custom_deserialize_default, custom_compare_ext_default,
  custom_fixed_length_default };

value ml_counter_make(value init) {
  value v = caml_alloc_custom(&counter_ops, sizeof(long), 0, 1);
  *(long *)Data_custom_val(v) = Long_val(init);
  return v;
}
value ml_counter_incr(value c) { return Val_long(++*(long *)Data_custom_val(c)); }
