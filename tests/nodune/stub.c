#include <caml/mlvalues.h>
#include <caml/alloc.h>
value ml_triple(value n) { return Val_long(3 * Long_val(n)); }
value ml_hello(value unit) { return caml_copy_string("hello from a hand-compiled stub"); }
